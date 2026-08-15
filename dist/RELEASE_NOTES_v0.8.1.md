# UltraWhisper v0.8.1

Quality-of-life release: UltraWhisper no longer turns your music down when you're wearing headphones.

---

## ✨ What's New

### 🎧 Bluetooth-aware volume ducking

UltraWhisper lowers your system volume while recording so speaker audio doesn't bleed into the
microphone. When you're on Bluetooth headphones or earbuds, there's nothing to bleed — so the duck
is now skipped automatically.

- Checks the default output device's CoreAudio transport type at the moment recording starts
- Bluetooth and Bluetooth LE outputs → **volume left alone**
- Built-in speakers or any other output → **ducks exactly as before**
- If the device can't be inspected, it ducks anyway (safe fallback)

### ⚙️ New setting

**Settings → Audio → Skip when Bluetooth headphones are connected** (on by default)

It appears nested under *Reduce system volume during recording*. Turn it off when you're playing
through a **Bluetooth speaker** — a speaker reports the same Bluetooth transport as headphones, but
its audio *can* reach your mic.

---

## 📥 Download

**Apple Silicon (M1/M2/M3/M4), macOS 13+**

`ultra-whisper-arm64-macos-v0.8.1.zip`

Verify your download:

```bash
shasum -a 256 -c ultra-whisper-arm64-macos-v0.8.1.zip.sha256
```

Unzip and drag `UltraWhisper.app` to `/Applications`. Fully self-contained — no Python, Homebrew, or
Xcode required.

On first launch, grant **Microphone** and **Accessibility** permissions when prompted (Accessibility
is needed for the global hotkeys and auto-paste).

---

## 🎛️ Hotkeys

| Shortcut | Action |
|---|---|
| `⌥⇧R` | Toggle recording |
| `⌥⇧E` | Toggle recording, then paste and press Enter |

---

## 🔄 Upgrading from v0.8.0

Replace the app in `/Applications`. Your existing settings carry over, and the new toggle defaults
to on.

**Full Changelog**: https://github.com/Rum1324/ultra-whisper-arm64/compare/v0.8.0...v0.8.1
