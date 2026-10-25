//! Renderer-independent saved source edits and project-scoped persistence.

use std::collections::BTreeMap;
use std::io::Read;
use std::ops::Range;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use typst::syntax::{LinkedNode, Source};

/// Maximum number of tracked local sources.
pub const MAX_SOURCES: usize = 256;
/// Maximum total UTF-8 source bytes retained in one history.
pub const MAX_SOURCE_BYTES: usize = 2 * 1024 * 1024;
/// Maximum number of separate navigation candidates retained for one save.
pub const MAX_EDIT_RANGES: usize = 256;

mod store;
pub use store::{MAX_RECORD_BYTES, SourceHistoryStore, default_path};

/// A writable local dependency from a successful compiler snapshot.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SourceFile {
    /// Absolute source path.
    pub filepath: PathBuf,
    /// Source text in the compiled snapshot.
    pub text: String,
}

/// The latest observed source edit, independent of the document palette.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SourceEdit {
    /// Absolute path of the edited local dependency.
    pub filepath: PathBuf,
    /// Fingerprint of the source containing this range.
    pub source_hash: String,
    /// Byte range in that exact UTF-8 source.
    pub range: Range<usize>,
    /// Separate authored hunks; older records retain their single range.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub ranges: Vec<Range<usize>>,
}

impl SourceEdit {
    /// Actual changed ranges, excluding unchanged text between separate hunks.
    pub fn changed_ranges(&self) -> &[Range<usize>] {
        if self.ranges.is_empty() {
            std::slice::from_ref(&self.range)
        } else {
            &self.ranges
        }
    }
}

/// Bounded authored-edit policy shared by every reader of a project.
#[derive(Default, Serialize, Deserialize)]
pub struct SourceHistory {
    sources: BTreeMap<PathBuf, String>,
    /// Monotonic sequence of authored content edits.
    pub sequence: u64,
    /// Latest authored range in its exact saved source.
    pub latest: Option<SourceEdit>,
}

impl SourceHistory {
    /// Whether all retained sources and the latest edit satisfy storage bounds.
    pub fn valid(&self) -> bool {
        self.sources.len() <= MAX_SOURCES
            && self.sources.values().map(String::len).sum::<usize>() <= MAX_SOURCE_BYTES
            && self.sources.keys().all(|path| path.is_absolute())
            && self.latest.as_ref().is_none_or(|edit| {
                self.sources.get(&edit.filepath).is_some_and(|text| {
                    edit.source_hash == source_hash(text)
                        && edit.ranges.len() <= MAX_EDIT_RANGES
                        && std::iter::once(&edit.range)
                            .chain(&edit.ranges)
                            .all(|range| {
                                range.start <= range.end
                                    && range.end <= text.len()
                                    && text.is_char_boundary(range.start)
                                    && text.is_char_boundary(range.end)
                                    && range.start >= edit.range.start
                                    && range.end <= edit.range.end
                            })
                        && edit
                            .ranges
                            .windows(2)
                            .all(|pair| pair[0].start <= pair[1].start)
                })
            })
    }

    /// Seed only new dependencies. A delayed theme must not roll history back.
    pub fn seed(&mut self, files: Vec<SourceFile>) -> bool {
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
            let hunks = edit_hunks(old, &text);
            let old_source = Source::detached(old);
            let new_source = Source::detached(&text);
            let mut ranges: Vec<_> = hunks
                .iter()
                .filter(|(before, after)| {
                    has_content(&old_source, before) || has_content(&new_source, after)
                })
                .map(|(_, range)| adjacent_range(&text, range.clone()))
                .take(MAX_EDIT_RANGES)
                .collect();
            ranges.sort_by_key(|range| (range.start, range.end));
            ranges.dedup();
            if !ranges.is_empty() {
                self.sequence = self.sequence.saturating_add(1);
                let range = ranges.iter().map(|r| r.start).min().unwrap()
                    ..ranges.iter().map(|r| r.end).max().unwrap();
                self.latest = Some(SourceEdit {
                    filepath: path.clone(),
                    source_hash: source_hash(&text),
                    range,
                    ranges,
                });
            } else if let Some(edit) = self.latest.as_mut().filter(|edit| edit.filepath == path) {
                // Comments must not replace the last authored edit. Rebase its
                // bytes so a later palette can still verify and map the anchor.
                let rebase = |offset: usize, start_boundary: bool| {
                    let (mut old_end, mut new_end) = (0, 0);
                    for (old_range, new_range) in &hunks {
                        if offset < old_range.start {
                            return offset - old_end + new_end;
                        }
                        if old_range.is_empty() && offset == old_range.start {
                            // Inserted trivia before the anchor moves its start;
                            // trivia after the anchor must not extend its end.
                            return if start_boundary {
                                new_range.end
                            } else {
                                new_range.start
                            };
                        } else if offset < old_range.end {
                            let mut boundary =
                                new_range.start + (offset - old_range.start).min(new_range.len());
                            while !text.is_char_boundary(boundary) {
                                boundary -= 1;
                            }
                            return boundary;
                        }
                        old_end = old_range.end;
                        new_end = new_range.end;
                    }
                    offset - old_end + new_end
                };
                for range in std::iter::once(&mut edit.range).chain(&mut edit.ranges) {
                    let start = rebase(range.start, true);
                    // A collapsed anchor stays collapsed after trivia insertion.
                    range.start = start;
                    range.end = rebase(range.end, false).max(start);
                }
                edit.source_hash = source_hash(&text);
            }
            self.sources.insert(path, text);
            changed = true;
        }
        changed
    }
}

/// Fingerprint used to bind a range to its exact UTF-8 source.
pub fn source_hash(text: &str) -> String {
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

fn edit_hunks(old: &str, new: &str) -> Vec<(Range<usize>, Range<usize>)> {
    // Line matching keeps remote edits separate. Trim each hunk to UTF-8
    // character boundaries, retaining precise single-word edits as before.
    let offsets = |lines: &[&str]| {
        let mut result = vec![0];
        for line in lines {
            result.push(result.last().unwrap() + line.len());
        }
        result
    };
    let diff = similar::TextDiff::configure()
        .timeout(std::time::Duration::from_millis(100))
        .diff_lines(old, new);
    let old_offsets = offsets(diff.old_slices());
    let new_offsets = offsets(diff.new_slices());
    diff.ops()
        .iter()
        .filter(|op| op.tag() != similar::DiffTag::Equal)
        .map(|op| {
            let before = op.old_range();
            let after = op.new_range();
            let old_start = old_offsets[before.start];
            let new_start = new_offsets[after.start];
            let (before, after) = edited_ranges(
                &old[old_start..old_offsets[before.end]],
                &new[new_start..new_offsets[after.end]],
            );
            (
                old_start + before.start..old_start + before.end,
                new_start + after.start..new_start + after.end,
            )
        })
        .collect()
}

fn adjacent_range(text: &str, range: Range<usize>) -> Range<usize> {
    if !range.is_empty() || text.is_empty() {
        return range;
    }
    // A deleted paragraph can leave only its surrounding newlines at this
    // offset. Anchor visible surviving text so every renderer can map the edit.
    let survivor = text[range.start..]
        .char_indices()
        .find(|(_, ch)| !ch.is_whitespace())
        .map(|(offset, ch)| (range.start + offset, ch))
        .or_else(|| {
            text[..range.start]
                .char_indices()
                .rev()
                .find(|(_, ch)| !ch.is_whitespace())
        });
    survivor.map_or(range, |(start, ch)| start..start + ch.len_utf8())
}

fn has_content(source: &Source, range: &Range<usize>) -> bool {
    if range.is_empty() {
        return false;
    }
    fn visit(node: LinkedNode<'_>, range: &Range<usize>) -> bool {
        let bounds = node.range();
        bounds.start < range.end
            && range.start < bounds.end
            && !node.kind().is_trivia()
            && (node.children().next().is_none()
                || node.children().any(|child| visit(child, range)))
    }
    visit(LinkedNode::new(source.root()), range)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn import_and_distant_body_edits_exclude_the_unchanged_heading() {
        let temporary = tempfile::tempdir().unwrap();
        let path = temporary.path().canonicalize().unwrap().join("main.typ");
        let original = "#import \"figures.typ\": before\n\n== Unchanged heading\n\nUnchanged introduction.\n\nOld body.\n\nUnchanged ending.";
        let updated = original
            .replace(": before", ": before, diagram")
            .replace("Old body", "새로운 body");
        std::fs::write(&path, original).unwrap();
        let mut history = SourceHistory::default();
        history.seed(vec![SourceFile {
            filepath: path.clone(),
            text: original.into(),
        }]);
        std::fs::write(&path, &updated).unwrap();
        assert!(history.observe_disk());
        let edit = history.latest.as_ref().unwrap();
        assert_eq!(edit.changed_ranges().len(), 2);
        let heading = updated.find("Unchanged heading").unwrap();
        assert!(
            edit.range.contains(&heading),
            "legacy envelope reproduces the bug"
        );
        assert!(
            edit.changed_ranges()
                .iter()
                .all(|range| !range.contains(&heading))
        );
        assert_eq!(&updated[edit.changed_ranges()[1].clone()], "새로운");
        assert!(history.valid());

        // Restart and several remote trivia changes must retain both hunks.
        let encoded = serde_json::to_vec(&history).unwrap();
        let mut history: SourceHistory = serde_json::from_slice(&encoded).unwrap();
        let commented = format!(
            "// 앞\n{}",
            updated.replace(
                "Unchanged introduction.",
                "Unchanged introduction.\n// 중간"
            )
        );
        std::fs::write(&path, &commented).unwrap();
        assert!(history.observe_disk());
        assert_eq!(history.sequence, 1);
        let edit = history.latest.as_ref().unwrap();
        assert_eq!(edit.changed_ranges().len(), 2);
        assert_eq!(&commented[edit.changed_ranges()[0].clone()], ", diagram");
        assert_eq!(&commented[edit.changed_ranges()[1].clone()], "새로운");
        assert!(history.valid());
    }

    #[test]
    fn legacy_ranges_and_invalid_precise_ranges() {
        let text = "한글 body";
        let value = serde_json::json!({"filepath": "/main.typ", "source_hash": source_hash(text),
                                     "range": {"start": 0, "end": text.len()}});
        let edit: SourceEdit = serde_json::from_value(value).unwrap();
        assert_eq!(edit.changed_ranges().len(), 1);
        assert_eq!(edit.changed_ranges()[0], 0..text.len());
        let mut history = SourceHistory::default();
        history.seed(vec![SourceFile {
            filepath: edit.filepath.clone(),
            text: text.into(),
        }]);
        history.latest = Some(edit);
        assert!(history.valid());
        for ranges in [
            std::iter::once(1..3).collect(),
            std::iter::once(0..text.len() + 1).collect(),
            vec![7..8, 0..3],
            vec![0..3; MAX_EDIT_RANGES + 1],
        ] {
            history.latest.as_mut().unwrap().ranges = ranges;
            assert!(!history.valid());
        }
    }

    #[test]
    fn unicode_edits_and_deletions_have_character_boundaries() {
        assert_eq!(edited_ranges("첫 문장", "첫 변경"), (4..10, 4..10));
        assert_eq!(adjacent_range("첫", 3..3), 0..3);
        assert_eq!(adjacent_range("첫 문장", 4..4), 4..7);
        assert_eq!(adjacent_range("Before.\n\n", 9..9), 6..7);
        assert_eq!(adjacent_range("Before. \n Next.", 7..7), 10..11);
        assert_eq!(adjacent_range("첫 \n 문장", 3..3), 6..9);
        assert_eq!(adjacent_range("첫 문장 \n", 12..12), 7..10);
        assert_eq!(adjacent_range(" \n", 2..2), 2..2);
        for newline in ["\n", "\r\n", "\r"] {
            let old = format!("Old{newline}Unchanged{newline}Old");
            let new = format!("새로운{newline}Unchanged{newline}새로운");
            let hunks = edit_hunks(&old, &new);
            assert_eq!(hunks.len(), 2);
            for (before, after) in hunks {
                assert_eq!(&old[before], "Old");
                assert_eq!(&new[after], "새로운");
            }
        }
    }

    #[test]
    fn deletion_at_document_end_anchors_surviving_content_without_tracking_whitespace() {
        let temporary = tempfile::tempdir().unwrap();
        let path = temporary.path().canonicalize().unwrap().join("main.typ");
        let original = "Before.\n\nDelete.\n";
        std::fs::write(&path, original).unwrap();
        let mut history = SourceHistory::default();
        history.seed(vec![SourceFile {
            filepath: path.clone(),
            text: original.into(),
        }]);
        let surviving = "Before.\n\n";
        std::fs::write(&path, surviving).unwrap();
        assert!(history.observe_disk());
        assert_eq!(history.sequence, 1);
        assert_eq!(
            &surviving[history.latest.as_ref().unwrap().range.clone()],
            "."
        );
        std::fs::write(&path, "Before.\n\n   \n").unwrap();
        assert!(history.observe_disk());
        assert_eq!(history.sequence, 1);
        assert_eq!(history.latest.as_ref().unwrap().range, 6..7);
        assert!(history.valid());
    }

    #[test]
    fn idle_observation_retains_order_and_rebases_comment_edits() {
        let path = std::env::temp_dir().join(format!("flow-source-{}.typ", std::process::id()));
        let original = "// Before\nOld body\n";
        std::fs::write(&path, original).unwrap();
        let mut history = SourceHistory::default();
        history.seed(vec![SourceFile {
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
    fn trivia_insertions_at_anchor_boundaries_keep_the_authored_word() {
        let temporary = tempfile::tempdir().unwrap();
        let path = temporary.path().canonicalize().unwrap().join("main.typ");
        std::fs::write(&path, "Old body.").unwrap();
        let mut history = SourceHistory::default();
        history.seed(vec![SourceFile {
            filepath: path.clone(),
            text: "Old body.".into(),
        }]);
        std::fs::write(&path, "New body.").unwrap();
        assert!(history.observe_disk());
        assert_eq!(history.latest.as_ref().unwrap().range, 0..3);
        for (text, range) in [
            ("// Comment\nNew body.", 11..14),
            ("// Comment\nNew/* Tail */ body.", 11..14),
            ("New/* Tail */ body.", 0..3),
            ("New body.", 0..3),
        ] {
            std::fs::write(&path, text).unwrap();
            assert!(history.observe_disk());
            assert_eq!(history.sequence, 1, "{text:?}");
            assert_eq!(history.latest.as_ref().unwrap().range, range);
            assert_eq!(&text[history.latest.as_ref().unwrap().range.clone()], "New");
            assert!(history.valid());
        }
    }

    #[test]
    fn unicode_comment_replacements_preserve_utf8_anchor_boundaries() {
        let temporary = tempfile::tempdir().unwrap();
        let path = temporary.path().canonicalize().unwrap().join("main.typ");
        std::fs::write(&path, "Old 문장.").unwrap();
        let mut history = SourceHistory::default();
        history.seed(vec![SourceFile {
            filepath: path.clone(),
            text: "Old 문장.".into(),
        }]);
        std::fs::write(&path, "새로운 문장.").unwrap();
        assert!(history.observe_disk());
        for (prefix, body) in [
            ("// 한글 주석\n", "새로운 문장."),
            ("// 더 긴 한글 주석\n", "새로운 문장."),
            ("// 더 긴 한글 주석\n", "새로운/* 뒤 */ 문장."),
            ("", "새로운/* 뒤 */ 문장."),
        ] {
            let text = format!("{prefix}{body}");
            std::fs::write(&path, &text).unwrap();
            assert!(history.observe_disk());
            assert_eq!(history.sequence, 1, "{text:?}");
            assert_eq!(
                history.latest.as_ref().unwrap().range,
                prefix.len()..prefix.len() + "새로운".len()
            );
            assert_eq!(
                &text[history.latest.as_ref().unwrap().range.clone()],
                "새로운"
            );
            assert!(history.valid());
        }
    }

    #[test]
    fn replacing_unicode_trivia_inside_a_saved_range_keeps_valid_boundaries() {
        let temporary = tempfile::tempdir().unwrap();
        let path = temporary.path().canonicalize().unwrap().join("main.typ");
        let original = "/* A */\nOld body.";
        std::fs::write(&path, original).unwrap();
        let mut history = SourceHistory::default();
        history.seed(vec![SourceFile {
            filepath: path.clone(),
            text: original.into(),
        }]);
        std::fs::write(&path, "/* 한글 */\nNew body.").unwrap();
        assert!(history.observe_disk());
        let replaced = "/*가나다 */\nNew body.";
        std::fs::write(&path, replaced).unwrap();
        assert!(history.observe_disk());
        assert_eq!(history.sequence, 1);
        assert!(history.valid());
        assert!(replaced[history.latest.as_ref().unwrap().range.clone()].contains("New"));
    }

    #[test]
    fn trivia_inserted_at_an_empty_anchor_keeps_a_valid_collapsed_range() {
        let temporary = tempfile::tempdir().unwrap();
        let path = temporary.path().canonicalize().unwrap().join("main.typ");
        std::fs::write(&path, "Old body.").unwrap();
        let mut history = SourceHistory::default();
        history.seed(vec![SourceFile {
            filepath: path.clone(),
            text: "Old body.".into(),
        }]);
        std::fs::write(&path, "").unwrap();
        assert!(history.observe_disk());
        assert_eq!(history.latest.as_ref().unwrap().range, 0..0);
        let comment = "// 한글 comment\n";
        std::fs::write(&path, comment).unwrap();
        assert!(history.observe_disk());
        assert_eq!(history.sequence, 1);
        assert_eq!(
            history.latest.as_ref().unwrap().range,
            comment.len()..comment.len()
        );
        assert!(history.valid());
    }

    #[test]
    fn source_budget_and_stale_palettes_do_not_replace_a_baseline() {
        let path = PathBuf::from("/example.typ");
        let mut history = SourceHistory::default();
        assert!(history.seed(vec![SourceFile {
            filepath: path.clone(),
            text: "current".into()
        }]));
        assert!(!history.seed(vec![SourceFile {
            filepath: path.clone(),
            text: "older".into()
        }]));
        assert!(!history.seed(vec![SourceFile {
            filepath: PathBuf::from("/too-large.typ"),
            text: "x".repeat(MAX_SOURCE_BYTES)
        }]));
        assert_eq!(history.sources[&path], "current");
        assert!(history.valid());
    }
}
