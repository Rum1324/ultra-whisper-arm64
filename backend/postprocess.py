#!/usr/bin/env python3
"""
Lightweight post-processing for whisper.cpp transcription output.
"""

import re

# Standalone filler words to strip when disfluency cleanup is on.
_FILLER_WORDS = r"(?:um+|uh+|uhm+|erm+|err?|hmm+)"
_FILLER_RE = re.compile(rf"\b{_FILLER_WORDS}\b[,]?", re.IGNORECASE)
# whisper sets a mid-sentence filler off with commas ("could, um, get"). Those
# commas marked the pause, not a clause break, so they go with the filler —
# otherwise the result reads "could, get".
_PAUSE_FILLER_RE = re.compile(rf",\s*\b{_FILLER_WORDS}\b,?", re.IGNORECASE)
_MULTI_SPACE_RE = re.compile(r"\s{2,}")
_SPACE_BEFORE_PUNCT_RE = re.compile(r"\s+([,.!?])")
_SENTENCE_BOUNDARY_RE = re.compile(r"([.!?]\s+)([a-z])")
_STANDALONE_I_RE = re.compile(r"\bi\b")


def _clean_disfluencies(text: str) -> str:
    text = _PAUSE_FILLER_RE.sub("", text)
    text = _FILLER_RE.sub("", text)
    text = _SPACE_BEFORE_PUNCT_RE.sub(r"\1", text)
    text = _MULTI_SPACE_RE.sub(" ", text)
    return text.strip()


def _apply_smart_capitalization(text: str) -> str:
    if not text:
        return text

    text = _STANDALONE_I_RE.sub("I", text)

    def _capitalize_after_boundary(match: "re.Match[str]") -> str:
        return match.group(1) + match.group(2).upper()

    text = _SENTENCE_BOUNDARY_RE.sub(_capitalize_after_boundary, text)

    first_alpha = re.search(r"[a-zA-Z]", text)
    if first_alpha:
        idx = first_alpha.start()
        text = text[:idx] + text[idx].upper() + text[idx + 1:]

    return text


# Sentence terminators, including full-width Japanese marks, so we neither
# double-punctuate (…です。 -> …です。.) nor add a Latin "." to Japanese text.
_TERMINAL_PUNCT = ".!?。！？…"

# Hiragana, katakana (incl. the long-vowel mark ー) and CJK ideographs.
_JA_CHAR = r"[぀-ヿ一-鿿]"
_JA_CHAR_RE = re.compile(_JA_CHAR)
_LATIN_LETTER_RE = re.compile(r"[A-Za-z]")
# A space whisper (or an LLM) put between Japanese characters or digits: "10 時 30 分".
_JA_INNER_SPACE_RE = re.compile(rf"(?<={_JA_CHAR}|\d) +(?={_JA_CHAR})|(?<={_JA_CHAR}) +(?=\d)")


def _is_japanese(text: str) -> bool:
    """Japanese when it has at least as many Japanese characters as Latin letters.

    Counting beats "contains any kana": a Japanese sentence routinely carries
    English words (GitHubのissue), and an English one can quote a single 漢字.
    """
    return len(_JA_CHAR_RE.findall(text)) >= max(1, len(_LATIN_LETTER_RE.findall(text)))


# A "." or "," is part of a token, not punctuation, when it sits between two
# characters of the same kind: 3.2, Node.js, example.com, 50,000.
_TOKEN_DOT_RE = re.compile(r"(?<![A-Za-z0-9])\.|\.(?![A-Za-z0-9])")
_TOKEN_COMMA_RE = re.compile(r"(?<!\d)[,，]|[,，](?!\d)")
_SPACE_AFTER_JA_PUNCT_RE = re.compile(r"(?<=[、。？！]) +")


def _normalize_japanese_punctuation(text: str) -> str:
    """Turn the ASCII , . ? ! whisper emits in Japanese into 、。？！.

    Only called on text _is_japanese() accepted. Decided per token rather than
    by "is the neighbour Japanese", because 「これでOK?」 ends a Japanese
    question on a Latin word, while 3.2 and Node.js must keep their dot.
    """
    text = text.replace("...", "…").replace("．", "。")
    text = _TOKEN_DOT_RE.sub("。", text)
    text = _TOKEN_COMMA_RE.sub("、", text)
    text = text.replace("?", "？").replace("!", "！")
    return _SPACE_AFTER_JA_PUNCT_RE.sub("", text)


def _ensure_terminal_punctuation(text: str) -> str:
    # whisper sometimes ends a clip mid-clause on a comma: "…the database queries,"
    text = text.rstrip(" ,;:、")
    if text and text[-1] not in _TERMINAL_PUNCT:
        return text + ("。" if _is_japanese(text) else ".")
    return text


def apply_post_processing(
    text: str,
    *,
    smart_caps: bool = True,
    punctuation: bool = True,
    disfluency_cleanup: bool = True,
) -> str:
    """
    Apply optional post-processing to a raw whisper.cpp transcript.

    whisper.cpp's large-v3-turbo model already produces cased, punctuated
    text in almost all cases, so `punctuation` here only fills in a missing
    terminal mark rather than doing full punctuation restoration from scratch.
    """
    if not text:
        return text

    if disfluency_cleanup:
        text = _clean_disfluencies(text)

    if smart_caps:
        text = _apply_smart_capitalization(text)

    if punctuation:
        if _is_japanese(text):
            text = _JA_INNER_SPACE_RE.sub("", text)
            text = _normalize_japanese_punctuation(text)
        text = _ensure_terminal_punctuation(text)

    return text
