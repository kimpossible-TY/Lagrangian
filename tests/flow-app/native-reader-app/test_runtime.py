"""NA11 initial MathML runtime: real offline relocated helper and native painter.

No optional skips. All mutable data stays on DevSSD. Frozen core is only read
while constructing the fixture; consumption denies all source/dependency roots.
"""
import hashlib
import ctypes
from collections import Counter
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import unittest

DEV = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
REPO = Path(__file__).resolve().parents[3]
CORE = REPO
CORE_SHA = '9b2dc87651eb16a809bb48dbe4539614cfe30d6a'
HELPER_SHA = CORE_SHA
MODEL_SHA = CORE_SHA
STAGE = DEV / 'build/delivery-production/runtime'
EVIDENCE = DEV / 'test-output/delivery-production/NA13/runtime'
RUNTIME = DEV / 'dependencies/native-runtime'
NODE = DEV / 'dependencies/portable-node/node-v22.23.5-darwin-arm64/bin/node'
FROZEN = ['tools/flow-reader/native/math_layout.mjs', 'apps/macos/NativeReaderDocument.swift',
          'apps/macos/NativeReaderOperations.swift', 'apps/macos/NativeReaderObjectRenderer.swift',
          'apps/macos/NativeReaderPagedLayout.swift',
          'tests/flow-app/native-reader-app/fixtures/objects.typ',
          'tests/flow-app/native-reader-app/fixtures/objects.expect.json']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def font_evidence(runtime):
    """Independent development-only reader; FreeType is not a product dependency."""
    library = Path('/opt/homebrew/opt/freetype/lib/libfreetype.6.dylib').resolve()
    ft = ctypes.CDLL(str(library))
    class Name(ctypes.Structure):
        _fields_ = [('platform', ctypes.c_ushort), ('encoding', ctypes.c_ushort),
                    ('language', ctypes.c_ushort), ('nameID', ctypes.c_ushort),
                    ('string', ctypes.POINTER(ctypes.c_ubyte)), ('length', ctypes.c_uint)]
    ft.FT_Init_FreeType.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
    ft.FT_New_Face.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.POINTER(ctypes.c_void_p)]
    ft.FT_Get_Sfnt_Name_Count.argtypes = [ctypes.c_void_p]
    ft.FT_Get_Sfnt_Name_Count.restype = ctypes.c_uint
    ft.FT_Get_Sfnt_Name.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.POINTER(Name)]
    ft.FT_Done_Face.argtypes = [ctypes.c_void_p]
    ft.FT_Done_FreeType.argtypes = [ctypes.c_void_p]
    handle = ctypes.c_void_p()
    if ft.FT_Init_FreeType(ctypes.byref(handle)):
        raise RuntimeError('FreeType init failed')
    records = []
    original = '(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.'
    added = 'Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n' + original
    try:
        for p in sorted((runtime / 'node_modules/@mathjax/mathjax-newcm-font/chtml/woff2').glob('*.woff2')):
            face = ctypes.c_void_p()
            if ft.FT_New_Face(handle, os.fsencode(p), 0, ctypes.byref(face)):
                raise RuntimeError('FreeType font parse failed: ' + str(p))
            names = []
            try:
                for index in range(ft.FT_Get_Sfnt_Name_Count(face)):
                    n = Name()
                    if ft.FT_Get_Sfnt_Name(face, index, ctypes.byref(n)):
                        raise RuntimeError('FreeType name parse failed')
                    if n.nameID not in [0, 5, 13, 14]:
                        continue
                    raw = ctypes.string_at(n.string, n.length)
                    value = raw.decode('utf-16-be' if n.platform in [0, 3] else 'mac_roman')
                    names.append(dict(nameID=n.nameID, platform=n.platform, encoding=n.encoding,
                                      language=n.language, value=value, rawSHA256=hashlib.sha256(raw).hexdigest()))
            finally:
                ft.FT_Done_Face(face)
            copyrights = {n['value'] for n in names if n['nameID'] == 0 and n['value'].strip()}
            if copyrights == {original}:
                category = 'original-gust'
            elif copyrights == {added}:
                category = 'mathjax-plus-original-gust'
            else:
                raise RuntimeError('unexpected original font notice: ' + repr(copyrights))
            records.append(dict(path=str(p.relative_to(runtime)), sha256=sha(p), category=category,
                                noticeSHA256=hashlib.sha256(next(iter(copyrights)).encode()).hexdigest(), names=names))
    finally:
        ft.FT_Done_FreeType(handle)
    counts = dict(Counter(r['category'] for r in records))
    if len(records) != 105 or counts != {'original-gust': 84, 'mathjax-plus-original-gust': 21}:
        raise RuntimeError('font count/notice classification mismatch: ' + repr(counts))
    return dict(reader='FT_Get_Sfnt_Name', library=str(library), librarySHA256=sha(library),
                parseErrors=0, count=len(records), classes=counts, fonts=records)


# This harness calls the frozen production decode/draw/worker implementations.
# Oracle: frozen author-written a/b fraction topology and scale-independent pt
# metrics, plus glyph IDs; range cases only claim delivery and paint smoke.
SWIFT = r'''
import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
func check(_ ok: Bool, _ message: String) throws {
    if !ok { throw NSError(domain: message, code: 1) }
}
final class WorkerLog: @unchecked Sendable {
    private let lock = NSLock()
    private var records = [NativeMathExecution]()
    func append(_ value: NativeMathExecution) { lock.lock(); records.append(value); lock.unlock() }
    var values: [NativeMathExecution] { lock.lock(); defer { lock.unlock() }; return records }
}
@main struct RuntimePaint {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let paintOnly = CommandLine.arguments.contains("--paint-only")
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("paint-input.json"))) as! [String: Any]
        let oracle = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("objects.expect.json"))) as! [String: Any]
        let expected = oracle["indivisibleMath20"] as! [String: Any]
        let runtime = URL(fileURLWithPath: config["runtime"] as! String)
        let log = WorkerLog()
        let worker = NativeMathWorker(node: URL(fileURLWithPath: config["node"] as! String), helper: runtime.appendingPathComponent("helper.mjs"), runtime: runtime, record: { log.append($0) })
        let identity = NativeDocumentIdentity(documentID: "NA11", serviceID: "offline", revision: "frozen-NA11", scope: .fixture)
        var rows = [[String: Any]]()
        for row in config["cases"] as! [[String: Any]] {
            let width = row["width"] as! Double, font = row["fontSize"] as! Double
            let context = NativeObjectContext(identity: identity, snapshotGeneration: 1, generation: 1, width: width, fontSize: font, fontName: "system", theme: .light, mode: .reflow, pageHeight: 1200)
            let math = NativeMath(mathML: row["mathML"] as! String, normalizedText: "", display: row["display"] as! Bool)
            let bytes = try Data(contentsOf: root.appendingPathComponent(row["file"] as! String))
            let layout = try NativeMathLayout.decode(bytes, math: math, context: context, width: width)
            let whole = layout.whole
            let scene = try NativeVectorScene.decode(Data(whole.svg.utf8), dark: false)
            try check(!scene.shapes.isEmpty && scene.image == nil, "actual native glyph paths")
            if row["name"] as! String == "fraction" {
                try check(whole.width / font * 20 >= expected["minimumWidth"] as! Double && whole.width / font * 20 <= expected["maximumWidth"] as! Double, "independent fraction width")
                try check(whole.ascent / font * 20 > expected["minimumAscent"] as! Double && whole.descent / font * 20 > expected["minimumDescent"] as! Double, "independent baseline extents")
                for key in ["numeratorGlyph", "denominatorGlyph"] { try check(whole.svg.contains(expected[key] as! String), "independent glyph identity") }
            }
            let scale = 4.0, w = Int(ceil(whole.width * scale + 24)), h = Int(ceil((whole.ascent + whole.descent) * scale + 24))
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw NativeObjectError.budget }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
            scene.draw(in: ctx, rect: CGRect(x: 12, y: 12, width: whole.width * scale, height: (whole.ascent + whole.descent) * scale))
            let axis = 12 + whole.ascent * scale - (expected["axisEm"] as! Double) * font * scale
            let thickness = (expected["ruleThicknessEm"] as! Double) * font * scale
            let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
            var ink = 0, above = 0, below = 0, rule = 0
            for y in 0..<h { for x in 0..<w {
                if pixels[y * ctx.bytesPerRow + x * 4] < 128 {
                    ink += 1
                    if Double(y) < axis - thickness { above += 1 }
                    else if Double(y) > axis + thickness { below += 1 }
                    else { rule += 1 }
                }
            } }
            try check(ink > 10, "native paint nonempty")
            if row["name"] as! String == "fraction" { try check(above > 10 && below > 10 && rule > 10, "independent fraction paint topology") }
            let dest = CGImageDestinationCreateWithURL(root.appendingPathComponent((row["file"] as! String) + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); try check(CGImageDestinationFinalize(dest), "PNG write")
            rows.append(["file": row["file"]!, "width": width, "fontSize": font, "display": math.display, "ink": ink, "above": above, "below": below, "rule": rule, "shapes": scene.shapes.count])
            // Exercise production async worker once per width/font/display group.
            if row["name"] as! String == "fraction" {
                if !paintOnly {
                    let actual = try await worker.calculate(math, context: context, width: width)
                    try check(actual.whole.svg == layout.whole.svg, "actual production worker output")
                }
                do { _ = try NativeMathLayout.decode(bytes, math: math, context: context, width: width + 1); throw NSError(domain: "stale accepted", code: 2) }
                catch NativeObjectError.stale { }
                let later = NativeObjectContext(identity: identity, snapshotGeneration: 1, generation: 2, width: width, fontSize: font, fontName: "system", theme: .light, mode: .reflow, pageHeight: 1200)
                do { _ = try NativeMathLayout.decode(bytes, math: math, context: later, width: width); throw NSError(domain: "stale generation accepted", code: 2) }
                catch NativeObjectError.stale { }
            }
        }
        if !paintOnly {
        let first = (config["cases"] as! [[String: Any]])[0]
        let math = NativeMath(mathML: first["mathML"] as! String, normalizedText: "", display: false)
        let c = NativeObjectContext(identity: identity, snapshotGeneration: 1, generation: 1, width: 320, fontSize: 14, fontName: "system", theme: .light, mode: .reflow, pageHeight: 1200)
        let slow = root.appendingPathComponent("slow.mjs")
        try "setTimeout(()=>process.stdout.write('{}'),10000);".write(to: slow, atomically: true, encoding: .utf8)
        let deadline = NativeMathWorker(node: URL(fileURLWithPath: config["node"] as! String), helper: slow, runtime: runtime, timeout: 0.1, record: { log.append($0) })
        do { _ = try await deadline.calculate(math, context: c, width: 320); throw NSError(domain: "timeout accepted", code: 2) }
        catch NativeObjectError.unsupported("math-helper-timeout") { }
        let cancel = NativeMathWorker(node: URL(fileURLWithPath: config["node"] as! String), helper: slow, runtime: runtime, record: { log.append($0) })
        let start = ProcessInfo.processInfo.systemUptime
        let pending = Task { try await cancel.calculate(math, context: c, width: 320) }
        try await Task.sleep(nanoseconds: 100000000); pending.cancel()
        do { _ = try await pending.value; throw NSError(domain: "cancel accepted", code: 2) }
        catch NativeObjectError.cancelled { }
        try check(ProcessInfo.processInfo.systemUptime - start < 2, "bounded child cancellation")
        let flood = root.appendingPathComponent("flood.mjs")
        try "process.stdout.write('x'.repeat(9*1024*1024));".write(to: flood, atomically: true, encoding: .utf8)
        let budget = NativeMathWorker(node: URL(fileURLWithPath: config["node"] as! String), helper: flood, runtime: runtime, record: { log.append($0) })
        do { _ = try await budget.calculate(math, context: c, width: 320); throw NSError(domain: "budget accepted", code: 2) }
        catch NativeObjectError.budget { }
        }
        let result: [String: Any] = ["matrix": rows, "count": rows.count, "skip": 0, "staleRejected": true, "timeoutRejected": !paintOnly, "cancelRejected": !paintOnly, "budgetRejected": !paintOnly,
            "workerChecksExecuted": !paintOnly, "sourceReadsDenied": paintOnly,
            "workerExecutions": try JSONSerialization.jsonObject(with: JSONEncoder().encode(log.values)),
            "knownUnsupported": ["NA10 final TeX helper", "general math fidelity", "frozen helper display=false conversion", "frozen bare Cyrillic unsupported-svg-style", "macOS13 runtime", "GUI/AX", "final .app delivery"]]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent(paintOnly ? "native-paint.json" : "native-worker.json")); print(String(decoding: data, as: UTF8.self))
    }
}
'''


class RuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = EVIDENCE / ('run-' + str(time.time_ns()))
        cls.out.mkdir(parents=True)
        cls.commands = []
        cls.env = {}
        for name, value in {'TMPDIR': DEV / 'tmp/delivery-production',
                            'CLANG_MODULE_CACHE_PATH': DEV / 'cache/delivery-production/clang',
                            'SWIFT_MODULECACHE_PATH': DEV / 'cache/delivery-production/swift',
                            'HOME': DEV / 'tmp/delivery-production/empty-home'}.items():
            value.mkdir(parents=True, exist_ok=True)
            cls.env[name] = str(value)
        cls.env.update(NODE_PATH='', NODE_OPTIONS='', PATH='/usr/bin:/bin')
        def command(argv, *, input=None, expected=0, timeout=60, cwd=None):
            argv = list(map(str, argv)); started = time.monotonic()
            try:
                p = subprocess.run(argv, input=input, capture_output=True, text=True, timeout=timeout,
                                   env=cls.env, cwd=cwd or cls.out)
                record = dict(argv=argv, cwd=str(cwd or cls.out), exit=p.returncode, elapsed=time.monotonic()-started, stdout=p.stdout, stderr=p.stderr)
            except subprocess.TimeoutExpired as e:
                record = dict(argv=argv, exit=None, timeout=True, stdout=str(e.stdout), stderr=str(e.stderr))
                cls.commands.append(record); save(cls.out / 'commands.json', cls.commands)
                raise
            if input is not None:
                record['stdin'] = input
            cls.commands.append(record); save(cls.out / 'commands.json', cls.commands)
            if p.returncode != expected:
                raise RuntimeError(f'exit {p.returncode}, expected {expected}: {argv}: {p.stderr[:3000]}')
            return p.stdout
        cls.command = staticmethod(command)
        for p in [NODE, Path('/usr/bin/sandbox-exec'), Path('/usr/bin/swiftc'), RUNTIME / 'package-lock.json']:
            if not p.exists():
                raise RuntimeError('required prerequisite missing: ' + str(p))
        head = command(['/usr/bin/git', '-C', CORE, 'rev-parse', 'HEAD']).strip()
        if subprocess.run(['/usr/bin/git', '-C', str(CORE), 'merge-base', '--is-ancestor', CORE_SHA, head]).returncode != 0:
            raise RuntimeError('frozen core revision mismatch')
        frozen = cls.out / 'frozen'; frozen.mkdir()
        hashes = []
        for rel in FROZEN:
            # Read committed bytes only; do not observe a changing writer's files.
            data = subprocess.check_output(['/usr/bin/git', '-C', str(CORE), 'show', CORE_SHA + ':' + rel])
            p = frozen / Path(rel).name; p.write_bytes(data)
            component = HELPER_SHA if rel.endswith(('math_layout.mjs', 'NativeReaderObjectRenderer.swift')) else MODEL_SHA if rel.endswith(('NativeReaderDocument.swift', 'NativeReaderOperations.swift')) else CORE_SHA
            original = subprocess.check_output(['/usr/bin/git', '-C', str(CORE), 'show', component + ':' + rel])
            if original != data:
                raise RuntimeError('component provenance mismatch: ' + rel)
            hashes.append(dict(path=rel, sha256=sha(p), componentSHA=component))
        proof = dict(coreSHA=CORE_SHA, contractSHA=MODEL_SHA, componentSHA=HELPER_SHA, files=hashes,
                     helperSHA256=sha(frozen / 'math_layout.mjs'), sourcePatchBaseline='cc790bc1778dd7560984eafca93f0d6c052805d4')
        cls.proof = cls.out / 'proof-input.json'; save(cls.proof, proof)
        cls.helper = frozen / 'math_layout.mjs'
        cls.fonts = font_evidence(RUNTIME)
        save(cls.out / 'font-license-evidence.json', cls.fonts)
        proof['fontLicenseEvidenceSHA256'] = sha(cls.out / 'font-license-evidence.json')
        save(cls.proof, proof)
        command([NODE, REPO / 'scripts/prepare-native-reader-runtime.mjs', '--runtime-source', RUNTIME,
                 '--helper', cls.helper, '--node', NODE, '--output', STAGE, '--proof-input', cls.proof], timeout=180)
        cls.manifest = json.loads((STAGE / 'runtime-manifest.json').read_text())
        installed = cls.out / 'relocated-installed'; installed.mkdir()
        cls.runtime = installed / 'Resources/native-runtime'
        shutil.copytree(STAGE, cls.runtime, symlinks=True)
        cls.node = cls.runtime / 'node/bin/node'
        blocked = [DEV / 'worktrees', DEV / 'dependencies', Path.home() / 'Library/Caches',
                   Path('/Users/taeyoung/.npm'), Path('/Users/taeyoung/.node_modules'),
                   Path('/Users/taeyoung/.node_libraries'), Path('/opt/homebrew/lib/node_modules'),
                   Path('/opt/homebrew/Cellar/node/26.13.1/lib/node')]
        cls.profile = '(version 1)(allow default)(deny network*)' + ''.join(
            '(deny file-read* (subpath ' + json.dumps(str(p)) + '))'
            for p in blocked)
        cls.sandbox = ['/usr/bin/sandbox-exec', '-p', cls.profile]
        # Mandatory real OS denial checks precede all consumption evidence.
        for code in ["require('net').createConnection({host:'127.0.0.1',port:9})", "require('net').createServer().listen(0,'127.0.0.1')"]:
            command(cls.sandbox + [cls.node, '-e', code], expected=1)
            if 'EPERM' not in cls.commands[-1]['stderr']:
                raise RuntimeError('network denial not proven')
        for denied in [REPO / 'package.json', RUNTIME / 'package.json', DEV / 'dependencies/mathjax413/package.json',
                       Path.home() / 'Library/Caches']:
            operation = 'readdirSync' if denied.is_dir() else 'readFileSync'
            if not denied.exists():
                raise RuntimeError('required denial probe input missing: ' + str(denied))
            command(cls.sandbox + [cls.node, '-e', 'require("fs").' + operation + '(process.argv[1])', denied], expected=1)
            if 'EPERM' not in cls.commands[-1]['stderr']:
                raise RuntimeError('source/scratch/cache denial not proven: ' + str(denied))
        cls.verify = json.loads(command(cls.sandbox + [cls.node, cls.runtime / 'verify-runtime.mjs', '--verify', cls.runtime, '--node', cls.node], timeout=180))
        oracle = json.loads((frozen / 'objects.expect.json').read_text())
        cases = []
        formulas = [('fraction', oracle['indivisibleMathML'])] + [
            (name, '<math><msub><' + tag + '>' + char + '</' + tag + '><mn>1</mn></msub></math>')
            for name, tag, char in [('cyrillic', 'mi', 'Ж'), ('hebrew', 'mi', 'א'),
                                    ('script', 'mi', '𝒜'), ('arrows', 'mo', '⟿'), ('shapes', 'mo', '♠')]]
        loaded = set()
        for width in oracle['widths']:
            for font in oracle['fonts']:
                for display in [False, True]:
                    for name, mml in formulas:
                        if display:
                            mml = mml.replace('<math>', '<math display="block">')
                        data = dict(mathML=mml, width=width, fontSize=font, font='MathJaxNewcm',
                                    context=dict(revision='frozen-NA11', generation=1, theme='light'))
                        raw = command(cls.sandbox + [cls.node, cls.runtime / 'helper.mjs', '--runtime', cls.runtime], input=json.dumps(data))
                        result = json.loads(raw)
                        filename = f'{name}-{width}-{font}-{display}.json'
                        (cls.out / filename).write_text(raw)
                        loaded.update(result['runtime']['loaded'])
                        cases.append(dict(name=name, width=width, fontSize=font, display=display, mathML=mml, file=filename))
        save(cls.out / 'dynamic-ranges.json', sorted(loaded))
        save(cls.out / 'paint-input.json', dict(runtime=str(cls.runtime), node=str(cls.node), cases=cases))
        shutil.copyfile(frozen / 'objects.expect.json', cls.out / 'objects.expect.json')
        swift = cls.out / 'RuntimePaint.swift'; swift.write_text(SWIFT)
        cls.binary = cls.out / 'RuntimePaint'
        command(['/usr/bin/swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-macosx13.0',
                 '-module-cache-path', cls.env['SWIFT_MODULECACHE_PATH'],
                 *[frozen / Path(p).name for p in FROZEN if p.endswith('.swift')], swift, '-o', cls.binary], timeout=180)
        command(cls.sandbox + [cls.binary, cls.out, '--paint-only'], timeout=120)
        # sandbox-exec cannot be nested (sandbox_apply exits 71). Production
        # NativeMathWorker supplies its own deny-network/write sandbox. Its
        # execution is separate from source-denied helper -> native paint proof.
        command([cls.binary, cls.out], timeout=120)
        cls.paint = json.loads((cls.out / 'native-paint.json').read_text())
        cls.worker = json.loads((cls.out / 'native-worker.json').read_text())
        save(EVIDENCE / 'latest.json', dict(output=str(cls.out), stage=str(STAGE), manifestSHA256=sha(STAGE / 'runtime-manifest.json'),
             proofSHA256=sha(cls.proof), paintSHA256=sha(cls.out / 'native-paint.json'), verifyReportSHA256=hashlib.sha256((json.dumps(cls.verify, indent=2)+'\n').encode()).hexdigest()))

    def test_complete_locked_payload_and_bound_report(self):
        self.assertEqual(self.verify['packages'], 18)
        self.assertEqual(self.verify['helperSHA256'], sha(self.helper))
        self.assertEqual(self.manifest['verifyReportSHA256'], hashlib.sha256((json.dumps(self.verify, indent=2)+'\n').encode()).hexdigest())
        self.assertEqual(self.manifest['proof']['coreSHA'], CORE_SHA)

    def test_required_native_matrix_and_independent_fraction(self):
        self.assertEqual(self.paint['count'], 108)
        self.assertEqual(self.paint['skip'], 0)
        self.assertTrue(all(r['ink'] > 10 and r['shapes'] > 0 for r in self.paint['matrix']))
        self.assertTrue(self.paint['sourceReadsDenied'])
        self.assertTrue(self.worker['workerChecksExecuted'])
        self.assertEqual(len(self.worker['workerExecutions']), 21)
        self.assertTrue(all(self.worker[k] for k in ['staleRejected', 'timeoutRejected', 'cancelRejected', 'budgetRejected']))

    def test_nondefault_dynamic_ranges_are_actually_consumed(self):
        ranges = json.loads((self.out / 'dynamic-ranges.json').read_text())
        for name in ['cyrillic', 'hebrew', 'script', 'arrows', 'shapes']:
            self.assertTrue(any('/dynamic/' + name + '.js' in p for p in ranges), (name, ranges))

    def test_portable_runtime_policy_and_missing_preflight(self):
        policy = self.manifest['node']
        self.assertEqual(policy['policy'], 'portable-bundled')
        self.assertEqual(policy['minOS'], '11.0')
        self.assertEqual(policy['hostLibraries'], [])
        self.command(self.sandbox + [self.node, self.runtime / 'verify-runtime.mjs', '--verify', self.runtime, '--node', '/nonexistent/node'], expected=1)

    def test_original_font_notices_match_independent_freetype_reader(self):
        preserved = self.manifest['fontPreservation']
        self.assertEqual(preserved['fontCount'], 105)
        self.assertEqual(preserved['classes'], self.fonts['classes'])
        independently_read = font_evidence(self.runtime)
        self.assertEqual(independently_read['fonts'], self.fonts['fonts'])
        expected = [{k: r[k] for k in ['path', 'sha256', 'noticeSHA256', 'category']} for r in self.fonts['fonts']]
        self.assertEqual(preserved['fonts'], expected)
        self.assertEqual(preserved['noticesSHA256'], sha(self.runtime / 'THIRD-PARTY-NOTICES.md'))

    def test_hostile_math_is_not_silently_counted(self):
        payload = dict(mathML='<math><img src="https://example.test/evil"/></math>', width=320, fontSize=14,
                       font='MathJaxNewcm', context=dict(revision='frozen-NA11', generation=1, theme='light'))
        self.command(self.sandbox + [self.node, self.runtime / 'helper.mjs', '--runtime', self.runtime], input=json.dumps(payload), expected=2)
        self.assertIn('unsupported', self.commands[-1]['stderr'])

    def test_canonical_typst_prebuilt_offline(self):
        compiler = str(DEV / 'dependencies/portable-typst/typst-aarch64-apple-darwin/typst')
        if not compiler:
            self.fail('required prebuilt Typst missing')
        self.command(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', compiler,
                      'compile', '--root', REPO, REPO / 'docs/tinymist/dev/native-reader-runtime.typ', self.out / 'native-reader-runtime.pdf'])

    @classmethod
    def tearDownClass(cls):
        save(cls.out / 'summary.json', dict(testCases=7, requiredSkip=0, nativeCases=cls.paint['count'],
             proof=cls.manifest['proof'], manifestSHA256=sha(STAGE / 'runtime-manifest.json'),
             paintSHA256=sha(cls.out / 'native-paint.json'), commandsSHA256=sha(cls.out / 'commands.json'),
             knownUnsupported=cls.paint['knownUnsupported']))


if __name__ == '__main__':
    unittest.main()
