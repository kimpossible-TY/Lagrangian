"""Repeated axis labels must not move a quotation to a different source figure."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from content import namespace_svg_ids
from figures import geometry_identity, stamp_canvas_identities
from passages import locate_passages
from sections import split_document


def figure(number, height):
    return (f'<div id="flow-canvas-{number}" data-flow-canvas-model="{{}}">'
            '<div class="flow-canvas-stage">'
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path d="M0 0L10 {height}"/></svg>'
            '</div><div class="flow-canvas-label-body">z₂</div></div>')


class FigureIdentityTests(unittest.TestCase):
    def test_internal_svg_names_and_attribute_order_do_not_change_identity(self):
        original = ('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">'
                    '<defs><clipPath id="clip"><rect width="20" height="20"/></clipPath></defs>'
                    '<path clip-path="url(#clip)" d="M0 0L10 10"/></svg>')
        renamed = original.replace('id="clip"', 'id="flow-svg-999-clip"').replace(
            'url(#clip)', 'url(#flow-svg-999-clip)').replace('width="100" height="100"',
                                                           'height="100" width="100"')
        self.assertEqual(geometry_identity(original), geometry_identity(renamed))
        self.assertNotEqual(geometry_identity(original),
                            geometry_identity(original.replace('L10 10', 'L10 20')))

    def test_repeated_axis_quotations_keep_their_figure_after_insertion(self):
        head = '<html><body><h2>Surfaces</h2>'
        before = head + figure(1, 10) + figure(2, 20) + '</body></html>'
        after = head + figure(1, 30) + figure(2, 10) + figure(3, 20) + '</body></html>'
        old = split_document(stamp_canvas_identities(namespace_svg_ids(before)), 'old')
        new = split_document(stamp_canvas_identities(namespace_svg_ids(after)), 'new')
        old_axes = [node for node in old.passages if node['text'] == 'z₂']
        new_axes = [node for node in new.passages if node['text'] == 'z₂']
        self.assertEqual([node['key'] for node in old_axes], [node['key'] for node in new_axes[1:]])
        self.assertEqual(len({node['key'] for node in new_axes}), 3)
        found = locate_passages(new.passages, [{'key': old_axes[1]['key'], 'exact': 'z₂'}])[0]
        self.assertEqual(found['state'], 'located')
        self.assertEqual(found['key'], new_axes[2]['key'])
        partitioned = split_document(stamp_canvas_identities(after), 'new-sections', max_blocks=1)
        identity = geometry_identity('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path d="M0 0L10 20"/></svg>')
        self.assertEqual(partitioned.manifest['canvasIdentities'][identity],
                         partitioned.manifest['anchors']['flow-canvas-3'])
        self.assertNotEqual(partitioned.manifest['canvasIdentities'][identity],
                            partitioned.manifest['anchors']['flow-canvas-2'])

    def test_stamping_is_idempotent_and_nested_figures_keep_their_own_geometry(self):
        original = '<html><body>' + figure(1, 10).replace('z₂', figure(2, 20)) + '</body></html>'
        stamped = stamp_canvas_identities(original)
        self.assertEqual(stamp_canvas_identities(stamped), stamped)
        self.assertEqual(stamped.count('data-flow-canvas-identity='), 2)

    def test_a_native_figure_without_geometry_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'missing its geometry'):
            stamp_canvas_identities('<div data-flow-canvas-model="{}"></div>')


if __name__ == '__main__':
    unittest.main()
