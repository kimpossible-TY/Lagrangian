//! Worker preparation, safe cancellation boundaries and CPU execution.

use std::sync::atomic::AtomicUsize;
use std::sync::{Arc, OnceLock};

use tinymist_task::ExportTarget;
use tinymist_world::{
    BundleCompilationTask, CompilerFeat, DiagnosticsTask, EntryReader, WorldComputeGraph,
};
use typst::World;
use typst::diag::At;
use typst::syntax::Span;

use super::report::log_compile_report;
use super::{
    CompileHandler, CompileOutcome, CompileReport, CompileStatusEnum, CompileStatusResult,
    CompileTicket, CompiledArtifact, FILE_MISSING_ERROR_MSG, ProjectInsState,
};

impl<F: CompilerFeat, Ext: 'static> ProjectInsState<F, Ext> {
    /// Compile the document once, preserving the synchronous API.
    pub(super) fn run_compile(
        h: Arc<dyn CompileHandler<F, Ext>>,
        graph: Arc<WorldComputeGraph<F>>,
        export_target: ExportTarget,
        syntax_only: bool,
    ) -> impl FnOnce() -> CompiledArtifact<F> {
        let work = Self::prepare_compile(h.clone(), graph, export_target, syntax_only, None);
        move || {
            let outcome = work();
            let compiled = outcome.artifact.expect("unconditional compilation");
            if !compiled
                .diagnostics()
                .any(|d| d.message == FILE_MISSING_ERROR_MSG)
            {
                h.status(compiled.world().revision().get(), outcome.report.unwrap());
                h.notify_compile(&compiled);
            }
            compiled
        }
    }

    pub(super) fn prepare_compile(
        h: Arc<dyn CompileHandler<F, Ext>>,
        graph: Arc<WorldComputeGraph<F>>,
        export_target: ExportTarget,
        syntax_only: bool,
        ticket: Option<CompileTicket>,
    ) -> impl FnOnce() -> CompileOutcome<F> {
        let queued_at = tinymist_std::time::Instant::now();
        let id = graph.world().main_id().unwrap();
        let revision = graph.world().revision().get();
        let project = graph.snap.id.clone();
        let guarded = ticket.is_some();
        let ticket = ticket.unwrap_or_else(|| {
            CompileTicket::new(project.clone(), revision, Arc::new(AtomicUsize::new(1)))
        });
        h.status(
            revision,
            CompileReport {
                id: project.clone(),
                compiling_id: Some(id),
                page_count: 0,
                status: CompileStatusEnum::Compiling,
            },
        );

        move || {
            let started_at = tinymist_std::time::Instant::now();
            let queued = queued_at.elapsed();
            if !ticket.is_current() {
                log::info!(
                    "compile timing project={project:?} revision={revision} outcome=discarded-before-start queue={queued:?}"
                );
                return CompileOutcome::discarded(ticket, false);
            }
            let _qos = tinymist_std::performance::QosGuard::enter(
                tinymist_std::performance::WorkClass::Interactive,
            );
            let memory_start = tinymist_std::performance::MemorySnapshot::capture();
            // Typst has no safe mid-evaluation cancellation API. Check only at
            // phase boundaries, and let an already running evaluation finish.
            let (doc, syntax_diagnostics) = if syntax_only {
                let main = graph.snap.world.main();
                let source_res = graph.world().source(main).at(Span::detached());
                let syntax_res = source_res.and_then(|source| {
                    let errors = source.root().errors_and_warnings().0;
                    if errors.is_empty() {
                        Ok(())
                    } else {
                        Err(errors.into_iter().map(|s| s.into()).collect())
                    }
                });
                (None, Some(DiagnosticsTask::from_errors(syntax_res.err())))
            } else {
                let doc = match export_target {
                    ExportTarget::Bundle => {
                        let _ = graph
                            .compute::<BundleCompilationTask>()
                            .expect("bundle compilation");
                        None
                    }
                    ExportTarget::Html => {
                        graph.shared_compile_html().expect("html").map(From::from)
                    }
                    ExportTarget::Paged => graph.shared_compile().expect("paged").map(From::from),
                };
                (doc, None)
            };
            let execution = started_at.elapsed();
            if !ticket.is_current() {
                log::info!(
                    "compile timing project={project:?} revision={revision} outcome=discarded-after-execution queue={queued:?} execution={execution:?} total={:?}",
                    queued_at.elapsed()
                );
                return CompileOutcome::discarded(ticket, true);
            }
            let diagnostics_at = tinymist_std::time::Instant::now();
            let diag = syntax_diagnostics
                .map(Arc::new)
                .unwrap_or_else(|| graph.shared_diagnostics().expect("diag"));
            let compiled = CompiledArtifact {
                diag,
                graph,
                doc,
                deps: OnceLock::default(),
                ticket: guarded.then(|| ticket.clone()),
            };
            let res = CompileStatusResult {
                diag: (compiled.warning_cnt() + compiled.error_cnt()) as u32,
                elapsed: queued_at.elapsed(),
            };
            let rep = CompileReport {
                id: project.clone(),
                compiling_id: Some(id),
                page_count: compiled.doc.as_ref().map_or(0, |doc| doc.num_of_pages()),
                status: if compiled.doc.is_some() || res.diag == 0 {
                    CompileStatusEnum::CompileSuccess(res)
                } else {
                    CompileStatusEnum::CompileError(res)
                },
            };
            let diagnostics = diagnostics_at.elapsed();
            log::info!(
                "compile timing project={project:?} revision={revision} outcome=finished queue={queued:?} execution={execution:?} diagnostics={diagnostics:?} total={:?}",
                queued_at.elapsed()
            );
            let memory_end = tinymist_std::performance::MemorySnapshot::capture();
            log::info!(
                "compile memory project={project:?} revision={revision} before={memory_start:?} after={memory_end:?}"
            );
            log_compile_report(&rep);
            CompileOutcome {
                ticket,
                executed: true,
                artifact: Some(compiled),
                report: Some(rep),
            }
        }
    }
}

// todo: move me to tinymist-std
#[cfg(not(target_arch = "wasm32"))]
/// Spawns a CPU thread to run a computing-heavy task.
pub fn spawn_cpu<F>(func: F)
where
    F: FnOnce() + Send + 'static,
{
    rayon::spawn(func);
}

#[cfg(target_arch = "wasm32")]
/// Spawns a CPU thread to run a computing-heavy task.
pub fn spawn_cpu<F>(func: F)
where
    F: FnOnce() + Send + 'static,
{
    func();
}
