"""Real offline MathJax regressions in a read-only, network-denied sandbox."""
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import unittest
import xml.etree.ElementTree as ET

from flow_reader.document.native_document import _Tree, _mathml


ROOT = Path(__file__).resolve().parents[3]
DEV = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')


class NativeMathRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.node = os.environ.get('FLOW_TEST_NODE') or shutil.which('node')
        cls.runtime = Path(os.environ.get('FLOW_TEST_NATIVE_RUNTIME', DEV / 'dependencies/mathjax413'))
        if not cls.node or not shutil.which('sandbox-exec'):
            raise RuntimeError('Node and macOS sandbox-exec required; missing prerequisites fail')
        for name in ['@mathjax/src', '@mathjax/mathjax-newcm-font']:
            package = cls.runtime / 'node_modules' / name / 'package.json'
            if json.loads(package.read_text())['version'] != '4.1.3':
                raise RuntimeError('Pinned offline MathJax 4.1.3 runtime required')
        cls.command = ['/usr/bin/sandbox-exec', '-p',
                       '(version 1)(allow default)(deny network*)(deny file-write*)',
                       cls.node, '--max-old-space-size=128', '--stack-size=1024',
                       str(ROOT / 'tools/flow-reader/native/math_layout.mjs'), '--runtime', str(cls.runtime)]

    def item(self, source, **overrides):
        return dict(mathML=source, width=1200, fontSize=18, font='MathJaxNewcm',
                    context=dict(theme='light', generation=1, revision='native-math-regression'), **overrides)

    def run_helper(self, request, expected=0):
        result = subprocess.run(self.command, input=json.dumps(request, ensure_ascii=False),
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, expected, result.stderr)
        self.assertNotIn('RangeError', result.stderr)
        self.assertNotIn('math-runtime-failure', result.stderr)
        if expected == 0:
            self.assertEqual(result.stderr, '')
            return json.loads(result.stdout)
        self.assertEqual(result.stdout, '')
        return json.loads(result.stderr)

    def test_large_diverse_imported_batch_with_overlapping_dynamic_fonts(self):
        bodies = [
            '<mi>α</mi><mo>+</mo><mi>β</mi><mo>=</mo><mi>Γ</mi>',
            '<munderover><mo>∑</mo><mn>0</mn><mi>∞</mi></munderover><mi>ω</mi>',
            '<msubsup><mo>∫</mo><mn>0</mn><mn>1</mn></msubsup><mi>ψ</mi>',
            '<mi>\U0001D4AF\uFE00</mi><mo>⊗</mo><mi>\U0001D49C</mi>',
            '<mi mathvariant="script">ABC</mi><mo>∈</mo><mi mathvariant="double-struck">R</mi>',
            '<mfrac><mi>∂</mi><mi>θ</mi></mfrac><msqrt><mi>λ</mi></msqrt>',
            '<mtable class="multiline-equation aligned"><mtr><mtd><mi>α</mi></mtd>'
            '<mtd><mo>=</mo><mi>\U0001D4AF\uFE0F</mi></mtd></mtr>'
            '<mtr><mtd><mi>β</mi></mtd><mtd><mo>=</mo><mi>Γ</mi></mtd></mtr></mtable>',
            '<mrow class="flow-mark" mathsize="2em" mathcolor="red" mathbackground="white">'
            '<mi>\U0001D4AF\uFE00</mi><mo>⊕</mo><mi>φ</mi></mrow>',
            '<math display="inline" xmlns="http://www.w3.org/1998/Math/MathML">'
            '<mrow><mi>ξ</mi><mo>≃</mo><mi>\U0001D4AF\uFE00</mi></mrow></math>',
            '<mover><mi>σ</mi><mo>→</mo></mover><mo>⋅</mo><mi>ϑ</mi>',
            '<mi mathvariant="fraktur">ABC</mi><mo>⊂</mo><mi mathvariant="bold">Ω</mi>',
            '<mroot><msup><mi>ζ</mi><mn>2</mn></msup><mn>3</mn></mroot>',
        ]
        items = []
        for index in range(96):
            source = '<math display="block">' + bodies[index % len(bodies)] + '<mn>' + str(index) + '</mn></math>'
            items.append(self.item(_mathml(_Tree(source).root.children[0])))
        output = self.run_helper(dict(kind='mathml-batch', items=items))
        self.assertEqual(output['kind'], 'mathml-batch')
        self.assertEqual(len(output['items']), len(items))
        loaded = set()
        for item, result in zip(items, output['items']):
            self.assertEqual(result['inputHash'], hashlib.sha256(item['mathML'].encode()).hexdigest())
            self.assertEqual(result['context'], item['context'])
            self.assertEqual(result['diagnostics'], [])
            for fragment in [result['whole'], *result['fragments']]:
                svg = ET.fromstring(fragment['svg'])
                self.assertEqual(svg.tag, '{http://www.w3.org/2000/svg}svg')
                self.assertTrue(any(node.tag.endswith('}path') for node in svg.iter()))
                self.assertFalse(any(node.tag.rsplit('}', 1)[-1] in {'text', 'image', 'use', 'mjx-merror'} for node in svg.iter()))
                self.assertTrue(all(math.isfinite(fragment[key]) and fragment[key] >= 0 for key in ['width', 'ascent', 'descent']))
                self.assertGreater(fragment['width'], 0)
            files = result['runtime']['loaded']
            self.assertEqual(len(files), len(set(files)))
            self.assertTrue(all(name.startswith('node_modules/@mathjax/mathjax-newcm-font/cjs/svg/dynamic/') and name.endswith('.js') for name in files))
            loaded.update(files)
        self.assertGreaterEqual(len(loaded), 3, 'Exercise multiple overlapping dynamic font modules')

    def test_helper_rejects_disallowed_attributes(self):
        for attribute in ['class', 'style', 'onclick', 'href', 'mathcolor', 'mathsize', 'mathbackground']:
            with self.subTest(attribute=attribute):
                result = self.run_helper(self.item('<math><mi ' + attribute + '="x">x</mi></math>'), expected=2)
                self.assertEqual(result['code'], 'mathml-attribute')

    def test_indivisible_overflow_remains_an_explicit_diagnostic(self):
        item = self.item('<math><mfrac><mi>abcdefghijklm</mi><mi>x</mi></mfrac></math>')
        item['width'] = 16
        result = self.run_helper(item)
        self.assertEqual(result['diagnostics'], ['indivisible-math-overflow'])
        self.assertGreater(result['whole']['width'], item['width'])

    def test_tex_compilation_remains_available(self):
        item = self.item('')
        del item['mathML']
        item.update(kind='tex', tex=r'\frac{\alpha}{2}', display=True)
        result = self.run_helper(item)
        self.assertEqual(result['kind'], 'tex')
        tree = ET.fromstring(result['normalizedMathML'])
        self.assertIsNotNone(tree.find('{http://www.w3.org/1998/Math/MathML}mfrac'))
        self.assertIn('fraction', result['semanticText'])
        self.assertEqual(result['diagnostics'], [])


if __name__ == '__main__':
    unittest.main()
