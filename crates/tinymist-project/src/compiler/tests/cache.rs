//! Cache retention preserves compiled document output.

use super::*;

#[test]
fn recent_cache_retention_preserves_edit_and_revert_output() {
    use typst::layout::{Frame, FrameItem, Point};
    use typst::visualize::Shape;

    fn shapes(artifact: CompiledArtifact<MockCompilerFeat>) -> Vec<(Point, Shape)> {
        fn collect(frame: &Frame, offset: Point, output: &mut Vec<(Point, Shape)>) {
            for (point, item) in frame.items() {
                match item {
                    FrameItem::Group(group) => collect(&group.frame, offset + *point, output),
                    FrameItem::Shape(shape, _) => output.push((offset + *point, shape.clone())),
                    _ => {}
                }
            }
        }

        assert_eq!(artifact.error_cnt(), 0);
        let Some(TypstDocument::Paged(doc)) = &artifact.doc else {
            panic!("expected a paged document");
        };
        assert_eq!(doc.pages().len(), 1);
        let mut output = Vec::new();
        collect(&doc.pages()[0].frame, Point::zero(), &mut output);
        output
    }

    let mut harness = ProjectCompilerHarness::new(&[
        (
            MAIN,
            "#set page(width: 100pt, height: 100pt, margin: 0pt)\n\
             #import \"dep.typ\": size\n\
             #rect(width: size, height: 10pt, fill: red)",
        ),
        (DEP, "#let size = 10pt"),
    ]);
    let initial = shapes(harness.compile_primary());
    assert!(!initial.is_empty());

    for _ in 0..3 {
        // Exercise fully expired entries as well as the normal automatic
        // sweeps. Other tests may evict concurrently; output must not depend
        // on which entries are still cached.
        for _ in 0..2 {
            comemo::evict(eviction::MAX_UNUSED_AGE);
        }
        let change = harness.workspace.update_source(DEP, "#let size = 20pt");
        harness.apply_update(&change, false);
        assert_ne!(shapes(harness.compile_pending()), initial);

        comemo::evict(eviction::MAX_UNUSED_AGE);
        let revert = harness.workspace.update_source(DEP, "#let size = 10pt");
        harness.apply_update(&revert, false);
        assert_eq!(shapes(harness.compile_pending()), initial);
    }
}
