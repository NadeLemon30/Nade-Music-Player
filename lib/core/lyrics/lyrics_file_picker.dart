import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A lyrics file chosen by the user, decoupled from the file-picker plugin so
/// screens stay easy to test.
class PickedLyricsFile {
  const PickedLyricsFile({required this.name, required this.bytes});

  /// The file's display name (e.g. `song.lrc`).
  final String name;

  /// Raw file bytes; decoded by the lyrics repository.
  final Uint8List bytes;
}

/// Opens a native file picker and returns the selected lyrics file, or `null`
/// when the user cancels.
typedef LyricsFilePicker = Future<PickedLyricsFile?> Function();

/// Default picker: a single `.lrc` or `.txt` file.
Future<PickedLyricsFile?> pickLyricsFile() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Select lyrics file',
    type: FileType.custom,
    allowedExtensions: const ['lrc', 'txt'],
  );
  if (file == null) return null;

  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) return null;

  return PickedLyricsFile(name: file.name, bytes: bytes);
}

/// Overridable in widget tests so no platform channel is invoked.
final lyricsFilePickerProvider = Provider<LyricsFilePicker>(
  (ref) => pickLyricsFile,
);
