import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test_app/controllers/library_controller.dart';

/// A [LibraryController] that serves a fixed [LibraryData] snapshot without
/// touching any repositories.
///
/// Screen tests use this to exercise the UI against the shared data controller
/// in isolation, instead of depending on Drift-backed repositories.
class FakeLibraryController extends LibraryController {
  FakeLibraryController(this.data);

  final LibraryData data;

  @override
  LibraryData build() => data;

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> scanAndRefresh() async {}
}

/// Convenience override that serves [data] through [libraryControllerProvider].
libraryProviderOverride(LibraryData data) {
  return libraryControllerProvider.overrideWith(() {
    return FakeLibraryController(data);
  });
}
