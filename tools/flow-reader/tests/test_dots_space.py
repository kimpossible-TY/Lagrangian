"""Real compiler regressions for prose and nested mathematical helper calls."""
from html.parser import HTMLParser
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.build import Project, compile_project, prepare_packages


class Element:
    def __init__(self, tag, attrs=(), parent=None):
        self.tag, self.attrs, self.parent = tag, dict(attrs), parent
        self.children = []

    def descendants(self, tag=None):
        for child in self.children:
            if isinstance(child, Element):
                if tag is None or child.tag == tag:
                    yield child
                yield from child.descendants(tag)

    def text(self):
        return ''.join(child.text() if isinstance(child, Element) else child
                       for child in self.children)

    def ancestors(self):
        current = self.parent
        while current is not None:
            yield current
            current = current.parent


class Document(HTMLParser):
    VOID = {'meta', 'link', 'br', 'hr', 'img', 'input', 'wbr', 'source'}

    def __init__(self, source):
        super().__init__()
        self.root = Element('document')
        self.current = self.root
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        node = Element(tag, attrs, self.current)
        self.current.children.append(node)
        if tag not in self.VOID:
            self.current = node

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in self.VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        node = self.current
        while node.parent is not None:
            if node.tag == tag:
                self.current = node.parent
                return
            node = node.parent

    def handle_data(self, text):
        self.current.children.append(text)


class DotsSpaceIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = os.environ.get('FLOW_READER_TYPST') or shutil.which('typst')
        packages = os.environ.get('FLOW_READER_PACKAGES')
        if not compiler or not packages:
            raise unittest.SkipTest('Set FLOW_READER_PACKAGES and optionally FLOW_READER_TYPST')
        cls.compiler, cls.packages = compiler, Path(packages)
        temporary = tempfile.TemporaryDirectory(prefix='reader-dots-space-')
        cls.addClassCleanup(temporary.cleanup)
        cls.work = Path(temporary.name)
        cls.entry = cls.work / 'main.typ'
        cls.entry.write_bytes((ROOT / 'tests/fixtures/dots-space.typ').read_bytes())
        project = Project(cls.work, Path('main.typ'), cls.packages, compiler=compiler)
        cls.report = compile_project(project, cls.work / 'html')
        cls.source = (cls.work / 'html/document.html').read_text()

    def test_all_calls_retain_native_math_context_and_spacing(self):
        self.assertEqual(self.report['exitCode'], 0, self.report)
        self.assertTrue(self.report['contentGatePassed'], self.report)
        self.assertEqual(self.report['compilerLossWarnings'], [])
        document = Document(self.source)
        rows = [node for node in document.root.descendants('mrow')
                if node.attrs.get('data-flow-selection-ignore') == 'dots-space']
        self.assertEqual(len(rows), 7)
        for row in rows:
            with self.subTest(row=row.text()):
                self.assertTrue(any(node.tag == 'math' for node in row.ancestors()))
                # apply-reader deliberately suppresses h spacing in HTML. Keep
                # the existing in-math output rather than introducing literal
                # replacement widths or a new operator's implicit spacing.
                self.assertEqual(list(row.descendants('mspace')), [])
                self.assertEqual([node.tag for node in row.descendants()], ['mi'])
                self.assertEqual(row.text(), '⋯')
        for math in document.root.descendants('math'):
            self.assertFalse(any(node.tag == 'math' for node in math.ancestors()),
                             'Nested helpers must flatten into the surrounding equation')
        paragraphs = [' '.join(node.text().split()) for node in document.root.descendants('p')]
        self.assertIn('Before helper ⋯ after helper.', paragraphs)

    def test_inline_helpers_do_not_add_equation_numbers_or_alignment_columns(self):
        document = Document(self.source)
        numbered = [node for node in document.root.descendants('div')
                    if 'flow-equation-number' in node.attrs.get('class', '').split()]
        self.assertEqual([node.text() for node in numbered], ['(1)', '(2)'])
        aligned = [node for node in document.root.descendants('mtable')
                   if 'aligned' in node.attrs.get('class', '').split()]
        self.assertEqual(len(aligned), 1)
        rows = [node for node in aligned[0].children if isinstance(node, Element) and node.tag == 'mtr']
        self.assertEqual(len(rows), 2)
        self.assertEqual([sum(isinstance(node, Element) and node.tag == 'mtd'
                              for node in row.children) for row in rows], [2, 2])

    def test_paged_fixture_matches_the_unmodified_installed_package(self):
        prepare_packages(self.packages, self.work / 'overlay')
        for name, packages in [('original', self.packages), ('reader', self.work / 'overlay')]:
            result = subprocess.run([
                self.compiler, 'compile', '--jobs', '1', '--creation-timestamp', '1760000000',
                '--package-path', str(packages), str(self.entry), str(self.work / (name+'.pdf'))],
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.work / 'original.pdf').read_bytes(),
                         (self.work / 'reader.pdf').read_bytes())


if __name__ == '__main__':
    unittest.main()
