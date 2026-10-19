//! Compilation status and user-facing status messages.

use core::fmt;

use tinymist_world::ProjectInsId;
use tinymist_world::vfs::{FileId, WorkspaceResolver};

/// The compilation status of a project.
#[derive(Debug, Clone)]
pub struct CompileReport {
    /// The project ID.
    pub id: ProjectInsId,
    /// The file getting compiled.
    pub compiling_id: Option<FileId>,
    /// The number of pages in the compiled document, zero if failed.
    pub page_count: u32,
    /// The status of the compilation.
    pub status: CompileStatusEnum,
}

/// The compilation status of a project.
#[derive(Debug, Clone)]
pub enum CompileStatusEnum {
    /// The project is suspended.
    Suspend,
    /// The project is compiling.
    Compiling,
    /// The project compiled successfully.
    CompileSuccess(CompileStatusResult),
    /// The project failed to compile.
    CompileError(CompileStatusResult),
    /// The project failed to export.
    ExportError(CompileStatusResult),
}

/// The compilation status result of a project.
#[derive(Debug, Clone)]
pub struct CompileStatusResult {
    /// The number of errors or warnings occur.
    pub(super) diag: u32,
    /// Used time
    pub(super) elapsed: tinymist_std::time::Duration,
}

impl CompileReport {
    /// Gets the status message.
    pub fn message(&self) -> CompileReportMsg<'_> {
        CompileReportMsg(self)
    }
}

/// A message of the compilation status.
pub struct CompileReportMsg<'a>(&'a CompileReport);

impl fmt::Display for CompileReportMsg<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        use CompileStatusEnum::*;
        use CompileStatusResult as Res;

        let input = WorkspaceResolver::display(self.0.compiling_id);
        let (stage, Res { diag, elapsed }) = match &self.0.status {
            Suspend => return f.write_str("suspended"),
            Compiling => return f.write_str("compiling"),
            CompileSuccess(Res { diag: 0, elapsed }) => {
                return write!(f, "{input:?}: compilation succeeded in {elapsed:?}");
            }
            CompileSuccess(res) => ("compilation succeeded", res),
            CompileError(res) => ("compilation failed", res),
            ExportError(res) => ("export failed", res),
        };
        write!(
            f,
            "{input:?}: {stage} with {diag} warnings and errors in {elapsed:?}"
        )
    }
}

pub(super) fn log_compile_report(rep: &CompileReport) {
    log::info!("{}", rep.message());
}
