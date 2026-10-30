//! Bounded, read-only Git source candidates for initial preview focus.

use std::collections::HashSet;
use std::ffi::OsStr;
use std::io::Read;
use std::ops::Range;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::time::{Duration, Instant};

const MAX_OUTPUT: u64 = 4 * 1024 * 1024;

struct Git {
    root: PathBuf,
    deadline: Instant,
}

impl Git {
    fn run(&self, args: &[&OsStr]) -> Option<(ExitStatus, Vec<u8>)> {
        if Instant::now() >= self.deadline {
            return None;
        }
        let mut child = Command::new("git")
            .args([
                "--no-pager",
                "--literal-pathspecs",
                "-c",
                "core.fsmonitor=false",
                "-C",
            ])
            .arg(&self.root)
            .args(args)
            .env_remove("GIT_DIR")
            .env_remove("GIT_WORK_TREE")
            .env_remove("GIT_INDEX_FILE")
            .env("GIT_OPTIONAL_LOCKS", "0")
            .env("GIT_TERMINAL_PROMPT", "0")
            .env("GIT_NO_LAZY_FETCH", "1")
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .stdout(Stdio::piped())
            .spawn()
            .ok()?;
        let stdout = child.stdout.take()?;
        std::thread::scope(|scope| {
            let output = scope.spawn(move || {
                let mut bytes = Vec::new();
                stdout.take(MAX_OUTPUT + 1).read_to_end(&mut bytes).ok()?;
                (bytes.len() as u64 <= MAX_OUTPUT).then_some(bytes)
            });
            let status = loop {
                match child.try_wait() {
                    Ok(Some(status)) => break Some(status),
                    Ok(None) if Instant::now() < self.deadline => {
                        std::thread::sleep(Duration::from_millis(5));
                    }
                    _ => {
                        let _ = child.kill();
                        let _ = child.wait();
                        break None;
                    }
                }
            };
            let bytes = output.join().ok()??;
            Some((status?, bytes))
        })
    }

    fn read(&self, args: &[&OsStr]) -> Option<Vec<u8>> {
        let (status, bytes) = self.run(args)?;
        status.success().then_some(bytes)
    }
}

fn git_text_line(bytes: &[u8]) -> Option<&str> {
    std::str::from_utf8(bytes)
        .ok()
        .map(|text| text.trim_end_matches(['\r', '\n']))
}

/// Git pathspecs use `/`. Windows `canonicalize` uses a `\\?\` prefix and `\`.
#[cfg(any(windows, test))]
fn normalize_git_path(path: &str) -> String {
    path.strip_prefix(r"\\?\")
        .unwrap_or(path)
        .replace('\\', "/")
}

#[cfg(any(windows, test))]
fn starts_with_git_path(path: &str, prefix: &str) -> bool {
    let path = path.trim_end_matches('/');
    let prefix = prefix.trim_end_matches('/');
    if prefix.is_empty() || path.len() < prefix.len() {
        return false;
    }
    let (head, tail) = path.split_at(prefix.len());
    let same = if cfg!(windows) {
        head.eq_ignore_ascii_case(prefix)
    } else {
        head == prefix
    };
    same && (tail.is_empty() || tail.starts_with('/'))
}

#[cfg(any(windows, test))]
fn git_relative_utf8(path: &str, root: &str, git_root: &str) -> Option<String> {
    let path = normalize_git_path(path);
    let root = normalize_git_path(root);
    let git_root = normalize_git_path(git_root);
    if !starts_with_git_path(&path, &root) || !starts_with_git_path(&path, &git_root) {
        return None;
    }
    let path = path.trim_end_matches('/');
    let git_root = git_root.trim_end_matches('/');
    if path.len() == git_root.len() {
        Some(String::new())
    } else {
        Some(path[git_root.len() + 1..].to_string())
    }
}

fn git_relative(path: &Path, root: &Path, git_root: &Path) -> Option<String> {
    // A backslash is a separator only on Windows. Elsewhere it is a file name
    // character, so `std::path` must keep it.
    #[cfg(windows)]
    if let (Some(path_text), Some(root_text), Some(git_root_text)) =
        (path.to_str(), root.to_str(), git_root.to_str())
    {
        if path_text.contains('\\') || root_text.contains('\\') || git_root_text.contains('\\') {
            return git_relative_utf8(path_text, root_text, git_root_text);
        }
    }
    if !path.starts_with(root) {
        return None;
    }
    path.strip_prefix(git_root)
        .ok()
        .and_then(Path::to_str)
        .map(str::to_string)
}

/// Return ranges only for disk sources identical to the compiled snapshot.
pub(super) fn changed_ranges(
    root: &Path,
    sources: &[(PathBuf, String)],
) -> Option<Vec<(usize, Vec<Range<usize>>)>> {
    let mut git = Git {
        root: root.to_owned(),
        deadline: Instant::now() + Duration::from_secs(3),
    };
    let repo_bytes = git.read(&["rev-parse".as_ref(), "--show-toplevel".as_ref()])?;
    let repo = git_text_line(&repo_bytes)?;
    git.root = PathBuf::from(repo);
    let (head, _) = git.run(&["rev-parse".as_ref(), "--verify".as_ref(), "HEAD".as_ref()])?;
    if !head.success() {
        // Only a missing branch reference is unborn. Corrupt or detached HEAD
        // failures must not make every tracked file look newly added.
        let branch = git.read(&["symbolic-ref".as_ref(), "--quiet".as_ref(), "HEAD".as_ref()])?;
        let branch = std::str::from_utf8(&branch).ok()?.trim_end();
        let (status, _) = git.run(&[
            "show-ref".as_ref(),
            "--verify".as_ref(),
            "--quiet".as_ref(),
            branch.as_ref(),
        ])?;
        if status.code() != Some(1) {
            return None;
        }
    }
    let added = if head.success() {
        git.read(&[
            "ls-files".as_ref(),
            "--others".as_ref(),
            "--exclude-standard".as_ref(),
            "-z".as_ref(),
        ])
    } else {
        git.read(&[
            "ls-files".as_ref(),
            "--cached".as_ref(),
            "--others".as_ref(),
            "--exclude-standard".as_ref(),
            "-z".as_ref(),
        ])
    }?;
    let added: HashSet<_> = added.split(|byte| *byte == 0).collect();
    let modified = if head.success() {
        git.read(&[
            "diff".as_ref(),
            "--no-ext-diff".as_ref(),
            "--no-color".as_ref(),
            "--no-textconv".as_ref(),
            "--no-renames".as_ref(),
            "--name-only".as_ref(),
            "-z".as_ref(),
            "HEAD".as_ref(),
            "--".as_ref(),
        ])?
    } else {
        vec![]
    };
    let modified: HashSet<_> = modified.split(|byte| *byte == 0).collect();
    let mut candidates = Vec::new();
    for (index, (path, source)) in sources.iter().enumerate() {
        if source.is_empty() || source.len() as u64 > MAX_OUTPUT {
            continue;
        }
        let Some(relative) = git_relative(path, root, &git.root) else {
            continue;
        };
        let is_added = added.contains(relative.as_bytes());
        if !is_added && !modified.contains(relative.as_bytes()) {
            continue;
        }
        let mut disk = String::new();
        if std::fs::File::open(path)
            .ok()?
            .take(MAX_OUTPUT + 1)
            .read_to_string(&mut disk)
            .is_err()
            || disk != *source
        {
            continue;
        }
        let ranges = if is_added {
            std::iter::once(0..source.len()).collect()
        } else {
            let patch = git.read(&[
                "diff".as_ref(),
                "--no-ext-diff".as_ref(),
                "--no-color".as_ref(),
                "--no-textconv".as_ref(),
                "--no-renames".as_ref(),
                "--text".as_ref(),
                "--unified=0".as_ref(),
                "--inter-hunk-context=0".as_ref(),
                "HEAD".as_ref(),
                "--".as_ref(),
                relative.as_ref(),
            ])?;
            hunk_ranges(std::str::from_utf8(&patch).ok()?, source)?
        };
        // A watcher may observe another save while Git is reading the file.
        disk.clear();
        if std::fs::File::open(path)
            .ok()?
            .take(MAX_OUTPUT + 1)
            .read_to_string(&mut disk)
            .is_err()
            || disk != *source
        {
            continue;
        }
        if !ranges.is_empty() {
            candidates.push((index, ranges));
        }
    }
    (Instant::now() < git.deadline).then_some(candidates)
}

fn hunk_ranges(patch: &str, source: &str) -> Option<Vec<Range<usize>>> {
    let mut offsets = vec![0];
    offsets.extend(source.match_indices('\n').map(|(index, _)| index + 1));
    let mut ranges = Vec::new();
    for line in patch.lines().filter(|line| line.starts_with("@@ ")) {
        let new = line.split_whitespace().nth(2)?.strip_prefix('+')?;
        let (start, count) = new.split_once(',').unwrap_or((new, "1"));
        let start = start.parse::<usize>().ok()?;
        let count = count.parse::<usize>().ok()?;
        if count == 0 {
            // Deletions point at the surviving next line, or the end of file.
            if !source.is_empty() {
                let offset = offsets
                    .get(start)
                    .copied()
                    .unwrap_or(source.len())
                    .min(source.len() - 1);
                ranges.push(offset..offset + 1);
            }
        } else {
            let start = start.checked_sub(1)?;
            let from = *offsets.get(start)?;
            let to = offsets
                .get(start.checked_add(count)?)
                .copied()
                .unwrap_or(source.len());
            if from < to {
                ranges.push(from..to);
            }
        }
    }
    Some(ranges)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn git(root: &Path, args: &[&str]) {
        assert!(Command::new("git")
            .args(["-c", "core.hooksPath=/dev/null", "-C"])
            .arg(root)
            .args(args)
            .output()
            .unwrap()
            .status
            .success());
    }

    #[test]
    fn separate_hunks_and_deletions_preserve_current_line_ranges() {
        let text = "첫째\nsecond\nthird\nfourth\n";
        let ranges = hunk_ranges("@@ -1 +1 @@\n@@ -3,2 +3,0 @@\n@@ -5 +4 @@\n", text).unwrap();
        assert_eq!(&text[ranges[0].clone()], "첫째\n");
        assert_eq!(ranges[1].start, text.find("fourth").unwrap());
        assert_eq!(&text[ranges[2].clone()], "fourth\n");
    }

    #[test]
    fn repository_candidates_include_staged_unstaged_and_new_but_not_ignored_or_stale() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().canonicalize().unwrap();
        git(&root, &["init", "-q"]);
        git(&root, &["config", "color.ui", "always"]);
        git(&root, &["config", "diff.interHunkContext", "99"]);
        std::fs::write(root.join(".gitignore"), "ignored.typ\n").unwrap();
        std::fs::write(root.join("tracked [한].typ"), "old\nunchanged\nold\n").unwrap();
        git(&root, &["add", "."]);
        git(
            &root,
            &[
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.invalid",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "-qm",
                "baseline",
            ],
        );
        std::fs::write(root.join("tracked [한].typ"), "staged\nunchanged\nold\n").unwrap();
        git(&root, &["add", "."]);
        std::fs::write(
            root.join("tracked [한].typ"),
            "staged\nunchanged\nunstaged\n",
        )
        .unwrap();
        std::fs::write(root.join("new.typ"), "new\n").unwrap();
        std::fs::write(root.join("ignored.typ"), "ignored\n").unwrap();
        let sources = vec![
            (
                root.join("tracked [한].typ"),
                "staged\nunchanged\nunstaged\n".into(),
            ),
            (root.join("new.typ"), "new\n".into()),
            (root.join("ignored.typ"), "ignored\n".into()),
            (root.join("new.typ"), "unsaved\n".into()),
        ];
        let result = changed_ranges(&root, &sources).unwrap();
        assert_eq!(result.len(), 2);
        assert_eq!(result[0].0, 0);
        assert_eq!(result[0].1, vec![0..7, 17..26]);
        assert_eq!(result[1], (1, std::iter::once(0..4).collect()));
    }

    #[test]
    fn unborn_repository_and_non_repository() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().canonicalize().unwrap();
        let source = vec![(root.join("new.typ"), "new".into())];
        std::fs::write(&source[0].0, "new").unwrap();
        assert!(changed_ranges(&root, &source).is_none());
        git(&root, &["init", "-q"]);
        assert_eq!(changed_ranges(&root, &source).unwrap().len(), 1);
        std::fs::write(
            root.join(".git/HEAD"),
            "0000000000000000000000000000000000000001\n",
        )
        .unwrap();
        assert!(changed_ranges(&root, &source).is_none());
    }

    #[test]
    fn git_toplevel_trims_crlf() {
        assert_eq!(git_text_line(b"C:\\repo\r\n").unwrap(), r"C:\repo");
        assert_eq!(git_text_line(b"/repo\n").unwrap(), "/repo");
    }

    #[test]
    fn windows_verbatim_paths_match_git_root_with_forward_slashes() {
        let root = r"\\?\C:\repo";
        let inside = r"\\?\C:\repo\dir\tracked [한].typ";
        assert_eq!(
            git_relative_utf8(inside, root, r"C:\repo").as_deref(),
            Some("dir/tracked [한].typ")
        );
        assert_eq!(
            git_relative_utf8(inside, root, "C:/repo").as_deref(),
            Some("dir/tracked [한].typ")
        );
        assert_eq!(
            git_relative_utf8(r"\\?\C:\other\file.typ", root, r"C:\repo"),
            None
        );
        assert_eq!(
            git_relative_utf8(r"\\?\C:\repository\file.typ", root, r"C:\repo"),
            None
        );
    }

    #[cfg(not(windows))]
    #[test]
    fn unix_backslash_remains_part_of_the_file_name() {
        let root = Path::new("/repo");
        let path = Path::new("/repo/dir\\file.typ");
        assert_eq!(
            git_relative(path, root, root).as_deref(),
            Some("dir\\file.typ")
        );
    }
}
