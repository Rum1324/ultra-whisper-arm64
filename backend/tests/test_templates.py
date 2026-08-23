#!/usr/bin/env python3
"""
Tests for the meeting-type templates.

Two properties matter more than the specific menus: an unknown type always
resolves to something usable, and the suggested titles stay a hint rather than
becoming an enum in the schema handed to the model.
"""

import pytest

from summarize.contracts import note_json_schema
from summarize.templates import (
    DEFAULT_MEETING_TYPE,
    GENERIC_TEMPLATE,
    TEMPLATES,
    MeetingTemplate,
    get_template,
    normalize_title,
    note_schema_for,
    style_for_title,
    suggested_titles_for,
)

EXPECTED_TYPES = {
    "coffee_chat",
    "one_on_one",
    "standup",
    "interview",
    "customer_call",
    "generic",
}


def test_every_expected_meeting_type_exists():
    assert EXPECTED_TYPES <= set(TEMPLATES)


@pytest.mark.parametrize("key", sorted(EXPECTED_TYPES))
def test_template_key_matches_its_own_meeting_type(key):
    assert TEMPLATES[key].meeting_type == key


@pytest.mark.parametrize("key", sorted(EXPECTED_TYPES))
def test_suggested_titles_are_usable_plain_text(key):
    titles = TEMPLATES[key].suggested_titles
    assert titles, f"{key} has no suggested titles"
    assert len(set(titles)) == len(titles), f"{key} repeats a title"
    for title in titles:
        assert title == title.strip()
        assert "\n" not in title
        assert not title.startswith(("#", "-", "*", ">"))


@pytest.mark.parametrize("key", sorted(EXPECTED_TYPES))
def test_checkbox_titles_are_drawn_from_the_menu(key):
    template = TEMPLATES[key]
    assert set(template.checkbox_titles) <= set(template.suggested_titles)
    for title in template.checkbox_titles:
        assert template.style_for(title) == "checkbox"


@pytest.mark.parametrize(
    "meeting_type",
    ["", "   ", None, 7, [], "totally_unknown", "Zoom Call", "coffee chat with someone new"],
)
def test_unknown_types_fall_back_to_generic(meeting_type):
    assert get_template(meeting_type) is GENERIC_TEMPLATE


@pytest.mark.parametrize(
    "spelling, expected",
    [
        ("one_on_one", "one_on_one"),
        ("One-on-One", "one_on_one"),
        ("1:1", "one_on_one"),
        ("1 on 1", "one_on_one"),
        (" COFFEE_CHAT ", "coffee_chat"),
        ("coffee", "coffee_chat"),
        ("Stand-up", "standup"),
        ("daily standup", "standup"),
        ("Interview", "interview"),
        ("customer call", "customer_call"),
        ("sales-call", "customer_call"),
        ("generic", "generic"),
    ],
)
def test_spellings_and_aliases_resolve(spelling, expected):
    assert get_template(spelling).meeting_type == expected


def test_default_meeting_type_is_the_fallback():
    assert get_template(DEFAULT_MEETING_TYPE) is GENERIC_TEMPLATE


@pytest.mark.parametrize(
    "title, expected",
    [
        ("Action Items", "checkbox"),
        ("action items", "checkbox"),
        ("  Action Items:  ", "checkbox"),
        ("Action Items For Me", "checkbox"),
        ("Next Steps", "checkbox"),
        ("Follow-Ups", "checkbox"),
        ("Follow ups", "checkbox"),
        ("My TODOs", "checkbox"),
        ("Commitments", "checkbox"),
        ("次のステップ", "checkbox"),
        ("アクションアイテム", "checkbox"),
        ("Key Points", "bullet"),
        ("Decisions", "bullet"),
        ("Their Background", "bullet"),
        ("Transaction Volume", "bullet"),
        ("", "bullet"),
        (None, "bullet"),
        (12, "bullet"),
    ],
)
def test_style_for_invented_titles(title, expected):
    """Titles are free text, so the style decision cannot be a table lookup alone."""
    assert style_for_title(title) == expected


def test_style_for_title_accepts_an_explicit_template():
    template = MeetingTemplate(meeting_type="x", checkbox_titles=("Homework",))
    assert style_for_title("Homework", template=template) == "checkbox"
    assert style_for_title("Homework", meeting_type="generic") == "checkbox"
    assert style_for_title("Anything Else", template=template) == "bullet"


def test_normalize_title_keeps_non_latin_titles_distinct():
    """A normalizer that strips non-ASCII would fold every JA title together."""
    assert normalize_title("次のステップ") != normalize_title("議題")
    assert normalize_title("Action Items") == normalize_title("action-items")
    assert normalize_title(None) == ""


def test_suggested_titles_helper_matches_the_template():
    assert suggested_titles_for("1:1") == TEMPLATES["one_on_one"].suggested_titles
    assert suggested_titles_for("unknown") == GENERIC_TEMPLATE.suggested_titles


def test_titles_reach_the_schema_as_a_hint_not_an_enum():
    schema = note_schema_for("coffee_chat")
    sections = schema["properties"]["sections"]
    description = sections["description"]

    for title in TEMPLATES["coffee_chat"].suggested_titles:
        assert title in description

    title_schema = sections["items"]["properties"]["title"]
    assert "enum" not in title_schema
    assert title_schema["type"] == "string"


def test_note_schema_for_matches_the_contract_helper():
    assert note_schema_for("interview") == note_json_schema(
        suggested_titles=TEMPLATES["interview"].suggested_titles
    )
    assert note_schema_for("interview", max_sections=3)["properties"]["sections"]["maxItems"] == 3
