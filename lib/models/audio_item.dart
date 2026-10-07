class AudioItem {
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String? url;

  const AudioItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    this.url,
  });

  AudioItem copyWith({
    String? id,
    String? title,
    String? artist,
    Duration? duration,
    String? url,
  }) {
    return AudioItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      duration: duration ?? this.duration,
      url: url ?? this.url,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'durationMs': duration.inMilliseconds,
      'url': url,
    };
  }

  factory AudioItem.fromMap(Map<String, dynamic> map) {
    return AudioItem(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String? ?? '',
      duration: Duration(milliseconds: map['durationMs'] as int? ?? 0),
      url: map['url'] as String?,
    );
  }
}
