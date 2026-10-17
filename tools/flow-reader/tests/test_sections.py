"""Section boundaries must preserve content, links and annotation associations."""

from pathlib import Path
import base64
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from sections import BodyIndex, assign_block_ids, separate_assets, split_document


def body(source):
    index = BodyIndex(source)
    index.feed(source)
    return source[index.body_start:index.body_end]


class SectionTests(unittest.TestCase):
    def test_native_label_keys_follow_content_and_nested_labels_have_leaf_keys(self):
        before = '<html><body><h2>Figure topic</h2><div class="flow-canvas-label"><span class="flow-canvas-label-number">1</span><div class="flow-canvas-label-body">Keep this readable label.</div></div></body></html>'
        after = before.replace('>1</span>', '>12</span>').replace('<div class="flow-canvas-label">',
            '<div class="flow-canvas-label-body">Inserted unrelated label.</div><div class="flow-canvas-label">')
        keys = []
        for source in (before, after):
            indexed = assign_block_ids(source)
            keys.append(re.search(r'<div\b[^>]*class="flow-canvas-label-body"[^>]*data-reader-key="([^"]+)"[^>]*>Keep this readable label\.', indexed)[1])
        self.assertEqual(keys[0], keys[1])
        nested = '<html><body><div class="flow-canvas-label-body">outer<div class="flow-canvas-label-body">leaf</div></div></body></html>'
        self.assertEqual(assign_block_ids(nested).count('data-reader-key='), 1)

    def test_embedded_image_bytes_and_dimensions_survive_asset_separation(self):
        content = b"test-image-content"
        source = '<html><body><img width="300" height="200" src="data:image/png;base64,' + base64.b64encode(content).decode() + '"></body></html>'
        bundle = split_document(source, "revision-a")
        self.assertEqual(list(bundle.assets.values()), [content])
        self.assertIn(b'width="300" height="200"', bundle.documents["section-0"])

    def test_annotation_and_mark_stay_together_and_all_text_is_retained(self):
        source = '''<!doctype html><html><head><title>수학</title></head><body>
<h2 id="start">시작</h2><p>첫 문단 <a href="#note">각주</a></p>
<div><math><mrow data-flow-mark="x">𝑥</mrow></math></div>
<p>중간 설명</p><span data-flow-targets='["x"]'>수식 해설</span>
<h3 id="next">다음 절</h3><p>마지막 문단</p><section id="note">각주 내용</section>
</body></html>'''
        bundle = split_document(source, "revision-a", max_chars=100, max_blocks=2)
        parts = [content.decode() for content in bundle.documents.values()]
        self.assertGreater(len(parts), 1)
        self.assertEqual("".join(map(body, parts)), body(assign_block_ids(source)))
        with_mark = next(part for part in parts if 'data-flow-mark="x"' in part)
        self.assertIn("수식 해설", with_mark)
        for anchor in ("start", "next", "note"):
            self.assertIn(f'id="{anchor}"', bundle.documents[bundle.manifest["anchors"][anchor]].decode())
        self.assertEqual([heading["title"] for heading in bundle.manifest["outline"]], ["시작", "다음 절"])
        self.assertEqual(bundle.manifest["revision"], "revision-a")

    def test_reading_key_survives_section_boundary_and_generated_label_changes(self):
        before = '<html><body><h2>Topic</h2><p>Earlier text.</p><p id="loc-2">My reading position.</p></body></html>'
        after = before.replace('<p id="loc-2">', '<p>New paragraph.</p><p>Another new paragraph.</p><p id="loc-3">')
        old = split_document(before, "old", max_blocks=2)
        new = split_document(after, "new", max_blocks=2)
        old_index = BodyIndex(assign_block_ids(before)); old_index.feed(old_index.source)
        new_index = BodyIndex(assign_block_ids(after)); new_index.feed(new_index.source)
        key = next(key for key, block in old_index.blocks.items() if block == old_index.anchors["loc-2"])
        self.assertEqual(new_index.blocks[key], new_index.anchors["loc-3"])
        self.assertNotEqual(old.manifest["blocks"][key], new.manifest["blocks"][key])
        self.assertIn('My reading position.', new.documents[new.manifest["blocks"][key]].decode())

    def test_large_vector_is_an_unchanged_asset_and_document_links_stay_inline(self):
        drawing = '<svg xmlns="http://www.w3.org/2000/svg" width="500" height="200">' + '<path d="M0 0L10 20"/>' * 2000 + '</svg>'
        source = '<html><body><figure>' + drawing + '</figure></body></html>'
        bundle = split_document(source, "revision-a")
        self.assertEqual(list(bundle.assets.values()), [drawing.encode()])
        self.assertLess(len(bundle.documents["section-0"]), 500)
        self.assertIn(b'loading="lazy"', bundle.documents["section-0"])
        native = '<div class="flow-canvas-stage">' + drawing + '</div>'
        self.assertEqual(separate_assets(native), (native, {}))
        linked = drawing.replace('</svg>', '<a href="#equation"><path d="M0 0L10 10"/></a></svg>')
        result, assets = separate_assets(linked)
        self.assertEqual(result, linked)
        self.assertEqual(assets, {})
        external = linked.replace('#equation', 'https://example.test/reference')
        self.assertEqual(separate_assets(external), (external, {}))


if __name__ == "__main__":
    unittest.main()
