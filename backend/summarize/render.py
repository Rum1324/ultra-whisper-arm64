#!/usr/bin/env python3
"""
Markdown rendering, and the guarantee that makes the note predictable.

The architecture rests on formatting being a RENDERER guarantee rather than
something the model is asked for politely in a prompt. Concretely, for any
input at all — parsed, hand-built, or deliberately hostile — every line this
module emits is one of:

* empty (a blank separator line), or
* `HEADER_PREFIX` + a non-empty single-line title, with no further `#`, or
* an optional single `INDENT`, then `BULLET_PREFIX` or `CHECKBOX_PREFIX`,
  then non-empty single-line text.

Nothing indents past one `INDENT`; items nested deeper are flattened up to
depth `MAX_NEST_DEPTH` rather than dropped, because a note that loses its
indentation is still useful and a note that loses content is not.

Three things break this guarantee if you let them, and all three are handled
below rather than assumed away:

1. Text containing a line break emits a second line that is neither a header
   nor a bullet. "Line break" here means every character `str.splitlines()`
   treats as one — not just `\\n` but `\\v`, `\\f`, `\\x85`, `\\u2028` and the
   file/group separators — otherwise a checker that splits the output sees
   lines the renderer never knew it wrote.
2. Markdown the model leaked into its own content (`#`, `-`, `*`, `+`, `>`,
   `[ ]`, `[x]`) turns into structure once it lands at the head of a line.
3. Bidi and zero-width controls can make a line *display* as something other
   than what it starts with, which defeats a guarantee stated in terms of
   what a line starts with.
"""

import re
from typing import Any, Iterator

from .contracts import (
    BULLET_PREFIX,
    CHECKBOX_PREFIX,
    HEADER_PREFIX,
    INDENT,
    MAX_NEST_DEPTH,
)

# Every character `str.splitlines()` splits on, so text can never smuggle a
# line past the renderer that the renderer did not intend to write. Written as
# escapes on purpose: several of these are invisible in an editor.
_LINE_BREAK_RE = re.compile(
    "[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]+"
)

# Zero-width and bidirectional-override controls, plus the C0/C1 controls that
# are not line breaks (those are handled above, and must become a space rather
# than vanish or they would weld two words together). Deleted rather than
# escaped: none of them can be transcribed speech, and a right-to-left override
# can make a line *display* as though it began with something other than its
# marker, which defeats a guarantee stated in terms of what a line starts with.
_INVISIBLE_RE = re.compile(
    "[\x00-\x08\x0e-\x1b\x7f-\x84\x86-\x9f"
    "\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]"
)

_WHITESPACE_RUN_RE = re.compile(r"\s+")

# Leaked list/heading/quote markers at the head of a string. A checkbox marker
# is listed first so `- [ ] x` peels in the expected order.
_LEADING_MARKUP_RE = re.compile(r"^(?:\[[ xX✓]?\]|[#>*+•·・-]+)[ \t]*")

# Bound on the peeling loop. `- - - [x]` needs a handful of passes; anything
# needing more is decoration rather than content.
_MAX_PEEL_PASSES = 8

# How many levels the item walk will descend before giving up. Only a cyclic
# or machine-generated tree gets near it; it exists so the walk terminates on
# one instead of hanging inside a function that is not allowed to fail.
_MAX_WALK_DEPTH = 64

_STYLE_PREFIXES = {
    "bullet": BULLET_PREFIX,
    "checkbox": CHECKBOX_PREFIX,
}


def collapse_line(value: Any) -> str:
    """
    Force any value onto a single, whitespace-normalized line.

    Non-strings are tolerated because the dataclasses in contracts.py are
    typed, not enforced, and this module refuses to be the thing that raises.
    """
    if not isinstance(value, str):
        if value is None:
            return ""
        try:
            value = str(value)
        except Exception:
            return ""
    value = _INVISIBLE_RE.sub("", value)
    value = _LINE_BREAK_RE.sub(" ", value)
    return _WHITESPACE_RUN_RE.sub(" ", value).strip()


def clean_text(value: Any) -> str:
    """
    Collapse to one line and peel off markdown the model leaked into content.

    Applied to titles as well as items: a title of "### Action Items" would
    otherwise emit `### ### Action Items`, which satisfies the letter of the
    guarantee and violates its point.
    """
    text = collapse_line(value)
    for _ in range(_MAX_PEEL_PASSES):
        peeled = _LEADING_MARKUP_RE.sub("", text, count=1)
        if peeled == text:
            break
        text = peeled
    return text.strip()


# Total items one section may emit. The hop bound below limits how DEEP the
# walk goes but not how WIDE: a tree that shares subtrees has exponentially
# many root-to-node paths, and an adversarial pass got 2,097,154 lines out of
# 41 objects. json.loads cannot build that sharing so it is unreachable from a
# model response, but "always terminates" should not depend on the caller.
_MAX_WALK_NODES = 20_000


def _safe_getattr(obj: Any, name: str, default: Any = None) -> Any:
    """
    `getattr` that cannot raise.

    The three-argument `getattr` only swallows AttributeError; a property or
    __getattr__ raising anything else propagates straight out. This module
    promises its guarantee holds for deliberately hostile input, and an object
    whose attributes fight back is exactly that.
    """
    try:
        return getattr(obj, name, default)
    except Exception:
        return default


def _prefix_for(section: Any) -> str:
    """Section style decides the marker; anything unrecognised is a bullet."""
    style = _safe_getattr(section, "style")
    if isinstance(style, str):
        try:
            return _STYLE_PREFIXES.get(style.strip().lower(), BULLET_PREFIX)
        except Exception:
            return BULLET_PREFIX
    return BULLET_PREFIX


def flatten_items(items: Any) -> Iterator[tuple[int, str]]:
    """
    Walk an item tree depth-first, yielding `(depth, cleaned text)` pairs.

    Depth is clamped to `MAX_NEST_DEPTH`, so a fourth-level sub-point still
    appears — indented once, next to its grandparent's other children.

    Two details worth keeping. An item whose text cleans away to nothing does
    not consume a depth level for its children, so surviving content is not
    pushed down by a parent that turned out to be decoration. And the walk is
    iterative, bounded by how far it has descended rather than by a visited
    set: recursion dies on a pathological tree, while a visited set would
    silently drop a genuine repeat, since two identical short strings can be
    the same interned object.

    The bound counts hops, not rendered depth. Rendered depth stalls on empty
    parents by design, so a cycle of empty items would never reach a cap
    expressed in those terms — it is the one shape that makes this loop
    non-terminating, and it is reachable by hand from mutable dataclasses.

    Hops bound depth but not breadth, so there is a second, unconditional cap
    on nodes visited: with shared subtrees the number of root-to-node paths is
    exponential in depth even with no cycle at all, and 41 objects were shown
    to produce 2,097,154 lines. Past the cap the walk simply stops. Truncating
    a note that has already gone insane is the lesser harm; a renderer that
    does not return takes the transcript down with it.
    """
    if not isinstance(items, (list, tuple)):
        return

    try:
        # (item, rendered depth, hops from the root)
        stack: list[tuple[Any, int, int]] = [(item, 0, 0) for item in reversed(items)]
    except Exception:
        return

    visited = 0
    while stack:
        item, depth, hops = stack.pop()
        if item is None:
            continue

        visited += 1
        if visited > _MAX_WALK_NODES:
            return

        text = clean_text(_safe_getattr(item, "text", item if isinstance(item, str) else None))
        if text:
            yield min(depth, MAX_NEST_DEPTH), text
            child_depth = depth + 1
        else:
            child_depth = depth

        if hops >= _MAX_WALK_DEPTH:
            continue
        children = _safe_getattr(item, "children")
        if isinstance(children, (list, tuple)):
            try:
                stack.extend((child, child_depth, hops + 1) for child in reversed(children))
            except Exception:
                continue


def render_section_lines(section: Any) -> list[str]:
    """
    Render one section.

    A blank title emits no header rather than a bare `###`; a section with no
    renderable items emits its header and stops. Neither is treated as an
    error — dropping the section would be an editorial decision, and this
    module only guarantees shape.
    """
    lines: list[str] = []
    title = clean_text(_safe_getattr(section, "title", ""))
    if title:
        lines.append(HEADER_PREFIX + title)

    prefix = _prefix_for(section)
    for depth, text in flatten_items(_safe_getattr(section, "items")):
        lines.append(INDENT * depth + prefix + text)
    return lines


def render_note_lines(
    note: Any,
    *,
    include_title: bool = True,
    blank_line_between_sections: bool = True,
) -> list[str]:
    """
    Render a whole note as a list of lines, with no trailing blank.

    The note's own title is emitted with `HEADER_PREFIX` like any section
    header. It is not given a shallower `#` heading because the guarantee
    forbids any other header depth; the compromise is that the note title and
    its sections sit at the same level.
    """
    lines: list[str] = []

    if include_title:
        title = clean_text(_safe_getattr(note, "title", ""))
        if title:
            lines.append(HEADER_PREFIX + title)

    sections = _safe_getattr(note, "sections")
    if not isinstance(sections, (list, tuple)):
        sections = ()

    for section in sections:
        section_lines = render_section_lines(section)
        if not section_lines:
            continue
        if lines and blank_line_between_sections:
            lines.append("")
        lines.extend(section_lines)

    return lines


def render_note(
    note: Any,
    *,
    include_title: bool = True,
    blank_line_between_sections: bool = True,
) -> str:
    """Render a note as markdown text, without a trailing newline."""
    return "\n".join(
        render_note_lines(
            note,
            include_title=include_title,
            blank_line_between_sections=blank_line_between_sections,
        )
    )
