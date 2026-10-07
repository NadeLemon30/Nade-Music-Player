import 'package:path/path.dart' as p;

import '../../models/folder_node.dart';
import '../../models/music_folder.dart';
import '../../models/track.dart';

/// Builds a virtual folder tree from the `filePath` values of the scanned
/// tracks, without persisting a separate folders table in SQLite.
///
/// Device audio paths are always POSIX (`/`-separated), so we use the `posix`
/// context (rather than the host platform context) to keep folder paths
/// consistent whether running on Android, on a test host, or elsewhere.
class FolderService {
  /// Returns the direct child folders of [parentPath] that contain one or more
  /// available tracks, sorted by name.
  List<MusicFolder> getChildFolders(
    String parentPath,
    List<Track> tracks,
  ) {
    final folders = <String, MusicFolder>{};

    for (final track in tracks) {
      if (!track.isAvailable) {
        continue;
      }

      final filePath = track.filePath;

      if (!p.posix.isWithin(parentPath, filePath)) {
        continue;
      }

      final relativePath = p.posix.relative(filePath, from: parentPath);

      final parts = p.posix.split(relativePath);

      if (parts.length < 2) {
        continue;
      }

      final folderName = parts.first;

      final folderPath = p.posix.join(parentPath, folderName);

      folders[folderPath] = MusicFolder(
        path: folderPath,
        name: folderName,
      );
    }

    final result = folders.values.toList();

    result.sort(
      (a, b) => a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          ),
    );

    return result;
  }

  /// Returns the available tracks whose direct parent directory is [folderPath],
  /// sorted by file name (`A → Z`), falling back to title for unnamed entries.
  ///
  /// Sorting by the physical file name matches the file-browser convention used
  /// by the rest of the folder views (folders already sort by name).
  List<Track> getTracksInFolder(
    String folderPath,
    List<Track> tracks,
  ) {
    final result = tracks.where((track) {
      if (!track.isAvailable) {
        return false;
      }

      return p.posix.dirname(track.filePath) == folderPath;
    }).toList();

    result.sort(
      (a, b) {
        final aname = a.fileName.isNotEmpty ? a.fileName : a.title;
        final bname = b.fileName.isNotEmpty ? b.fileName : b.title;
        final byName = aname.toLowerCase().compareTo(bname.toLowerCase());
        if (byName != 0) return byName;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      },
    );

    return result;
  }

  /// Returns every available track inside [folderPath], including its nested
  /// subfolders (recursive), sorted by physical file path.
  ///
  /// Used by "Add Folder to Playlist" (spec 10): users expect a folder action
  /// to include its contents recursively, so this resolves a folder down to all
  /// of the audio it (and its children) contain.
  List<Track> getTracksInFolderRecursive(
    String folderPath,
    List<Track> tracks,
  ) {
    final result = tracks.where((track) {
      if (!track.isAvailable) {
        return false;
      }
      return p.posix.isWithin(folderPath, track.filePath);
    }).toList();

    // Order by physical path (case-insensitive) so direct files and nested
    // folders surface in their natural layout order.
    result.sort(
      (a, b) => a.filePath.toLowerCase().compareTo(b.filePath.toLowerCase()),
    );

    return result;
  }

  /// Determines the top-level folders exposed by the scanned tracks.
  ///
  /// Because Android uses scoped storage, we must not browse arbitrary
  /// filesystem paths. Instead, the root folders are derived purely from the
  /// `filePath`s MediaStore has already granted us access to.
  ///
  /// Note: the root extraction below is a reasonable heuristic for the common
  /// `/storage/emulated/0/...` layout, but storage paths can vary between
  /// devices. Prefer deriving the full hierarchy directly from all scanned
  /// paths rather than depending on this hard-coded root depth.
  List<MusicFolder> getRootFolders(
    List<Track> tracks,
  ) {
    final folders = <String, MusicFolder>{};

    for (final track in tracks) {
      if (!track.isAvailable) {
        continue;
      }

      final path = track.filePath;

      final parts = p.posix.split(path);

      if (parts.length < 2) {
        continue;
      }

      final rootPath = p.posix.joinAll(
        parts.sublist(0, parts.length - 1).take(4),
      );

      folders[rootPath] = MusicFolder(
        path: rootPath,
        name: p.posix.basename(rootPath),
      );
    }

    return folders.values.toList();
  }

  /// Groups available tracks by their immediate parent directory path.
  Map<String, List<Track>> groupTracksByDirectory(List<Track> tracks) {
    final map = <String, List<Track>>{};
    for (final track in tracks) {
      if (!track.isAvailable || track.filePath.isEmpty) {
        continue;
      }
      final dir = directoryOf(track.filePath);
      map.putIfAbsent(dir, () => []).add(track);
    }
    return map;
  }

  /// Returns the parent directory of a file path (POSIX-normalized).
  String directoryOf(String filePath) {
    return p.posix.dirname(filePath);
  }

  /// Returns the display name (last segment) of a folder path.
  String getName(String folderPath) {
    return p.posix.basename(folderPath);
  }

  /// Finds the single common root directory shared by every available track.
  ///
  /// Returns `null` when there are no available tracks.
  ///
  /// Note: when the library spans multiple storage volumes (e.g. internal
  /// storage and an SD card), this collapses everything to the shallowest
  /// shared path — which is exactly the limitation the multi-root support
  /// ([findStorageRoots]) addresses.
  String? findCommonRoot(List<Track> tracks) {
    final paths = tracks
        .where((track) => track.isAvailable)
        .map((track) => p.posix.dirname(track.filePath))
        .toList();

    if (paths.isEmpty) {
      return null;
    }

    final splitPaths = paths.map(p.posix.split).toList();

    final minimumLength =
        splitPaths.map((parts) => parts.length).reduce((a, b) => a < b ? a : b);

    var commonLength = 0;

    for (var i = 0; i < minimumLength; i++) {
      final segment = splitPaths.first[i];

      final same = splitPaths.every((parts) => parts[i] == segment);

      if (!same) {
        break;
      }

      commonLength++;
    }

    return p.posix.joinAll(splitPaths.first.take(commonLength));
  }

  /// Discovers the distinct storage roots represented by the scanned tracks.
  ///
  /// A device can expose several storage volumes (internal storage, an SD
  /// card, USB OTG, ...). This returns the top-most directory for each distinct
  /// volume so the browser can group them (e.g. `Internal Storage`, `SD Card`)
  /// rather than assuming a single root.
  ///
  /// Heuristic for v0.1 (documented as Android-flavored): Android exposes each
  /// volume under `/storage/<volume-id>`, with the internal volume nested one
  /// level deeper as `/storage/emulated/<user-id>`. We fold the user-id into the
  /// internal root so it surfaces as a single `Internal Storage` entry, and the
  /// SD card as its own `/storage/<volume-id>` entry. Paths outside `/storage`
  /// fall back to their leading mount segment.
  ///
  /// Because it keys on the volume path (not on content folders), tracks under
  /// `Music/` and `Ringtones/` in the same volume still resolve to one root.
  List<String> findStorageRoots(List<Track> tracks) {
    final roots = <String>{};

    for (final track in tracks) {
      if (!track.isAvailable || track.filePath.isEmpty) continue;
      final dir = p.posix.dirname(track.filePath);
      final splitDir = p.posix.split(dir);
      final isAbsolute =
          splitDir.isNotEmpty && splitDir.first == p.posix.separator;
      final segments = splitDir
          .where((s) => s.isNotEmpty && s != p.posix.separator)
          .toList();
      if (segments.isEmpty) continue;

      final String rawRoot;
      if (segments.first == 'storage' && segments.length >= 2) {
        if (segments[1] == 'emulated' && segments.length >= 3) {
          rawRoot = p.posix.joinAll(['storage', 'emulated', segments[2]]);
        } else {
          rawRoot = p.posix.joinAll(['storage', segments[1]]);
        }
      } else {
        // Not under /storage: fall back to the leading mount segment.
        rawRoot = segments.first;
      }

      final root = isAbsolute && !rawRoot.startsWith(p.posix.separator)
          ? p.posix.join(p.posix.separator, rawRoot)
          : rawRoot;

      roots.add(root);
    }

    return roots.toList();
  }

  /// Returns a friendly display label for a storage root path.
  String storageRootLabel(String rootPath) {
    if (rootPath.contains('/emulated')) {
      return 'Internal Storage';
    }
    return 'SD Card';
  }

  /// Returns the child folders (first) and files (second) of [folderPath] as
  /// folder-tree nodes, ready for display.
  List<FolderNode> getChildren(
    String folderPath,
    List<Track> tracks,
  ) {
    final result = <FolderNode>[];

    for (final folder in getChildFolders(folderPath, tracks)) {
      result.add(FolderNode(
        name: folder.name,
        path: folder.path,
        isFolder: true,
      ));
    }

    for (final track in getTracksInFolder(folderPath, tracks)) {
      result.add(FolderNode(
        name: track.fileName,
        path: track.filePath,
        isFolder: false,
      ));
    }

    return result;
  }

  /// Returns the normalized top-level folders for the root folder browser view.
  ///
  /// The virtual tree is built from all scanned paths, but the technical Android
  /// path components (e.g. `/storage/emulated/0`) are hidden. Instead we surface
  /// the first meaningful directory of each scanned track (relative to the
  /// shared storage root). Tracks that sit directly in the storage root are
  /// grouped under an `Other` folder.
  ///
  /// When the library spans multiple storage volumes ([findStorageRoots] returns
  /// more than one), the top-level view instead surfaces one entry per storage
  /// root (`Internal Storage`, `SD Card`, ...) which can then be drilled into.
  ///
  /// This is a v0.1 heuristic; storage roots may vary between devices.
  List<FolderNode> getTopLevelFolders(List<Track> tracks) {
    final dirs = <String>{};
    for (final track in tracks) {
      if (!track.isAvailable || track.filePath.isEmpty) continue;
      dirs.add(p.posix.dirname(track.filePath));
    }
    if (dirs.isEmpty) return [];

    // Multiple storage volumes (internal + SD card) => surface each volume.
    final volumes = findStorageRoots(tracks);
    if (volumes.length > 1) {
      final result = [
        for (final root in volumes)
          FolderNode(
            name: storageRootLabel(root),
            path: root,
            isFolder: true,
          ),
      ];
      result.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return result;
    }

    final baseSegments = _commonPrefixSegments(dirs);

    // name -> full path of each top-level folder
    final buckets = <String, String>{};
    var hasLoose = false;

    for (final dir in dirs) {
      final segments = p.posix
          .split(dir)
          .where((s) => s.isNotEmpty)
          .toList();
      final relative = segments.sublist(
        baseSegments.length >= segments.length
            ? segments.length
            : baseSegments.length,
      );
      if (relative.isEmpty) {
        hasLoose = true;
      } else {
        final first = relative.first;
        final full = p.posix.joinAll([...baseSegments, first]);
        buckets[first] = full;
      }
    }

    // If every track collapsed into the base (e.g. all files live in one deep
    // folder), surface the base's own name as a single top-level folder.
    if (buckets.isEmpty) {
      final basePath = p.posix.joinAll(baseSegments);
      if (basePath.isNotEmpty && baseSegments.isNotEmpty) {
        buckets[baseSegments.last] = basePath;
        hasLoose = false;
      }
    }

    final result = <FolderNode>[
      for (final entry in buckets.entries)
        FolderNode(name: entry.key, path: entry.value, isFolder: true),
    ];

    if (hasLoose) {
      result.add(FolderNode(
        name: 'Other',
        path: p.posix.joinAll(baseSegments),
        isFolder: true,
      ));
    }

    result.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return result;
  }

  /// Returns the longest run of leading path segments that every directory
  /// shares (e.g. `['storage', 'emulated', '0']`).
  List<String> _commonPrefixSegments(Iterable<String> dirs) {
    final splitDirs = dirs
        .map((d) => p.posix.split(d).where((s) => s.isNotEmpty).toList())
        .toList();
    if (splitDirs.isEmpty) return const [];

    final minLen =
        splitDirs.map((s) => s.length).reduce((a, b) => a < b ? a : b);
    int common = 0;
    for (int i = 0; i < minLen; i++) {
      final segment = splitDirs.first[i];
      if (splitDirs.every((s) => s[i] == segment)) {
        common++;
      } else {
        break;
      }
    }
    return splitDirs.first.sublist(0, common);
  }
}
