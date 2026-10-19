//! Per-project world, demand, snapshots and accepted compilation state.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, OnceLock};

use ecow::{EcoVec, eco_vec};
use tinymist_std::{ImmutPath, typst::TypstDocument};
use tinymist_task::ExportTarget;
use tinymist_world::vfs::FsProvider;
use tinymist_world::{
    CompileSignal, CompileSnapshot, CompilerFeat, CompilerUniverse, EntryReader, ProjectInsId,
    WorldComputeGraph, WorldDeps,
};

use super::{
    CompileHandler, CompileOutcome, CompileTicket, CompiledArtifact, eviction, no_reason,
    reason_by_entry_change, spawn_cpu,
};

/// A project instance state.
pub struct ProjectInsState<F: CompilerFeat, Ext> {
    /// The project instance id.
    pub id: ProjectInsId,
    /// The extension
    pub ext: Ext,
    /// The underlying universe.
    pub verse: CompilerUniverse<F>,
    /// Specifies the current export target.
    pub export_target: ExportTarget,
    /// Whether to run in syntax-only mode.
    pub syntax_only: bool,
    /// The reason to compile.
    pub reason: CompileSignal,
    /// The compilation handle.
    pub handler: Arc<dyn CompileHandler<F, Ext>>,
    /// The file dependencies.
    pub(super) deps: EcoVec<ImmutPath>,

    /// The latest compute graph (snapshot), derived lazily from
    /// `latest_compilation` as needed.
    pub cached_snapshot: Option<Arc<WorldComputeGraph<F>>>,
    /// The latest compilation.
    pub latest_compilation: OnceLock<CompiledArtifact<F>>,
    /// The latest successly compiled document.
    pub latest_success_doc: Option<TypstDocument>,

    pub(super) committed_revision: usize,
    pub(super) compile_generation: Arc<AtomicUsize>,
    compile_revision: usize,
    demanded: bool,
}

impl<F: CompilerFeat, Ext> Drop for ProjectInsState<F, Ext> {
    fn drop(&mut self) {
        self.compile_generation.store(0, Ordering::Release);
    }
}

impl<F: CompilerFeat, Ext: 'static> ProjectInsState<F, Ext> {
    pub(super) fn new(
        id: ProjectInsId,
        verse: CompilerUniverse<F>,
        export_target: ExportTarget,
        syntax_only: bool,
        handler: Arc<dyn CompileHandler<F, Ext>>,
    ) -> Self
    where
        Ext: Default,
    {
        let compile_revision = verse.revision.get();
        Self {
            id,
            ext: Default::default(),
            syntax_only,
            verse,
            reason: no_reason(),
            cached_snapshot: None,
            handler,
            export_target,
            latest_compilation: OnceLock::default(),
            latest_success_doc: None,
            deps: Default::default(),
            committed_revision: 0,
            compile_generation: Arc::new(AtomicUsize::new(1)),
            compile_revision,
            demanded: true,
        }
    }

    /// Whether automatic compilation is currently requested by a consumer.
    pub fn is_demanded(&self) -> bool {
        self.demanded
    }

    /// Pauses or resumes automatic work without discarding the world or caches.
    pub fn set_demand(&mut self, demanded: bool) {
        if self.demanded == demanded {
            return;
        }
        self.demanded = demanded;
        // A paused in-flight task may have consumed its compile reason. A
        // clean, already committed document remains usable on reconnection and
        // for a save signal with no input changes. Paused input edits already
        // invalidate its generation through sync_compile_revision.
        if !demanded && self.committed_revision != self.verse.revision.get() {
            self.invalidate_compiles();
            self.reason.merge(reason_by_entry_change());
        }
    }

    /// Prevents queued or completed work from publishing after shutdown.
    pub fn invalidate_compiles(&mut self) {
        self.compile_generation.fetch_add(1, Ordering::AcqRel);
    }

    pub(super) fn sync_compile_revision(&mut self) {
        let revision = self.verse.revision.get();
        if revision != self.compile_revision {
            self.compile_revision = revision;
            self.invalidate_compiles();
        }
    }

    fn compile_ticket(&mut self) -> CompileTicket {
        self.sync_compile_revision();
        CompileTicket::new(
            self.id.clone(),
            self.verse.revision.get(),
            self.compile_generation.clone(),
        )
    }

    /// Returns whether an artifact belongs to the current project lifetime.
    pub fn accepts_artifact(&self, artifact: &CompiledArtifact<F>) -> bool {
        artifact
            .ticket
            .as_ref()
            .is_none_or(|ticket| ticket.is_current() && ticket.belongs_to(&self.compile_generation))
    }

    /// Gets a snapshot of the project.
    pub fn snapshot(&mut self) -> Arc<WorldComputeGraph<F>> {
        match self.cached_snapshot.as_ref() {
            Some(snap) if snap.world().revision() == self.verse.revision => snap.clone(),
            _ => {
                let snap = self.make_snapshot();
                self.cached_snapshot = Some(snap.clone());
                snap
            }
        }
    }

    /// Creates a new snapshot of the project derived from `latest_compilation`.
    pub(super) fn make_snapshot(&self) -> Arc<WorldComputeGraph<F>> {
        let world = self.verse.snapshot();
        let snap = CompileSnapshot {
            id: self.id.clone(),
            world,
            signal: self.reason,
            success_doc: self.latest_success_doc.clone(),
        };
        WorldComputeGraph::new(snap)
    }

    /// Compiles the document once if there is any reason and the entry is
    /// active. (this is used for experimenting typst.node compilations)
    #[must_use]
    pub fn may_compile2<'a>(
        &mut self,
        compute: impl FnOnce(&Arc<WorldComputeGraph<F>>) + 'a,
    ) -> Option<impl FnOnce() -> Arc<WorldComputeGraph<F>> + 'a> {
        if !self.demanded || !self.reason.any() || self.verse.entry_state().is_inactive() {
            return None;
        }

        let snap = self.snapshot();
        self.reason = Default::default();
        Some(move || {
            compute(&snap);
            snap
        })
    }

    /// Compiles the document once if there is any reason and the entry is
    /// active.
    #[must_use]
    pub fn may_compile(
        &mut self,
        handler: &Arc<dyn CompileHandler<F, Ext>>,
    ) -> Option<impl FnOnce() -> CompiledArtifact<F> + 'static> {
        if !self.demanded || !self.reason.any() || self.verse.entry_state().is_inactive() {
            return None;
        }

        let snap = self.snapshot();
        self.reason = Default::default();

        Some(Self::run_compile(
            handler.clone(),
            snap,
            self.export_target,
            self.syntax_only,
        ))
    }

    /// Queues work that can be discarded before execution or publication.
    #[must_use]
    pub fn may_compile_latest(
        &mut self,
        handler: &Arc<dyn CompileHandler<F, Ext>>,
    ) -> Option<(
        CompileTicket,
        impl FnOnce() -> CompileOutcome<F> + 'static + use<F, Ext>,
    )> {
        if !self.demanded || !self.reason.any() || self.verse.entry_state().is_inactive() {
            return None;
        }
        let ticket = self.compile_ticket();
        let snap = self.snapshot();
        self.reason = Default::default();
        Some((
            ticket.clone(),
            Self::prepare_compile(
                handler.clone(),
                snap,
                self.export_target,
                self.syntax_only,
                Some(ticket),
            ),
        ))
    }

    pub(super) fn process_compile(
        &mut self,
        artifact: CompiledArtifact<F>,
        maintains_shared_cache: bool,
    ) -> bool {
        let world = &artifact.snap.world;
        let compiled_revision = world.revision().get();
        if !self.accepts_artifact(&artifact) || self.committed_revision >= compiled_revision {
            return false;
        }

        // Updates state.
        let doc = artifact.doc.clone();
        self.committed_revision = compiled_revision;
        if doc.is_some() {
            self.latest_success_doc = doc;
        }
        self.cached_snapshot = None; // invalidate; will be recomputed on demand

        // Notifies the new file dependencies.
        let mut deps = eco_vec![];
        world.iter_dependencies(&mut |dep| {
            if let Ok(x) = world.file_path(dep).and_then(|e| e.to_err()) {
                deps.push(x.into())
            }
        });

        self.deps = deps.clone();

        let mut world = world.clone();

        // All projects share comemo's caches. One demanded project requests
        // automatic sweeps, coalesced independently of world cleanup.
        if maintains_shared_cache {
            eviction::schedule();
        }

        let queued_at = tinymist_std::time::Instant::now();
        spawn_cpu(move || {
            let _qos = tinymist_std::performance::QosGuard::enter(
                tinymist_std::performance::WorkClass::Maintenance,
            );
            let queued = queued_at.elapsed();
            if maintains_shared_cache {
                let start = tinymist_std::time::Instant::now();
                world.evict_source_cache(30);
                log::debug!(
                    "ProjectCompiler: evict source cache in {:?}",
                    start.elapsed()
                );
            }

            let start = tinymist_std::time::Instant::now();
            world.evict_vfs(60);
            log::debug!(
                "ProjectCompiler: evict VFS cache in {:?} (queued {queued:?})",
                start.elapsed()
            );
        });

        true
    }
}
