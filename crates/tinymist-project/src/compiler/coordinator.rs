//! Project coordination and ordered application of runtime interrupts.

use core::fmt;
use std::collections::HashSet;
use std::path::Path;
use std::sync::Arc;

use ecow::EcoVec;
use tinymist_std::ImmutPath;
use tinymist_std::error::prelude::Result;
use tinymist_task::ExportTarget;
use tinymist_world::vfs::RevisingVfs;
use tinymist_world::vfs::notify::{
    FilesystemEvent, MemoryEvent, NotifyDeps, NotifyMessage, UpstreamUpdateEvent,
};
use tinymist_world::{
    CompilerFeat, CompilerUniverse, EntryReader, EntryState, ProjectInsId, TaskInputs,
    WorldComputeGraph,
};
use tokio::sync::mpsc;

use super::{
    CompileOutcome, CompileReport, CompileStatusEnum, CompiledArtifact, ProjectInsState, eviction,
    reason_by_entry_change, reason_by_fs, reason_by_mem,
};

/// A project compiler handler.
pub trait CompileHandler<F: CompilerFeat, Ext>: Send + Sync + 'static {
    /// Called when there is any reason to compile. This doesn't mean that the
    /// project should be compiled.
    fn on_any_compile_reason(&self, state: &mut ProjectCompiler<F, Ext>);
    // todo: notify project specific compile
    /// Called when a compilation is done.
    fn notify_compile(&self, res: &CompiledArtifact<F>);
    /// Called when a project is removed.
    fn notify_removed(&self, _id: &ProjectInsId) {}
    /// Called when the compilation status is changed.
    fn status(&self, revision: usize, rep: CompileReport);
}

/// No need so no compilation.
impl<F: CompilerFeat + Send + Sync + 'static, Ext: 'static> CompileHandler<F, Ext>
    for std::marker::PhantomData<fn(F, Ext)>
{
    fn on_any_compile_reason(&self, _state: &mut ProjectCompiler<F, Ext>) {
        log::info!("ProjectHandle: no need to compile");
    }
    fn notify_compile(&self, _res: &CompiledArtifact<F>) {}
    fn status(&self, _revision: usize, _rep: CompileReport) {}
}

/// An interrupt to the compiler.
pub enum Interrupt<F: CompilerFeat> {
    /// Compile anyway.
    Compile(ProjectInsId),
    /// Settle a dedicated project.
    Settle(ProjectInsId),
    /// Compiled from computing thread.
    Compiled(CompiledArtifact<F>),
    /// A worker completed or discarded a revision-guarded compilation.
    CompileFinished(CompileOutcome<F>),
    /// Enables or pauses automatic compilation while retaining world updates.
    SetDemand(ProjectInsId, bool),
    /// Change the watching entry.
    ChangeTask(ProjectInsId, TaskInputs),
    /// Font changes.
    Font(Arc<F::FontResolver>),
    /// Creation timestamp changes.
    CreationTimestamp(Option<i64>),
    /// Memory file changes.
    Memory(MemoryEvent),
    /// File system event.
    Fs(FilesystemEvent),
    /// Save a file.
    Save(ImmutPath),
}

impl<F: CompilerFeat> fmt::Debug for Interrupt<F> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Interrupt::Compile(id) => write!(f, "Compile({id:?})"),
            Interrupt::Settle(id) => write!(f, "Settle({id:?})"),
            Interrupt::Compiled(artifact) => write!(f, "Compiled({:?})", artifact.id()),
            Interrupt::CompileFinished(outcome) => {
                write!(f, "CompileFinished({:?})", outcome.ticket)
            }
            Interrupt::SetDemand(id, active) => write!(f, "SetDemand({id:?}, {active})"),
            Interrupt::ChangeTask(id, change) => {
                write!(f, "ChangeTask({id:?}, entry={:?})", change.entry.is_some())
            }
            Interrupt::Font(..) => write!(f, "Font(..)"),
            Interrupt::CreationTimestamp(ts) => write!(f, "CreationTimestamp({ts:?})"),
            Interrupt::Memory(..) => write!(f, "Memory(..)"),
            Interrupt::Fs(..) => write!(f, "Fs(..)"),
            Interrupt::Save(path) => write!(f, "Save({path:?})"),
        }
    }
}

/// A tagged memory event with logical tick.
struct TaggedMemoryEvent {
    /// The logical tick when the event is received.
    logical_tick: usize,
    /// The memory event happened.
    event: MemoryEvent,
}

/// The compiler server options.
pub struct CompileServerOpts<F: CompilerFeat, Ext> {
    /// The compilation handler.
    pub handler: Arc<dyn CompileHandler<F, Ext>>,
    /// Whether to ignoring the first fs sync event.
    pub ignore_first_sync: bool,
    /// Specifies the current export target.
    pub export_target: ExportTarget,
    /// Whether to run in syntax-only mode.
    pub syntax_only: bool,
}

impl<F: CompilerFeat + Send + Sync + 'static, Ext: 'static> Default for CompileServerOpts<F, Ext> {
    fn default() -> Self {
        Self {
            handler: Arc::new(std::marker::PhantomData),
            ignore_first_sync: false,
            syntax_only: false,
            export_target: ExportTarget::Paged,
        }
    }
}

/// The synchronous compiler that runs on one project or multiple projects.
pub struct ProjectCompiler<F: CompilerFeat, Ext> {
    /// The compilation handle.
    pub handler: Arc<dyn CompileHandler<F, Ext>>,
    /// Specifies the current export target.
    export_target: ExportTarget,
    /// Whether to run in syntax-only mode.
    syntax_only: bool,
    /// Channel for sending interrupts to the compiler actor.
    dep_tx: mpsc::UnboundedSender<NotifyMessage>,
    /// Whether to ignore the first sync event.
    pub ignore_first_sync: bool,

    /// The current logical tick.
    logical_tick: usize,
    /// Last logical tick when invalidation is caused by shadow update.
    dirty_shadow_logical_tick: usize,
    /// Estimated latest set of shadow files.
    estimated_shadow_files: HashSet<Arc<Path>>,

    /// The primary state.
    pub primary: ProjectInsState<F, Ext>,
    /// The states for dedicate tasks
    pub dedicates: Vec<ProjectInsState<F, Ext>>,
    /// The project file dependencies.
    deps: ProjectDeps,
}

impl<F: CompilerFeat + Send + Sync + 'static, Ext: Default + 'static> ProjectCompiler<F, Ext> {
    /// Creates a compiler with options
    pub fn new(
        verse: CompilerUniverse<F>,
        dep_tx: mpsc::UnboundedSender<NotifyMessage>,
        CompileServerOpts {
            handler,
            ignore_first_sync,
            export_target,
            syntax_only,
        }: CompileServerOpts<F, Ext>,
    ) -> Self {
        eviction::initialize_retention();
        let primary = ProjectInsState::new(
            ProjectInsId("primary".into()),
            verse,
            export_target,
            syntax_only,
            handler.clone(),
        );
        Self {
            handler,
            dep_tx,
            export_target,
            syntax_only,

            logical_tick: 1,
            dirty_shadow_logical_tick: 0,

            estimated_shadow_files: Default::default(),
            ignore_first_sync,

            primary,
            deps: Default::default(),
            dedicates: vec![],
        }
    }

    /// Creates a snapshot of the primary project.
    pub fn snapshot(&mut self) -> Arc<WorldComputeGraph<F>> {
        self.primary.snapshot()
    }

    /// Compiles the document once.
    pub fn compile_once(&mut self) -> CompiledArtifact<F> {
        let snap = self.primary.make_snapshot();
        ProjectInsState::run_compile(
            self.handler.clone(),
            snap,
            self.export_target,
            self.syntax_only,
        )()
    }

    /// Gets the iterator of all projects.
    pub fn projects(&mut self) -> impl Iterator<Item = &mut ProjectInsState<F, Ext>> {
        std::iter::once(&mut self.primary).chain(self.dedicates.iter_mut())
    }

    /// Find a project by id, but with less borrow checker restriction.
    pub fn find_project<'a>(
        primary: &'a mut ProjectInsState<F, Ext>,
        dedicates: &'a mut [ProjectInsState<F, Ext>],
        id: &ProjectInsId,
    ) -> &'a mut ProjectInsState<F, Ext> {
        if id == &primary.id {
            return primary;
        }

        dedicates.iter_mut().find(|e| e.id == *id).unwrap()
    }

    /// Clear all dedicate projects.
    pub fn clear_dedicates(&mut self) {
        self.dedicates.clear();
    }

    /// Restart a dedicate project.
    pub fn restart_dedicate(&mut self, group: &str, entry: EntryState) -> Result<ProjectInsId> {
        let id = ProjectInsId(group.into());

        let verse = CompilerUniverse::<F>::new_raw(
            entry,
            self.primary.verse.features.clone(),
            Some(self.primary.verse.inputs().clone()),
            self.primary.verse.vfs().fork(),
            self.primary.verse.registry.clone(),
            self.primary.verse.font_resolver.clone(),
            self.primary.verse.creation_timestamp,
        );

        let mut proj = ProjectInsState::new(
            id.clone(),
            verse,
            self.export_target,
            self.syntax_only,
            self.handler.clone(),
        );
        proj.reason.merge(reason_by_entry_change());

        self.remove_dedicates(&id);
        self.dedicates.push(proj);

        Ok(id)
    }

    fn remove_dedicates(&mut self, id: &ProjectInsId) {
        let proj = self.dedicates.iter().position(|e| e.id == *id);
        if let Some(idx) = proj {
            // Resets the handle state, e.g. notified revision
            self.handler.notify_removed(id);
            self.deps.project_deps.remove_mut(id);

            let _proj = self.dedicates.remove(idx);
            // todo: kill compilations

            let res = self
                .dep_tx
                .send(NotifyMessage::SyncDependency(Box::new(self.deps.clone())));
            log_send_error("dep_tx", res);
        } else {
            log::warn!("ProjectCompiler: settle project not found {id:?}");
        }
    }

    // Shared cache ages advance once per update when multiple demanded themes
    // compile. If the primary has no viewers, an active dedicated project owns
    // maintenance so dark-only preview sessions still have bounded caches.
    pub(super) fn cache_owner(&self) -> Option<&ProjectInsId> {
        std::iter::once(&self.primary)
            .chain(self.dedicates.iter())
            .find(|proj| proj.is_demanded() && !proj.verse.entry_state().is_inactive())
            .map(|proj| &proj.id)
    }

    /// Process an interrupt.
    pub fn process(&mut self, intr: Interrupt<F>) {
        self.process_inner(intr);
        for proj in self.projects() {
            proj.sync_compile_revision();
        }
        // Customized Project Compilation Handler
        self.handler.clone().on_any_compile_reason(self);
    }

    fn process_inner(&mut self, intr: Interrupt<F>) {
        match intr {
            Interrupt::Compile(id) => {
                let proj = Self::find_project(&mut self.primary, &mut self.dedicates, &id);
                // Increment the revision anyway.
                proj.verse.increment_revision(|verse| {
                    verse.flush();
                });

                proj.reason.merge(reason_by_entry_change());
            }
            Interrupt::CompileFinished(outcome) => {
                // Superseded running evaluations still allocate memoized data.
                // Maintain the shared cache even during continuous edits; work
                // discarded before execution must not advance cache ages.
                if outcome.executed
                    && self.cache_owner() == Some(&outcome.ticket.id)
                    && std::iter::once(&self.primary)
                        .chain(self.dedicates.iter())
                        .any(|proj| {
                            proj.id == outcome.ticket.id
                                && outcome.ticket.belongs_to(&proj.compile_generation)
                        })
                {
                    eviction::schedule();
                }
            }
            Interrupt::SetDemand(id, demanded) => {
                if let Some(proj) = self.projects().find(|proj| proj.id == id) {
                    proj.set_demand(demanded);
                }
            }
            Interrupt::Compiled(artifact) => {
                let maintains_shared_cache = self.cache_owner() == Some(artifact.id());
                let Some(proj) = std::iter::once(&mut self.primary)
                    .chain(self.dedicates.iter_mut())
                    .find(|proj| &proj.id == artifact.id())
                else {
                    return;
                };

                let processed = proj.process_compile(artifact, maintains_shared_cache);

                if processed {
                    self.deps
                        .project_deps
                        .insert_mut(proj.id.clone(), proj.deps.clone());

                    let event = NotifyMessage::SyncDependency(Box::new(self.deps.clone()));
                    let err = self.dep_tx.send(event);
                    log_send_error("dep_tx", err);
                }
            }
            Interrupt::Settle(id) => {
                self.remove_dedicates(&id);
            }
            Interrupt::ChangeTask(id, change) => {
                let proj = Self::find_project(&mut self.primary, &mut self.dedicates, &id);
                proj.verse.increment_revision(|verse| {
                    if let Some(inputs) = change.inputs.clone() {
                        verse.set_inputs(inputs);
                    }

                    if let Some(entry) = change.entry.clone() {
                        let res = verse.mutate_entry(entry);
                        if let Err(err) = res {
                            log::error!("ProjectCompiler: change entry error: {err:?}");
                        }
                    }
                });

                // After incrementing the revision
                if let Some(entry) = change.entry {
                    // todo: dedicate suspended
                    if entry.is_inactive() {
                        log::info!("ProjectCompiler: removing diag");
                        self.handler.status(proj.verse.revision.get(), {
                            CompileReport {
                                id: proj.id.clone(),
                                compiling_id: None,
                                page_count: 0,
                                status: CompileStatusEnum::Suspend,
                            }
                        });
                    }

                    // Forget the document state of previous entry.
                    proj.latest_success_doc = None;
                }

                proj.reason.merge(reason_by_entry_change());
            }

            Interrupt::Font(fonts) => {
                self.projects().for_each(|proj| {
                    let font_changed = proj.verse.increment_revision(|verse| {
                        verse.set_fonts(fonts.clone());
                        verse.font_changed()
                    });
                    if font_changed {
                        // todo: reason_by_font_change
                        proj.reason.merge(reason_by_entry_change());
                    }
                });
            }
            Interrupt::CreationTimestamp(creation_timestamp) => {
                self.projects().for_each(|proj| {
                    let timestamp_changed = proj.verse.increment_revision(|verse| {
                        verse.set_creation_timestamp(creation_timestamp);
                        // Creation timestamp changes affect compilation
                        verse.creation_timestamp_changed()
                    });
                    if timestamp_changed {
                        proj.reason.merge(reason_by_entry_change());
                    }
                });
            }
            Interrupt::Memory(event) => {
                log::debug!("ProjectCompiler: memory event incoming");

                // Emulate memory changes.
                let mut files = HashSet::new();
                if matches!(event, MemoryEvent::Sync(..)) {
                    std::mem::swap(&mut files, &mut self.estimated_shadow_files);
                }

                let (MemoryEvent::Sync(e) | MemoryEvent::Update(e)) = &event;
                for path in &e.removes {
                    self.estimated_shadow_files.remove(path);
                    files.insert(Arc::clone(path));
                }
                for (path, _) in &e.inserts {
                    self.estimated_shadow_files.insert(Arc::clone(path));
                    files.remove(path);
                }

                // If there is no invalidation happening, apply memory changes directly.
                if files.is_empty() && self.dirty_shadow_logical_tick == 0 {
                    let changes = std::iter::repeat_n(event, 1 + self.dedicates.len());
                    let proj = std::iter::once(&mut self.primary).chain(self.dedicates.iter_mut());
                    for (proj, event) in proj.zip(changes) {
                        log::debug!("memory update: vfs {:#?}", proj.verse.vfs().display());
                        let vfs_changed = proj.verse.increment_revision(|verse| {
                            log::debug!("memory update: {:?}", proj.id);
                            Self::apply_memory_changes(&mut verse.vfs(), event.clone());
                            log::debug!("memory update: changed {}", verse.vfs_changed());
                            verse.vfs_changed()
                        });
                        if vfs_changed {
                            proj.reason.merge(reason_by_mem());
                        }
                        log::debug!("memory update: vfs after {:#?}", proj.verse.vfs().display());
                    }
                    return;
                }

                // Otherwise, send upstream update event.
                // Also, record the logical tick when shadow is dirty.
                self.dirty_shadow_logical_tick = self.logical_tick;
                let event = NotifyMessage::UpstreamUpdate(UpstreamUpdateEvent {
                    invalidates: files.into_iter().collect(),
                    opaque: Box::new(TaggedMemoryEvent {
                        logical_tick: self.logical_tick,
                        event,
                    }),
                });
                let err = self.dep_tx.send(event);
                log_send_error("dep_tx", err);
            }
            Interrupt::Save(event) => {
                let changes = std::iter::repeat_n(&event, 1 + self.dedicates.len());
                let proj = std::iter::once(&mut self.primary).chain(self.dedicates.iter_mut());

                for (proj, saved_path) in proj.zip(changes) {
                    log::debug!(
                        "ProjectCompiler({}, rev={}): save changes",
                        proj.verse.revision.get(),
                        proj.id
                    );

                    // todo: only emit if saved_path is related
                    let _ = saved_path;

                    proj.reason.merge(reason_by_fs());
                }
            }
            Interrupt::Fs(event) => {
                log::debug!("ProjectCompiler: fs event incoming {event:?}");

                // Apply file system changes.
                let dirty_tick = &mut self.dirty_shadow_logical_tick;
                let (changes, is_sync, event) = event.split_with_is_sync();
                let changes = std::iter::repeat_n(changes, 1 + self.dedicates.len());
                let proj = std::iter::once(&mut self.primary).chain(self.dedicates.iter_mut());

                for (proj, changes) in proj.zip(changes) {
                    log::debug!(
                        "ProjectCompiler({}, rev={}): fs changes applying",
                        proj.verse.revision.get(),
                        proj.id
                    );

                    proj.verse.increment_revision(|verse| {
                        let mut vfs = verse.vfs();

                        // Handle delayed upstream update event before applying file system
                        // changes
                        if Self::apply_delayed_memory_changes(&mut vfs, dirty_tick, &event)
                            .is_none()
                        {
                            log::warn!("ProjectCompiler: unknown upstream update event");

                            // Actual a delayed memory event.
                            proj.reason.merge(reason_by_mem());
                        }
                        vfs.notify_fs_changes(changes);
                    });

                    log::debug!(
                        "ProjectCompiler({},rev={}): fs changes applied, {is_sync}",
                        proj.id,
                        proj.verse.revision.get(),
                    );

                    if !self.ignore_first_sync || !is_sync {
                        // A queued world may not have read this source yet, so
                        // VFS dependency tracking can leave its revision intact.
                        // The accepted input event still supersedes queued work.
                        proj.invalidate_compiles();
                        proj.cached_snapshot = None;
                        proj.reason.merge(reason_by_fs());
                    }
                }
            }
        }
    }

    /// Apply delayed memory changes to underlying compiler.
    fn apply_delayed_memory_changes(
        verse: &mut RevisingVfs<'_, F::AccessModel>,
        dirty_shadow_logical_tick: &mut usize,
        event: &Option<UpstreamUpdateEvent>,
    ) -> Option<()> {
        // Handle delayed upstream update event before applying file system changes
        if let Some(event) = event {
            let TaggedMemoryEvent {
                logical_tick,
                event,
            } = event.opaque.as_ref().downcast_ref()?;

            // Recovery from dirty shadow state.
            if logical_tick == dirty_shadow_logical_tick {
                *dirty_shadow_logical_tick = 0;
            }

            Self::apply_memory_changes(verse, event.clone());
        }

        Some(())
    }

    /// Apply memory changes to underlying compiler.
    fn apply_memory_changes(vfs: &mut RevisingVfs<'_, F::AccessModel>, event: MemoryEvent) {
        if matches!(event, MemoryEvent::Sync(..)) {
            vfs.reset_shadow();
        }
        match event {
            MemoryEvent::Update(event) | MemoryEvent::Sync(event) => {
                for path in event.removes {
                    let _ = vfs.unmap_shadow(&path);
                }
                for (path, snap) in event.inserts {
                    let _ = vfs.map_shadow(&path, snap);
                }
            }
        }
    }
}

#[inline]
fn log_send_error<T>(chan: &'static str, res: Result<(), mpsc::error::SendError<T>>) -> bool {
    res.map_err(|err| log::warn!("ProjectCompiler: send to {chan} error: {err}"))
        .is_ok()
}

#[derive(Debug, Clone, Default)]
struct ProjectDeps {
    project_deps: rpds::RedBlackTreeMapSync<ProjectInsId, EcoVec<ImmutPath>>,
}

impl NotifyDeps for ProjectDeps {
    fn dependencies(&self, f: &mut dyn FnMut(&ImmutPath)) {
        for deps in self.project_deps.values().flat_map(|e| e.iter()) {
            f(deps);
        }
    }
}
