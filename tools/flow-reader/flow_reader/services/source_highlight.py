"""Prove an explicit source highlight against the complete compiled HTML body."""

from dataclasses import replace
import hashlib
import os
from pathlib import Path
import re
import stat
import tempfile
import unicodedata
import uuid

from flow_reader.compiler.build import compile_project
from flow_reader.compiler.execution import CompileRequest
from flow_reader.compiler.inputs import shadow_sources, source_paths
from flow_reader.document.passages import PassageIndex, locate_passages, normalized, normalized_offsets, occurrences, validate_fragments
from flow_reader.document.sections import assign_block_ids, split_document
from flow_reader.services.source_mapping import mapped_source_range


class StaleSelection(ValueError):
    """The accepted inputs changed while an explicit edit was being verified."""



def selection_pattern(fragments):
    """Candidates are hints only; compilation must prove their rendered origin."""
    patterns, mathematical = [], False
    for fragment in fragments:
        parts = fragment.get("segments", [{"text": fragment["exact"]}])
        if not isinstance(parts, list) or not 1 <= len(parts) <= 16:
            raise ValueError("Invalid source selection segments")
        if any(not isinstance(part, dict) or not isinstance(part.get("text"), str) for part in parts):
            raise ValueError("Invalid source selection segment")
        if normalized("".join(part.get("text", "") for part in parts)) != normalized(fragment["exact"]):
            raise ValueError("Selection segments do not match their quotation")
        pattern = []
        for number, part in enumerate(parts):
            if part.get("math"):
                if part.get("complete") is not True:
                    return None, True
                mathematical = True
                pattern.append(r"\$(?:[^$\\]|\\.){1,16384}\$")
            else:
                value = part["text"]
                if number == 0:
                    value = value.lstrip()
                if number == len(parts) - 1:
                    value = value.rstrip()
                text, _ = normalized_offsets(value, True)
                # Keep boundary spaces between text and mathematical segments.
                if value[:1].isspace():
                    text = " " + text
                if text.strip() and value[-1:].isspace():
                    text += " "
                pattern.append(re.escape(text))
        patterns.append("".join(pattern))
    return re.compile(" ".join(patterns)), mathematical


class MarkedPassages(PassageIndex):
    """Keep marker intervals in canonical passage coordinates after HTML parsing."""

    def __init__(self, source, block_sections, token):
        self.token = token
        self.marker_depth = None
        self.number_depth = None
        self.markers = 0
        self.marked = {}
        self.raw = {}
        super().__init__(source, block_sections)

    def handle_starttag(self, tag, attrs):
        marked = dict(attrs).get("data-flow-source-edit") == self.token
        super().handle_starttag(tag, attrs)
        if marked:
            self.markers += 1
            self.marker_depth = len(self.stack)
        if "flow-equation-number" in dict(attrs).get("class", "").split():
            self.number_depth = len(self.stack)

    def handle_data(self, data):
        if self.active and self.stack and not self.stack[-1][1]:
            passage = self.active[-1]
            if self.marker_depth and self.number_depth is None:
                start = sum(map(len, passage["text"]))
                interval = self.marked.setdefault(id(passage), [start, start])
                interval[1] = start + len(data)
        super().handle_data(data)

    def handle_endtag(self, tag):
        if self.stack and self.stack[-1][0] == tag:
            passage = self.stack[-1][2]
            if passage:
                self.raw[id(passage)] = "".join(passage["text"])
            if self.marker_depth == len(self.stack):
                self.marker_depth = None
            if self.number_depth == len(self.stack):
                self.number_depth = None
        super().handle_endtag(tag)

    def intervals(self):
        result = []
        for ordinal, passage in enumerate(self.passages):
            interval = self.marked.get(id(passage))
            if interval is None:
                continue
            text, offsets = normalized_offsets(self.raw[id(passage)])
            selected = [i for i, offset in enumerate(offsets)
                        if interval[0] <= offset < interval[1] and not text[i].isspace()]
            if selected:
                result.append((ordinal, selected[0], selected[-1] + 1))
        return result


def shadow_project(root, entry, relative, destination, updated):
    """Copy only the changed path; all other inputs remain read-only links."""
    files = {Path(entry): (root / entry).read_text(), relative: updated}
    shadow_sources(root, destination, files)


def source_candidates(project, dependencies, pattern):
    for path in source_paths(project, dependencies):
        original = path.read_bytes()
        try:
            source = original.decode("utf-8")
        except UnicodeDecodeError:
            continue
        text, offsets = normalized_offsets(source, True)
        for match in pattern.finditer(text):
            if match.start() == match.end():
                continue
            start, end = offsets[match.start()], offsets[match.end() - 1] + 1
            if end - start <= 65536:
                yield path, original, source, start, end


def math_hint(text):
    """Rank candidates only; this never authorizes a source edit."""
    result = []
    for character in unicodedata.normalize("NFKD", text):
        name = unicodedata.name(character, "")
        if name.startswith(("GREEK SMALL LETTER ", "GREEK CAPITAL LETTER ")):
            result.append(name.rsplit(" ", 1)[-1].lower())
        elif character.isalnum():
            result.append(character.lower())
    return "".join(result)


def paged_candidate_compiles(project, destination):
    """The shared source must also compile with the original paged packages."""
    result = project.execute(CompileRequest(
        compiler=project.compiler, root=project.root, packages=project.packages.resolve(),
        target="pdf", entry=project.root / project.relative_entry(),
        fonts=tuple((project.root / font).resolve() for font in project.fonts)))
    if result.returncode == 0:
        destination.write_bytes(result.artifact)
    return result.returncode == 0


def apply_highlight(project, output, bundle, dependencies, fragments, fresh, writer=None):
    clean = validate_fragments(fragments)
    locations = locate_passages(bundle.passages, clean)
    if any(location["state"] != "located" for location in locations):
        return "unmapped"
    expected = []
    for fragment, location in zip(clean, locations):
        ordinal = next(i for i, passage in enumerate(bundle.passages)
                       if passage["key"] == location["key"])
        text = bundle.passages[ordinal]["text"]
        start = list(occurrences(text, fragment["exact"]))[location["occurrence"]]
        expected.append((ordinal, start, start + len(fragment["exact"])))
    pattern, mathematical = selection_pattern(fragments)
    if pattern is None:
        return "unsupported"
    candidates, best = [], -1
    prefix, _ = normalized_offsets(clean[0]["prefix"], True)
    suffix, _ = normalized_offsets(clean[-1]["suffix"], True)
    math_text = "".join(part["text"] for fragment in fragments
                        for part in fragment.get("segments", []) if part.get("math"))
    hint = math_hint(math_text)
    # Rendered references (for example, "Equation (3.4.25)") do not appear
    # literally in Typst source. Prefer the compiler-carried source intervals
    # when they cover this exact selection, then keep the same isolated compile
    # proof below before writing anything.
    mapped = mapped_source_range(project, dependencies, bundle, clean)
    mapped_candidate = None
    if mapped and mapped.get("status") == "located":
        path = mapped["path"]
        spans = mapped["spans"]
        raw = path.read_bytes()
        source = raw.decode("utf-8")
        if hashlib.sha256(raw).hexdigest() != mapped["source_hash"]:
            return "stale"
        start = min(span[1] for span in spans)
        end = max(span[2] for span in spans)
        if 0 <= start < end <= len(source):
            mapped_candidate = (path, raw, source, start, end)

    candidates_to_check = (
        [mapped_candidate]
        if mapped_candidate is not None
        else source_candidates(project, dependencies, pattern)
    )
    for candidate in candidates_to_check:
        _, _, source, start, end = candidate
        before, _ = normalized_offsets(source[max(0, start - 256):start], True)
        after, _ = normalized_offsets(source[end:end + 256], True)
        score = 0
        for context, observed, preceding in ((prefix, before, True), (suffix, after, False)):
            if not context:
                continue
            matches = observed.endswith if preceding else observed.startswith
            if matches(context):
                score += 2
            elif len(context) >= 12 and matches(context[-12:] if preceding else context[:12]):
                score += 1
        if hint:
            equations = re.findall(r"\$(?:[^$\\]|\\.)+\$", source[start:end])
            if math_hint("".join(equations)) == hint:
                score += 4
        if score > best:
            candidates, best = [], score
        if score == best and len(candidates) <= 24:
            candidates.append(candidate)
    if len(candidates) > 24:
        return "unsupported"
    baseline = [passage["text"] for passage in bundle.passages]
    verified = []
    token = uuid.uuid4().hex
    root = project.root.resolve()
    for path, original, source, start, end in candidates:
        for function in (["highlighted"] if mathematical else ["highlighted", "highlight"]):
            fresh()
            highlighted = f"#{function}[{source[start:end]}]"
            marked = (f'#html.elem("span", attrs: ("data-flow-source-edit": "{token}"))'
                      f'[{highlighted}]')
            updated = source[:start] + marked + source[end:]
            with tempfile.TemporaryDirectory(prefix="source-highlight-", dir=output) as temporary:
                work = Path(temporary)
                shadow = work / "project"
                shadow_project(root, project.relative_entry(), path.relative_to(root), shadow, updated)
                # An absolute entry must still point into the verified shadow project.
                candidate_project = replace(project, root=shadow,
                                            entry=Path(project.relative_entry()))
                report = compile_project(candidate_project, work / "marked", map_sources=False)
                fresh()
                if not report["contentGatePassed"]:
                    continue
                document = (work / "marked/document.html").read_text()
                compiled = split_document(document, "candidate")
                # Parse one complete document after globally assigning reading keys.
                keyed = assign_block_ids(document)
                index = MarkedPassages(keyed, compiled.manifest["blocks"], token)
                if (index.markers != 1 or [item["text"] for item in index.passages] != baseline
                        or index.intervals() != expected):
                    continue
                final = source[:start] + highlighted + source[end:]
                (shadow / path.relative_to(root)).write_text(final, encoding="utf-8")
                report = compile_project(candidate_project, work / "final", map_sources=False)
                fresh()
                if not report["contentGatePassed"]:
                    continue
                final_bundle = split_document((work / "final/document.html").read_text(), "candidate")
                if [item["text"] for item in final_bundle.passages] != baseline:
                    continue
                if not paged_candidate_compiles(candidate_project, work / "candidate.pdf"):
                    continue
                fresh()
                verified.append((path, original, final))
                break
        if len(verified) > 1:
            return "unmapped"
    if not verified:
        return "unmapped"
    path, original, updated = verified[0]
    fresh()
    if path.read_bytes() != original:
        raise StaleSelection("Source changed during highlight verification")
    mode = stat.S_IMODE(path.stat().st_mode)
    if not mode & 0o222:
        return "unsupported"
    if writer is not None:
        return writer(path, original, updated.encode("utf-8"))
    descriptor, temporary = tempfile.mkstemp(prefix=".flow-highlight-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(updated.encode())
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        # A temporary file changes directory entry names; the final source byte
        # comparison still protects a concurrent editor save before replacement.
        if path.read_bytes() != original:
            raise StaleSelection("Source changed before highlight save")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return "highlighted"
