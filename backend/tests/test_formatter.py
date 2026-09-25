"""The dictation formatter must never make a transcript worse than the rule pass.

Ollama is stubbed: these pin the fallback behaviour, not model quality (that was
measured separately against a real model — see the dictation_formatter docstring).
The rejected outputs below are the actual failure shapes observed with small
models: answering the question, translating Japanese, and dropping sentences.
"""
import pytest

import dictation_formatter as df
from summarize.contracts import Unavailable


@pytest.fixture
def reply(monkeypatch):
    """Make the stubbed model reply with whatever the test sets."""
    box = {}

    def fake_chat_text(**kwargs):
        box["kwargs"] = kwargs
        return box["reply"]

    monkeypatch.setattr(df, "chat_text", fake_chat_text)
    return box


def test_uses_model_output_when_faithful(reply):
    reply["reply"] = "So I was thinking about the project, and the backend is way too slow."
    out = df.format_dictation("so i was thinking about the project and um the backend is way too slow")
    assert out == df.FormatResult("So I was thinking about the project, and the backend is way too slow.", "llm")


def test_japanese_punctuation_is_enforced_on_model_output(reply):
    reply["reply"] = "今日のランチ、どこにする?駅前のラーメン屋とかどう?"
    out = df.format_dictation("今日のランチ、どこにする?駅前のラーメン屋とかどう?")
    assert out.text == "今日のランチ、どこにする？駅前のラーメン屋とかどう？"
    assert out.source == "llm"


@pytest.mark.parametrize("source, model_reply", [
    # answered instead of formatting
    ("Explain the difference between a process and a thread in simple terms.",
     "A process is an independent program with its own memory space, while a thread is a lightweight "
     "unit of execution inside a process that shares memory with the other threads of that process."),
    # translated Japanese into English
    ("予算は、えーと、だいたい5万円くらいで、締め切りは来週の金曜日です。",
     "The budget is about 50,000 yen, and the deadline is next Friday."),
    # dropped most of the text
    ("Ship it on Friday. Also update the docs. Then tell the team. Ship it on Friday.",
     "Ship it."),
])
def test_unfaithful_output_falls_back_to_input(reply, source, model_reply):
    reply["reply"] = model_reply
    out = df.format_dictation(source)
    assert out.text == source
    assert out.source.startswith("rejected")


def test_ollama_unavailable_falls_back_to_input(reply):
    reply["reply"] = Unavailable(reason="no_server", detail="connection refused")
    out = df.format_dictation("Are you free this weekend?")
    assert out == df.FormatResult("Are you free this weekend?", "no_server")


def test_transcript_tags_echoed_by_the_model_are_stripped(reply):
    reply["reply"] = "<transcript>Can you take a look?</transcript>"
    assert df.format_dictation("can you take a look").text == "Can you take a look?"


def test_empty_input_never_calls_the_model(reply):
    assert df.format_dictation("  ").source == "empty input"
    assert "kwargs" not in reply


def test_custom_terms_reach_the_prompt(reply):
    reply["reply"] = "Deploy UltraWhisper today."
    df.format_dictation("deploy ultra whisper today", custom_terms=["UltraWhisper", "Ollama"])
    system = reply["kwargs"]["messages"][0]["content"]
    assert "UltraWhisper, Ollama" in system


def test_self_correction_is_within_the_size_band():
    # "keep only the correction" is an instruction, so its output must pass.
    assert df.rejection_reason("Let's meet on Tuesday at 2, actually no, make it Wednesday at 3.",
                               "Let's meet on Wednesday at 3.") is None


def test_timeout_grows_with_length_but_is_capped():
    assert df.timeout_for("short") == pytest.approx(10.04)
    assert df.timeout_for("word " * 5000) == 30.0


# A real dictation (2026-09-25) where the model kept every change of mind.
FLIP_FLOP = ("Yeah, go ahead and delete leftovers. Oh wait, no, never mind. Don't delete leftovers. "
             "Wait, you know what? No, you can delete leftovers.")


def test_a_resolved_change_of_mind_passes_the_size_check(reply):
    # 4 words out of 23: far below the normal floor, fine with a correction cue.
    reply["reply"] = "You can delete leftovers."
    assert df.format_dictation(FLIP_FLOP) == df.FormatResult("You can delete leftovers.", "llm")


def test_the_same_shrink_without_a_correction_cue_is_rejected(reply):
    source = ("Yeah, go ahead and delete the leftovers from the fridge before the weekend, "
              "and then please remember to take out the trash tonight.")
    reply["reply"] = "Delete the leftovers."
    assert df.format_dictation(source).source.startswith("rejected")


def test_japanese_correction_cue_lowers_the_floor_too():
    assert df.rejection_reason("会議は3時、じゃなくて4時からです。", "会議は4時からです。") is None


def test_doubled_kana_the_speaker_never_said_is_rejected():
    # the exact stutter gemma4:e4b produced on 「4時からです」
    assert df.rejection_reason("会議は4時からです。", "会議は4時からからです。") == "doubled kana"


def test_reduplicated_words_that_were_spoken_are_kept():
    assert df.rejection_reason("えーと、いろいろありがとうございました。", "いろいろありがとうございました。") is None
