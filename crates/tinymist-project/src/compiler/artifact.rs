//! Compiled documents, diagnostics and dependency snapshots.

use core::fmt;
use std::sync::{Arc, OnceLock};

use ecow::EcoVec;
use tinymist_std::typst::TypstDocument;
use tinymist_world::vfs::FileId;
use tinymist_world::{
    BundleCompilationTask, CompileSignal, CompilerFeat, DiagnosticsTask, ProjectInsId,
    WorldComputeGraph, WorldDeps,
};

use super::CompileTicket;

/// A compiled artifact.
pub struct CompiledArtifact<F: CompilerFeat> {
    /// The used compute graph.
    pub graph: Arc<WorldComputeGraph<F>>,
    /// The diagnostics of the document.
    pub diag: Arc<DiagnosticsTask>,
    /// The compiled document.
    pub doc: Option<TypstDocument>,
    /// The depended files.
    pub deps: OnceLock<EcoVec<FileId>>,
    /// The queued task that produced this artifact, if it is revision guarded.
    pub ticket: Option<CompileTicket>,
}

impl<F: CompilerFeat> fmt::Display for CompiledArtifact<F> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let rev = self.graph.snap.world.revision();
        write!(f, "CompiledArtifact({:?}, rev={rev:?})", self.graph.snap.id)
    }
}

impl<F: CompilerFeat> std::ops::Deref for CompiledArtifact<F> {
    type Target = Arc<WorldComputeGraph<F>>;

    fn deref(&self) -> &Self::Target {
        &self.graph
    }
}

impl<F: CompilerFeat> Clone for CompiledArtifact<F> {
    fn clone(&self) -> Self {
        Self {
            graph: self.graph.clone(),
            doc: self.doc.clone(),
            diag: self.diag.clone(),
            deps: self.deps.clone(),
            ticket: self.ticket.clone(),
        }
    }
}

impl<F: CompilerFeat> CompiledArtifact<F> {
    /// Returns the project id.
    pub fn id(&self) -> &ProjectInsId {
        &self.graph.snap.id
    }

    /// Returns the last successfully compiled document.
    pub fn success_doc(&self) -> Option<TypstDocument> {
        self.doc
            .as_ref()
            .cloned()
            .or_else(|| self.snap.success_doc.clone())
    }

    /// Returns the depended files.
    pub fn depended_files(&self) -> &EcoVec<FileId> {
        self.deps.get_or_init(|| {
            let mut deps = EcoVec::default();
            self.graph.snap.world.iter_dependencies(&mut |f| {
                deps.push(f);
            });

            deps
        })
    }

    /// Runs the compiler and returns the compiled document.
    pub fn from_graph(graph: Arc<WorldComputeGraph<F>>, is_html: bool) -> CompiledArtifact<F> {
        let doc = if is_html {
            graph.shared_compile_html().expect("html").map(From::from)
        } else {
            graph.shared_compile().expect("paged").map(From::from)
        };

        CompiledArtifact {
            diag: graph.shared_diagnostics().expect("diag"),
            graph,
            doc,
            deps: OnceLock::default(),
            ticket: None,
        }
    }

    /// Runs diagnostics without precompiling a paged or HTML document.
    pub fn from_graph_without_doc(graph: Arc<WorldComputeGraph<F>>) -> CompiledArtifact<F> {
        let _ = graph
            .compute::<BundleCompilationTask>()
            .expect("bundle compilation");
        CompiledArtifact {
            diag: graph.shared_diagnostics().expect("diag"),
            graph,
            doc: None,
            deps: OnceLock::default(),
            ticket: None,
        }
    }

    /// Returns the error count.
    pub fn error_cnt(&self) -> usize {
        self.diag.error_cnt()
    }

    /// Returns the warning count.
    pub fn warning_cnt(&self) -> usize {
        self.diag.warning_cnt()
    }

    /// Returns the diagnostics.
    pub fn diagnostics(&self) -> impl Iterator<Item = &typst::diag::SourceDiagnostic> + Clone {
        self.diag.diagnostics()
    }

    /// Returns whether there are any errors.
    pub fn has_errors(&self) -> bool {
        self.error_cnt() > 0
    }

    /// Sets the signal.
    pub fn with_signal(mut self, signal: CompileSignal) -> Self {
        let mut snap = self.snap.clone();
        snap.signal = signal;

        self.graph = self.graph.snapshot_unsafe(snap);
        self
    }
}
