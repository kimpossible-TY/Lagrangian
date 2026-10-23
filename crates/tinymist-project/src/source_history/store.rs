//! Serialized transactions for the existing project change record.

use std::collections::BTreeMap;
use std::fs::{File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::{SourceFile, SourceHistory};

/// Maximum size of the shared source history and renderer metadata record.
pub const MAX_RECORD_BYTES: u64 = 16 * 1024 * 1024;
const SCHEMA_VERSION: u32 = 2;

#[derive(Serialize, Deserialize)]
struct Record {
    schema_version: u32,
    project: String,
    #[serde(default)]
    variants: BTreeMap<String, Value>,
    #[serde(default)]
    source_history: SourceHistory,
}

/// Project source history with renderer-owned metadata preserved in every write.
///
/// A sibling file lock serializes complete read/modify/write transactions across
/// processes. No in-memory record is authoritative after a transaction ends.
#[derive(Clone)]
pub struct SourceHistoryStore {
    path: PathBuf,
    project: String,
    strict_identity: bool,
}

fn identity(root: &Path, entry: &Path) -> io::Result<String> {
    let root = root.canonicalize()?;
    let entry = root.join(entry).canonicalize()?;
    if !root.is_dir() || !entry.is_file() || !entry.starts_with(&root) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "source history requires an entry file inside the project root",
        ));
    }
    Ok(serde_json::to_string(&(root, entry))?)
}

fn path_for_project(project: &str) -> io::Result<PathBuf> {
    let support = match std::env::var_os("FLOW_DATA_DIR") {
        Some(path) => PathBuf::from(path),
        None => dirs::data_dir()
            .ok_or_else(|| io::Error::other("missing application data directory"))?
            .join("tinymist-flow"),
    };
    let support = if support.is_absolute() {
        support
    } else {
        std::env::current_dir()?.join(support)
    };
    path_for_project_at(project, &support)
}

fn resolved_profile_path(path: &Path) -> io::Result<PathBuf> {
    let absolute = std::path::absolute(path)?;
    match absolute.canonicalize() {
        Ok(path) => Ok(path),
        // A removed, unrelated profile must not prevent another project's use.
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            Ok(tinymist_std::path::clean(absolute))
        }
        Err(error) => Err(error),
    }
}

fn path_for_project_at(project: &str, support: &Path) -> io::Result<PathBuf> {
    #[derive(Deserialize)]
    struct Settings {
        #[serde(rename = "schemaVersion")]
        schema_version: u32,
        profiles: Vec<Profile>,
    }
    #[derive(Deserialize)]
    struct Profile {
        id: String,
        root: PathBuf,
        entry: PathBuf,
    }
    let read = || -> io::Result<Settings> {
        let mut bytes = Vec::new();
        File::open(support.join("profiles.json"))?
            .take(MAX_RECORD_BYTES + 1)
            .read_to_end(&mut bytes)?;
        if bytes.len() as u64 > MAX_RECORD_BYTES {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Flow profiles are oversized",
            ));
        }
        Ok(serde_json::from_slice(&bytes)?)
    };
    match read() {
        Ok(settings) => {
            if settings.schema_version != 1 {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "invalid Flow profiles schema",
                ));
            }
            let (root, entry): (PathBuf, PathBuf) = serde_json::from_str(project)?;
            let mut matched = None;
            for profile in settings.profiles {
                let profile_root = resolved_profile_path(&profile.root)?;
                let profile_entry = resolved_profile_path(&profile_root.join(&profile.entry))?;
                if profile_root != root || profile_entry != entry {
                    continue;
                }
                let id = profile.id.as_bytes();
                let valid = !id.is_empty()
                    && id.len() <= 64
                    && (id[0].is_ascii_lowercase() || id[0].is_ascii_digit())
                    && id.iter().all(|byte| {
                        byte.is_ascii_lowercase() || byte.is_ascii_digit() || *byte == b'-'
                    });
                if !valid {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "invalid Flow profile ID",
                    ));
                }
                if matched.is_some() {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "ambiguous Flow project profiles",
                    ));
                }
                matched = Some(support.join("changes").join(format!("{}.json", profile.id)));
            }
            if let Some(path) = matched {
                return Ok(path);
            }
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }
    Ok(support
        .join("changes")
        .join(format!("project-{}.json", super::source_hash(project))))
}

/// Resolve an exact Flow profile's record, or the canonical project's default path.
pub fn default_path(root: &Path, entry: &Path) -> io::Result<PathBuf> {
    path_for_project(&identity(root, entry)?)
}

impl SourceHistoryStore {
    /// Open one canonical local project, using the shared default unless overridden.
    /// A foreign project record is rejected without being overwritten.
    pub fn open(root: &Path, entry: &Path, path: Option<PathBuf>) -> io::Result<Self> {
        let project = identity(root, entry)?;
        let path = path.map_or_else(|| path_for_project(&project), Ok)?;
        let mut store = Self::for_project(path, project)?;
        store.strict_identity = true;
        Ok(store)
    }

    /// Open a legacy preview identity without changing its public input contract.
    /// Invalid or foreign legacy records establish an empty baseline as before.
    pub fn for_project(path: PathBuf, project: String) -> io::Result<Self> {
        if !path.is_absolute() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "source history path must be absolute",
            ));
        }
        let parent = path
            .parent()
            .ok_or_else(|| io::Error::other("missing source history directory"))?;
        std::fs::create_dir_all(parent)?;
        let path = match path.canonicalize() {
            Ok(path) => path,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                if std::fs::symlink_metadata(&path)
                    .is_ok_and(|metadata| metadata.file_type().is_symlink())
                {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidInput,
                        "source history symlink must have an existing target",
                    ));
                }
                parent.canonicalize()?.join(
                    path.file_name()
                        .ok_or_else(|| io::Error::other("missing source history filename"))?,
                )
            }
            Err(error) => return Err(error),
        };
        Ok(Self {
            path,
            project,
            strict_identity: false,
        })
    }

    /// Absolute record path shared by the readers and editor restoration.
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Serialized canonical project identity stored in the record.
    pub fn project(&self) -> &str {
        &self.project
    }

    /// Observe saved changes, then seed only newly discovered source snapshots.
    pub fn observe(&self, files: Vec<SourceFile>) -> io::Result<u64> {
        self.transaction(|history, _| {
            history.seed(files);
            Ok(history.sequence)
        })
    }

    /// Run one serialized transaction after observing edits to retained sources.
    ///
    /// Renderer metadata belongs to its adapter. This store preserves its JSON
    /// payload while enforcing the shared record's identity and byte budget.
    pub fn transaction<R>(
        &self,
        operation: impl FnOnce(&mut SourceHistory, &mut BTreeMap<String, Value>) -> io::Result<R>,
    ) -> io::Result<R> {
        let mut lock_path = self.path.as_os_str().to_os_string();
        lock_path.push(".lock");
        let mut options = OpenOptions::new();
        options.read(true).write(true).create(true).truncate(false);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let lock = options.open(PathBuf::from(lock_path))?;
        lock.lock()?;
        let (mut record, reset) = self.load()?;
        let before = serde_json::to_vec(&record)?;
        record.source_history.observe_disk();
        let result = operation(&mut record.source_history, &mut record.variants)?;
        if !record.source_history.valid() {
            return Err(io::Error::other("invalid source history transaction"));
        }
        let after = serde_json::to_vec(&record)?;
        if reset || after != before {
            self.write(&after)?;
        }
        Ok(result)
    }

    fn empty(&self) -> Record {
        Record {
            schema_version: SCHEMA_VERSION,
            project: self.project.clone(),
            variants: BTreeMap::new(),
            source_history: SourceHistory::default(),
        }
    }

    fn load(&self) -> io::Result<(Record, bool)> {
        let read = || -> io::Result<Value> {
            let mut bytes = Vec::new();
            File::open(&self.path)?
                .take(MAX_RECORD_BYTES + 1)
                .read_to_end(&mut bytes)?;
            if bytes.len() as u64 > MAX_RECORD_BYTES {
                return Err(io::Error::other("source history record is oversized"));
            }
            Ok(serde_json::from_slice(&bytes)?)
        };
        let value = match read() {
            Ok(value) => value,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                return Ok((self.empty(), true));
            }
            Err(error) => {
                log::warn!("Ignoring invalid project source history: {error}");
                return Ok((self.empty(), true));
            }
        };
        if self.strict_identity
            && value
                .get("project")
                .and_then(Value::as_str)
                .is_some_and(|project| project != self.project)
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "source history belongs to another project",
            ));
        }
        match serde_json::from_value::<Record>(value) {
            Ok(record)
                if record.schema_version == SCHEMA_VERSION
                    && record.project == self.project
                    && record.source_history.valid() =>
            {
                Ok((record, false))
            }
            Ok(_) => Ok((self.empty(), true)),
            Err(error) => {
                log::warn!("Ignoring invalid project source history: {error}");
                Ok((self.empty(), true))
            }
        }
    }

    fn write(&self, bytes: &[u8]) -> io::Result<()> {
        if bytes.len() as u64 >= MAX_RECORD_BYTES {
            return Err(io::Error::other("source history exceeds its byte budget"));
        }
        let temp = self.path.with_extension(format!(
            "{}.{}.tmp",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        ));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&temp)?;
        let result = (|| {
            file.write_all(bytes)?;
            file.write_all(b"\n")?;
            file.sync_all()?;
            std::fs::rename(&temp, &self.path)
        })();
        if result.is_err() {
            let _ = std::fs::remove_file(temp);
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use std::process::{Command, Stdio};
    use std::sync::{Arc, Barrier};

    use super::*;

    fn project() -> (tempfile::TempDir, PathBuf, PathBuf) {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().canonicalize().unwrap();
        let entry = root.join("main.typ");
        std::fs::write(&entry, "Original body").unwrap();
        (temp, root, entry)
    }

    fn source(path: &Path, text: &str) -> SourceFile {
        SourceFile {
            filepath: path.to_owned(),
            text: text.to_owned(),
        }
    }

    #[test]
    fn alternating_stores_preserve_source_edits_and_renderer_payloads() {
        let (_temp, root, entry) = project();
        let path = root.join("changes.json");
        let pdf = SourceHistoryStore::open(&root, &entry, Some(path.clone())).unwrap();
        let html =
            SourceHistoryStore::open(&root, Path::new("main.typ"), Some(path.clone())).unwrap();
        assert_eq!(pdf.project(), html.project());
        assert_eq!(
            pdf.observe(vec![source(&entry, "Original body")]).unwrap(),
            0
        );
        pdf.transaction(|_, variants| {
            variants.insert(
                "light".into(),
                serde_json::json!({"page_hashes": [1], "position": [1, 2, 3]}),
            );
            Ok(())
        })
        .unwrap();
        std::fs::write(&entry, "첫 변경 body").unwrap();
        assert_eq!(html.observe(vec![]).unwrap(), 1);
        pdf.transaction(|history, variants| {
            assert_eq!(history.sequence, 1);
            assert_eq!(history.latest.as_ref().unwrap().filepath, entry);
            assert_eq!(variants["light"]["position"], serde_json::json!([1, 2, 3]));
            variants.insert("dark".into(), serde_json::json!({"private": true}));
            Ok(())
        })
        .unwrap();
        let restarted = SourceHistoryStore::open(&root, &entry, Some(path)).unwrap();
        restarted
            .transaction(|history, variants| {
                assert_eq!(history.sequence, 1);
                assert_eq!(variants.len(), 2);
                assert_eq!(variants["dark"]["private"], true);
                Ok(())
            })
            .unwrap();
    }

    #[test]
    fn simultaneous_writers_reload_after_acquiring_the_file_lock() {
        let (_temp, root, entry) = project();
        let path = root.join("changes.json");
        let barrier = Arc::new(Barrier::new(2));
        let writers: Vec<_> = ["light", "dark"]
            .into_iter()
            .map(|variant| {
                let store = SourceHistoryStore::open(&root, &entry, Some(path.clone())).unwrap();
                let barrier = barrier.clone();
                std::thread::spawn(move || {
                    barrier.wait();
                    for _ in 0..20 {
                        store
                            .transaction(|_, variants| {
                                let next =
                                    variants.get(variant).and_then(Value::as_u64).unwrap_or(0) + 1;
                                variants.insert(variant.into(), Value::from(next));
                                Ok(())
                            })
                            .unwrap();
                    }
                })
            })
            .collect();
        for writer in writers {
            writer.join().unwrap();
        }
        let store = SourceHistoryStore::open(&root, &entry, Some(path)).unwrap();
        store
            .transaction(|_, variants| {
                assert_eq!(variants["light"], 20);
                assert_eq!(variants["dark"], 20);
                Ok(())
            })
            .unwrap();
    }

    #[test]
    fn separate_processes_preserve_both_writers() {
        let (_temp, root, entry) = project();
        let children = ["light", "dark"].map(|variant| {
            Command::new(std::env::current_exe().unwrap())
                .arg("--exact")
                .arg("source_history::store::tests::process_writer")
                .env("TINYMIST_SOURCE_HISTORY_TEST_ROOT", &root)
                .env("TINYMIST_SOURCE_HISTORY_TEST_VARIANT", variant)
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .unwrap()
        });
        for child in children {
            let result = child.wait_with_output().unwrap();
            let stdout = String::from_utf8_lossy(&result.stdout);
            assert!(
                result.status.success(),
                "{}{}",
                stdout,
                String::from_utf8_lossy(&result.stderr)
            );
            assert!(stdout.contains("running 1 test"), "{stdout}");
            assert!(stdout.contains("1 passed; 0 failed"), "{stdout}");
        }
        let store =
            SourceHistoryStore::open(&root, &entry, Some(root.join("changes.json"))).unwrap();
        store
            .transaction(|_, variants| {
                assert_eq!(variants["light"], 20);
                assert_eq!(variants["dark"], 20);
                Ok(())
            })
            .unwrap();
    }

    #[test]
    fn process_writer() {
        let Some(root) = std::env::var_os("TINYMIST_SOURCE_HISTORY_TEST_ROOT") else {
            return;
        };
        let root = PathBuf::from(root);
        let variant = std::env::var("TINYMIST_SOURCE_HISTORY_TEST_VARIANT").unwrap();
        let store = SourceHistoryStore::open(
            &root,
            Path::new("main.typ"),
            Some(root.join("changes.json")),
        )
        .unwrap();
        for _ in 0..20 {
            store
                .transaction(|_, variants| {
                    let next = variants.get(&variant).and_then(Value::as_u64).unwrap_or(0) + 1;
                    variants.insert(variant.clone(), Value::from(next));
                    Ok(())
                })
                .unwrap();
        }
    }

    #[test]
    fn comments_deletions_and_stale_snapshots_preserve_utf8_history() {
        let (_temp, root, entry) = project();
        let path = root.join("changes.json");
        let store = SourceHistoryStore::open(&root, &entry, Some(path.clone())).unwrap();
        let original = "// Comment\n첫 문장\n";
        std::fs::write(&entry, original).unwrap();
        store.observe(vec![source(&entry, original)]).unwrap();
        std::fs::write(&entry, "// Comment\n첫 변경\n").unwrap();
        assert_eq!(store.observe(vec![]).unwrap(), 1);
        let commented = "// Longer comment\n첫 변경\n";
        std::fs::write(&entry, commented).unwrap();
        assert_eq!(store.observe(vec![]).unwrap(), 1);
        store
            .transaction(|history, _| {
                let edit = history.latest.as_ref().unwrap();
                assert_eq!(&commented[edit.range.clone()], "변경");
                Ok(())
            })
            .unwrap();
        let deleted = "// Longer comment\n첫 \n";
        std::fs::write(&entry, deleted).unwrap();
        let restarted = SourceHistoryStore::open(&root, &entry, Some(path)).unwrap();
        assert_eq!(
            restarted.observe(vec![source(&entry, original)]).unwrap(),
            2
        );
        restarted
            .transaction(|history, _| {
                let edit = history.latest.as_ref().unwrap();
                assert!(deleted.is_char_boundary(edit.range.start));
                assert!(deleted.is_char_boundary(edit.range.end));
                assert_eq!(edit.source_hash, super::super::source_hash(deleted));
                assert!(history.valid());
                Ok(())
            })
            .unwrap();
        assert_eq!(store.observe(vec![]).unwrap(), 2);
    }

    #[test]
    fn foreign_project_and_outside_entry_are_rejected_without_rewriting() {
        let (_temp, root, entry) = project();
        let path = root.join("changes.json");
        let bytes = br#"{"schema_version":2,"project":"foreign","variants":{}}"#;
        std::fs::write(&path, bytes).unwrap();
        let store = SourceHistoryStore::open(&root, &entry, Some(path.clone())).unwrap();
        assert!(store.observe(vec![]).is_err());
        assert_eq!(std::fs::read(path).unwrap(), bytes);
        let other = tempfile::NamedTempFile::new().unwrap();
        assert!(SourceHistoryStore::open(&root, other.path(), None).is_err());
    }

    #[test]
    fn canonical_identity_produces_one_default_path() {
        let (_temp, root, entry) = project();
        let support = root.join("data");
        assert_eq!(
            path_for_project_at(&identity(&root, &entry).unwrap(), &support).unwrap(),
            path_for_project_at(&identity(&root, Path::new("./main.typ")).unwrap(), &support)
                .unwrap()
        );
        let other = root.join("other.typ");
        std::fs::write(&other, "Other").unwrap();
        assert_ne!(
            path_for_project_at(&identity(&root, &entry).unwrap(), &support).unwrap(),
            path_for_project_at(&identity(&root, &other).unwrap(), &support).unwrap()
        );
    }

    #[test]
    fn first_observation_publishes_an_empty_baseline_before_compilation() {
        let (_temp, root, entry) = project();
        let path = root.join("changes.json");
        let store = SourceHistoryStore::open(&root, &entry, Some(path.clone())).unwrap();
        assert!(!path.exists());
        assert_eq!(store.observe(vec![]).unwrap(), 0);
        let record: Value = serde_json::from_reader(File::open(path).unwrap()).unwrap();
        assert_eq!(record["source_history"]["sequence"], 0);
        assert!(record["source_history"]["latest"].is_null());
    }

    #[cfg(unix)]
    #[test]
    fn symlink_aliases_share_the_record_and_preserve_the_link_during_writes() {
        let (_temp, root, entry) = project();
        let path = root.join("changes.json");
        let canonical = SourceHistoryStore::open(&root, &entry, Some(path.clone())).unwrap();
        canonical
            .observe(vec![source(&entry, "Original body")])
            .unwrap();
        let alias = root.join("alias.json");
        std::os::unix::fs::symlink(&path, &alias).unwrap();
        let linked = SourceHistoryStore::open(&root, &entry, Some(alias.clone())).unwrap();
        assert_eq!(canonical.path(), linked.path());
        std::fs::write(&entry, "Updated body").unwrap();
        assert_eq!(linked.observe(vec![]).unwrap(), 1);
        canonical
            .transaction(|history, variants| {
                assert_eq!(history.sequence, 1);
                variants.insert("light".into(), Value::from(7));
                Ok(())
            })
            .unwrap();
        linked
            .transaction(|history, variants| {
                assert_eq!(history.sequence, 1);
                assert_eq!(variants["light"], 7);
                Ok(())
            })
            .unwrap();
        assert_eq!(std::fs::read_link(&alias).unwrap(), path);
        assert_eq!(
            std::fs::read(&alias).unwrap(),
            std::fs::read(&path).unwrap()
        );
        assert!(!root.join("alias.json.lock").exists());
        assert!(root.join("changes.json.lock").is_file());
        let dangling = root.join("dangling.json");
        std::os::unix::fs::symlink(root.join("missing.json"), &dangling).unwrap();
        assert!(SourceHistoryStore::open(&root, &entry, Some(dangling.clone())).is_err());
        assert!(
            std::fs::symlink_metadata(dangling)
                .unwrap()
                .file_type()
                .is_symlink()
        );
    }

    #[cfg(unix)]
    #[test]
    fn new_records_resolve_parent_directory_aliases_before_deriving_the_lock() {
        let (_temp, root, entry) = project();
        let directory = root.join("records");
        std::fs::create_dir(&directory).unwrap();
        let alias = root.join("records-alias");
        std::os::unix::fs::symlink(&directory, &alias).unwrap();
        let canonical =
            SourceHistoryStore::open(&root, &entry, Some(directory.join("new.json"))).unwrap();
        let linked = SourceHistoryStore::open(&root, &entry, Some(alias.join("new.json"))).unwrap();
        assert_eq!(canonical.path(), linked.path());
        assert!(!canonical.path().exists());
        canonical.observe(vec![]).unwrap();
        assert_eq!(linked.observe(vec![]).unwrap(), 0);
        assert!(alias.join("new.json").is_file());
    }

    #[test]
    fn the_source_budget_fits_even_with_maximum_json_escaping() {
        let (_temp, root, entry) = project();
        let path = root.join("changes.json");
        let store = SourceHistoryStore::open(&root, &entry, Some(path.clone())).unwrap();
        let text = "\0".repeat(super::super::MAX_SOURCE_BYTES);
        std::fs::write(&entry, &text).unwrap();
        assert_eq!(store.observe(vec![source(&entry, &text)]).unwrap(), 0);
        let size = std::fs::metadata(&path).unwrap().len();
        assert!(size > 4 * 1024 * 1024);
        assert!(size < MAX_RECORD_BYTES);
        let restarted = SourceHistoryStore::open(&root, &entry, Some(path)).unwrap();
        assert_eq!(restarted.observe(vec![]).unwrap(), 0);
    }

    #[test]
    fn exact_profile_path_matches_both_readers_without_selecting_another_project() {
        let (_temp, root, entry) = project();
        let support = root.join("data");
        std::fs::create_dir_all(&support).unwrap();
        let project = identity(&root, &entry).unwrap();
        let fallback = path_for_project_at(&project, &support).unwrap();
        let other_entry = root.join("other.typ");
        std::fs::write(&other_entry, "Other").unwrap();
        let profiles = serde_json::json!({"schemaVersion": 1, "profiles": [
            {"id": "unrelated", "root": root, "entry": "other.typ"},
            {"id": "removed", "root": root.join("removed"), "entry": "main.typ"},
            {"id": "main-profile", "root": root.join("."), "entry": "./main.typ"}
        ]});
        std::fs::write(
            support.join("profiles.json"),
            serde_json::to_vec(&profiles).unwrap(),
        )
        .unwrap();
        assert_eq!(
            path_for_project_at(&project, &support).unwrap(),
            support.join("changes/main-profile.json")
        );
        let unmatched = identity(&root, &other_entry).unwrap();
        assert_eq!(
            path_for_project_at(&unmatched, &support).unwrap(),
            support.join("changes/unrelated.json")
        );
        let no_match = serde_json::json!({"schemaVersion": 1, "profiles": []});
        std::fs::write(
            support.join("profiles.json"),
            serde_json::to_vec(&no_match).unwrap(),
        )
        .unwrap();
        assert_eq!(path_for_project_at(&project, &support).unwrap(), fallback);
    }

    #[test]
    fn invalid_or_ambiguous_profiles_never_choose_a_fallback() {
        let (_temp, root, entry) = project();
        let support = root.join("data");
        std::fs::create_dir_all(&support).unwrap();
        let project = identity(&root, &entry).unwrap();
        let duplicate = serde_json::json!({"schemaVersion": 1, "profiles": [
            {"id": "first", "root": root, "entry": "main.typ"},
            {"id": "second", "root": root, "entry": "main.typ"}
        ]});
        let bad_id = serde_json::json!({"schemaVersion": 1, "profiles": [
            {"id": "../escape", "root": root, "entry": "main.typ"}
        ]});
        for contents in [
            duplicate.to_string(),
            bad_id.to_string(),
            "bad json".into(),
            r#"{"schemaVersion":2,"profiles":[]}"#.into(),
            r#"{"schemaVersion":1,"profiles":[{}]}"#.into(),
        ] {
            std::fs::write(support.join("profiles.json"), contents).unwrap();
            assert!(path_for_project_at(&project, &support).is_err());
        }
        // An explicit path does not inspect the malformed profile catalog.
        let explicit = root.join("explicit.json");
        let store = SourceHistoryStore::open(&root, &entry, Some(explicit.clone())).unwrap();
        assert_eq!(store.path(), explicit);
        assert!(
            !explicit.exists(),
            "opening a path must not write a source record"
        );
    }
}
