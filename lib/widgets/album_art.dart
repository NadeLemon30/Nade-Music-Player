import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../services/artwork/artwork_service.dart';

/// Reusable artwork image widget backed by high-speed memory and disk caching.
///
/// Ensures embedded artwork is extracted only once and smoothly displayed without UI jank.
class AlbumArt extends ConsumerWidget {
  final String? artUrl;
  final Track? track;
  final Album? album;
  final Uint8List? artwork;
  final double size;
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;
  final Widget? placeholder;

  const AlbumArt({
    super.key,
    this.artUrl,
    this.track,
    this.album,
    this.artwork,
    this.size = 56.0,
    this.width,
    this.height,
    this.borderRadius = AppConstants.defaultRadius,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  /// Effective width of the artwork, falling back to [size] when [width] is null.
  double get _effectiveWidth => width ?? size;

  /// Effective height of the artwork, falling back to [size] when [height] is null.
  double get _effectiveHeight => height ?? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: _effectiveWidth,
        height: _effectiveHeight,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: _buildArtworkContent(context, ref),
      ),
    );
  }

  Widget _buildArtworkContent(BuildContext context, WidgetRef ref) {
    // 0. Raw artwork bytes (preloaded / passed directly)
    if (artwork != null && artwork!.isNotEmpty) {
      return Image.memory(
        artwork!,
        width: _effectiveWidth,
        height: _effectiveHeight,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
      );
    }

    final effectiveUrl = artUrl ?? track?.albumArtUri ?? album?.artworkKey;

    // 1. Network Image
    if (effectiveUrl != null &&
        (effectiveUrl.startsWith('http://') || effectiveUrl.startsWith('https://'))) {
      return Image.network(
        effectiveUrl,
        width: _effectiveWidth,
        height: _effectiveHeight,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
      );
    }

    // 2. Bundled Asset Image
    if (effectiveUrl != null && effectiveUrl.startsWith('assets/')) {
      return Image.asset(
        effectiveUrl,
        width: _effectiveWidth,
        height: _effectiveHeight,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
      );
    }

    // 3. Direct Local File Path
    if (effectiveUrl != null &&
        (effectiveUrl.startsWith('/') || effectiveUrl.contains(':\\')) &&
        File(effectiveUrl).existsSync()) {
      return Image.file(
        File(effectiveUrl),
        width: _effectiveWidth,
        height: _effectiveHeight,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
      );
    }

    // 4. Cached / Extracted Embedded Artwork
    final artworkService = ref.watch(artworkServiceProvider);
    final identifier = effectiveUrl ?? track?.id ?? album?.id.toString() ?? '';
    final filePath = track?.filePath;

    if (identifier.isNotEmpty || (filePath != null && filePath.isNotEmpty)) {
      // Route by WHERE the identifier came from, not merely that it is numeric.
      // A non-null numeric album-art key (track.albumArtUri = song.albumId,
      // album.artworkKey = album id) resolves as *album* artwork via
      // queryArtwork(ArtworkType.ALBUM) — the AUDIO query would treat it as a
      // song id and return nothing. But when there is NO album-art key
      // (effectiveUrl is null) we fall back to track.id, a MediaStore *song* id:
      // routing that numeric value as an album id can return a *different*
      // album's artwork (and collide cache keys across unrelated songs), so it
      // must stay per-audio extraction.
      final isAlbumArt = album != null ||
          (effectiveUrl != null && int.tryParse(effectiveUrl) != null);
      final sourceType =
          isAlbumArt ? ArtworkSourceType.album : ArtworkSourceType.audio;
      final cacheKey =
          '${sourceType.name}_${identifier.isNotEmpty ? identifier : filePath}';

      // Check synchronous memory cache first for 0ms latency
      final memoryBytes = artworkService.getFromMemoryCache(cacheKey);
      if (memoryBytes != null) {
        return Image.memory(
          memoryBytes,
          width: _effectiveWidth,
          height: _effectiveHeight,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
        );
      }

      // Query asynchronous ArtworkService (Disk Cache -> Extractor)
      return FutureBuilder<Uint8List?>(
        future: artworkService.getArtwork(
          id: identifier,
          filePath: filePath,
          sourceType: sourceType,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.isNotEmpty) {
            return Image.memory(
              snapshot.data!,
              width: _effectiveWidth,
              height: _effectiveHeight,
              fit: fit,
              errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
            );
          }

          return _buildPlaceholder(context);
        },
      );
    }

    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    if (placeholder != null) return placeholder!;

    return Center(
      child: Icon(
        album != null ? Icons.album : Icons.music_note,
        size: _iconSize,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// Resolves a finite placeholder icon size, falling back to [size] when the
  /// artwork dimensions are unbounded (e.g. `double.infinity`).
  double get _iconSize {
    final smallest = _effectiveHeight < _effectiveWidth
        ? _effectiveHeight
        : _effectiveWidth;
    return smallest.isFinite ? smallest * 0.45 : size * 0.45;
  }
}
