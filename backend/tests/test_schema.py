#!/usr/bin/env python3
"""
Tests for tolerant parsing.

Everything here is about the malformed case. The happy path is one test; the
rest are shapes a 2B-class local model actually produces, plus the shapes the
schema's own `required` list makes legal.
"""

import math

import pytest

from summarize.contracts import Fact, MeetingNote, NoteItem, NoteSection
from summarize.render import render_note
from summarize.schema import parse_facts, parse_note
from test_render import assert_note_invariants


def test_well_formed_payload_round_trips():
    note = parse_note(
        {
            "title": "Weekly Sync",
            "sections": [
                {
                    "title": "Decisions",
                    "style": "bullet",
                    "items": [{"text": "ship on Friday"}],
                }
            ],
        },
        meeting_type="one_on_one",
    )
    assert isinstance(note, MeetingNote)
    assert note.title == "Weekly Sync"
    assert note.meeting_type == "one_on_one"
    assert note.sections[0].items == [NoteItem(text="ship on Friday")]


# ---------------------------------------------------------------------------
# The deviations contracts.py predicts
# ---------------------------------------------------------------------------


def test_items_may_be_bare_strings():
    """The single most common deviation: a string where an object was asked for."""
    note = parse_note({"title": "T", "sections": [{"title": "S", "items": ["do the thing"]}]})
    assert note.sections[0].items == [NoteItem(text="do the thing")]


def test_missing_style_falls_back_to_the_template():
    """`style` is absent from the schema's `required`; models simply omit it."""
    note = parse_note(
        {"title": "T", "sections": [{"title": "Action Items", "items": ["x"]}]},
        meeting_type="one_on_one",
    )
    assert note.sections[0].style == "checkbox"

    bulleted = parse_note(
        {"title": "T", "sections": [{"title": "Updates", "items": ["x"]}]},
        meeting_type="one_on_one",
    )
    assert bulleted.sections[0].style == "bullet"


def test_invented_title_still_gets_a_sensible_style():
    note = parse_note({"title": "T", "sections": [{"title": "Follow-Ups For Me", "items": ["x"]}]})
    assert note.sections[0].style == "checkbox"


def test_explicit_style_is_honoured_and_can_be_overridden():
    payload = {"title": "T", "sections": [{"title": "Notes", "style": "checkbox", "items": ["x"]}]}
    assert parse_note(payload).sections[0].style == "checkbox"
    assert parse_note(payload, prefer_template_style=True).sections[0].style == "bullet"


def test_nonsense_style_is_ignored_in_favour_of_the_template():
    note = parse_note(
        {"title": "T", "sections": [{"title": "Action Items", "style": "sparkles", "items": ["x"]}]}
    )
    assert note.sections[0].style == "checkbox"


@pytest.mark.parametrize("sections", [None, "nope", 7, {}, [], [None, 3, True]])
def test_missing_or_wrong_sections_degrade_to_an_empty_note(sections):
    note = parse_note({"title": "T", "sections": sections})
    assert note.sections == []
    assert note.title == "T"


@pytest.mark.parametrize("items", [None, "single string item", 7, {"text": "one"}, [], "  "])
def test_missing_or_wrong_items_never_raise(items):
    note = parse_note({"title": "T", "sections": [{"title": "S", "items": items}]})
    assert isinstance(note, MeetingNote)
    assert all(isinstance(i, NoteItem) for s in note.sections for i in s.items)


def test_extra_keys_are_ignored():
    note = parse_note(
        {
            "title": "T",
            "confidence": 0.9,
            "sections": [
                {"title": "S", "items": [{"text": "x", "owner": "me", "due": "Friday"}], "id": 3}
            ],
        }
    )
    assert note.sections[0].items == [NoteItem(text="x")]


@pytest.mark.parametrize("children", [None, {}, [], [None], [{"nope": 1}], [""], True])
def test_null_or_junk_children_become_an_empty_list(children):
    note = parse_note(
        {"title": "T", "sections": [{"title": "S", "items": [{"text": "x", "children": children}]}]}
    )
    assert note.sections[0].items[0].children == []


@pytest.mark.parametrize("children, expected", [("solo", "solo"), (5, "5")])
def test_a_scalar_child_is_read_as_one_child(children, expected):
    """Same leniency as `items`: a bare scalar where an array was specified."""
    note = parse_note(
        {"title": "T", "sections": [{"title": "S", "items": [{"text": "x", "children": children}]}]}
    )
    assert note.sections[0].items[0].children == [NoteItem(text=expected)]


def test_nested_children_are_preserved_for_the_renderer_to_flatten():
    note = parse_note(
        {
            "title": "T",
            "sections": [
                {
                    "title": "S",
                    "items": [
                        {"text": "a", "children": [{"text": "b", "children": [{"text": "c"}]}]}
                    ],
                }
            ],
        }
    )
    first = note.sections[0].items[0]
    assert first.children[0].children[0].text == "c"


@pytest.mark.parametrize(
    "value, expected",
    [
        ("plain", "plain"),
        ("  padded  ", "padded"),
        (42, "42"),
        (3.5, "3.5"),
        (True, ""),
        (None, ""),
        ({"text": "nested"}, ""),
        (["a"], ""),
        (float("nan"), ""),
    ],
)
def test_item_text_coercion(value, expected):
    note = parse_note({"title": "T", "sections": [{"title": "S", "items": [{"text": value}]}]})
    got = note.sections[0].items[0].text if note.sections and note.sections[0].items else ""
    assert got == expected


def test_item_with_no_usable_text_but_real_children_is_kept():
    note = parse_note(
        {"title": "T", "sections": [{"title": "S", "items": [{"children": [{"text": "kept"}]}]}]}
    )
    assert note.sections[0].items[0].text == ""
    assert note.sections[0].items[0].children == [NoteItem(text="kept")]


def test_section_with_neither_title_nor_items_is_dropped():
    note = parse_note({"title": "T", "sections": [{}, {"title": "", "items": []}, {"items": ["x"]}]})
    assert len(note.sections) == 1
    assert note.sections[0].items == [NoteItem(text="x")]


def test_title_falls_back_when_missing_or_unusable():
    for payload in ({}, {"title": ""}, {"title": None}, {"title": []}):
        assert parse_note(payload, fallback_title="Meeting").title == "Meeting"


def test_meeting_type_is_canonicalized():
    assert parse_note({}, meeting_type="1:1").meeting_type == "one_on_one"
    assert parse_note({}, meeting_type="Coffee Chat").meeting_type == "coffee_chat"
    assert parse_note({}, meeting_type="nonsense").meeting_type == "generic"


def test_raw_json_string_and_fenced_json_are_accepted():
    raw = '{"title": "T", "sections": [{"title": "S", "items": ["x"]}]}'
    assert parse_note(raw).sections[0].items == [NoteItem(text="x")]
    assert parse_note("```json\n" + raw + "\n```").title == "T"
    assert parse_note(raw.encode("utf-8")).title == "T"


def test_bare_array_of_sections_is_accepted():
    note = parse_note([{"title": "S", "items": ["x"]}])
    assert len(note.sections) == 1


def test_deeply_nested_children_do_not_blow_the_stack():
    payload: dict = {"text": "leaf"}
    for _ in range(500):
        payload = {"text": "branch", "children": [payload]}
    note = parse_note({"title": "T", "sections": [{"title": "S", "items": [payload]}]})
    assert isinstance(note, MeetingNote)
    assert_note_invariants(render_note(note))


# ---------------------------------------------------------------------------
# Nothing may raise, ever
# ---------------------------------------------------------------------------

MALFORMED_PAYLOADS = [
    None,
    "",
    "not json at all",
    "null",
    "[]",
    "{}",
    0,
    3.5,
    True,
    [],
    [1, 2, 3],
    {"sections": {}},
    {"sections": [[]]},
    {"sections": [{"title": {"a": 1}, "items": [{"text": {"b": 2}}]}]},
    {"title": ["list", "title"], "sections": None},
    {"title": "T", "sections": [{"title": "S", "items": [[{"text": "nested list"}]]}]},
    {"title": "T", "sections": ["bare section title", 5, None]},
    {"sections": [{"title": "S", "items": [{"text": "x", "children": [[]]}]}]},
    {"title": "\n\n", "sections": [{"title": "\n", "items": ["\n"]}]},
    {"title": "T", "sections": [{"title": "S", "style": None, "items": [None, "", "  "]}]},
    b'{"title": "bytes"}',
    ("tuple", "payload"),
    {"facts": [{"text": "wrong schema entirely"}]},
]


@pytest.mark.parametrize("payload", MALFORMED_PAYLOADS)
def test_parse_note_never_raises_and_always_renders(payload):
    note = parse_note(payload)
    assert isinstance(note, MeetingNote)
    assert isinstance(note.title, str) and note.title
    assert all(isinstance(s, NoteSection) for s in note.sections)
    assert_note_invariants(render_note(note))


@pytest.mark.parametrize("payload", MALFORMED_PAYLOADS)
def test_parse_facts_never_raises(payload):
    facts = parse_facts(payload)
    assert isinstance(facts, list)
    assert all(isinstance(f, Fact) for f in facts)
    assert all(f.speaker in ("me", "them") for f in facts)
    assert all(isinstance(f.t0, float) and math.isfinite(f.t0) and f.t0 >= 0 for f in facts)


# ---------------------------------------------------------------------------
# Facts
# ---------------------------------------------------------------------------


def test_facts_happy_path():
    facts = parse_facts({"facts": [{"text": "they use Postgres", "speaker": "them", "t0": 61.5}]})
    assert facts == [Fact(text="they use Postgres", speaker="them", t0=61.5)]


def test_facts_accept_a_bare_list_and_bare_strings():
    assert parse_facts([{"text": "a", "speaker": "me", "t0": 1}])[0].speaker == "me"
    assert parse_facts(["just a string"]) == [Fact(text="just a string", speaker="them", t0=0.0)]


def test_facts_without_text_are_dropped():
    facts = parse_facts({"facts": [{"speaker": "me", "t0": 1}, {"text": "  "}, {"text": "kept"}]})
    assert [f.text for f in facts] == ["kept"]


@pytest.mark.parametrize(
    "raw, expected",
    [
        ("me", "me"),
        ("Them", "them"),
        (" ME ", "me"),
        ("Speaker 1", "me"),
        ("speaker 2", "them"),
        ("nobody", "them"),
        (None, "them"),
        (3, "them"),
    ],
)
def test_speaker_coercion_defaults_to_them(raw, expected):
    assert parse_facts({"facts": [{"text": "x", "speaker": raw, "t0": 0}]})[0].speaker == expected


def test_speaker_default_is_overridable():
    facts = parse_facts({"facts": [{"text": "x", "speaker": "???"}]}, default_speaker="me")
    assert facts[0].speaker == "me"


@pytest.mark.parametrize(
    "raw, expected",
    [
        (12, 12.0),
        (12.5, 12.5),
        ("12.5", 12.5),
        ("00:01:05", 65.0),
        ("[00:01:05]", 65.0),
        ("1:05", 65.0),
        ("01:00:00", 3600.0),
        (-5, 0.0),
        ("-5", 0.0),
        ("later", 0.0),
        (None, 0.0),
        (True, 0.0),
        (float("inf"), 0.0),
        (float("nan"), 0.0),
        ({"seconds": 5}, 0.0),
    ],
)
def test_timestamp_coercion(raw, expected):
    """Models copy the `[HH:MM:SS]` stamp out of the prompt as often as not."""
    assert parse_facts({"facts": [{"text": "x", "t0": raw}]})[0].t0 == expected
