"""Post-processing of raw whisper output, focused on Japanese punctuation.

Inputs are real whisper large-v3-turbo outputs (or close to them): it emits
ASCII ? in Japanese questions and an LLM pass can leave "10 時 30 分" spacing.
"""
import pytest

from postprocess import _is_japanese, apply_post_processing


def post(text):
    return apply_post_processing(text)


@pytest.mark.parametrize("raw, expected", [
    # ASCII question marks from whisper -> full-width
    ("今日のランチ、どこにする?駅前のラーメン屋とかどう?", "今日のランチ、どこにする？駅前のラーメン屋とかどう？"),
    # ASCII comma and period -> 、。
    ("明日は10時半から,会議です.", "明日は10時半から、会議です。"),
    # a question ending on a Latin word is still a Japanese question
    ("これでOK?", "これでOK？"),
    # English word followed by a Japanese comma position
    ("GitHubのissueに,再現手順を書きました.", "GitHubのissueに、再現手順を書きました。"),
    # already correct text is untouched
    ("お疲れ様です。資料を共有しました。", "お疲れ様です。資料を共有しました。"),
])
def test_japanese_ascii_punctuation_becomes_full_width(raw, expected):
    assert post(raw) == expected


@pytest.mark.parametrize("raw, expected", [
    # decimals and versions keep their dot
    ("バージョン3.2をリリースしました。", "バージョン3.2をリリースしました。"),
    # thousands separators keep their comma
    ("予算は50,000円です。", "予算は50,000円です。"),
    # dotted names are one token, not a sentence end
    ("Node.jsで書き直しました。", "Node.jsで書き直しました。"),
])
def test_dots_and_commas_inside_tokens_are_kept(raw, expected):
    assert post(raw) == expected


def test_spaces_between_japanese_characters_are_removed():
    assert post("10 時 30 分くらいには着くと思います。") == "10時30分くらいには着くと思います。"


def test_japanese_without_terminal_mark_gets_a_japanese_period():
    assert post("ありがとうございます、助かりました") == "ありがとうございます、助かりました。"


@pytest.mark.parametrize("text", [
    "Version 3.2 is out, right?",
    "The budget is $12,500. Can you check Node.js too?",
])
def test_english_is_untouched(text):
    assert post(text) == text


def test_english_with_one_kanji_is_not_japanese():
    assert not _is_japanese("The word for tree is 木, pronounced ki.")


@pytest.mark.parametrize("raw, expected", [
    # real whisper outputs: the commas around a filler marked a pause, not a clause
    ("Hi Professor Tanaka, I wanted to ask if I could, um, get an extension.",
     "Hi Professor Tanaka, I wanted to ask if I could get an extension."),
    ("Reminder to buy, um, milk, eggs, and bread.", "Reminder to buy milk, eggs, and bread."),
    ("Um, so I think we should go.", "So I think we should go."),
    # a clip that ends mid-clause on a comma gets a clean full stop
    ("i think we should add caching first and then, um, look at the database queries,",
     "I think we should add caching first and then look at the database queries."),
])
def test_filler_removal_leaves_no_orphan_commas(raw, expected):
    assert post(raw) == expected
