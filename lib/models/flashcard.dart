/// Study flashcard generated from a lecture session.
class Flashcard {
  const Flashcard({
    this.id,
    required this.sessionId,
    required this.frontQuestion,
    required this.backAnswer,
    this.masteryLevel = 0,
  });

  final int? id;
  final int sessionId;
  final String frontQuestion;
  final String backAnswer;

  /// 0 = baru, 1 = perlu ulang, 2 = sudah paham.
  final int masteryLevel;

  /// Creates a [Flashcard] from a SQLite row map.
  factory Flashcard.fromMap(Map<String, Object?> map) {
    return Flashcard(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      frontQuestion: map['front_question'] as String,
      backAnswer: map['back_answer'] as String,
      masteryLevel: (map['mastery_level'] as int?) ?? 0,
    );
  }

  /// Converts this [Flashcard] to a SQLite-compatible map.
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'session_id': sessionId,
      'front_question': frontQuestion,
      'back_answer': backAnswer,
      'mastery_level': masteryLevel,
    };
  }

  /// Returns a copy with overridden fields.
  Flashcard copyWith({
    int? id,
    int? sessionId,
    String? frontQuestion,
    String? backAnswer,
    int? masteryLevel,
  }) {
    return Flashcard(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      frontQuestion: frontQuestion ?? this.frontQuestion,
      backAnswer: backAnswer ?? this.backAnswer,
      masteryLevel: masteryLevel ?? this.masteryLevel,
    );
  }
}
