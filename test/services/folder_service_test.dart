import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/models/track.dart';
import 'package:nades_music_player/services/folders/folder_service.dart';

void main() {
  final service = FolderService();

  Track buildTrack(
    String id,
    String title,
    String filePath, {
    bool isAvailable = true,
    String fileName = '',
  }) {
    return Track(
      id: id,
      title: title,
      artist: 'Artist',
      album: '',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: null,
      filePath: filePath,
      fileName: fileName,
      fileSize: null,
      mimeType: null,
      isAvailable: isAvailable,
    );
  }

  group('FolderService.getChildFolders', () {
    final tracks = [
      buildTrack('t1', 'Papercut',
          '/storage/emulated/0/Music/Linkin Park/Hybrid Theory/01 Papercut.mp3'),
      buildTrack('t2', 'Numb',
          '/storage/emulated/0/Music/Linkin Park/Meteora/13 Numb.mp3'),
      buildTrack('t3', 'One More Time',
          '/storage/emulated/0/Music/Daft Punk/Discovery/01 One More Time.mp3'),
      buildTrack('t4', 'Loose Track',
          '/storage/emulated/0/Music/Various Artists/loose_track.mp3'),
      buildTrack('t5', 'Top Level', '/storage/emulated/0/Music/top.mp3'),
    ];

    test('returns direct child folders only, sorted by name', () {
      final children = service.getChildFolders(
        '/storage/emulated/0/Music',
        tracks,
      );

      expect(children.map((f) => f.name), [
        'Daft Punk',
        'Linkin Park',
        'Various Artists',
      ]);
    });

    test('returns nested children for a subfolder', () {
      final children = service.getChildFolders(
        '/storage/emulated/0/Music/Linkin Park',
        tracks,
      );

      expect(children.map((f) => f.name), ['Hybrid Theory', 'Meteora']);
    });

    test('returns empty when parent has no children', () {
      final children = service.getChildFolders(
        '/storage/emulated/0/Music/Linkin Park/Meteora',
        tracks,
      );
      expect(children, isEmpty);
    });

    test('captures correct path for each child folder', () {
      final children = service.getChildFolders(
        '/storage/emulated/0/Music',
        tracks,
      );
      final linkin = children.firstWhere((f) => f.name == 'Linkin Park');
      expect(linkin.path, '/storage/emulated/0/Music/Linkin Park');
    });

    test('ignores unavailable tracks', () {
      final localTracks = [
        buildTrack(
          'a1',
          'Gone',
          '/storage/emulated/0/Music/Missing/gone.mp3',
          isAvailable: false,
        ),
        buildTrack(
          'a2',
          'Here',
          '/storage/emulated/0/Music/Present/here.mp3',
        ),
      ];

      final children = service.getChildFolders(
        '/storage/emulated/0/Music',
        localTracks,
      );

      expect(children.map((f) => f.name), ['Present']);
      expect(children.single.path, '/storage/emulated/0/Music/Present');
    });

    test('does not create folders from file names that live directly in parent',
        () {
      final localTracks = [
        buildTrack(
          'f1',
          'Root Song',
          '/storage/emulated/0/Music/root_song.mp3',
        ),
      ];
      final children = service.getChildFolders(
        '/storage/emulated/0/Music',
        localTracks,
      );
      expect(children, isEmpty);
    });
  });

  group('FolderService.getTracksInFolder', () {
    final tracks = [
      buildTrack('t1', 'Zebra',
          '/storage/emulated/0/Music/Album/zebra.mp3'),
      buildTrack('t2', 'Alpha',
          '/storage/emulated/0/Music/Album/alpha.mp3'),
      buildTrack('t3', 'Nested',
          '/storage/emulated/0/Music/Album/Sub/nested.mp3'),
      buildTrack('t4', 'Other',
          '/storage/emulated/0/Music/Other/other.mp3'),
    ];

    test('returns only direct-parent tracks, sorted by file name A-Z', () {
      final localTracks = [
        buildTrack('t1', 'Zebra',
            '/storage/emulated/0/Music/Album/zebra.mp3',
            fileName: 'zebra.mp3'),
        buildTrack('t2', 'Alpha',
            '/storage/emulated/0/Music/Album/alpha.mp3',
            fileName: 'alpha.mp3'),
      ];

      final result = service.getTracksInFolder(
        '/storage/emulated/0/Music/Album',
        localTracks,
      );

      expect(result.map((t) => t.fileName), ['alpha.mp3', 'zebra.mp3']);
    });

    test('falls back to title ordering when file names are empty', () {
      final result = service.getTracksInFolder(
        '/storage/emulated/0/Music/Album',
        tracks,
      );

      expect(result.map((t) => t.title), ['Alpha', 'Zebra']);
    });

    test('excludes nested subfolder tracks', () {
      final result = service.getTracksInFolder(
        '/storage/emulated/0/Music/Album',
        tracks,
      );
      expect(result.map((t) => t.id), isNot(contains('t3')));
    });

    test('returns empty for a folder with no direct tracks', () {
      final result = service.getTracksInFolder(
        '/storage/emulated/0/Music/Empty',
        tracks,
      );
      expect(result, isEmpty);
    });

    test('ignores unavailable tracks', () {
      final localTracks = [
        buildTrack('u1', 'Hidden',
            '/storage/emulated/0/Music/Album/hidden.mp3',
            isAvailable: false),
        buildTrack('u2', 'Shown',
            '/storage/emulated/0/Music/Album/shown.mp3'),
      ];
      final result = service.getTracksInFolder(
        '/storage/emulated/0/Music/Album',
        localTracks,
      );
      expect(result.map((t) => t.title), ['Shown']);
    });
  });

  group('FolderService.getTracksInFolderRecursive', () {
    final tracks = [
      buildTrack('t1', 'Direct One',
          '/storage/emulated/0/Music/Album/direct_one.mp3'),
      buildTrack('t2', 'Nested',
          '/storage/emulated/0/Music/Album/Sub/nested.mp3'),
      buildTrack('t3', 'Deep Nested',
          '/storage/emulated/0/Music/Album/Sub/zzz/deep.mp3'),
      buildTrack('t4', 'Outside',
          '/storage/emulated/0/Music/Other/outside.mp3'),
    ];

    test('includes direct files and nested subfolder tracks', () {
      final result = service.getTracksInFolderRecursive(
        '/storage/emulated/0/Music/Album',
        tracks,
      );
      expect(result.map((t) => t.id).toSet(),
          {'t1', 't2', 't3'});
    });

    test('excludes tracks outside the folder', () {
      final result = service.getTracksInFolderRecursive(
        '/storage/emulated/0/Music/Album',
        tracks,
      );
      expect(result.map((t) => t.id), isNot(contains('t4')));
    });

    test('orders by physical path (direct files before nested)', () {
      final result = service.getTracksInFolderRecursive(
        '/storage/emulated/0/Music/Album',
        tracks,
      );
      expect(result.first.id, 't1');
      expect(result.map((t) => t.id), ['t1', 't2', 't3']);
    });

    test('ignores unavailable tracks', () {
      final localTracks = [
        buildTrack('u1', 'Gone',
            '/storage/emulated/0/Music/Album/gone.mp3',
            isAvailable: false),
        buildTrack('u2', 'Here',
            '/storage/emulated/0/Music/Album/here.mp3'),
      ];
      final result = service.getTracksInFolderRecursive(
        '/storage/emulated/0/Music/Album',
        localTracks,
      );
      expect(result.map((t) => t.id), ['u2']);
    });

    test('returns empty for a folder with no audio anywhere under it', () {
      final result = service.getTracksInFolderRecursive(
        '/storage/emulated/0/Music/Empty',
        tracks,
      );
      expect(result, isEmpty);
    });
  });

  group('FolderService.getRootFolders', () {
    test('groups scanned tracks under the common storage root', () {
      final roots = service.getRootFolders([
        buildTrack('a1', 'A',
            '/storage/emulated/0/Music/A.mp3'),
        buildTrack('a2', 'B',
            '/storage/emulated/0/Music/Rock/B.mp3'),
        buildTrack('a3', 'D',
            '/storage/emulated/0/Download/D.mp3'),
      ]);

      expect(roots.map((f) => f.path).toSet(),
          {'/storage/emulated/0'});
      expect(roots.single.name, '0');
    });

    test('ignores unavailable tracks when computing roots', () {
      final roots = service.getRootFolders([
        buildTrack('u1', 'Hidden',
            '/storage/emulated/0/Music/hidden.mp3',
            isAvailable: false),
        buildTrack('u2', 'Shown',
            '/storage/emulated/0/Podcasts/shown.mp3'),
      ]);

      expect(roots.single.path, '/storage/emulated/0');
      expect(roots.single.name, '0');
    });

    test('returns empty when no tracks qualify', () {
      expect(service.getRootFolders([]), isEmpty);
    });
  });

  group('FolderService.getTopLevelFolders', () {
    test('hides technical Android prefix and exposes top-level folders', () {
      final tops = service.getTopLevelFolders([
        buildTrack('a1', 'A', '/storage/emulated/0/Music/A.mp3'),
        buildTrack('a2', 'B', '/storage/emulated/0/Music/Rock/B.mp3'),
        buildTrack('a3', 'C', '/storage/emulated/0/Download/C.mp3'),
      ]);

      expect(tops.map((n) => n.name).toSet(), {'Music', 'Download'});
      expect(tops.every((n) => n.isFolder), isTrue);

      final music = tops.firstWhere((n) => n.name == 'Music');
      final download = tops.firstWhere((n) => n.name == 'Download');
      expect(music.path, '/storage/emulated/0/Music');
      expect(download.path, '/storage/emulated/0/Download');
    });

    test('groups loose files in the storage root under Other', () {
      final tops = service.getTopLevelFolders([
        buildTrack('a1', 'Loose', '/storage/emulated/0/loose.mp3'),
        buildTrack('a2', 'Nested', '/storage/emulated/0/Music/Nested.mp3'),
      ]);

      expect(tops.map((n) => n.name).toSet(), {'Music', 'Other'});
      final other = tops.firstWhere((n) => n.name == 'Other');
      expect(other.isFolder, isTrue);
      expect(other.path, '/storage/emulated/0');
    });

    test('exposes the sole folder when all tracks share one deep folder', () {
      final tops = service.getTopLevelFolders([
        buildTrack('a1', 'A', '/storage/emulated/0/Music/Album/A.mp3'),
        buildTrack('a2', 'B', '/storage/emulated/0/Music/Album/B.mp3'),
      ]);

      expect(tops.map((n) => n.name).toSet(), {'Album'});
      expect(tops.single.path, '/storage/emulated/0/Music/Album');
      expect(tops.single.isFolder, isTrue);
    });

    test('ignores unavailable tracks and returns empty for empty library', () {
      expect(service.getTopLevelFolders([]), isEmpty);
      final tops = service.getTopLevelFolders([
        buildTrack('u1', 'Hidden', '/storage/emulated/0/Music/h.mp3',
            isAvailable: false),
      ]);
      expect(tops, isEmpty);
    });
  });

  group('FolderService.getChildren', () {
    final tracks = [
      buildTrack('t1', 'Zebra',
          '/storage/emulated/0/Music/Album/zebra.mp3',
          fileName: 'zebra.mp3'),
      buildTrack('t2', 'Alpha',
          '/storage/emulated/0/Music/Album/alpha.mp3',
          fileName: 'alpha.mp3'),
      buildTrack('t3', 'Nested',
          '/storage/emulated/0/Music/Album/Sub/nested.mp3',
          fileName: 'nested.mp3'),
    ];

    test('returns subfolders first, then direct files as nodes', () {
      final nodes = service.getChildren('/storage/emulated/0/Music/Album', tracks);

      final folders = nodes.where((n) => n.isFolder).toList();
      final files = nodes.where((n) => !n.isFolder).toList();

      expect(folders.single.name, 'Sub');
      expect(folders.single.path, '/storage/emulated/0/Music/Album/Sub');
      expect(files.map((n) => n.name).toList(), ['alpha.mp3', 'zebra.mp3']);
    });

    test('returns empty when folder has neither folders nor files', () {
      final nodes = service.getChildren('/storage/emulated/0/Music/Empty', tracks);
      expect(nodes, isEmpty);
    });
  });

  group('FolderService path helpers', () {
    test('directoryOf returns the immediate parent directory', () {
      expect(
        service.directoryOf('/storage/emulated/0/Music/Rock/song.mp3'),
        '/storage/emulated/0/Music/Rock',
      );
    });

    test('getName returns the last path segment', () {
      expect(service.getName('/storage/emulated/0/Music/Rock'), 'Rock');
      expect(service.getName('/storage/emulated/0/Music'), 'Music');
    });

    test('groupTracksByDirectory groups by parent dir and skips unavailable', () {
      final grouped = service.groupTracksByDirectory([
        buildTrack('a', 'A', '/Music/Linkin Park/Hybrid Theory/a.mp3'),
        buildTrack('b', 'B', '/Music/Linkin Park/Hybrid Theory/b.mp3'),
        buildTrack('c', 'C', '/Music/Daft Punk/Discovery/c.mp3'),
        buildTrack('d', 'D', '/Music/Missing/d.mp3', isAvailable: false),
      ]);

      expect(grouped.keys.length, 2);
      expect(grouped['/Music/Linkin Park/Hybrid Theory']!.length, 2);
      expect(grouped['/Music/Daft Punk/Discovery']!.length, 1);
      expect(grouped.containsKey('/Music/Missing'), isFalse);
    });
  });

  group('FolderService.findCommonRoot', () {
    test('returns the common parent directory across all tracks', () {
      expect(
        service.findCommonRoot([
          buildTrack('a', 'A', '/storage/emulated/0/Music/Linkin Park/a.mp3'),
          buildTrack('b', 'B', '/storage/emulated/0/Music/Linkin Park/Meteora/b.mp3'),
          buildTrack('c', 'C', '/storage/emulated/0/Music/Daft Punk/c.mp3'),
        ]),
        '/storage/emulated/0/Music',
      );
    });

    test('returns null when there are no available tracks', () {
      expect(service.findCommonRoot([]), isNull);
      expect(
        service.findCommonRoot([
          buildTrack('a', 'A', '/Music/a.mp3', isAvailable: false),
        ]),
        isNull,
      );
    });

    test('returns the full path when all tracks share the same directory', () {
      expect(
        service.findCommonRoot([
          buildTrack('a', 'A', '/storage/emulated/0/Music/Album/a.mp3'),
          buildTrack('b', 'B', '/storage/emulated/0/Music/Album/b.mp3'),
        ]),
        '/storage/emulated/0/Music/Album',
      );
    });
  });

  group('FolderService multiple storage roots', () {
    test('findStorageRoots detects internal + SD volumes', () {
      final roots = service.findStorageRoots([
        buildTrack('a', 'A', '/storage/emulated/0/Music/A.mp3'),
        buildTrack('b', 'B', '/storage/emulated/0/Download/B.mp3'),
        buildTrack('c', 'C', '/storage/ABCD-1234/Music/C.mp3'),
        buildTrack('d', 'D', '/storage/ABCD-1234/Ringtones/D.mp3'),
      ]);

      expect(roots.toSet(),
          {'/storage/emulated/0', '/storage/ABCD-1234'});
    });

    test('findStorageRoots returns a single root for internal-only storage', () {
      final roots = service.findStorageRoots([
        buildTrack('a', 'A', '/storage/emulated/0/Music/A.mp3'),
        buildTrack('b', 'B', '/storage/emulated/0/Ringtones/B.mp3'),
      ]);

      expect(roots, ['/storage/emulated/0']);
    });

    test('storageRootLabel maps emulated to Internal Storage', () {
      expect(service.storageRootLabel('/storage/emulated/0'), 'Internal Storage');
      expect(service.storageRootLabel('/storage/ABCD-1234'), 'SD Card');
    });

    test('getTopLevelFolders surfaces one node per volume for multiple roots', () {
      final tops = service.getTopLevelFolders([
        buildTrack('a', 'A', '/storage/emulated/0/Music/A.mp3'),
        buildTrack('b', 'B', '/storage/ABCD-1234/Music/B.mp3'),
      ]);

      expect(tops.map((n) => n.name).toSet(),
          {'Internal Storage', 'SD Card'});
      expect(tops.every((n) => n.isFolder), isTrue);

      final internal = tops.firstWhere((n) => n.name == 'Internal Storage');
      final sd = tops.firstWhere((n) => n.name == 'SD Card');
      expect(internal.path, '/storage/emulated/0');
      expect(sd.path, '/storage/ABCD-1234');
    });
  });
}
