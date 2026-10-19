"""Index accepted document passages for explicit selections and source navigation."""

from html.parser import HTMLParser


def normalized(text):
    return " ".join(text.split())


class PassageIndex(HTMLParser):
    def __init__(self, source, block_sections):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.active = []
        self.passages = []
        self.block_sections = block_sections
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        excluded = bool(self.stack and self.stack[-1][1]) or tag in {"svg", "script", "style", "nav"} or (
            "data-flow-targets" in attributes)
        key = attributes.get("data-reader-key")
        passage = None
        if key and not excluded:
            passage = {"key": key, "id": attributes.get("id"), "text": [],
                       "section": self.block_sections[key]}
            self.active.append(passage)
        if tag not in {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
                       "param", "source", "track", "wbr"}:
            self.stack.append((tag, excluded, passage))

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1][0] != tag:
            return
        _, _, passage = self.stack.pop()
        if passage:
            self.active.pop()
            passage["text"] = normalized("".join(passage["text"]))
            if passage["text"]:
                self.passages.append(passage)

    def handle_data(self, data):
        if self.active and self.stack and not self.stack[-1][1]:
            self.active[-1]["text"].append(data)


def validate_fragments(fragments):
    if not isinstance(fragments, list) or not 1 <= len(fragments) <= 32:
        raise ValueError("Expected 1–32 saved passage fragments")
    result = []
    for fragment in fragments:
        if not isinstance(fragment, dict):
            raise ValueError("Expected a saved passage object")
        value = {}
        for field, limit in (("key", 128), ("exact", 20000), ("prefix", 120), ("suffix", 120)):
            text = fragment.get(field, "")
            if not isinstance(text, str) or len(text) > limit:
                raise ValueError(f"Invalid passage {field}")
            value[field] = normalized(text)
        if not value["exact"]:
            raise ValueError("A saved passage needs quotation text")
        result.append(value)
    return result


def occurrences(text, exact):
    offset = 0
    while (position := text.find(exact, offset)) >= 0:
        yield position
        offset = position + 1


def locate_passages(passages, fragments):
    results = []
    for fragment in validate_fragments(fragments):
        best, score, tied = None, (-1, -1), False
        for passage in passages:
            text = passage["text"]
            for occurrence, start in enumerate(occurrences(text, fragment["exact"])):
                end = start + len(fragment["exact"])
                before, after = text[:start].rstrip(), text[end:].lstrip()
                context = int(bool(fragment["prefix"]) and before.endswith(fragment["prefix"])) + (
                    int(bool(fragment["suffix"]) and after.startswith(fragment["suffix"])))
                candidate_score = (int(passage["key"] == fragment["key"]), context)
                if candidate_score > score:
                    best = {key: passage[key] for key in ("key", "id", "section")}
                    best.update(state="located", occurrence=occurrence)
                    score, tied = candidate_score, False
                elif candidate_score == score:
                    tied = True
        results.append({"state": "ambiguous"} if tied else best or {"state": "missing"})
    return results
