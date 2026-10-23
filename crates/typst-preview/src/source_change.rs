//! Compatibility aliases for renderer-independent project source edits.

pub(crate) use tinymist_project::source_history::source_hash;
pub use tinymist_project::source_history::{
    SourceEdit as PreviewSourceEdit, SourceFile as PreviewSourceFile,
};
