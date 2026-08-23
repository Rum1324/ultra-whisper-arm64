# Meeting session wire protocol

Phase 0 contract for the meeting-notes feature. `server.py` (Phase 3), the Swift
capture layer (Phase 2) and the Flutter services (Phase 3) are written against
this document independently, so treat it as frozen: add fields, don't rename them.

The Python-side shapes are in [`backend/summarize/contracts.py`](../backend/summarize/contracts.py).

## Relationship to the existing protocol

Same envelope as today — `{type, id, data}` text frames plus raw binary frames —
on the same connection and the same fixed port 8082.

**The dictation path is untouched.** `start_session` / `end_session` / `cancel`
keep their exact current behavior, including buffering to `TranscriptionSession`
and discarding on end. A meeting is a *different session kind*, not a mode flag
on the existing one. Any change that alters single-shot dictation output is a
regression, not a refactor.

### Field naming

New meeting messages use **camelCase throughout**, in both directions.

This is a deliberate break from the legacy events, which are inconsistent:
commands already use `sessionId`, but `final` and `stats` emit `session_id` and
`avg_logprob` because they are built straight from Python dicts, and the Dart
side papers over it with `@JsonKey(name: ...)`. Rather than propagate that,
new messages are uniform. Legacy fields stay exactly as they are.

## Commands (Flutter → backend)

### `start_meeting`

```jsonc
{
  "type": "start_meeting",
  "id": "<uuid>",
  "data": {
    "meetingId": "<uuid>",
    "meetingType": "coffee_chat",   // see summarize/templates.py; "generic" if unknown
    "language": null,                // null | "en" | "ja" — null means auto-detect
    "title": "Coffee chat with Ana", // optional, from the calendar match
    "windowSeconds": 120             // rolling transcribe window; see below
  }
}
```

Creates a meeting session. Unlike `start_session`, this session **retains
absolute-stamped segments and discards audio** as it goes (see "Rolling
transcribe"), so it is safe to leave open for hours.

### Audio frames (binary)

Meeting audio frames carry **one leading track byte**, then PCM int16 LE mono
16 kHz — the same sample format as dictation.

```
byte 0   : track    0x00 = mic ("me"), 0x01 = system tap ("them")
byte 1.. : PCM int16 little-endian, mono, 16 kHz
```

Dictation frames stay bare PCM with no prefix. The server knows which framing to
expect from the session kind, so the two never collide.

One byte rather than a JSON sidecar because these arrive every 20–40 ms for the
length of a meeting; the framing cost matters and the tag never needs to carry
anything else.

### `end_meeting`

```jsonc
{ "type": "end_meeting", "id": "<uuid>", "data": { "meetingId": "<uuid>" } }
```

Flushes the trailing partial window, emits a final `transcript_window`, and
keeps the session alive so `summarize` can still run against it. Does **not**
free the transcript — `cancel` does that.

### `summarize`

```jsonc
{
  "type": "summarize",
  "id": "<uuid>",
  "data": {
    "meetingId": "<uuid>",
    "model": "gemma4:e2b",          // Ollama tag; a user setting
    "meetingType": "coffee_chat"     // optional override of the start_meeting value
  }
}
```

Runs classify → map → reduce → render. Safe to call more than once on the same
meeting, including with a different model — that is the intended way to retry
with a bigger model after seeing a weak note.

### `cancel`

Existing command, extended: given a `meetingId`, drops the meeting session and
its retained transcript.

## Events (backend → Flutter)

### `transcript_window`

Emitted as each rolling window finishes transcribing, so the UI can show a
transcript growing live.

```jsonc
{
  "type": "transcript_window",
  "data": {
    "meetingId": "<uuid>",
    "index": 3,
    "t0": 360.0,                    // absolute seconds from meeting start
    "t1": 480.0,
    "segments": [
      { "t0": 372.4, "t1": 375.1, "speaker": "me",   "text": "..." },
      { "t0": 375.6, "t1": 381.0, "speaker": "them", "text": "..." }
    ]
  }
}
```

`t0`/`t1` on every segment are **absolute from the start of the meeting**.
whisper.cpp restarts its own segment times at zero on each `whisper_full()`
call, so the rolling-transcribe path adds the window offset before emitting.
Consumers may assume these are monotonic across the whole meeting.

### `summary_progress`

```jsonc
{
  "type": "summary_progress",
  "data": {
    "meetingId": "<uuid>",
    "stage": "map",                 // "classify" | "map" | "reduce" | "render"
    "completed": 4,
    "total": 9
  }
}
```

A summarization run takes minutes. It executes via `run_in_executor` — the same
pattern `handle_end_session` already uses — so the WebSocket loop stays
responsive and these can actually be delivered while it runs.

### `summary_final`

```jsonc
{
  "type": "summary_final",
  "data": {
    "meetingId": "<uuid>",
    "markdown": "### Their Background\n- ...",
    "note": { "title": "...", "meetingType": "coffee_chat", "sections": [ ... ] },
    "model": "gemma4:e2b",
    "elapsedSeconds": 84.2
  }
}
```

`markdown` is the deliverable and is what the UI shows. `note` is the structured
form behind it, carried so the UI can offer per-section actions later without a
markdown re-parse.

### `summary_unavailable`

**Not an error.** Summarization is an enhancement layered on a transcript that
already works; Ollama being missing must never cost the user their transcript.

```jsonc
{
  "type": "summary_unavailable",
  "data": {
    "meetingId": "<uuid>",
    "reason": "no_model",           // "no_server" | "no_model" | "timeout" | "bad_response"
    "detail": "model \"qwen3.6:27b\" is not pulled",
    "remedy": "ollama pull qwen3.6:27b"   // safe to show verbatim; may be null
  }
}
```

The UI shows the transcript, states that notes are unavailable, and offers
`remedy` as copyable text. It must not present this as a failed operation.

`error` is still used for genuine faults — unknown `meetingId`, malformed
frames, a transcription crash.

## Rolling transcribe

Meeting audio is transcribed in fixed windows (`windowSeconds`, default 120) as
it arrives; the audio is then **discarded** and only stamped text is retained.

Two reasons, both measured rather than assumed:

1. `TranscriptionSession.audio_buffer` is a plain Python list built with
   `.extend(numpy_array)`. One hour of mono 16 kHz is 57.6M elements — roughly
   **460 MB in pointers alone** versus 115 MB as `int16` numpy, doubled for two
   tracks, and `get_audio_array()` copies the lot again.
2. Absolute timestamps have no other source, since whisper restarts segment
   times per call.

Each track is windowed and transcribed independently, then the two segment lists
are merged by `t0` to produce the interleaved transcript. That merge is where
speaker attribution comes from — there is no diarization anywhere in this
system, the separation is physical.

The energy VAD at `server.py:111` applies per window. A window of pure silence
yields no segments, which is correct and expected for a meeting where one side
is quiet for minutes at a time.
