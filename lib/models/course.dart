/// Represents a university course within a [Semester].
class Course {
  const Course({
    this.id,
    required this.semesterId,
    required this.name,
    this.lecturerName,
    required this.colorHex,
    required this.createdAt,
    this.sessionCount = 0,
    this.pendingSessionCount = 0,
    this.flashcardCount = 0,
    this.quizCount = 0,
  });

  final int? id;
  final int semesterId;
  final String name;
  final String? lecturerName;
  final String colorHex;
  final DateTime createdAt;

  // Aggregated counts from joined queries (not stored as columns).
  final int sessionCount;
  final int pendingSessionCount;
  final int flashcardCount;
  final int quizCount;

  /// Creates a [Course] from a SQLite query row (supports optional aggregate counts).
  factory Course.fromMap(Map<String, Object?> map) {
    return Course(
      id: map['id'] as int?,
      semesterId: map['semester_id'] as int,
      name: map['name'] as String,
      lecturerName: map['lecturer_name'] as String?,
      colorHex: map['color_hex'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      sessionCount: (map['session_count'] as int?) ?? 0,
      pendingSessionCount: (map['pending_session_count'] as int?) ?? 0,
      flashcardCount: (map['flashcard_count'] as int?) ?? 0,
      quizCount: (map['quiz_count'] as int?) ?? 0,
    );
  }

  /// Converts persisted columns to a SQLite-compatible map.
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'semester_id': semesterId,
      'name': name,
      'lecturer_name': lecturerName,
      'color_hex': colorHex,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Returns a copy with overridden fields.
  Course copyWith({
    int? id,
    int? semesterId,
    String? name,
    String? lecturerName,
    String? colorHex,
    DateTime? createdAt,
    int? sessionCount,
    int? pendingSessionCount,
    int? flashcardCount,
    int? quizCount,
  }) {
    return Course(
      id: id ?? this.id,
      semesterId: semesterId ?? this.semesterId,
      name: name ?? this.name,
      lecturerName: lecturerName ?? this.lecturerName,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
      sessionCount: sessionCount ?? this.sessionCount,
      pendingSessionCount: pendingSessionCount ?? this.pendingSessionCount,
      flashcardCount: flashcardCount ?? this.flashcardCount,
      quizCount: quizCount ?? this.quizCount,
    );
  }
}
