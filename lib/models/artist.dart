/// Represents an artist entity.
class Artist {
  final String id;
  final String name;
  final int trackCount;

  const Artist({
    required this.id,
    required this.name,
    this.trackCount = 0,
  });

  Artist copyWith({
    String? id,
    String? name,
    int? trackCount,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackCount: trackCount ?? this.trackCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'trackCount': trackCount,
    };
  }

  factory Artist.fromMap(Map<String, dynamic> map) {
    return Artist(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown Artist',
      trackCount: map['trackCount'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'Artist(id: $id, name: $name, trackCount: $trackCount)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Artist &&
        other.id == id &&
        other.name == name &&
        other.trackCount == trackCount;
  }

  @override
  int get hashCode => Object.hash(id, name, trackCount);
}
