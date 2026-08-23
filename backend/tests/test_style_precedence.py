"""
Who decides whether a section renders as bullets or checkboxes.

This is a deliberate product decision, not an implementation detail, and it was
changed after the module was first written — so it gets its own tests. Neither
obvious rule is right on its own:

* template-always ignores the model correctly marking a section whose title the
  template's keyword list never anticipated;
* model-always lets model noise overrule knowledge the template actually has.

The rule: the template wins wherever it has a POSITIVE opinion. "checkbox"
encodes real knowledge about a title; "bullet" is only its fallback for a title
it does not recognise, so an explicit model style is honoured there.
"""

import pytest

from summarize import parse_note


def _style(title, model_style=None, meeting_type="coffee_chat"):
    section = {"title": title, "items": ["x"]}
    if model_style is not None:
        section["style"] = model_style
    payload = {"title": "t", "sections": [section]}
    return parse_note(payload, meeting_type=meeting_type).sections[0].style


@pytest.mark.parametrize("model_style", [None, "bullet", "checkbox"])
def test_template_checkbox_knowledge_always_wins(model_style):
    """"Action Items" is a title the template knows. The model cannot demote it."""
    assert _style("Action Items", model_style) == "checkbox"


# A title the keyword list genuinely does not match — verified, because the
# obvious candidates do: "Commitments I Made" and "Follow-Ups For Me" both
# resolve to checkbox on their own, so using either here would have made these
# tests pass without exercising the model-honouring branch at all.
_UNRECOGNISED = "Topics Discussed"


def test_the_unrecognised_title_really_is_unrecognised():
    """Guards the premise of the two tests below against template edits."""
    assert _style(_UNRECOGNISED) == "bullet"


def test_model_style_is_honoured_where_the_template_has_no_opinion():
    """
    The template returns its "bullet" fallback here, which is absence of
    knowledge rather than a judgement — so the model's explicit style is the
    only real signal and it is used.
    """
    assert _style(_UNRECOGNISED, "checkbox") == "checkbox"


@pytest.mark.parametrize("model_style", [None, "bullet"])
def test_unrecognised_title_defaults_to_bullets(model_style):
    assert _style("Their Background", model_style) == "bullet"


@pytest.mark.parametrize("junk", ["", "  ", "CHECKBOXES", "true", 1, None, {}, []])
def test_invalid_model_style_falls_back_to_the_template(junk):
    """An unparseable style is the same as no style, never an error."""
    assert _style("Their Background", junk) == "bullet"
    assert _style("Action Items", junk) == "checkbox"


def test_prefer_template_style_gives_the_strict_reading():
    """The escape hatch for callers wanting contracts.py read literally."""
    payload = {
        "title": "t",
        "sections": [{"title": _UNRECOGNISED, "style": "checkbox", "items": ["x"]}],
    }
    strict = parse_note(payload, meeting_type="coffee_chat", prefer_template_style=True)
    assert strict.sections[0].style == "bullet"
