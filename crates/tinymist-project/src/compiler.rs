//! Project compiler for tinymist.
//!
//! The coordinator applies runtime inputs before notifying the compile handler.
//! Each instance owns its world and accepted state; execution owns worker phase
//! boundaries. Artifacts, reports, scheduling guards and cache maintenance retain
//! their separate contracts behind this module's public reexports.

use ecow::EcoString;
use tinymist_world::CompileSignal;
use typst::diag::FileError;

mod artifact;
mod coordinator;
mod eviction;
mod execution;
mod instance;
mod report;
mod scheduling;

pub use artifact::CompiledArtifact;
pub use coordinator::{CompileHandler, CompileServerOpts, Interrupt, ProjectCompiler};
pub use execution::spawn_cpu;
pub use instance::ProjectInsState;
pub use report::{CompileReport, CompileReportMsg, CompileStatusEnum, CompileStatusResult};
pub use scheduling::{CompileOutcome, CompileTicket};

const FILE_MISSING_ERROR_MSG: EcoString = EcoString::inline("t-file-missing");
/// The file missing error constant.
pub const FILE_MISSING_ERROR: FileError = FileError::Other(Some(FILE_MISSING_ERROR_MSG));

fn no_reason() -> CompileSignal {
    CompileSignal::default()
}

fn reason_by_mem() -> CompileSignal {
    CompileSignal {
        by_mem_events: true,
        ..CompileSignal::default()
    }
}

fn reason_by_fs() -> CompileSignal {
    CompileSignal {
        by_fs_events: true,
        ..CompileSignal::default()
    }
}

fn reason_by_entry_change() -> CompileSignal {
    CompileSignal {
        by_entry_update: true,
        ..CompileSignal::default()
    }
}

#[cfg(test)]
mod tests;
