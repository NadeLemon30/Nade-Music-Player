/// Represents a physical music folder in the library.
///
/// Folders are derived from `Track.filePath` at browse time — the database does
/// not keep a separate folders table. `songCount` and `childFolderCount` will be
/// added when needed.
class MusicFolder {
  /// Full filesystem path of the folder.
  final String path;

  /// Display name of the folder (last path segment).
  final String name;

  const MusicFolder({
    required this.path,
    required this.name,
  });

  @override
  String toString() => 'MusicFolder(path: $path, name: $name)';
}
