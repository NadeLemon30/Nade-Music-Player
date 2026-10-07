import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/folder_node.dart';

void main() {
  group('FolderNode Model', () {
    test('supports copyWith, equality, and properties', () {
      const node = FolderNode(
        name: 'Music',
        path: '/storage/emulated/0/Music',
        isFolder: true,
      );

      expect(node.name, 'Music');
      expect(node.path, '/storage/emulated/0/Music');
      expect(node.isFolder, isTrue);

      final file = node.copyWith(
        name: 'Numb.mp3',
        path: '/storage/emulated/0/Music/Numb.mp3',
        isFolder: false,
      );
      expect(file.name, 'Numb.mp3');
      expect(file.isFolder, isFalse);
      expect(file == node, isFalse);

      final identicalCopy = node.copyWith();
      expect(identicalCopy, equals(node));
      expect(identicalCopy.hashCode, equals(node.hashCode));
    });

    test('distinguishes folders from files', () {
      const folder = FolderNode(
        name: 'Linkin Park',
        path: '/storage/emulated/0/Music/Linkin Park',
        isFolder: true,
      );
      const track = FolderNode(
        name: '01 - Foreword.mp3',
        path: '/storage/emulated/0/Music/Linkin Park/01 - Foreword.mp3',
        isFolder: false,
      );

      expect(folder.isFolder, isTrue);
      expect(track.isFolder, isFalse);
      expect(folder == track, isFalse);
    });

    test('equals compares by name, path, and isFolder', () {
      const a = FolderNode(name: 'x', path: '/a/x', isFolder: true);
      const b = FolderNode(name: 'x', path: '/a/x', isFolder: true);
      const c = FolderNode(name: 'x', path: '/a/y', isFolder: true);
      const d = FolderNode(name: 'x', path: '/a/x', isFolder: false);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
      expect(a == d, isFalse);
    });

    test('toString includes name, path, and isFolder', () {
      const node = FolderNode(name: 'Meteora', path: '/Music/Meteora', isFolder: true);
      expect(node.toString(),
          contains('FolderNode(name: Meteora, path: /Music/Meteora, isFolder: true)'));
    });
  });
}
