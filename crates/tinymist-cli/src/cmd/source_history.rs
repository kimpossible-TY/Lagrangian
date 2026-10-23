//! Bounded transport for the shared project source-history owner.

use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use anyhow::Result;
use serde::{Deserialize, Serialize};
use tinymist_project::source_history::{
    MAX_SOURCE_BYTES, MAX_SOURCES, SourceFile, SourceHistoryStore,
};

// JSON escaping can expand a bounded 2 MiB source snapshot six-fold.
const MAX_REQUEST_BYTES: u64 = 16 * 1024 * 1024;

/// Observe disk edits and register newly accepted source baselines.
#[derive(Debug, Clone, clap::Parser)]
pub struct SourceHistoryArgs {
    /// Absolute workspace root.
    #[clap(long)]
    root: PathBuf,
    /// Entry document, relative to the workspace root or absolute.
    #[clap(long, default_value = "main.typ")]
    entry: PathBuf,
    /// Existing shared record; otherwise use the deterministic project path.
    #[clap(long)]
    change_file: Option<PathBuf>,
    /// Resolve the record path without observing sources or writing a record.
    #[clap(long)]
    path_only: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    #[serde(default)]
    sources: Vec<Snapshot>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Snapshot {
    filepath: PathBuf,
    text: String,
}

#[derive(Serialize)]
struct Response<'a> {
    path: &'a Path,
    #[serde(skip_serializing_if = "Option::is_none")]
    sequence: Option<u64>,
}

fn read_request(reader: impl Read) -> Result<Request> {
    let mut bytes = Vec::new();
    reader.take(MAX_REQUEST_BYTES + 1).read_to_end(&mut bytes)?;
    anyhow::ensure!(
        bytes.len() as u64 <= MAX_REQUEST_BYTES,
        "source-history request is oversized"
    );
    let request: Request = serde_json::from_slice(&bytes)?;
    anyhow::ensure!(
        request.sources.len() <= MAX_SOURCES,
        "too many source-history inputs"
    );
    anyhow::ensure!(
        request
            .sources
            .iter()
            .map(|source| source.text.len())
            .sum::<usize>()
            <= MAX_SOURCE_BYTES,
        "source-history inputs exceed the source budget"
    );
    Ok(request)
}

/// Run one serialized source-only transaction. No compiler is started.
pub fn source_history_main(args: &SourceHistoryArgs) -> Result<()> {
    let root = args.root.canonicalize()?;
    let entry = root.join(&args.entry).canonicalize()?;
    anyhow::ensure!(
        root.is_dir() && entry.is_file() && entry.starts_with(&root),
        "entry must be a source file inside the project root"
    );
    if args.path_only {
        let path = args.change_file.clone().map_or_else(
            || tinymist_project::source_history::default_path(&root, &entry),
            Ok,
        )?;
        anyhow::ensure!(path.is_absolute(), "source history path must be absolute");
        return respond(&path, None);
    }
    let request = read_request(std::io::stdin().lock())?;
    let mut files = Vec::with_capacity(request.sources.len());
    for source in request.sources {
        anyhow::ensure!(
            source.filepath.is_absolute(),
            "source path must be absolute"
        );
        let filepath = source.filepath.canonicalize()?;
        anyhow::ensure!(
            filepath.starts_with(&root),
            "source must be a project-local file"
        );
        let mut saved = Vec::new();
        std::fs::File::open(&filepath)?
            .take(MAX_SOURCE_BYTES as u64 + 1)
            .read_to_end(&mut saved)?;
        anyhow::ensure!(
            saved == source.text.as_bytes(),
            "accepted source snapshot is stale"
        );
        files.push(SourceFile {
            filepath,
            text: source.text,
        });
    }
    let store = SourceHistoryStore::open(&root, &entry, args.change_file.clone())?;
    let sequence = store.observe(files)?;
    respond(store.path(), Some(sequence))
}

fn respond(path: &Path, sequence: Option<u64>) -> Result<()> {
    let mut stdout = std::io::stdout().lock();
    serde_json::to_writer(&mut stdout, &Response { path, sequence })?;
    writeln!(stdout)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_contract_rejects_unknown_invalid_and_oversized_inputs() {
        assert!(read_request(br#"{"sources":[]}"#.as_slice()).is_ok());
        for bytes in [
            br#"null"#.as_slice(),
            br#"{"variants":{}}"#,
            br#"{"sources":[{}]}"#,
        ] {
            assert!(read_request(bytes).is_err());
        }
        let oversized = "x".repeat(MAX_SOURCE_BYTES + 1);
        let request = serde_json::json!({"sources":[{"filepath":"/main.typ","text":oversized}]});
        assert!(read_request(request.to_string().as_bytes()).is_err());
        assert!(read_request(std::io::repeat(b' ').take(MAX_REQUEST_BYTES + 1)).is_err());
    }
}
