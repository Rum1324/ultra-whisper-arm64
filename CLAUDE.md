# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **UltraWhisper v0.9.0** - a fast, local-only macOS transcription utility built with Flutter (macOS frontend) + Python backend (**whisper.cpp via hand-written ctypes bindings**, Metal GPU). It provides a minimal, glass-like floating UI for voice transcription with two toggle hotkeys and automatic pasting into the currently focused app.

**Key Features:**
- Local-only transcription for privacy and offline use
- Flutter macOS app with glass/vibrancy floating overlay window
- Python backend calling whisper.cpp through ctypes with Metal GPU acceleration
- WebSocket communication between Flutter app and Python backend
- Two toggle hotkeys: record (`⌥⇧R`) and record-then-press-Enter (`⌥⇧E`)
- Automatic paste, leaving the transcript on the clipboard
- Optional AI handoff macro with configurable keystroke sequences
- Multi-language support (EN/JA auto-detect)

## Development Commands

### Flutter Commands
```bash
# Get dependencies
flutter pub get

# Run the app (macOS)
flutter run -d macos

# Build for release
flutter build macos --release

# Analyze code
flutter analyze

# Run tests
flutter test
```

### Backend Development (Python)
```bash
# Set up virtual environment (in backend directory)
python -m venv venv
source venv/bin/activate  # or `venv\Scripts\activate` on Windows

# Install dependencies
pip install -r backend/requirements.txt

# Run backend server
python backend/src/server.py

# Run with UV (if available)
uv venv && uv pip install -r backend/requirements.txt
```

### Testing Commands
```bash
# Run Flutter widget tests
flutter test

# Run Python backend tests (if pytest is configured)
pytest backend/

# Lint Python code (if ruff is configured)
ruff check backend/
```

### Distribution & Verification Commands
```bash
# Build release version
flutter build macos --release

# Verify app is standalone (no external dependencies)
./macos/Scripts/verify_standalone.sh build/macos/Build/Products/Release/UltraWhisper.app

# Create distributable archive
cd build/macos/Build/Products/Release
zip -r UltraWhisper-v0.4.0-macOS.zip UltraWhisper.app
```

### Backend Tests

```bash
# Python backend tests (pytest resolves the `summarize` package via backend/conftest.py)
cd backend && pytest tests/ -q
```

## Architecture Overview

### High-Level Structure
- **Frontend**: Flutter macOS app provides UI (menu bar status, floating overlay, settings window)
- **Backend**: Python service calling whisper.cpp through ctypes ([backend/whisper_wrapper.py](backend/whisper_wrapper.py))
- **Communication**: WebSocket on `127.0.0.1`. `server.py` defaults to `--port 0`, but the Flutter side pins **8082** ([backend_service.dart](lib/services/backend_service.dart)); the server prints `SERVER_PORT:<n>` on stdout and Flutter parses that line to confirm startup
- **Audio Processing**: 16kHz PCM audio streaming in 20-40ms chunks
- **Models**: `ggml-large-v3-turbo.bin` bundled, Metal GPU acceleration

### Key Components

#### Flutter App Structure
- `lib/main.dart` - Entry point
- `lib/services/app_service.dart` - Orchestrator wiring audio, hotkeys, backend, and paste
- `lib/services/backend_service.dart` - Spawns the Python backend and sets `DYLD_LIBRARY_PATH` so `@rpath/libggml*.dylib` resolves inside the bundle
- `lib/models/websocket_messages.dart` - Wire types, generated with **json_serializable + build_runner**
- Menu bar status item, floating overlay, and settings window are implemented

#### Backend Architecture
- `server.py` - asyncio WebSocket server, session management, energy VAD
- `whisper_wrapper.py` - ctypes bindings to `libwhisper.dylib`, mirroring `whisper_full_params` field-for-field. Includes `detect_language()` for cheap encode-only pre-detection
- `postprocess.py` - smart caps, terminal punctuation, disfluency cleanup, and Japanese punctuation (ASCII `, . ? !` → `、。？！`, decided per token so `3.2` and `Node.js` keep their dot)
- `dictation_formatter.py` - optional LLM clean-up of each dictation (`gemma4:e4b` via Ollama, few-shot prompt); see *AI formatting* below
- `summarize/` - meeting-note generation; see [docs/MEETING_PROTOCOL.md](docs/MEETING_PROTOCOL.md)

**Two behaviors worth knowing before changing transcription:**
- Energy VAD rejects a clip whose **loudest** 30ms window has RMS < 0.01. It deliberately measures the window peak, not the whole-clip average — averaging over the silence padding in toggle mode dropped short or quiet utterances.
- The custom-vocabulary initial prompt is gated to English speech. It wrecked Japanese punctuation when applied unconditionally.

### AI formatting

Settings → Advanced → *AI Formatting (local)*, on by default, runs each dictation through `gemma4:e4b` in Ollama after the rule pass: fillers, natural punctuation, numbers as digits, Japanese 、。. It adds ~1 s. The model and prompt were picked by measurement (2026-09-25, 22 realistic EN/JA dictations through whisper): e4b with rules **plus few-shot examples** passed 22/22; gemma4:e2b and qwen3.5:4b/9b managed 17–18, with e2b translating Japanese into English and the Qwens leaving Japanese fillers. The examples, not the rules, are what made fillers like えーと go away.

The LLM output is **discarded** — and the rule-based text pasted — when Ollama is unreachable, the model is missing, it times out, the language changed, or the output is outside 40–125% of the input size (words for English, characters for Japanese). That size band is what catches a small model *answering* a dictated question or dropping sentences. The floor drops to 12% only when the dictation carries a correction cue (*no wait*, *never mind*, *scratch that*, いや, じゃなくて…), because resolving a change of mind to the final decision is the one legitimate way to lose most of the text; self-correction resolution needed its own few-shot examples — the rule alone was ignored. Output with a doubled kana run the speaker never said is also discarded: e4b turns 「4時からです」 into 「4時からからです」 without an example showing it. The rule pass runs again on accepted output, so Japanese punctuation is guaranteed by code rather than by the prompt. `start_session` preloads the model so its load overlaps with speaking.

### Communication Protocol
- WebSocket messages use JSON envelope `{type, id, data}` with raw binary frames for audio
- Commands: `hello`, `start_session`, `<binary audio>`, `end_session`, `cancel`
- Events: `hello_ack`, `session_started`, `final`, `error`
- Note: `PartialEvent` and `StatsEvent` exist on the Dart side, but `server.py` never emits `partial` or `stats`
- Audio format: PCM 16-bit mono, 16kHz, 20-40ms chunks
- Meeting sessions extend this protocol; see [docs/MEETING_PROTOCOL.md](docs/MEETING_PROTOCOL.md)

## Development Setup

### Prerequisites
- Flutter stable SDK with macOS desktop support enabled
- Xcode for macOS development
- Python 3.11+ for backend development
- Optional: UV for Python package management
- Optional: BlackHole 2ch for system audio testing

### First-Time Setup
1. Enable Flutter macOS desktop: `flutter config --enable-macos-desktop`
2. Install dependencies: `flutter pub get`
3. Set up Python backend environment (when backend code exists)
4. Request necessary macOS permissions (Microphone, Accessibility)

### Permissions Required
- **NSMicrophoneUsageDescription**: For audio capture
- **Accessibility**: For global hotkeys and synthetic keystroke generation
- These permissions are configured in macOS-specific Info.plist files

## Project Status

**Current State**: v0.9.0, shipping. The Flutter UI, Swift hotkey/status-bar/paste layer, whisper.cpp backend, and standalone bundling are all implemented and working.

**In progress**: meeting notes — record a meeting as two tracks, transcribe it, and generate a structured note with a local LLM. Merged to `main`. See [docs/MEETING_PROTOCOL.md](docs/MEETING_PROTOCOL.md) and `backend/summarize/`.

Capture, protocol, backend, detection, orchestration and a minimal panel are all in place, and the Core Audio process tap is **verified working on real hardware** (2026-08-25: 16 kHz mono, peak 23513/32767, confirmed by measuring the dumped WAV outside the app). What remains is an end-to-end run through a real meeting.

Audio Recording (`kTCCServiceAudioCapture`) is a **separate TCC service from Microphone** (`kTCCServiceMicrophone`); a grant for one says nothing about the other, and a denied tap returns digital silence rather than an error. Before debugging a silent "them" track, read the header comment in [AudioTapController.swift](macos/Runner/AudioTapController.swift) — and dump the audio to a WAV and measure it outside the process first. A measurement bug, not the tap, caused a multi-day false trail.

The opt-in self-test (`touch ~/.ultrawhisper_tap_selftest`, optionally with a pid in it) writes `~/.ultrawhisper_tap_selftest-<app>.result`, a per-callback trace to `~/.ultrawhisper_tap_diag-<app>`, and the captured audio to `~/ultrawhisper-tap-<name>.wav`. Launch with `open` or Finder, never `flutter run` — TCC attributes a grant to the responsible process, which for a shell launch is the terminal.

### Meeting detection

A meeting is detected app-agnostically: a real-time call is the one common situation where a **single process** is capturing the microphone and playing audio at the same time. Music is output-only, dictation is input-only, and a browser in a Google Meet call is both — which is why the rule works without a list of meeting apps. The same signal also names the process to tap for the "them" track. See [lib/services/meeting_detector.dart](lib/services/meeting_detector.dart) and `test/meeting_detector_test.dart`.

Dictation is refused while a meeting records: both want the microphone through the one `AudioService`, and the second subscriber would silently get nothing.

### Departure from the all-bundled policy

Meeting-note summarization talks to **Ollama** over `127.0.0.1:11434` and is the one part of the app that is *not* self-contained: it needs Ollama installed and a model pulled.

This is deliberate. Bundling a `llama-server` would mean vendoring llama.cpp and shipping its ggml dylibs — which have **the same filenames** as whisper.cpp's (`libggml.dylib`, `libggml-base.dylib`, `libggml-metal.dylib`), all resolved via `@rpath`. Since `DYLD_LIBRARY_PATH` already points at whisper's copies and dyld consults it *before* `@rpath`, a bundled llama-server would load whisper's ggml and fail.

The notes model is chosen in Settings → Meetings from three presets, all Unsloth Dynamic GGUFs of Qwen3.6-35B-A3B pulled straight from HuggingFace: Balanced (`UD-Q3_K_XL`, ~16.8 GB), Light (`UD-Q2_K_XL`, ~12.3 GB) and Lightest (`UD-IQ2_M`, ~11.5 GB). Sizes are shown in the UI because the model is the one thing in this app the user physically feels — 17 GB resident is real memory pressure on a laptop. See [lib/models/notes_model_presets.dart](lib/models/notes_model_presets.dart).

**The model is evicted from Ollama as soon as a note is finished** (`summarize_meeting(unload_after=True)`, default). Ollama otherwise keeps it resident for its `keep_alive` — five minutes of memory pressure after the note is already on screen. Eviction is a single `keep_alive: 0` request at the end rather than on every call, so the pipeline's classify/map/reduce passes still share one load. Nothing is evicted when nothing was loaded, so an empty transcript or a missing model never puts a request on the wire.

AI formatting of dictation uses the same Ollama, under the same rule: it is never a dependency, and every failure falls back to the rule-based transcript.

Consequently, **summarization degrades gracefully rather than failing**: if Ollama is absent or the model is not pulled, transcription and the raw transcript still work and the app reports that notes are unavailable. Do not make meeting notes a hard dependency of the transcription path.

## Key Implementation Notes

- Target platform is **macOS 13+ on Apple Silicon** (optimized for M3 Max with 32GB RAM)
- Backend will be packaged as embedded Python runtime inside .app bundle
- Models stored in `~/Library/Application Support/UltraWhisper/models/`
- WebSocket communication on `127.0.0.1` with ephemeral port negotiation
- Paste goes through the clipboard, and the transcript **stays** there afterwards. Settings → Advanced → Pasting has a toggle (`keepTranscriptOnClipboard`, default on) that restores the previous clipboard instead. The old behaviour restored unconditionally, which meant the one thing the user could not recover — the text they had just spoken — was the thing that got thrown away
- AI Handoff uses configurable keystroke sequence: `⌥Space → ⌘N → ⌃V → Enter` with 100ms delays

### Standalone Distribution System

The app is **completely self-contained** with no external dependencies:

- **Bundled Python Runtime**: Python 3.12 (arm64) with websockets + numpy (~91 MB)
- **whisper.cpp Libraries**: All GGML libraries with Metal GPU support (~3 MB)
- **Whisper Model**: large-v3-turbo GGML model embedded in app (1.5 GB)
- **Total App Size**: ~1.7 GB

**Build Process** ([macos/Scripts/copy_backend.sh](macos/Scripts/copy_backend.sh)):
1. Copies Python runtime and dependencies into app bundle
2. Copies whisper.cpp libraries (libwhisper, GGML libs, Metal shader)
3. Fixes library install_name paths to use `@loader_path` instead of absolute paths
4. Verifies all critical dependencies are present
5. Sets correct permissions

**Verification** ([macos/Scripts/verify_standalone.sh](macos/Scripts/verify_standalone.sh)):
- Checks all library dependencies use `@rpath`, `@executable_path`, or `@loader_path`
- Verifies no external library dependencies (only system frameworks allowed)
- Confirms all required files are bundled
- Validates code signatures

**Runtime Library Resolution** ([lib/services/backend_service.dart](lib/services/backend_service.dart)):
- Sets `DYLD_LIBRARY_PATH` environment variable to resolve `@rpath` at runtime
- Points to all GGML library locations within the app bundle
- Ensures Python can find libpython3.12.dylib using `@loader_path`

The app works on any macOS 13+ Apple Silicon Mac **without requiring**:
- Xcode or development tools
- Homebrew or package managers
- System Python installation
- Any external library installations

## Configuration Files

- `pubspec.yaml` - Flutter dependencies and project configuration
- `analysis_options.yaml` - Dart/Flutter linting rules using flutter_lints package
- Platform-specific configuration in respective directories (macos/, ios/, android/, etc.)
- Future: Settings will be stored in macOS preferences/UserDefaults