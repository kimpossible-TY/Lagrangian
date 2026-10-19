"""Compile-only source carriers, accepted only when the exported HTML agrees.

The scanner deliberately recognizes a subset of markup. Isolated compilation
must carry each range into a corresponding accepted block with the same identity
and canonical text. Carriers are discarded before publication.
"""

from collections import Counter
import hashlib
import json
import re
import subprocess
import uuid

from flow_reader.compiler.audit import diagnostic_warnings, normalize_content, unhandled_warnings
from flow_reader.compiler.inputs import shadow_sources, source_paths
from flow_reader.document.content import MathHtmlEmbedding
from flow_reader.document.passages import PassageIndex, normalized_offsets
from flow_reader.document.sections import assign_block_ids, split_document

MAX_RANGES = 100000


def compile_source_map(project, dependencies, command, wrapper, baseline, work):
    """Build optional correspondence without making carrier failure a compile failure."""
    carriers = SourceCarriers()
    root = project.root.resolve()
    sources = {path.relative_to(root): carriers.instrument(path)
               for path in source_paths(project, dependencies)}
    sources = {path: value for path, value in sources.items() if value is not None}
    shadow = work / "source-root"
    shadow_sources(root, shadow, sources)
    mapped_command = command.copy()
    mapped_command[mapped_command.index("--root") + 1] = str(shadow)
    mapped_command[mapped_command.index("--deps") + 1] = str(work / "mapped-dependencies.json")
    mapped_command[-1] = str(work / "mapped.html")
    result = subprocess.run(mapped_command, input=wrapper, text=True,
                            capture_output=True, cwd=root, timeout=60)
    if result.returncode or unhandled_warnings(diagnostic_warnings(result.stderr)):
        return {"sourceMap": {}, "sourceMapStatus": "compiler-rejected"}
    annotated = carriers.normalize((work / "mapped.html").read_text())
    mapping = carriers.extract(baseline, annotated)
    return {"sourceMap": mapping,
            "sourceMapStatus": "verified" if carriers.complete else "partial" if mapping else "unmapped"}


def markup_ranges(source):
    """Recognize prose/content calls and whole equations, excluding code/raw.

    Unknown hash expressions are skipped through their line and balanced code
    delimiters. Content arguments of direct calls such as #proof[...] recurse
    in markup mode, including content returned by closures in call arguments.
    Definitions, raw code and strings do not become prose candidates.
    """
    length = len(source)
    call_pattern = re.compile(r"#[\w-]+(?:\.[\w-]+)*")

    def opaque(position, closing=None):
        while position < length:
            if source.startswith("//", position):
                end = source.find("\n", position)
                position = length if end < 0 else end
            elif source.startswith("/*", position):
                depth, position = 1, position + 2
                while position < length and depth:
                    if source.startswith("/*", position):
                        depth, position = depth + 1, position + 2
                    elif source.startswith("*/", position):
                        depth, position = depth - 1, position + 2
                    else:
                        position += 1
            elif source[position] == '"':
                position += 1
                while position < length:
                    if source[position] == "\\":
                        position += 2
                    elif source[position] == '"':
                        position += 1
                        break
                    else:
                        position += 1
            elif source[position] in "([{":
                position = opaque(position + 1, {"(": ")", "[": "]", "{": "}"}[source[position]])
            elif closing and source[position] == closing:
                return position + 1
            elif not closing and source[position] in ")]}":
                return position
            elif not closing and source[position] == "\n":
                return position
            else:
                position += 1
        return position

    def arguments(position, closing):
        while position < length:
            character = source[position]
            if character == closing:
                return position + 1
            if character == "[":
                position = yield from markup(position + 1, True)
            elif character in "({":
                position = yield from arguments(position + 1, {"(": ")", "{": "}"}[character])
            elif character == '"':
                position += 1
                while position < length:
                    if source[position] == "\\":
                        position += 2
                    elif source[position] == '"':
                        position += 1
                        break
                    else:
                        position += 1
            elif source.startswith(("//", "/*"), position):
                position = opaque(position)
            else:
                position += 1
        return position

    def markup(position, closing=False):
        initial = position
        while position < length:
            character = source[position]
            if position == initial or source[position - 1] == "\n":
                prefix = re.match(r"[ \t]*(?:(?:[-+/]|[0-9]+\.)[ \t]+)?", source[position:])
                if prefix.end():
                    position += prefix.end()
                    continue
            if character == "]" and closing:
                return position + 1
            if character == "=" and not source[source.rfind("\n", 0, position) + 1:position].strip():
                position = opaque(position)
                continue
            if (character in "-+" and source[position + 1:position + 2].isspace()
                    and not source[source.rfind("\n", 0, position) + 1:position].strip()):
                position += 1
                continue
            if source.startswith(("//", "/*"), position):
                # Reuse the code skipper, without consuming the next prose line.
                position = opaque(position)
            elif character == "`":
                count = len(source[position:]) - len(source[position:].lstrip("`"))
                end = source.find("`" * count, position + count)
                position = length if end < 0 else end + count
            elif character == "\\":
                position += 2
            elif character == "$":
                end = position + 1
                while end < length and source[end] != "$":
                    if source[end] == "\\":
                        end += 2
                    elif source[end] == "#":
                        call = call_pattern.match(source, end)
                        end = call.end() if call else end + 1
                        while end < length and source[end] in "([{":
                            end = opaque(end + 1, {"(": ")", "[": "]", "{": "}"}[source[end]])
                    else:
                        end += 1
                if end < length:
                    # Labels must stay attached to the equation, inside its
                    # carrier; attaching them to html.elem changes references.
                    label = re.match(r"\s*#?<[^<>\s]+>", source[end + 1:])
                    end += label.end() if label else 0
                    # A computed label can be a following hash expression.
                    # Keep its attachment to the original equation as well.
                    tail = re.match(r"[ \t]*#(?:[\w.-]+|\([\w.-]+\))", source[end + 1:])
                    if tail:
                        stop = end + 1 + tail.end()
                        while stop < length and source[stop] in "([":
                            stop = opaque(stop + 1, {"(": ")", "[": "]"}[source[stop]])
                        end = stop - 1
                    yield position, end + 1, "math"
                position = min(length, end + 1)
            elif character == "#":
                call = call_pattern.match(source, position)
                if not call:
                    end = position + 1
                    if end < length and source[end] in "({":
                        end = opaque(end + 1, {"(": ")", "{": "}"}[source[end]])
                        while end < length and source[end] in "([":
                            end = opaque(end + 1, {"(": ")", "[": "]"}[source[end]])
                        position = end
                    elif end < length and source[end] == "<":
                        end = source.find(">", end + 1)
                        position = length if end < 0 else end + 1
                    else:
                        position = opaque(end)
                    continue
                end = call.end()
                name = call[0][1:]
                if name in {"let", "set", "show", "if", "for", "while", "import", "include", "context"}:
                    position = opaque(end)
                    continue
                if end < length and source[end] == "(":
                    end = yield from arguments(end + 1, ")")
                if end < length and source[end] == "[":
                    position = yield from markup(end + 1, True)
                else:
                    # A variable or unknown expression is not literal prose.
                    position = end
            elif character == "[":
                position = yield from markup(position + 1, True)
            elif character in "\n\r*<>@_{}]":
                if character == "<":
                    end = source.find(">", position + 1)
                    position = length if end < 0 else end + 1
                elif character == "@":
                    label = re.match(r"@[^\s\[\]{}(),;]+", source[position:])
                    position += label.end() if label else 1
                else:
                    position += 1
            else:
                end = position + 1
                while (end < length and source[end] not in '#$[]{}*_<>@`\\\n\r'
                       and not source.startswith(("//", "/*"), end)):
                    end += 1
                start = position
                while start < end and source[start].isspace():
                    start += 1
                stop = end
                while stop > start and source[stop - 1].isspace():
                    stop -= 1
                if stop > start:
                    yield start, stop, "text"
                position = end
        return position

    yield from markup(0)


class SourceCarriers:
    """Private carrier identities and their original saved source ranges."""

    def __init__(self):
        self.attribute = "data-flow-source-" + uuid.uuid4().hex
        self.ranges = {}
        self.verified = False
        self.complete = False

    def instrument(self, path):
        raw = path.read_bytes()
        try:
            source = raw.decode("utf-8")
        except UnicodeDecodeError:
            return None
        digest = hashlib.sha256(raw).hexdigest()
        pieces, previous = [], 0
        for start, end, kind in markup_ranges(source):
            if len(self.ranges) >= MAX_RANGES:
                raise ValueError("Source range carrier limit exceeded")
            identifier = str(len(self.ranges))
            self.ranges[identifier] = {"path": str(path), "source_hash": digest,
                                       "start": start, "end": end, "kind": kind}
            body = source[start:end]
            tag = "div" if (kind == "math" and body[1:2].isspace()
                            and body.rsplit("$", 1)[0][-1:].isspace()) else "span"
            def edge(name):
                return (f'#html.elem("{tag}", attrs: ({json.dumps(self.attribute)}: "{identifier}", '
                        f'"data-flow-source-edge": "{name}"), []);')
            pieces.extend((source[previous:start], edge("start"), body, edge("end")))
            previous = end
        pieces.append(source[previous:])
        return "".join(pieces)

    def normalize(self, content):
        """Keep compile-only empty markers native to their exported namespace."""
        parser = CarrierMathHtml(self.attribute)
        parser.feed(content)
        return normalize_content("".join(parser.output))

    def extract(self, baseline, annotated):
        """Keep only uniquely corresponding accepted block identities and text.

        Empty carriers can change Typst's paragraph/whitespace scaffolding. The
        original HTML is always delivered. Changed or missing blocks are never
        mapped; duplicate identities require the complete ordered block sequence
        to agree so an earlier change cannot shift their occurrence numbers.
        """
        self.verified = self.complete = False
        bundle = split_document(annotated, "source-map")
        index = CarrierPassages(assign_block_ids(annotated), bundle.manifest["blocks"], self)
        if not index.valid or index.carrier_stack:
            return {}
        accepted = split_document(baseline, "source-map").passages
        original = {part["key"]: part["text"] for part in accepted}
        def signature(part):
            return part["key"].rsplit("-", 1)[0], part["text"]
        before, after = list(map(signature, accepted)), list(map(signature, index.passages))
        counts = Counter(before + after)
        self.complete = before == after
        result = {part["key"]: {"text": part["text"], "ranges": part["source_ranges"]}
                for part in index.passages
                if part.get("source_ranges") and original.get(part["key"]) == part["text"]
                and (self.complete or counts[signature(part)] == 2)}
        self.verified = bool(result)
        return result


class CarrierMathHtml(MathHtmlEmbedding):
    """Empty carriers inside math must not create HTML integration wrappers."""

    def __init__(self, attribute):
        super().__init__()
        self.attribute, self.retagged, self.tag_text = attribute, [], None

    def get_starttag_text(self):
        return self.tag_text or super().get_starttag_text()

    def start(self, tag, self_closing, attrs):
        in_math = (self.stack and self.stack[-1][1] == "math"
                   and self.stack[-1][0] not in self.TOKENS)
        if in_math and self.attribute in dict(attrs):
            self.tag_text = re.sub(r"^<[^\s>]+", "<mrow", super().get_starttag_text())
            if not self_closing:
                self.retagged.append((len(self.stack), tag))
            tag = "mrow"
        try:
            super().start(tag, self_closing, attrs)
        finally:
            self.tag_text = None

    def handle_endtag(self, tag):
        if self.retagged and self.retagged[-1] == (len(self.stack) - 1, tag):
            self.retagged.pop()
            tag = "mrow"
        super().handle_endtag(tag)


class CarrierPassages(PassageIndex):
    """Translate compiler-carried ranges into normalized HTML block offsets."""

    def __init__(self, source, blocks, carriers):
        self.carriers, self.carrier_stack, self.raw_ranges = carriers, [], {}
        self.number_depth = None
        self.valid = True
        super().__init__(source, blocks)

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        identifier = attributes.get(self.carriers.attribute)
        super().handle_starttag(tag, attrs)
        if identifier in self.carriers.ranges:
            if attributes.get("data-flow-source-edge") == "start":
                if self.carrier_stack:
                    self.valid = False
                self.carrier_stack.append(identifier)
            elif self.carrier_stack and self.carrier_stack[-1] == identifier:
                self.carrier_stack.pop()
            else:
                self.valid = False
        if "flow-equation-number" in attributes.get("class", "").split():
            self.number_depth = len(self.stack)

    def handle_data(self, data):
        if (self.active and self.stack and not self.stack[-1][1]
                and self.carrier_stack and self.number_depth is None):
            passage = self.active[-1]
            offset = sum(map(len, passage["text"]))
            ranges = self.raw_ranges.setdefault(id(passage), [])
            identifier = self.carrier_stack[-1]
            if ranges and ranges[-1][2] == identifier and ranges[-1][1] == offset:
                ranges[-1][1] += len(data)
            else:
                ranges.append([offset, offset + len(data), identifier])
        super().handle_data(data)

    def handle_endtag(self, tag):
        if self.stack and self.stack[-1][0] == tag:
            passage = self.stack[-1][2]
            if passage:
                _, offsets = normalized_offsets("".join(passage["text"]))
                result = []
                for start, end, identifier in self.raw_ranges.get(id(passage), []):
                    covered = [i for i, offset in enumerate(offsets) if start <= offset < end]
                    if covered:
                        result.append({**self.carriers.ranges[identifier],
                                       "text_start": covered[0], "text_end": covered[-1] + 1})
                passage["source_ranges"] = result
            if self.number_depth == len(self.stack):
                self.number_depth = None
        super().handle_endtag(tag)
