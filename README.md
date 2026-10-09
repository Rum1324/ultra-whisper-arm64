<div align="center">
  <img src=".github/assets/app_icon.png" alt="UltraWhisper Icon" width="200"/>

  # UltraWhisper

  **Fast local transcription, private by default, optimized for Apple Silicon**

  [![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos)
  [![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M1%2FM2%2FM3-orange.svg)](https://www.apple.com/mac)
  [![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
  [![Latest Release](https://img.shields.io/github/v/release/Rum1324/ultra-whisper-arm64)](https://github.com/Rum1324/ultra-whisper-arm64/releases/latest)

</div>

---

## Features

- **🔒 Private by Default** - All transcription happens on your device. After the one-time model download no internet is needed, and no audio or text leaves your Mac — unless you choose Claude for AI formatting ([below](#ai-formatting-on-your-mac-or-with-claude))
- **✨ AI Formatting** - Tidies each dictation: fillers out, natural punctuation, numbers as digits, Japanese 、。. Runs on your Mac, or on Claude Haiku with your own API key
- **🗒️ Meeting Notes (beta)** - When a call starts, offers to transcribe your side and theirs, then writes a summary with decisions and action items using a local model. Beta: it works, but has not yet been tested end to end on real meetings
- **⚡ Blazing Fast** - Metal GPU acceleration on Apple Silicon for real-time transcription
- **📋 Auto-Paste** - Automatically pastes transcribed text into your current app when done
- **🎙️ Two Hotkeys** - `⌥⇧R` to dictate, `⌥⇧E` to dictate and press Return
- **🧭 Guided Setup** - A first-run window checks permissions, sets your shortcuts, and picks models that suit your Mac
- **🌍 Multi-Language** - Auto-detect English and Japanese (more languages coming soon)
- **🎯 Menu Bar Integration** - Clean, native macOS status bar app with quick controls
- **📚 Custom Dictionary** - Add technical terms and domain-specific keywords for better accuracy
- **🎨 Flexible Visibility** - Show in menu bar only, Dock only, or both
- **🔊 Smart Audio** - Volume ducking during recording for clear capture

## Installation

### Download Pre-Built App

1. Download the latest `ultra-whisper-arm64-macos-v*.zip` (about 40 MB) from the [Releases](https://github.com/Rum1324/ultra-whisper-arm64/releases/latest) page
2. Unzip and move **UltraWhisper.app** to your Applications folder
3. Open it once. macOS will refuse, because the app is not notarized by Apple — this is expected:
   - Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the UltraWhisper message, then confirm.
   - Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/UltraWhisper.app`
4. The setup window walks you through the rest:
   - **Microphone** and **Accessibility** permissions
   - Your two shortcuts
   - The speech model, recommended for your Mac's memory and disk (190 MB – 1.6 GB download)
   - Optional local AI — tidier dictation and meeting notes (beta). UltraWhisper downloads its own copy of [Ollama](https://ollama.com) for these, or uses yours if it is already running. Nothing else needs installing.

Models can be downloaded, switched or deleted later in **Settings → Speech model** and **Local AI**. They live in `~/Library/Application Support/UltraWhisper`.

### System Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon (M1 or later)
- 8 GB memory works with the light speech model; 16 GB for the full one; 24 GB+ for AI formatting on your Mac (any Mac with Claude)
- 1–2 GB free disk, plus ~10 GB for AI formatting on your Mac and ~12–17 GB for meeting notes

## Usage

### Quick Start

1. **Launch UltraWhisper** - Look for the app icon in your menu bar
2. **Start Recording** - press `⌥⇧R` (or click the menu bar icon → "Start Recording")
3. **Speak** into your microphone
4. **Stop Recording** - press `⌥⇧R` again, or `⌥⇧E` to also press Return after pasting
5. **Get Your Text** - Transcribed text is pasted into your active app and left on the clipboard

### Customization

Open **Settings** from the menu bar to customize:

- **Capture Mode**: Hold-to-talk vs. Toggle recording
- **Hotkeys**: Configure your preferred keyboard shortcuts
- **Custom Dictionary**: Add technical terms like "Kubernetes", "PostgreSQL", etc.
- **App Visibility**: Choose menu bar only, Dock only, or both
- **AI Handoff**: Optional macro to send transcribed text to AI assistants
- **AI Formatting**: On your Mac or with Claude — see below

### AI formatting: on your Mac or with Claude

**Settings → Advanced → AI formatting** cleans up each dictation after it is transcribed. Pick where it runs under **Engine**:

| | On this Mac | Claude (API key) |
|---|---|---|
| Model | gemma4:e4b via Ollama | Claude Haiku 5.5 |
| Wait after you stop talking | ~0.4 s when loaded, 4–7 s after it was unloaded | ~0.8 s, every time |
| Needs | 24 GB+ memory, ~10 GB download | An Anthropic API key and internet |
| Cost | Free | About $0.0001 per dictation, billed to your Anthropic account |
| Your text | Never leaves your Mac | Sent to Anthropic |

To use Claude, create a key at [platform.claude.com](https://platform.claude.com) → API keys and paste it into **Anthropic API key** — saving it turns AI formatting on and switches the engine to Claude. Removing the key switches back to your Mac. The key is stored in your macOS Keychain — never in a file, a log, or the app — and you can remove it there at any time.

**What Claude means for privacy:** with Claude selected, the text of each dictation (never the audio) goes to Anthropic's API. Anthropic does not train on API data by default and deletes it after 30 days ([details](https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data)). Anything you dictate — including other people's names — is part of that text. Transcription itself always stays on your Mac.

Either engine falls back to the plain transcript when it can't run: no model, no key, offline, out of credits, or an answer that doesn't look like a cleanup of what you said.

## How It Works

UltraWhisper uses a hybrid architecture to deliver fast, private transcription:

1. **Frontend**: Flutter macOS app provides the native UI and system integration
2. **Backend**: Python service running [whisper.cpp](https://github.com/ggerganov/whisper.cpp) with Metal GPU acceleration
3. **GPU Acceleration**: Metal backend leverages Apple Silicon's GPU for real-time performance
4. **Model**: Whisper large-v3-turbo or a lighter variant (GGML format), downloaded once at setup and stored locally
5. **Communication**: WebSocket connection on localhost for low-latency audio streaming

**Privacy First**: Transcription runs locally on your Mac. No telemetry, no data collection. The one optional exception is AI formatting with Claude, which sends dictation text to Anthropic with your own key — off unless you choose it.

## Troubleshooting

### App won't open / "Apple could not verify" / "App is damaged"
The app is not notarized, so macOS blocks the first launch. Either click **Open Anyway** in **System Settings → Privacy & Security**, or run:
```bash
xattr -dr com.apple.quarantine /Applications/UltraWhisper.app
```

### Setup window closed before the download finished
Click the menu bar icon → **Settings**, or open UltraWhisper again from Applications — setup reopens until a speech model is in place. Downloads resume where they stopped.

### No transcription output
- Check microphone permissions in **System Settings → Privacy & Security → Microphone**
- Ensure UltraWhisper has microphone access enabled
- Try restarting the app

### Poor transcription quality
- Add domain-specific terms to **Settings → Custom Dictionary**
- Speak clearly and minimize background noise
- Check your microphone input level in System Settings

### Menu bar icon not appearing
- Go to **Settings → App Visibility** and ensure it's not set to "Dock Only"
- Try restarting the app

### Auto-paste not working
- Grant Accessibility permissions in **System Settings → Privacy & Security → Accessibility**
- Ensure UltraWhisper is checked in the list

---

## For Developers

### Building from Source

#### Prerequisites
- Flutter SDK (stable channel) with macOS desktop support
- Xcode 14.0 or later
- Python 3.11+
- Homebrew (recommended)

#### Setup

1. **Clone the repository**
```bash
git clone https://github.com/Rum1324/ultra-whisper-arm64.git
cd ultra-whisper-arm64
```

2. **Install Flutter dependencies**
```bash
flutter pub get
```

3. **Set up Python backend**
```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cd ..
```

4. **Run the app**
```bash
flutter run -d macos
```

5. **Build release version**
```bash
flutter build macos --release
```

The built app will be in `build/macos/Build/Products/Release/UltraWhisper.app`

### Project Structure

```
ultra-whisper-arm64/
├── lib/                      # Flutter/Dart frontend
│   ├── main.dart            # App entry point
│   ├── models/              # Data models
│   ├── services/            # Business logic
│   ├── widgets/             # UI components
│   └── windows/             # Multi-window architecture
├── macos/                   # macOS native code
│   └── Runner/
│       ├── AppDelegate.swift         # App lifecycle
│       ├── StatusBarController.swift # Menu bar integration
│       └── AppLifecycleHandler.swift # Dock visibility
├── backend/                 # Python transcription service
│   ├── server.py           # WebSocket server
│   └── requirements.txt    # Python dependencies
└── docs/                    # Documentation
```

### Key Technologies

- **Frontend**: Flutter, Swift
- **Backend**: Python, whisper.cpp (Metal GPU optimized)
- **Communication**: WebSocket (JSON + binary audio)
- **GPU Acceleration**: Metal (via whisper.cpp)
- **Audio Format**: 16kHz PCM, 16-bit mono

## Contributing

Contributions are welcome! Here's how you can help:

1. **Report Bugs**: Open an issue with detailed steps to reproduce
2. **Suggest Features**: Share your ideas in the issues section
3. **Submit PRs**:
   - Fork the repository
   - Create a feature branch (`git checkout -b feature/amazing-feature`)
   - Commit your changes (`git commit -m 'Add amazing feature'`)
   - Push to your branch (`git push origin feature/amazing-feature`)
   - Open a Pull Request

Please ensure your code follows the existing style and includes appropriate tests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [OpenAI Whisper](https://github.com/openai/whisper) - The foundation model
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - High-performance C++ inference with Metal GPU support
- [Flutter](https://flutter.dev) - Cross-platform UI framework

---

<div align="center">
  Made with ❤️ for Apple Silicon

  [Report Bug](https://github.com/Rum1324/ultra-whisper-arm64/issues) · [Request Feature](https://github.com/Rum1324/ultra-whisper-arm64/issues)
</div>
