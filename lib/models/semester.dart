/// Represents an academic semester grouping courses.
class Semester {
  const Semester({
    this.id,
    required this.name,
    this.isActive = true,
    required this.createdAt,
  });

  final int? id;
  final String name;
  final bool isActive;
  final DateTime createdAt;

  /// Creates a [Semester] instance from a SQLite row map.
  factory Semester.fromMap(Map<String, Object?> map) {
    return Semester(
      id: map['id'] as int?,
      name: map['name'] as String,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Converts this [Semester] to a SQLite-compatible map.
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Returns a copy with overridden fields.
  Semester copyWith({
    int? id,
    String? name,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Semester(
      id: id ?? this.id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
