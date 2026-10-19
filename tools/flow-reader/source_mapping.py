"""Conservative saved-source mapping for explicit HTML Codex context."""

import hashlib
from pathlib import Path
import re

from passages import locate_passages, occurrences, validate_fragments
from source_edits import normalized_offsets

MAX_SOURCE_BYTES = 2 * 1024 * 1024


def source_paths(project, dependencies):
    """Only inspect accepted, bounded Typst dependencies inside the workspace."""
    root = project.root.resolve()
    packages = project.packages.resolve()
    names = {Path(name) for name in dependencies} | {root / project.entry}
    for path in sorted({name.resolve() for name in names}):
        if (path.suffix != ".typ" or not path.is_relative_to(root)
                or path.is_relative_to(packages) or not path.is_file()
                or path.stat().st_size > MAX_SOURCE_BYTES):
            continue
        yield path


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


def source_location(project, dependencies, bundle, fragments):
    """Map a unique selected literal paragraph to its saved source coordinates."""
    clean = validate_fragments(fragments)
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
