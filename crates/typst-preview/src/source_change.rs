//! Bounded source history shared by demand-driven document variants.

use std::collections::BTreeMap;
use std::io::Read;
use std::ops::Range;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use typst::syntax::{LinkedNode, Source};

const MAX_SOURCES: usize = 256;
const MAX_SOURCE_BYTES: usize = 2 * 1024 * 1024;

/// A writable local dependency from a successful compiler snapshot.
pub struct PreviewSourceFile {
    /// Absolute source path.
    pub filepath: PathBuf,
    /// Source text in the compiled snapshot.
    pub text: String,
}

/// The latest observed source edit, independent of the document palette.
#[derive(Clone, Serialize, Deserialize)]
pub struct PreviewSourceEdit {
    /// Absolute path of the edited local dependency.
    pub filepath: PathBuf,
    /// Fingerprint of the source containing this range.
    pub source_hash: String,
    /// Byte range in that exact UTF-8 source.
    pub range: Range<usize>,
}

#[derive(Default, Serialize, Deserialize)]
pub(crate) struct SourceHistory {
    sources: BTreeMap<PathBuf, String>,
    pub sequence: u64,
    pub latest: Option<PreviewSourceEdit>,
}

impl SourceHistory {
    pub fn valid(&self) -> bool {
        self.sources.len() <= MAX_SOURCES
            && self.sources.values().map(String::len).sum::<usize>() <= MAX_SOURCE_BYTES
            && self.sources.keys().all(|path| path.is_absolute())
            && self.latest.as_ref().is_none_or(|edit| {
                self.sources.get(&edit.filepath).is_some_and(|text| {
                    edit.source_hash == source_hash(text)
                        && edit.range.start <= edit.range.end
                        && edit.range.end <= text.len()
                        && text.is_char_boundary(edit.range.start)
                        && text.is_char_boundary(edit.range.end)
                })
            })
    }

    /// Seed only new dependencies. A delayed theme must not roll history back.
    pub fn seed(&mut self, files: Vec<PreviewSourceFile>) -> bool {
        let mut changed = false;
        let mut bytes = self.sources.values().map(String::len).sum::<usize>();
        for file in files {
            if !file.filepath.is_absolute()
                || self.sources.contains_key(&file.filepath)
                || self.sources.len() >= MAX_SOURCES
                || bytes + file.text.len() > MAX_SOURCE_BYTES
            {
                continue;
            }
            bytes += file.text.len();
            self.sources.insert(file.filepath, file.text);
            changed = true;
        }
        changed
    }

    /// Observe filesystem changes without compiling either palette.
    pub fn observe_disk(&mut self) -> bool {
        let mut changes = vec![];
        for (path, old) in &self.sources {
            let read = || -> Option<_> {
                let file = std::fs::File::open(path).ok()?;
                let before = file.metadata().ok()?;
                if before.len() > MAX_SOURCE_BYTES as u64 {
                    return None;
                }
                let mut text = String::new();
                file.take(MAX_SOURCE_BYTES as u64 + 1)
                    .read_to_string(&mut text)
                    .ok()?;
                let after = std::fs::metadata(path).ok()?;
                (text.len() <= MAX_SOURCE_BYTES
                    && before.len() == after.len()
                    && before.modified().ok() == after.modified().ok())
                .then_some((after.modified().ok(), text))
            };
            if let Some((modified, text)) = read()
                && &text != old
            {
                changes.push((modified, path.clone(), text));
            }
        }
        // Separate watcher turns preserve edit order. Coalesced filesystem
        // saves use modification time, never Git patch or filename ordering.
        changes.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
        let mut changed = false;
        for (_, path, text) in changes {
            let old = &self.sources[&path];
            let bytes = self.sources.values().map(String::len).sum::<usize>();
            if bytes - old.len() + text.len() > MAX_SOURCE_BYTES {
                continue;
            }
            let (old_range, new_range) = edited_ranges(old, &text);
            if has_content(old, &old_range) || has_content(&text, &new_range) {
                self.sequence = self.sequence.saturating_add(1);
                self.latest = Some(PreviewSourceEdit {
                    filepath: path.clone(),
                    source_hash: source_hash(&text),
                    range: adjacent_range(&text, new_range),
                });
            } else if let Some(edit) = self.latest.as_mut().filter(|edit| edit.filepath == path) {
                // Comments must not replace the last authored edit. Rebase its
                // bytes so a later palette can still verify and map the anchor.
                let rebase = |offset: usize| {
                    if offset <= old_range.start {
                        offset
                    } else if offset >= old_range.end {
                        offset - old_range.len() + new_range.len()
                    } else {
                        new_range.start + (offset - old_range.start).min(new_range.len())
                    }
                };
                edit.range = rebase(edit.range.start)..rebase(edit.range.end);
                edit.source_hash = source_hash(&text);
            }
            self.sources.insert(path, text);
            changed = true;
        }
        changed
    }
}

pub(crate) fn source_hash(text: &str) -> String {
    format!("{:032x}", tinymist_std::hash::hash128(&text))
}

fn edited_ranges(old: &str, new: &str) -> (Range<usize>, Range<usize>) {
    let prefix = old
        .chars()
        .zip(new.chars())
        .take_while(|(a, b)| a == b)
        .map(|(ch, _)| ch.len_utf8())
        .sum::<usize>();
    let suffix = old[prefix..]
        .chars()
        .rev()
        .zip(new[prefix..].chars().rev())
        .take_while(|(a, b)| a == b)
        .map(|(ch, _)| ch.len_utf8())
        .sum::<usize>();
    (prefix..old.len() - suffix, prefix..new.len() - suffix)
}

fn adjacent_range(text: &str, range: Range<usize>) -> Range<usize> {
    if !range.is_empty() || text.is_empty() {
        return range;
    }
    let start = if range.start < text.len() {
        range.start
    } else {
        text.char_indices()
            .next_back()
            .map_or(0, |(offset, _)| offset)
    };
    start..start + text[start..].chars().next().unwrap().len_utf8()
}

fn has_content(text: &str, range: &Range<usize>) -> bool {
    fn visit(node: LinkedNode<'_>, range: &Range<usize>) -> bool {
        let bounds = node.range();
        bounds.start < range.end
            && range.start < bounds.end
            && !node.kind().is_trivia()
            && (node.children().next().is_none()
                || node.children().any(|child| visit(child, range)))
    }
    visit(LinkedNode::new(Source::detached(text).root()), range)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unicode_edits_and_deletions_have_character_boundaries() {
        assert_eq!(edited_ranges("첫 문장", "첫 변경"), (4..10, 4..10));
        assert_eq!(adjacent_range("첫", 3..3), 0..3);
        assert_eq!(adjacent_range("첫 문장", 4..4), 4..7);
    }

    #[test]
    fn idle_observation_retains_order_and_rebases_comment_edits() {
        let path = std::env::temp_dir().join(format!("flow-source-{}.typ", std::process::id()));
        let original = "// Before\nOld body\n";
        std::fs::write(&path, original).unwrap();
        let mut history = SourceHistory::default();
        history.seed(vec![PreviewSourceFile {
            filepath: path.clone(),
            text: original.into(),
        }]);
        std::fs::write(&path, "// Before\nLatest body\n").unwrap();
        assert!(history.observe_disk());
        let sequence = history.sequence;
        std::fs::write(&path, "// Longer comment\nLatest body\n").unwrap();
        assert!(history.observe_disk());
        assert_eq!(history.sequence, sequence);
        assert_eq!(
            &history.sources[&path][history.latest.as_ref().unwrap().range.clone()],
            "Latest"
        );
        assert!(history.valid());
        assert!(!history.observe_disk());
        let encoded = serde_json::to_vec(&history).unwrap();
        let mut restarted: SourceHistory = serde_json::from_slice(&encoded).unwrap();
        assert!(restarted.valid());
        std::fs::write(&path, "// Longer comment\nNewest body\n").unwrap();
        assert!(restarted.observe_disk());
        assert!(restarted.sequence > sequence);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn source_budget_and_stale_palettes_do_not_replace_a_baseline() {
        let path = PathBuf::from("/example.typ");
        let mut history = SourceHistory::default();
        assert!(history.seed(vec![PreviewSourceFile {
            filepath: path.clone(),
            text: "current".into()
        }]));
        assert!(!history.seed(vec![PreviewSourceFile {
            filepath: path.clone(),
            text: "older".into()
        }]));
        assert!(!history.seed(vec![PreviewSourceFile {
            filepath: PathBuf::from("/too-large.typ"),
            text: "x".repeat(MAX_SOURCE_BYTES)
        }]));
        assert_eq!(history.sources[&path], "current");
        assert!(history.valid());
    }
}
