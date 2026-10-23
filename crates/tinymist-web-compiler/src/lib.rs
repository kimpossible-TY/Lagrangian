//! Snapshot-only compilation for browser Workers, using the maintained Tinymist world.
//!
//! This module has no filesystem or network access. Missing inputs fail compilation;
//! Python remains responsible for accepting the exported HTML and source edits.

use std::{
    collections::BTreeMap,
    path::{Component, Path, PathBuf},
    sync::Arc,
};

use tinymist_vfs::{Vfs, dummy::DummyAccessModel};
use tinymist_world::{
    CompilationTask, CompilerFeat, CompilerUniverse, EntryState, ShadowApi,
    font::{FontResolverImpl, memory::MemoryFontSearcher},
    package::{PackageError, PackageRegistry, PackageSpec, RegistryPathMapper},
};
use typst::{
    Features,
    diag::SourceDiagnostic,
    foundations::{Bytes, Dict, IntoValue},
};
use wasm_bindgen::prelude::*;

#[derive(Debug)]
struct SnapshotRegistry;

impl PackageRegistry for SnapshotRegistry {
    fn resolve(&self, spec: &PackageSpec) -> Result<Arc<Path>, PackageError> {
        Ok(PathBuf::from("/packages")
            .join(spec.namespace.as_str())
            .join(spec.name.as_str())
            .join(spec.version.to_string())
            .into())
    }
}

#[derive(Debug, Clone, Copy)]
struct SnapshotFeature;

impl CompilerFeat for SnapshotFeature {
    type FontResolver = FontResolverImpl;
    type AccessModel = DummyAccessModel;
    type Registry = SnapshotRegistry;
}

/// Persistent evaluator and virtual filesystem belonging to one browser Worker.
#[wasm_bindgen]
pub struct BrowserCompiler {
    world: CompilerUniverse<SnapshotFeature>,
    fonts: Vec<Bytes>,
    fonts_dirty: bool,
}

impl Default for BrowserCompiler {
    fn default() -> Self {
        Self::new()
    }
}

#[wasm_bindgen]
impl BrowserCompiler {
    /// Creates an empty compiler. Supply fonts and immutable files before compiling.
    #[wasm_bindgen(constructor)]
    pub fn new() -> Self {
        let registry = Arc::new(SnapshotRegistry);
        let resolver = Arc::new(RegistryPathMapper::new(registry.clone()));
        Self {
            world: CompilerUniverse::new_raw(
                EntryState::new_rooted(PathBuf::from("/workspace").into(), None),
                Features::default(),
                None,
                Vfs::new(resolver, DummyAccessModel),
                registry,
                Arc::new(MemoryFontSearcher::new().build()),
                None,
            ),
            fonts: vec![],
            fonts_dirty: true,
        }
    }

    /// Maps one supplied file; changing only edited files preserves incremental caches.
    pub fn set_file(&mut self, path: &str, data: &[u8]) -> Result<(), String> {
        let path = checked_path(path)?;
        self.world
            .map_shadow(path, Bytes::new(data.to_vec()))
            .map_err(|e| e.to_string())
    }

    /// Removes a file absent from the next snapshot, including failed import cache entries.
    pub fn remove_file(&mut self, path: &str) -> Result<(), String> {
        self.world
            .unmap_shadow(checked_path(path)?)
            .map_err(|e| e.to_string())
    }

    /// Adds an explicit font before the bundled fallback fonts.
    pub fn add_font(&mut self, data: &[u8]) {
        self.fonts.push(Bytes::new(data.to_vec()));
        self.fonts_dirty = true;
    }

    /// Compiles raw HTML or PDF. Success does not authorize publication or source writes.
    pub fn compile(
        &mut self,
        entry: &str,
        target: &str,
        inputs_json: &str,
        timestamp: i64,
    ) -> Result<RawResult, String> {
        let entry: Arc<Path> = checked_path(entry)?.into();
        if !entry.starts_with("/workspace") {
            return Err("Entry is outside the workspace".into());
        }
        if !matches!(target, "html" | "pdf") {
            return Err("Unsupported target".into());
        }
        let inputs: BTreeMap<String, String> =
            serde_json::from_str(inputs_json).map_err(|e| e.to_string())?;
        let inputs: Dict = inputs
            .into_iter()
            .map(|(key, value)| (key.into(), value.into_value()))
            .collect();
        if self.fonts_dirty {
            let mut fonts = MemoryFontSearcher::new();
            for font in &self.fonts {
                fonts.add_memory_font(font.clone());
            }
            for font in typst_assets::fonts() {
                fonts.add_memory_font(Bytes::new(font));
            }
            self.world
                .increment_revision(|world| world.set_fonts(Arc::new(fonts.build())));
            self.fonts_dirty = false;
        }
        self.world
            .increment_revision(|world| {
                world.set_inputs(Arc::new(inputs.into()));
                world.set_creation_timestamp(Some(timestamp));
                world.set_entry_file(entry)
            })
            .map_err(|e| format!("{e:?}"))?;
        let world = self.world.snapshot();
        let mut diagnostics = String::new();
        let output = if target == "html" {
            let compiled = CompilationTask::<typst_html::HtmlDocument>::execute(&world);
            append_diagnostics(&mut diagnostics, "warning", &compiled.warnings);
            compiled.output.and_then(|document| {
                typst_html::html(&document, &Default::default()).map(String::into_bytes)
            })
        } else {
            let compiled = CompilationTask::<typst_layout::PagedDocument>::execute(&world);
            append_diagnostics(&mut diagnostics, "warning", &compiled.warnings);
            compiled
                .output
                .and_then(|document| typst_pdf::pdf(&document, &Default::default()))
        };
        let dependencies = world
            .depended_fs_paths()
            .iter()
            .map(|p| p.to_string_lossy().into_owned())
            .collect::<Vec<_>>();
        let ok = output.is_ok();
        let artifact = match output {
            Ok(bytes) => bytes,
            Err(errors) => {
                append_diagnostics(&mut diagnostics, "error", &errors);
                vec![]
            }
        };
        // Keep entries used by the latest compile. Retaining ten obsolete full
        // documents exhausts wasm32 memory during repeated whole-book edits.
        comemo::evict(1);
        Ok(RawResult {
            artifact,
            diagnostics,
            dependencies,
            ok,
        })
    }
}

fn checked_path(path: &str) -> Result<&Path, String> {
    let path = Path::new(path);
    if !(path.starts_with("/workspace") || path.starts_with("/packages"))
        || path
            .components()
            .any(|p| matches!(p, Component::ParentDir | Component::CurDir))
    {
        return Err("Invalid snapshot path".into());
    }
    Ok(path)
}

fn append_diagnostics(output: &mut String, severity: &str, diagnostics: &[SourceDiagnostic]) {
    for diagnostic in diagnostics {
        output.push_str(&format!("{severity}: {}\n", diagnostic.message));
        for hint in &diagnostic.hints {
            output.push_str(&format!("  hint: {}\n", hint.v));
        }
    }
}

/// Raw output transferred from the Worker to the server's acceptance pipeline.
#[wasm_bindgen]
pub struct RawResult {
    artifact: Vec<u8>,
    diagnostics: String,
    dependencies: Vec<String>,
    ok: bool,
}

#[wasm_bindgen]
impl RawResult {
    /// Whether compilation and export succeeded.
    pub fn ok(&self) -> bool {
        self.ok
    }
    /// Exported bytes; empty on compilation failure.
    pub fn artifact(&self) -> Vec<u8> {
        self.artifact.clone()
    }
    /// Diagnostics in the existing Python compiler gate's line format.
    pub fn diagnostics(&self) -> String {
        self.diagnostics.clone()
    }
    /// Actual virtual dependencies as a JSON array.
    pub fn dependencies(&self) -> String {
        serde_json::to_string(&self.dependencies).unwrap()
    }
}

/// Committed WASM linear memory, including the allocator; not total browser process RAM.
#[wasm_bindgen]
pub fn memory_bytes() -> usize {
    #[cfg(target_arch = "wasm32")]
    {
        core::arch::wasm32::memory_size(0) * 65536
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn incremental_imports_and_missing_files_never_read_the_host() {
        let mut compiler = BrowserCompiler::new();
        compiler
            .set_file("/workspace/main.typ", b"#include \"part.typ\"")
            .unwrap();
        compiler
            .set_file("/workspace/part.typ", b"First $x^2$.")
            .unwrap();
        let first = compiler
            .compile("/workspace/main.typ", "html", "{}", 1760000000)
            .unwrap();
        assert!(first.ok, "{}", first.diagnostics);
        assert!(String::from_utf8(first.artifact).unwrap().contains("First"));
        assert!(first.dependencies.contains(&"/workspace/part.typ".into()));
        compiler
            .set_file("/workspace/part.typ", b"Second.")
            .unwrap();
        let second = compiler
            .compile("/workspace/main.typ", "html", "{}", 1760000000)
            .unwrap();
        assert!(
            String::from_utf8(second.artifact)
                .unwrap()
                .contains("Second")
        );
        compiler.remove_file("/workspace/part.typ").unwrap();
        assert!(
            !compiler
                .compile("/workspace/main.typ", "html", "{}", 1760000000)
                .unwrap()
                .ok
        );
        compiler
            .set_file("/workspace/part.typ", b"Restored.")
            .unwrap();
        let pdf = compiler
            .compile("/workspace/main.typ", "pdf", "{}", 1760000000)
            .unwrap();
        assert!(pdf.ok, "{}", pdf.diagnostics);
        assert!(pdf.artifact.starts_with(b"%PDF"));
        assert!(compiler.set_file("/etc/passwd", b"no").is_err());
        assert!(compiler.set_file("/workspace/../private", b"no").is_err());
    }
}
