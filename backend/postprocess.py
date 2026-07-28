#!/usr/bin/env python3
"""
Lightweight post-processing for whisper.cpp transcription output.
"""

import re

# Standalone filler words to strip when disfluency cleanup is on.
_FILLER_WORDS = r"(?:um+|uh+|uhm+|erm+|err?|hmm+)"
_FILLER_RE = re.compile(rf"\b{_FILLER_WORDS}\b[,]?", re.IGNORECASE)
_MULTI_SPACE_RE = re.compile(r"\s{2,}")
_SPACE_BEFORE_PUNCT_RE = re.compile(r"\s+([,.!?])")
_SENTENCE_BOUNDARY_RE = re.compile(r"([.!?]\s+)([a-z])")
_STANDALONE_I_RE = re.compile(r"\bi\b")


def _clean_disfluencies(text: str) -> str:
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


def _ensure_terminal_punctuation(text: str) -> str:
    if text and text[-1] not in _TERMINAL_PUNCT:
        return text + "."
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
        text = _ensure_terminal_punctuation(text)

    return text
