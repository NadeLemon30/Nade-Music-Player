/// A single node in the virtual folder tree.
///
/// The folder browser is built entirely from `Track.filePath` values scanned
/// from MediaStore (no separate folders table). A node is either a folder
/// ([isFolder] true) or an individual audio file ([isFolder] false).
class FolderNode {
  /// Display name — the folder name or file basename.
  final String name;

  /// Full filesystem path — a directory for folders, a file path for tracks.
  final String path;

  /// Whether this node represents a folder (vs. an audio file).
  final bool isFolder;

  const FolderNode({
    required this.name,
    required this.path,
    required this.isFolder,
  });

  FolderNode copyWith({
    String? name,
    String? path,
    bool? isFolder,
  }) {
    return FolderNode(
      name: name ?? this.name,
      path: path ?? this.path,
      isFolder: isFolder ?? this.isFolder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderNode &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          path == other.path &&
          isFolder == other.isFolder;

  @override
  int get hashCode => Object.hash(name, path, isFolder);

  @override
  String toString() =>
      'FolderNode(name: $name, path: $path, isFolder: $isFolder)';
}
