/// Represents a musical genre entity.
class Genre {
  final String id;
  final String name;
  final int trackCount;

  const Genre({
    required this.id,
    required this.name,
    this.trackCount = 0,
  });

  Genre copyWith({
    String? id,
    String? name,
    int? trackCount,
  }) {
    return Genre(
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

  factory Genre.fromMap(Map<String, dynamic> map) {
    return Genre(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown Genre',
      trackCount: map['trackCount'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'Genre(id: $id, name: $name, trackCount: $trackCount)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Genre &&
        other.id == id &&
        other.name == name &&
        other.trackCount == trackCount;
  }

  @override
  int get hashCode => Object.hash(id, name, trackCount);
}
