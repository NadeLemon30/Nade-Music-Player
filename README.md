# 🎵 Nade's Music Player

An offline Android music player built with Flutter, designed to provide a powerful local music experience inspired by players such as VLC, with additional statistics and personalization features inspired by Spotify Wrapped.

> **Status:** 🚧 Active Development  
> **Platform:** Android  
> **Framework:** Flutter  
> **Language:** Dart

---

## 📥 Download

The latest Android APK is available through the project's **GitHub Releases**.

### Latest Release

👉 **[Download the latest APK](../../releases/latest)**

1. Open the latest release.
2. Go to the **Assets** section.
3. Download the `.apk` file.
4. Transfer it to your Android device if necessary.
5. Install the APK.
6. If Android prevents the installation, allow installation from unknown sources for the application you used to open the APK.

> **Note:** The APK is distributed through GitHub Releases while the project is under active development.

---

## 📖 Table of Contents

- [📥 Download](#-download)
- [✨ Features](#-features)
- [🛠️ Installation](#️-installation)
- [▶️ Usage](#️-usage)
- [📁 Project Structure](#-project-structure)
- [⚙️ Configuration](#️-configuration)
- [🏗️ Architecture](#️-architecture)
- [🗄️ Data Storage](#️-data-storage)
- [🧪 Testing](#-testing)
- [🐛 Troubleshooting](#-troubleshooting)
- [🤝 Contributing](#-contributing)
- [🗺️ Roadmap](#️-roadmap)
- [📄 License](#-license)
- [📞 Contact & Support](#-contact--support)
- [📝 Additional Notes](#-additional-notes)

---

# ✨ Features

## 🎵 Music Library

Nade's Music Player is designed primarily for playing music stored locally on the user's Android device.

Current and planned library functionality includes:

- Local music scanning
- Music library
- Songs
- Albums
- Artists
- Folder browser
- Search
- Album artwork
- Music metadata
- Automatic library synchronization

> **Genres are intentionally not included in the current roadmap because the project's target local music files may not contain reliable embedded genre metadata.**

---

## ▶️ Playback

Core playback functionality includes:

- Play / Pause
- Previous track
- Next track
- Seek
- Shuffle
- Repeat
- Queue management
- Background playback
- Lock-screen controls
- Notification controls
- Resume playback position

The application uses a centralized playback architecture rather than creating separate audio players for different features.

---

## ❤️ Favorites

Users can mark songs as favorites.

Features include:

- Add songs to favorites
- Remove songs from favorites
- Favorite status in song lists
- Dedicated Favorites screen
- Persistent favorite state
- Automatic cleanup when tracks are removed from the library

Favorites do not modify or delete the original music files.

---

## 🕘 Playback History

The application tracks listening activity locally.

Supported functionality includes:

- Play count
- Recently played songs
- Last played timestamp
- Resume position
- Persistent playback history
- Automatic cleanup of deleted tracks

Playback history is stored independently from the music files.

---

## 📋 Playlists

Users can create and manage personal playlists.

Playlist functionality includes:

- Create playlists
- Rename playlists
- Delete playlists
- Add songs
- Remove songs
- Reorder songs
- Play playlists
- Shuffle playlists
- Play Next
- Add to Queue
- Multi-select song actions
- Add albums to playlists
- Add artists' songs to playlists
- Add folder contents to playlists

Deleting a playlist only removes the playlist relationship. It does **not** delete the user's music files.

---

## 🌙 Sleep Timer

The Sleep Timer allows playback to automatically stop after a selected amount of time.

Available functionality includes:

- 15 minutes
- 30 minutes
- 45 minutes
- 60 minutes
- 90 minutes
- Custom duration
- Countdown display
- Cancel timer
- Background operation
- Automatic playback stop on expiration

The timer does not modify:

- Playlists
- Favorites
- Queue
- Playback history
- Music files

---

## 🎚️ Equalizer & Audio Effects

The planned audio-effects system includes:

- Graphic equalizer
- Equalizer presets
- Custom EQ
- Bass Boost
- Virtualizer / spatial effect
- Preamp
- Persistent effect settings
- Background playback support

The effects system is designed to work with the application's existing audio player rather than creating another playback system.

---

# 🛠️ Installation

## For Regular Users

The easiest way to install Nade's Music Player is to download the latest APK from:

**[GitHub Releases](../../releases/latest)**

No Flutter or development environment is required.

---

## For Developers

### 1. Clone the Repository

```bash
git clone <your-repository-url>
cd "Nade's Music Player"
```

### 2. Check Flutter

Make sure Flutter is installed and available from your terminal:

```bash
flutter doctor
```

### 3. Install Dependencies

```bash
flutter pub get
```

### 4. Connect an Android Device

Connect an Android phone using USB and verify that Flutter detects it:

```bash
flutter devices
```

### 5. Run the Application

```bash
flutter run
```

---

## Building an APK

To generate a debug APK:

```bash
flutter build apk --debug
```

For a release APK:

```bash
flutter build apk --release
```

The generated APK will normally be located under:

```text
build/app/outputs/flutter-apk/
```

---

# ▶️ Usage

## Installing the APK

After downloading a release APK:

1. Open the APK on your Android device.
2. Allow installation if Android requests permission.
3. Install the application.
4. Launch Nade's Music Player.
5. Grant the required media permissions.
6. Allow the application to scan your local music.
7. Select a song to begin playback.

---

## 🎵 Playing Music

The general playback flow is:

```text
Open App
   ↓
Scan Music
   ↓
Music Library
   ↓
Select Song
   ↓
Player
   ↓
Background Playback
```

Users can then control:

- Playback
- Seek position
- Queue
- Shuffle
- Repeat
- Favorites
- Playlists
- Sleep timer
- Audio effects

---

# 📁 Project Structure

The project follows a feature-oriented Flutter structure.

```text
Nade's Music Player/
│
├── android/
│
├── ios/
│
├── lib/
│   │
│   ├── core/
│   │   ├── audio/
│   │   └── playback/
│   │
│   ├── data/
│   │   ├── models/
│   │   └── repositories/
│   │
│   ├── screens/
│   │   ├── library/
│   │   ├── playlists/
│   │   ├── player/
│   │   └── settings/
│   │
│   ├── widgets/
│   │   ├── playlists/
│   │   └── ...
│   │
│   └── main.dart
│
├── test/
│
├── pubspec.yaml
├── README.md
└── LICENSE
```

The exact structure may evolve as development continues.

---

# ⚙️ Configuration

## Flutter

The project currently targets a modern Flutter environment.

Development environment used during development includes:

```text
Flutter 3.44.4
Dart 3.12.2
DevTools 2.57.0
```

The project should be developed using a compatible stable Flutter release.

---

## Android

Android development requires:

- Android SDK
- Android SDK Platform
- Android SDK Build Tools
- Android SDK Command-line Tools
- Android device or emulator

For physical-device testing, enable:

```text
Developer Options
USB Debugging
```

on the Android device.

---

## Permissions

Because the application scans locally stored music, Android media permissions are required.

Depending on the Android version, the application may use the appropriate Android media-access permission.

Users should grant media/audio access when requested so the application can discover their local music.

---

# 🏗️ Architecture

The application is designed around a centralized playback system.

A simplified architecture is:

```text
                  ┌───────────────────┐
                  │        UI         │
                  └─────────┬─────────┘
                            │
                            ▼
                  ┌───────────────────┐
                  │ PlayerController  │
                  └─────────┬─────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
              ▼             ▼             ▼
        AudioHandler    Queue System   Sleep Timer
              │
              ▼
        Audio Engine
```

Additional systems connect to the central playback architecture:

```text
PlayerController
       │
       ├── Playback History
       ├── Favorites
       ├── Playlists
       ├── Sleep Timer
       └── Audio Effects
```

The primary design principle is:

> **One playback system should control audio playback.**

Features such as the equalizer, sleep timer, history, and queue should integrate with the existing playback system rather than creating independent players.

---

# 🗄️ Data Storage

The application uses local persistent storage for application data.

Current data concepts include:

## Playback History

```text
playback_history

track_id
play_count
last_played_at
resume_position_ms
```

---

## Favorites

```text
favorites

track_id
favorited_at
```

---

## Playlists

```text
playlists

id
name
created_at
```

Playlist relationships:

```text
playlist_tracks

playlist_id
track_id
position
```

---

## Playlist History

Playlist listening statistics are kept separate from individual song playback history.

```text
playlist_history

playlist_id
play_count
last_played_at
```

This allows the application to distinguish:

```text
Playing a song
```

from:

```text
Explicitly playing a playlist
```

---

# 🧪 Testing

The application should be tested on a physical Android device whenever possible.

Important areas include:

### Music Library

- [ ] Music scanning works
- [ ] Songs appear correctly
- [ ] Albums appear correctly
- [ ] Artists appear correctly
- [ ] Artwork loads correctly
- [ ] Deleted files are removed from the library

### Playback

- [ ] Play
- [ ] Pause
- [ ] Seek
- [ ] Previous
- [ ] Next
- [ ] Shuffle
- [ ] Repeat
- [ ] Queue
- [ ] Background playback

### Favorites

- [ ] Add favorite
- [ ] Remove favorite
- [ ] Favorite state persists
- [ ] Deleted tracks are cleaned up

### History

- [ ] Play count updates
- [ ] Recently played updates
- [ ] Resume position saves
- [ ] Resume position restores

### Playlists

- [ ] Create
- [ ] Rename
- [ ] Delete
- [ ] Add tracks
- [ ] Remove tracks
- [ ] Reorder
- [ ] Play playlist
- [ ] Shuffle playlist
- [ ] Play Next
- [ ] Add to Queue

### Sleep Timer

- [ ] Presets work
- [ ] Custom duration works
- [ ] Countdown works
- [ ] Cancellation works
- [ ] Background operation works
- [ ] Playback stops when timer expires

### Audio Effects

- [ ] Equalizer
- [ ] Presets
- [ ] Custom EQ
- [ ] Bass Boost
- [ ] Virtualizer
- [ ] Settings persistence
- [ ] Background playback

---

# 🐛 Troubleshooting

## Flutter Dependencies

If dependencies appear out of sync:

```bash
flutter pub get
```

---

## Clean Build

If the Android build behaves unexpectedly:

```bash
flutter clean
flutter pub get
```

Then try:

```bash
flutter run
```

A clean build should generally be used for troubleshooting rather than before every normal test run.

---

## Check Connected Devices

```bash
flutter devices
```

If the Android phone does not appear:

```bash
adb devices
```

Make sure:

- USB debugging is enabled.
- The phone is unlocked.
- The computer is authorized on the phone.
- The USB cable supports data transfer.

---

## Check Flutter Environment

```bash
flutter doctor -v
```

This provides detailed information about the Flutter, Android SDK, Java, and development environment configuration.

---

# 🤝 Contributing

Contributions, bug reports, feature suggestions, and improvements are welcome.

## Development Workflow

1. Fork the repository.
2. Create a feature branch.

```bash
git checkout -b feature/my-feature
```

3. Make your changes.
4. Test the application.
5. Commit your changes.

```bash
git commit -m "Add my feature"
```

6. Push the branch.

```bash
git push origin feature/my-feature
```

7. Open a Pull Request.

---

## Contribution Guidelines

When contributing:

- Keep the existing architecture consistent.
- Avoid creating duplicate playback systems.
- Do not delete or modify user music files unexpectedly.
- Keep database operations isolated in repositories.
- Test changes on Android where possible.
- Avoid introducing unnecessary dependencies.
- Document significant architectural changes.
- Keep UI components reusable when practical.

---

# 🗺️ Roadmap

## Essential Features

- [x] Local music scanning
- [x] Music library foundation
- [x] Songs
- [x] Albums
- [x] Artists
- [x] Folder browser
- [x] Search foundation
- [x] Play / Pause
- [x] Previous / Next
- [x] Seek
- [x] Shuffle
- [x] Repeat
- [x] Queue
- [x] Playlists
- [x] Background playback
- [x] Lock-screen controls
- [x] Notification controls
- [x] Album artwork
- [x] Metadata
- [x] Favorites
- [x] Playback history
- [x] Recently played
- [x] Resume position
- [x] Sleep timer

### Planned

- [ ] Lyrics
- [ ] Audio normalization
- [ ] Gapless playback
- [ ] ReplayGain
- [ ] Crossfade
- [ ] Playback speed
- [ ] A-B repeat
- [ ] Headphone controls
- [ ] Android Auto
- [ ] Chromecast
- [ ] Network playback
- [ ] NAS / SMB support
- [ ] Android widgets

---

# 🚀 Long-Term Vision

The long-term goal is to develop Nade's Music Player into a powerful local media player comparable to the flexibility of VLC while maintaining a music-focused interface.

Potential future functionality includes:

- Video playback
- Subtitle support
- Multiple audio tracks
- Hardware decoding
- 360° video
- HDR
- Network streaming
- UPnP / DLNA
- FTP / SFTP / NFS
- Picture-in-Picture
- Advanced audio processing

These features are part of the long-term vision and are not necessarily part of the current release.

---

# 📄 License

A license has not yet been formally selected for this project.

Until a license is added to the repository, users should not assume that the source code is freely available for redistribution, modification, or commercial use.

A `LICENSE` file should be added once the project's licensing terms have been decided.

---

# 📞 Contact & Support

For bugs, feature requests, and development discussions, use the repository's GitHub issue tracker:

👉 **[Report an Issue](../../issues)**

For source code and project information:

👉 **[GitHub Repository](.)**

When reporting a bug, include:

- Android version
- Device model
- Application version
- Steps to reproduce the issue
- Expected behavior
- Actual behavior
- Relevant error messages or screenshots

---

# 📝 Additional Notes

## Offline-First Design

Nade's Music Player is designed primarily around locally stored music.

The application does not require an online music-streaming service for its core playback functionality.

---

## User Music Files

The application should treat the user's music files as external data.

Deleting a:

- Favorite
- Playlist
- History record
- Queue entry

must **not** delete the original music file.

---

## Stable Track Identity

Features such as:

- Favorites
- Playback history
- Resume position
- Playlists

depend on stable track identifiers.

A library rescan should therefore preserve existing relationships whenever the same music file can be identified.

---

## Playlist vs Queue

A playlist and the playback queue are separate concepts.

```text
Playlist
    ↓
Saved collection of songs
```

while:

```text
Queue
    ↓
Current playback order
```

Playing or shuffling a playlist should generate a playback queue without permanently changing the saved playlist order.

---

## Generated Code

If the project later introduces code-generation tools such as `build_runner`, generated files should only be regenerated when the corresponding source definitions change or generated output needs to be refreshed.

For example:

```bash
dart run build_runner build --delete-conflicting-outputs
```

This is **not required before every normal application run**.

---

## Development Commands

Useful Flutter commands:

```bash
flutter pub get
```

```bash
flutter run
```

```bash
flutter clean
```

```bash
flutter doctor -v
```

```bash
flutter devices
```

```bash
flutter build apk --release
```

---

# 🎯 Project Goal

Nade's Music Player aims to provide a clean, powerful, and privacy-friendly local music experience without requiring users to upload their personal music collection to a streaming service.

The project combines:

```text
Local Music
     +
Powerful Playback
     +
Playlists
     +
Favorites
     +
Listening History
     +
Audio Controls
     +
Personal Statistics
```

into one Android music player.

> **Nade's Music Player — Your music, your device, your experience.**