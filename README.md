# Music Player (Phase 0 Baseline)

A modular, clean-architecture Flutter audio application.

## Project Structure

```
music_player/
│
├── android/
│
├── ios/
│
├── lib/
│   │
│   ├── core/
│   │   ├── constants/       # App-wide constants, dimensions, strings
│   │   ├── theme/           # Centralized Material 3 light and dark themes
│   │   └── utils/           # Utility functions (e.g. duration formatting)
│   │
│   ├── models/              # Immutable data models (e.g. Track)
│   │
│   ├── services/
│   │   └── audio/           # Audio playback service interface and implementations
│   │
│   ├── controllers/         # State management controllers (UI -> Controller -> Service)
│   │
│   ├── screens/             # Top-level screen views
│   │
│   ├── widgets/             # Reusable UI components (MiniPlayer, TrackTile, SeekBar, etc.)
│   │
│   └── main.dart            # App entry point
│
├── test/                    # Unit and widget tests
│
├── pubspec.yaml             # Project dependencies (Riverpod, etc.)
└── README.md
```

## Architectural Principles

- **Decoupled Audio Backend:** The UI layer never interacts directly with underlying audio packages. All operations flow through `PlayerController` to `AudioPlayerService`.
- **State Management:** **Riverpod** is the designated reactive state management solution.
- **Database & Persistence:** **Drift** (relational SQLite) is selected for future multi-table persistence (Phase 3+).
- **Theme Centralization:** All styles, colors, and typography are defined in `lib/core/theme/app_theme.dart`.
- **Android Permissions Strategy:** Phase 0 maintains a clean baseline `AndroidManifest.xml`; media permissions will be added conditionally in Phase 2 (Local Music Scanner).

## Running the App

```bash
# Get dependencies
flutter pub get

# Run tests
flutter test

# Run the app
flutter run
```
