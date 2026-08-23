#!/usr/bin/env python3
"""
Adversarial tests for the render guarantee.

The point of these is not that a handful of examples format nicely; it is that
the invariants hold over structurally varied, deliberately hostile input. The
checker below is written against the constants in `contracts.py`, so changing
the promise there breaks these tests rather than silently loosening them.
"""

import random
from collections import Counter

import pytest

from summarize.contracts import (
    BULLET_PREFIX,
    CHECKBOX_PREFIX,
    HEADER_PREFIX,
    INDENT,
    MAX_NEST_DEPTH,
    MeetingNote,
    NoteItem,
    NoteSection,
)
from summarize.render import (
    clean_text,
    collapse_line,
    flatten_items,
    render_note,
    render_note_lines,
    render_section_lines,
)

# Strings chosen to attack the guarantee from every angle the renderer claims
# to defend: leaked markdown, every flavour of line break, invisible controls,
# whitespace-only content, and text that is already a rendered bullet.
HOSTILE_TEXTS = [
    "a normal point",
    "",
    "   ",
    "\n",
    "\r\n",
    "line one\nline two",
    "line one\rline two",
    "vertical\vtab",
    "form\ffeed",
    "next\x85line",
    "unicode\u2028separator",
    "para\u2029separator",
    "- already a bullet",
    "- [ ] already a checkbox",
    "- [x] already done",
    "[ ] bare box",
    "[x] bare done",
    "### leaked header",
    "#### deeper header",
    "#",
    "###",
    "* star point",
    "+ plus point",
    "> quoted line",
    ">>> deeply quoted",
    "- - - dashes",
    "-*+#>",
    "\u200bzero width lead",
    "\u202eright to left override",
    "\ufeffbyte order mark",
    "   padded on both sides   ",
    "\t\ttabbed",
    "日本語の箇条書き",
    "### 見出しの漏れ",
    "emoji 🎉 point",
    "a" * 400,
    "trailing whitespace   ",
    "mixed\n\n\nblank lines",
    "- [ ] multi\nline\ncheckbox",
]

# Styles the renderer may be handed. The dataclasses in contracts.py are typed
# but not enforced, so a wrong value is reachable in production.
HOSTILE_STYLES = ["bullet", "checkbox", "CHECKBOX", " bullet ", "", "todo", None, 7]


def classify_line(line: str) -> str:
    """
    Assert one emitted line satisfies the guarantee, and say what it is.

    Returns "blank", "header" or "content" so callers can make claims about
    the mix as well as about each line.
    """
    assert line == line.rstrip(), f"trailing whitespace in {line!r}"
    assert line.splitlines() == ([line] if line else []), f"line breaks inside {line!r}"

    if not line:
        return "blank"

    if line.startswith(HEADER_PREFIX):
        title = line[len(HEADER_PREFIX):]
        assert title, f"empty header in {line!r}"
        assert not title.startswith("#"), f"stacked hashes in {line!r}"
        assert title == title.strip(), f"unstripped header title in {line!r}"
        return "header"

    assert not line.startswith("#"), f"non-conforming header in {line!r}"

    body = line
    if body.startswith(INDENT):
        body = body[len(INDENT):]
        assert not body.startswith(INDENT), f"indent deeper than {MAX_NEST_DEPTH} in {line!r}"
        assert not body.startswith(" "), f"ragged indent in {line!r}"

    if body.startswith(CHECKBOX_PREFIX):
        text = body[len(CHECKBOX_PREFIX):]
    elif body.startswith(BULLET_PREFIX):
        text = body[len(BULLET_PREFIX):]
    else:
        pytest.fail(f"line is neither header nor bullet: {line!r}")

    assert text, f"empty content line {line!r}"
    assert text == text.strip(), f"unstripped content in {line!r}"
    return "content"


def assert_note_invariants(rendered: str) -> Counter:
    """Check every line of a rendered note; return the kind counts."""
    assert rendered.splitlines() == rendered.split("\n") or rendered == ""
    kinds = Counter(classify_line(line) for line in rendered.split("\n") if rendered)
    return kinds


def content_texts(rendered: str) -> list:
    """The item texts recovered from a rendered note, in emitted order."""
    texts = []
    for line in rendered.split("\n"):
        if not line or line.startswith(HEADER_PREFIX):
            continue
        body = line[len(INDENT):] if line.startswith(INDENT) else line
        if body.startswith(CHECKBOX_PREFIX):
            texts.append(body[len(CHECKBOX_PREFIX):])
        elif body.startswith(BULLET_PREFIX):
            texts.append(body[len(BULLET_PREFIX):])
    return texts


def expected_texts(items) -> list:
    """Every non-empty cleaned text in a tree, in depth-first order."""
    out = []
    for item in items:
        text = clean_text(item.text)
        if text:
            out.append(text)
        out.extend(expected_texts(item.children))
    return out


def random_item(rng: random.Random, depth: int) -> NoteItem:
    children = []
    if depth < 4 and rng.random() < 0.45:
        children = [random_item(rng, depth + 1) for _ in range(rng.randint(1, 3))]
    return NoteItem(text=rng.choice(HOSTILE_TEXTS), children=children)


def random_note(rng: random.Random) -> MeetingNote:
    sections = []
    for _ in range(rng.randint(0, 4)):
        section = NoteSection(
            title=rng.choice(HOSTILE_TEXTS),
            style=rng.choice(HOSTILE_STYLES),
            items=[random_item(rng, 0) for _ in range(rng.randint(0, 5))],
        )
        sections.append(section)
    return MeetingNote(
        title=rng.choice(HOSTILE_TEXTS),
        meeting_type="generic",
        sections=sections,
    )


# ---------------------------------------------------------------------------
# Property-style sweeps
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("seed", range(200))
def test_every_line_satisfies_the_guarantee(seed):
    note = random_note(random.Random(seed))
    assert_note_invariants(render_note(note))


@pytest.mark.parametrize("seed", range(200))
def test_no_item_text_is_ever_dropped(seed):
    """Flattening changes an item's depth, never whether it appears."""
    note = random_note(random.Random(seed))
    rendered = render_note(note)

    expected = []
    for section in note.sections:
        expected.extend(expected_texts(section.items))

    assert content_texts(rendered) == expected


@pytest.mark.parametrize("seed", range(50))
def test_guarantee_holds_without_blank_separators(seed):
    note = random_note(random.Random(seed))
    rendered = render_note(note, blank_line_between_sections=False)
    kinds = assert_note_invariants(rendered)
    assert kinds["blank"] == 0


# ---------------------------------------------------------------------------
# Targeted cases
# ---------------------------------------------------------------------------


def test_title_with_newline_collapses_to_one_line():
    note = MeetingNote(title="Sync\nwith Ana", meeting_type="generic")
    lines = render_note_lines(note)
    assert lines == [HEADER_PREFIX + "Sync with Ana"]


def test_item_with_newline_collapses_to_one_line():
    section = NoteSection(title="Notes", items=[NoteItem(text="first\nsecond")])
    assert render_section_lines(section) == [
        HEADER_PREFIX + "Notes",
        BULLET_PREFIX + "first second",
    ]


@pytest.mark.parametrize(
    "raw",
    ["\x0b", "\x0c", "\x1c", "\x1d", "\x1e", "\x85", "\u2028", "\u2029", "\r", "\r\n"],
)
def test_every_splitlines_boundary_is_neutralized(raw):
    """
    `str.splitlines()` splits on far more than `\\n`.

    A renderer that only collapses `\\n` still emits text that any consumer
    splitting the output sees as two lines, one of which has no marker.
    """
    section = NoteSection(title=f"a{raw}b", items=[NoteItem(text=f"c{raw}d")])
    rendered = "\n".join(render_section_lines(section))
    assert len(rendered.splitlines()) == 2
    assert_note_invariants(rendered)


def test_leaked_markdown_is_stripped_from_items():
    section = NoteSection(
        title="### Action Items",
        style="checkbox",
        items=[
            NoteItem(text="- [ ] ship the thing"),
            NoteItem(text="> they said this"),
            NoteItem(text="#### heading-ish"),
            NoteItem(text="* star"),
            NoteItem(text="+ plus"),
        ],
    )
    assert render_section_lines(section) == [
        HEADER_PREFIX + "Action Items",
        CHECKBOX_PREFIX + "ship the thing",
        CHECKBOX_PREFIX + "they said this",
        CHECKBOX_PREFIX + "heading-ish",
        CHECKBOX_PREFIX + "star",
        CHECKBOX_PREFIX + "plus",
    ]


def test_deep_nesting_is_flattened_not_dropped():
    deepest = NoteItem(text="level four")
    third = NoteItem(text="level three", children=[deepest])
    second = NoteItem(text="level two", children=[third])
    first = NoteItem(text="level one", children=[second])
    section = NoteSection(title="Deep", items=[first])

    lines = render_section_lines(section)
    assert lines == [
        HEADER_PREFIX + "Deep",
        BULLET_PREFIX + "level one",
        INDENT + BULLET_PREFIX + "level two",
        INDENT + BULLET_PREFIX + "level three",
        INDENT + BULLET_PREFIX + "level four",
    ]
    assert all("level" in line for line in lines[1:])


def test_empty_parent_does_not_push_children_down():
    section = NoteSection(
        title="Notes",
        items=[NoteItem(text="   ", children=[NoteItem(text="survivor")])],
    )
    assert render_section_lines(section) == [
        HEADER_PREFIX + "Notes",
        BULLET_PREFIX + "survivor",
    ]


def test_blank_title_emits_no_header():
    section = NoteSection(title="   ", items=[NoteItem(text="orphan")])
    assert render_section_lines(section) == [BULLET_PREFIX + "orphan"]


def test_title_that_is_only_markup_emits_no_header():
    section = NoteSection(title="### ", items=[NoteItem(text="kept")])
    assert render_section_lines(section) == [BULLET_PREFIX + "kept"]


def test_section_with_no_items_emits_only_its_header():
    assert render_section_lines(NoteSection(title="Empty")) == [HEADER_PREFIX + "Empty"]


def test_empty_note_renders_to_empty_string():
    assert render_note(MeetingNote(title="", meeting_type="generic")) == ""


def test_unknown_style_falls_back_to_bullet():
    section = NoteSection(title="T", style="sparkles", items=[NoteItem(text="x")])
    assert render_section_lines(section)[1].startswith(BULLET_PREFIX)


def test_include_title_can_be_suppressed():
    note = MeetingNote(
        title="Weekly Sync",
        meeting_type="generic",
        sections=[NoteSection(title="Notes", items=[NoteItem(text="x")])],
    )
    assert HEADER_PREFIX + "Weekly Sync" in render_note_lines(note)
    assert HEADER_PREFIX + "Weekly Sync" not in render_note_lines(note, include_title=False)


def test_render_tolerates_wrong_types_everywhere():
    """The dataclasses are typed, not enforced; nothing here may raise."""
    assert render_note(None) == ""
    assert render_note(MeetingNote(title=None, meeting_type="generic", sections=None)) == ""

    note = MeetingNote(title=12, meeting_type="generic", sections="not a list")
    assert_note_invariants(render_note(note))

    section = NoteSection(title=3.5, style=None, items={"not": "a list"})
    assert render_section_lines(section) == [HEADER_PREFIX + "3.5"]

    numeric = NoteSection(title="N", items=[NoteItem(text=42, children=None)])
    assert render_section_lines(numeric) == [HEADER_PREFIX + "N", BULLET_PREFIX + "42"]


@pytest.mark.parametrize("text", ["loop", "", "   ", "###"])
def test_self_referential_tree_terminates(text):
    """
    A cyclic tree is reachable by hand, and the empty-text cycle is the nasty
    one: rendered depth deliberately stalls on empty parents, so a bound
    expressed in rendered depth would never fire.
    """
    item = NoteItem(text=text)
    item.children.append(item)
    lines = render_section_lines(NoteSection(title="Cycle", items=[item]))
    assert 1 <= len(lines) < 200
    assert_note_invariants("\n".join(lines))


def test_wide_shallow_tree_is_not_truncated():
    """The walk's bound counts depth, not items — a wide note keeps everything."""
    items = [NoteItem(text=f"point {n}") for n in range(500)]
    lines = render_section_lines(NoteSection(title="Many", items=items))
    assert len(lines) == 501


def test_duplicate_items_are_all_kept():
    """Identical short strings can be the same interned object — still two items."""
    section = NoteSection(title="T", items=[NoteItem(text="dup"), NoteItem(text="dup")])
    assert render_section_lines(section).count(BULLET_PREFIX + "dup") == 2


def test_flatten_items_reports_clamped_depths():
    tree = [NoteItem(text="a", children=[NoteItem(text="b", children=[NoteItem(text="c")])])]
    assert list(flatten_items(tree)) == [(0, "a"), (1, "b"), (1, "c")]
    assert all(depth <= MAX_NEST_DEPTH for depth, _ in flatten_items(tree))
    assert list(flatten_items(None)) == []


def test_collapse_and_clean_are_idempotent():
    for raw in HOSTILE_TEXTS:
        once = clean_text(raw)
        assert clean_text(once) == once
        assert collapse_line(once) == once
