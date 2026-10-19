//! Compiler regression suites and shared private test support.

use super::*;

use std::path::PathBuf;

use tinymist_std::typst::TypstDocument;
use tinymist_world::{
    EntryReader, ProjectInsId,
    mock::{MockCompilerFeat, MockWorkspaceWorldExt},
    vfs::{
        FileChangeSet, FileSnapshot, FilesystemEvent, FsProvider,
        mock::{MockChange, MockWorkspace},
        notify::{NotifyMessage, UpstreamUpdateEvent},
    },
};
use tokio::sync::mpsc;
use typst::{
    World,
    diag::{FileError, FileResult},
    foundations::Bytes,
};

use crate::mock::{MockProjectBuilderExt, MockProjectChangeExt, MockProjectCompiler};

mod cache;
mod filesystem;
mod lifecycle;
mod support;

use support::*;

const MAIN: &str = "main.typ";
const DEP: &str = "dep.typ";
const RENAMED_DEP: &str = "renamed.typ";
const UNRELATED: &str = "notes.typ";
