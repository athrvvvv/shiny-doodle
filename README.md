# 🎵 MP3 Downloader (Flutter)

A sleek, well-optimized Flutter application that converts and downloads YouTube and YouTube Shorts audio directly into high-quality **320kbps MP3** on your Android device.

---

## ✨ Features

- **Simple & Intuitive:** Just paste a YouTube link or tap **Paste** from clipboard and hit **Download MP3**.
- **100% Standalone & On-Device:** Runs natively on your phone without relying on external servers or API limits using embedded Python (`yt-dlp`) and hardware-accelerated FFmpeg.
- **High-Quality 320kbps MP3:** Audio streams are transcoded into clean MP3 with embedded ID3 metadata tags (Song Title & Artist).
- **Public Downloads Folder:** Files are saved directly to `/storage/emulated/0/Download/` so they appear immediately in Samsung Music, Google Files, VLC, and other music players.
- **Real-Time Visual Download Process:**
  - Album artwork and duration preview
  - Live animated download progress and percentage
  - Status updates (Metadata extraction ➔ Audio download ➔ FFmpeg MP3 encoding)
- **Built-in Play & Share:** Listen to your downloaded MP3s directly or share them via WhatsApp, Telegram, Google Drive, or Bluetooth.
- **Session History:** Fast access to recently downloaded tracks in the app.

---

## 🛠️ Architecture & Tech Stack

- **Framework:** Flutter 3.47+ / Dart 3.13+ (Material 3 Dark Theme)
- **Embedded Python Engine:** [Chaquopy](https://chaquo.com/) bundling Python 3.12 and [yt-dlp](https://github.com/yt-dlp/yt-dlp) for on-device YouTube extraction without bot-detection / 403 blocks.
- **Audio Transcoding:** [ffmpeg_kit_flutter_new_audio](https://pub.dev/packages/ffmpeg_kit_flutter_new_audio) with `libmp3lame` encoder at 320k CBR.
- **Storage & System Integration:** Android Scoped Storage integration, `open_filex`, and `share_plus`.

---

## 📱 Installation

Download the latest APK from the [Releases](https://github.com/athrvvvv/shiny-doodle/releases) page and install it on any 64-bit Android device (Android 7.0 / API 24+).
