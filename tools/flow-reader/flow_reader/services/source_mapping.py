"""Accepted HTML source ranges shared by Codex context and editor navigation."""

from bisect import bisect_left
import hashlib
from pathlib import Path
import re

from flow_reader.document.passages import locate_passages, normalized_offsets, occurrences, validate_fragments
from flow_reader.compiler.inputs import source_paths


def literal_blocks(source):
    """Yield only plain markup paragraphs/headings outside Typst constructs.

    This intentionally is not a source map or a Typst parser. Anything involving
    code, content delimiters, math, references, escapes, emphasis or raw text is
    excluded. Lexical state keeps multiline definitions/comments/raw blocks from
    being mistaken for authored prose on a following line.
    """
    start = end = None
    delimiters = []
    comment_depth = 0
    raw_ticks = 0
    mathematical = quoted = pending_code = False
    offset = 0
    special = re.compile(r"[#$\[\]{}()\\<>@`*_]|//|/\*|\*/")
    for line in source.splitlines(keepends=True):
        text = line.rstrip("\r\n")
        clear = not (delimiters or comment_depth or raw_ticks or mathematical
                     or quoted or pending_code)
        eligible = clear and bool(text.strip()) and not special.search(text)
        heading = re.match(r"\s*=+\s+", text) if eligible else None
        if not eligible or heading:
            if start is not None:
                yield start, end
                start = end = None
        if eligible:
            if heading:
                yield offset + heading.end(), offset + len(text)
            else:
                if start is None:
                    start = offset
                end = offset + len(text)

        code = pending_code
        i = 0
        while i < len(text):
            pair = text[i:i + 2]
            character = text[i]
            if comment_depth:
                if pair == "/*":
                    comment_depth += 1
                    i += 2
                elif pair == "*/":
                    comment_depth -= 1
                    i += 2
                else:
                    i += 1
                continue
            if raw_ticks:
                if character == "`":
                    count = len(text[i:]) - len(text[i:].lstrip("`"))
                    if count == raw_ticks:
                        raw_ticks = 0
                    i += count
                else:
                    i += 1
                continue
            if quoted:
                if character == "\\":
                    i += 2
                    continue
                if character == '"':
                    quoted = False
                i += 1
                continue
            if pair == "//":
                break
            if pair == "/*":
                comment_depth = 1
                i += 2
                continue
            if character == "\\":
                i += 2
                continue
            if character == "`":
                raw_ticks = len(text[i:]) - len(text[i:].lstrip("`"))
                i += raw_ticks
                continue
            if character == "$":
                mathematical = not mathematical
            elif not mathematical:
                if character == "#":
                    code = True
                elif character == '"' and (code or delimiters):
                    quoted = True
                elif character in "([{":
                    delimiters.append(character)
                elif character in ")]}":
                    if delimiters and {"(": ")", "[": "]", "{": "}"}[delimiters[-1]] == character:
                        delimiters.pop()
            i += 1
        if text.strip():
            pending_code = code and text.rstrip().endswith(("=", ",", "+", "-", "*", "/", ".", ":"))
        offset += len(line)
    if start is not None:
        yield start, end


def transparent_highlights(source):
    """Remove only plain-text highlight wrappers while retaining exact offsets."""
    pieces, offsets, previous = [], [], 0
    pattern = re.compile(r"#highlight(?:ed)?\[([^\[\]#$}{()\\<>@`*_]+)\]")
    for match in pattern.finditer(source):
        body = match.group(1)
        if any(marker in body for marker in ("//", "/*", "*/")):
            continue
        pieces.extend((source[previous:match.start()], body))
        offsets.extend(range(previous, match.start()))
        offsets.extend(range(match.start(1), match.end(1)))
        previous = match.end()
    if not pieces:
        return source, range(len(source))
    pieces.append(source[previous:])
    offsets.extend(range(previous, len(source)))
    return "".join(pieces), offsets


def literal_index(project, dependencies):
    for path in source_paths(project, dependencies):
        try:
            source = path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            continue
        literal, origins = transparent_highlights(source)
        for start, end in literal_blocks(literal):
            text, offsets = normalized_offsets(literal[start:end], smart_quotes=True)
            if text:
                yield {"path": path, "source": source, "start": start, "end": end,
                       "literal": literal, "origins": origins, "text": text,
                       "offsets": [origins[start + position] for position in offsets]}


def source_position(source, offset):
    line_start = source.rfind("\n", 0, offset) + 1
    return {"line": source.count("\n", 0, offset) + 1,
            "column": len(source[line_start:offset].encode("utf-8"))}


def mapped_source_range(project, dependencies, bundle, clean):
    """Resolve covered ordered text/math/reference ranges to source offsets."""
    passages = {part["key"]: part for part in bundle.passages}
    if not any(passages.get(part["key"], {}).get("source_ranges") for part in clean):
        return None
    locations = locate_passages(bundle.passages, clean)
    paths = set(source_paths(project, dependencies))
    sources, selected = {}, []
    for fragment, location in zip(clean, locations):
        if location["state"] != "located":
            return {"status": "ambiguous" if location["state"] == "ambiguous" else "unmapped"}
        if location["key"] != fragment["key"]:
            return {"status": "unmapped"}
        passage = passages[location["key"]]
        start = list(occurrences(passage["text"], fragment["exact"]))[location["occurrence"]]
        end = start + len(fragment["exact"])
        covered = set()
        for span in passage.get("source_ranges", []):
            first, last = max(start, span["text_start"]), min(end, span["text_end"])
            if first >= last or not passage["text"][first:last].strip():
                continue
            path = Path(span["path"]).resolve()
            if path not in paths:
                return {"status": "unmapped"}
            if path not in sources:
                raw = path.read_bytes()
                sources[path] = (raw.decode("utf-8"), hashlib.sha256(raw).hexdigest())
            source, digest = sources[path]
            if digest != span["source_hash"]:
                return {"status": "stale"}
            if not 0 <= span["start"] < span["end"] <= len(source):
                return {"status": "unmapped"}
            source_start, source_end = span["start"], span["end"]
            if span["kind"] == "text":
                text, offsets = normalized_offsets(source[source_start:source_end], smart_quotes=True)
                rendered, _ = normalized_offsets(
                    passage["text"][span["text_start"]:span["text_end"]], smart_quotes=True)
                if text != rendered:
                    return {"status": "unmapped"}
                source_end = source_start + offsets[last - span["text_start"] - 1] + 1
                source_start += offsets[first - span["text_start"]]
            elif (span["kind"] not in {"math", "reference"}
                  or first != span["text_start"] or last != span["text_end"]):
                return {"status": "unmapped"}
            selected.append((path, source_start, source_end, span["kind"]))
            covered.update(range(first, last))
        if any(not passage["text"][i].isspace() and i not in covered for i in range(start, end)):
            return {"status": "unmapped"}
    if not selected or len({path for path, _, _, _ in selected}) != 1:
        return {"status": "unmapped"}
    if any(left[2] > right[1] for left, right in zip(selected, selected[1:])):
        return {"status": "ambiguous"}
    path = selected[0][0]
    source, digest = sources[path]
    return {"status": "located", "path": path, "source": source, "source_hash": digest,
            "spans": [(kind, start, end) for _, start, end, kind in selected]}


def mapped_source_location(project, dependencies, bundle, clean):
    """Resolve fully covered, ordered selections using compiler-carried ranges."""
    mapped = mapped_source_range(project, dependencies, bundle, clean)
    if mapped is None or mapped.get("status") != "located":
        return mapped
    source, spans = mapped["source"], mapped["spans"]
    end_position = source_position(source, spans[-1][2])
    return {"status": "located", "path": str(mapped["path"]),
            "source_hash": mapped["source_hash"],
            **source_position(source, spans[0][1]),
            "end_line": end_position["line"], "end_column": end_position["column"]}


def source_location(project, dependencies, bundle, fragments):
    """Prefer accepted source ranges, retaining the conservative literal fallback."""
    clean = validate_fragments(fragments)
    mapped = mapped_source_location(project, dependencies, bundle, clean)
    if mapped is not None:
        return mapped
    if len(clean) != 1:
        return {"status": "unmapped"}
    segments = fragments[0].get("segments", [])
    if not isinstance(segments, list) or any(
        not isinstance(part, dict) or part.get("math") for part in segments
    ):
        return {"status": "unmapped"}
    location = locate_passages(bundle.passages, clean)[0]
    if location["state"] != "located":
        return {"status": "ambiguous" if location["state"] == "ambiguous" else "unmapped"}
    passage = next(part for part in bundle.passages if part["key"] == location["key"])
    text, _ = normalized_offsets(passage["text"], smart_quotes=True)
    matches = [block for block in literal_index(project, dependencies) if block["text"] == text]
    if len(matches) != 1:
        return {"status": "ambiguous" if matches else "unmapped"}
    # The full normalized paragraph agrees, so the selected occurrence has the
    # same logical offset in the literal source (including smart quote changes).
    exact, _ = normalized_offsets(clean[0]["exact"], smart_quotes=True)
    starts = list(occurrences(text, exact))
    if location["occurrence"] >= len(starts):
        return {"status": "unmapped"}
    block = matches[0]
    offset = block["offsets"][starts[location["occurrence"]]]
    return {"status": "located", "path": str(block["path"]),
            "source_hash": hashlib.sha256(block["source"].encode("utf-8")).hexdigest(),
            **source_position(block["source"], offset)}


ATTACHED_LABEL = re.compile(r"\s*<[\w.:-]+>\s*$")


def source_excerpt(project, dependencies, bundle, fragments):
    """Return one complete expression's verified Typst slice for copying."""
    clean = validate_fragments(fragments)
    if len(clean) != 1:
        return {"status": "unmapped"}
    mapped = mapped_source_range(project, dependencies, bundle, clean)
    if mapped is None:
        return {"status": "unmapped"}
    if mapped.get("status") != "located":
        return mapped
    spans = mapped["spans"]
    if len(spans) != 1 or spans[0][0] != "math":
        return {"status": "unmapped"}
    _, start, end = spans[0]
    text = mapped["source"][start:end]
    closing = text.rfind("$")
    # A verified equation range may carry its attached label. Copying the
    # expression keeps it reusable without duplicating the author's label.
    if closing >= 0 and ATTACHED_LABEL.fullmatch(text[closing + 1:]):
        text = text[:closing + 1]
    if not text.startswith("$") or not text.endswith("$") or len(text) > 20000:
        return {"status": "unmapped"}
    return {"status": "located", "text": text}


def cursor_location(project, dependencies, bundle, path, line, column):
    """Map a saved UTF-8 byte cursor to a unique accepted source-backed block."""
    if (not isinstance(path, str) or not Path(path).is_absolute()
            or type(line) is not int or type(column) is not int
            or line < 1 or column < 0):
        raise ValueError("Expected an absolute source path, one-based line and UTF-8 byte column")
    path = Path(path).resolve()
    if path not in set(source_paths(project, dependencies)):
        return {"status": "unmapped"}
    source = path.read_bytes().decode("utf-8")
    offset = cursor_offset(source, line, column)
    digest = hashlib.sha256(source.encode("utf-8")).hexdigest()
    matches = []
    # Carried paths were canonicalized at compilation; avoid a filesystem walk
    # for every range during editor cursor polling.
    canonical_path = str(path)
    for passage in bundle.passages:
        for span in passage.get("source_ranges", []):
            if span["path"] == canonical_path and span["start"] <= offset < span["end"]:
                if span["source_hash"] != digest:
                    return {"status": "stale"}
                matches.append(passage)
                break
    if len(matches) > 1:
        return {"status": "ambiguous"}
    if matches:
        passage = matches[0]
        return {"status": "located", "key": passage["key"], "section": passage["section"],
                "exact": passage["text"]}
    blocks = [block for block in literal_index(project, dependencies) if block["path"] == path]
    if not blocks:
        return {"status": "unmapped"}
    literal_offset = bisect_left(blocks[0]["origins"], offset)
    block = next((block for block in blocks
                  if block["start"] <= literal_offset <= block["end"]), None)
    if not block:
        # A cursor on the heading's leading '=' still identifies that heading.
        literal = blocks[0]["literal"]
        line_start = literal.rfind("\n", 0, literal_offset) + 1
        block = next((block for block in blocks
                      if line_start <= literal_offset < block["start"]
                      and re.fullmatch(r"\s*=+\s+", literal[line_start:block["start"]])), None)
    if not block:
        return {"status": "unmapped"}
    matches = [passage for passage in bundle.passages
               if normalized_offsets(passage["text"], smart_quotes=True)[0] == block["text"]]
    if len(matches) != 1:
        return {"status": "ambiguous" if matches else "unmapped"}
    passage = matches[0]
    return {"status": "located", "key": passage["key"], "section": passage["section"],
            "exact": passage["text"]}


def edit_location(project, dependencies, bundle, edit):
    """Map the earliest covered part of one shared edit, rejecting repeated output."""
    path = Path(edit["path"])
    if path not in set(source_paths(project, dependencies)):
        return {"status": "unmapped"}
    containers = [span for span in bundle.navigation_ranges
                  if span["path"] == str(path) and span["start"] < edit["end"]
                  and edit["start"] < span["end"]]
    if any(span["source_hash"] != edit["source_hash"] for span in containers):
        return {"status": "stale"}
    matches = []
    for passage in bundle.passages:
        offsets = []
        for span in passage.get("source_ranges", []):
            if (span["path"] == str(path) and span["start"] < edit["end"]
                    and edit["start"] < span["end"]):
                if span["source_hash"] != edit["source_hash"]:
                    return {"status": "stale"}
                offsets.append(max(span["start"], edit["start"]))
        if offsets:
            matches.append((min(offsets), passage))
    if matches or containers:
        first = min([offset for offset, _ in matches] +
                    [max(span["start"], edit["start"]) for span in containers])
        targets = {(span["target"], span["section"]) for span in containers
                   if max(span["start"], edit["start"]) == first}
        if targets:
            if len(targets) != 1:
                return {"status": "ambiguous"}
            target, section = targets.pop()
            return {"status": "located", "target": target, "section": section}
        passages = [passage for offset, passage in matches if offset == first]
        if len(passages) != 1:
            return {"status": "ambiguous"}
        passage = passages[0]
        return {"status": "located", "key": passage["key"], "section": passage["section"]}
    return cursor_location(project, dependencies, bundle, edit["path"], edit["line"], edit["column"])


def cursor_offset(source, line, column):
    """Validate and translate a one-based line and UTF-8 byte column."""
    lines = source.split("\n")
    if line > len(lines):
        raise ValueError("Source cursor line is outside the saved file")
    content = lines[line - 1].rstrip("\r")
    encoded = content.encode("utf-8")
    if column > len(encoded):
        raise ValueError("Source cursor column is outside the saved line")
    try:
        prefix = encoded[:column].decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValueError("Source cursor column splits a UTF-8 character") from error
    return sum(len(part) + 1 for part in lines[:line - 1]) + len(prefix)
