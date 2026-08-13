"""
Regressions for defects found by an adversarial pass against the renderer.

Twelve reports deduplicated to four classes, all reproduced before being fixed.
These tests exist because every one of them passed the module's own 726-test
suite first: the author's tests prove internal consistency, not that the
guarantee survives input the author did not imagine.

Each test names what it is defending and why, because a future reader looking
at, say, a node budget will otherwise assume it is arbitrary and tune it away.
"""

import json
import time

import pytest

from summarize.contracts import MeetingNote, NoteItem, NoteSection
from summarize.render import render_note
from summarize.schema import parse_facts, parse_note

# Generous enough that a slow machine never flakes, tight enough that the
# defects these guard against — which ran for hours — cannot possibly pass.
_BUDGET_SECONDS = 5.0


def _timed(fn):
    start = time.monotonic()
    result = fn()
    return result, time.monotonic() - start


# ---------------------------------------------------------------------------
# 1. ReDoS in the code-fence stripper. The only class here reachable from an
#    ordinary model response, and therefore the one that mattered.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "filler",
    [" ", "\n", "\t", " ", "　", "\xa0"],
    ids=["space", "newline", "tab", "line-sep", "ideographic", "nbsp"],
)
def test_unterminated_fence_does_not_backtrack(filler):
    """
    A model that opens ```json and then hits its token limit emits exactly
    this. The original regex backtracked cubically on it — measured 0.036s at
    307 characters and 17.3s at 2407, extrapolating to hours at 20k.
    """
    payload = "```json" + filler * 20_000
    _, elapsed = _timed(lambda: parse_note(payload))
    assert elapsed < _BUDGET_SECONDS


def test_fence_stripping_still_works():
    """The fix must not cost the feature: well-formed fences still unwrap."""
    body = json.dumps({"title": "T", "sections": [{"title": "S", "items": ["a"]}]})
    for wrapped in (f"```json\n{body}\n```", f"```\n{body}\n```", f"```{body}```"):
        note = parse_note(wrapped)
        assert note.title == "T", wrapped[:20]
        assert note.sections[0].items[0].text == "a"


# ---------------------------------------------------------------------------
# 2. Unbounded walks. Not reachable through json.loads, which cannot express
#    shared references — but "always returns" should not depend on the caller.
# ---------------------------------------------------------------------------


def test_self_referential_item_terminates():
    """Reachable by hand: the dataclasses in contracts.py are mutable."""
    item = NoteItem("A")
    item.children = [item, item]
    note = MeetingNote("T", "generic", [NoteSection("S", "bullet", [item])])
    _, elapsed = _timed(lambda: render_note(note))
    assert elapsed < _BUDGET_SECONDS


def test_acyclic_shared_subtree_is_bounded():
    """
    No cycle at all — 31 objects, each holding the same child twice. The number
    of root-to-node PATHS is exponential in depth, which a depth bound alone
    does not catch: this produced 2,097,154 lines before the node cap.
    """
    node = NoteItem("leaf")
    for _ in range(30):
        node = NoteItem("n", [node, node])
    note = MeetingNote("T", "generic", [NoteSection("S", "bullet", [node])])
    out, elapsed = _timed(lambda: render_note(note))
    assert elapsed < _BUDGET_SECONDS
    assert len(out.splitlines()) < 50_000


def test_self_referential_payload_terminates_in_parse():
    """
    Depth was capped at 8, but fan-out was not: a children list containing the
    dict that owns it materialised fan-out**8 items — 6.5e12 at fan-out 40.
    """
    items = []
    node = {"text": "a", "children": items}
    for _ in range(40):
        items.append(node)
    payload = {"title": "t", "sections": [{"title": "s", "items": items}]}
    _, elapsed = _timed(lambda: parse_note(payload))
    assert elapsed < _BUDGET_SECONDS


# ---------------------------------------------------------------------------
# 3. Attributes that fight back. Three-argument getattr swallows only
#    AttributeError; anything else propagated straight out of render_note.
# ---------------------------------------------------------------------------


class _RaisingTitle:
    style = "bullet"
    items = ()

    @property
    def title(self):
        raise ValueError("boom")


class _RaisingItems:
    title = "S"
    style = "bullet"

    @property
    def items(self):
        raise KeyError("boom")


class _RaisingChildren:
    text = "p"

    @property
    def children(self):
        raise RuntimeError("boom")


class _RaisingStyle:
    title = "S"
    items = ()

    @property
    def style(self):
        raise IndexError("boom")


class _BadReversed(list):
    def __reversed__(self):
        raise TypeError("nope")


@pytest.mark.parametrize(
    "section",
    [
        _RaisingTitle(),
        _RaisingItems(),
        _RaisingStyle(),
        NoteSection("S", "bullet", [_RaisingChildren()]),
        NoteSection("S", "bullet", [NoteItem("p", _BadReversed([NoteItem("c")]))]),
    ],
    ids=["title", "items", "style", "children", "reversed"],
)
def test_hostile_attributes_do_not_escape(section):
    out = render_note(MeetingNote("T", "generic", [section]))
    assert isinstance(out, str)


# ---------------------------------------------------------------------------
# 4. Numeric conversion is not total. CPython caps int->str at 4300 digits and
#    float() of a large enough int overflows.
# ---------------------------------------------------------------------------


def test_absurd_int_in_text_slot_does_not_raise():
    assert isinstance(parse_note({"title": 10**5000, "sections": []}), MeetingNote)


def test_absurd_int_in_t0_does_not_raise():
    facts = parse_facts({"facts": [{"text": "x", "speaker": "me", "t0": 10**5000}]})
    assert facts[0].t0 == 0.0


def test_json_loads_is_the_real_first_guard():
    """
    Documents WHY the two tests above are hardening rather than bug fixes: a
    huge int never reaches the parser through the real path, because json.loads
    rejects it first and llm.py turns that into an Unavailable.
    """
    with pytest.raises(ValueError):
        json.loads('{"t0": 1' + "0" * 5000 + "}")
