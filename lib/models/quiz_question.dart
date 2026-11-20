import 'dart:convert';

/// Multiple-choice quiz question generated from a lecture session.
class QuizQuestion {
  const QuizQuestion({
    this.id,
    required this.sessionId,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final int? id;
  final int sessionId;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  /// Creates a [QuizQuestion] from a SQLite row map.
  factory QuizQuestion.fromMap(Map<String, Object?> map) {
    final decoded = jsonDecode(map['options_json'] as String) as List<dynamic>;
    return QuizQuestion(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      question: map['question'] as String,
      options: decoded.map((item) => item.toString()).toList(growable: false),
      correctIndex: map['correct_index'] as int,
      explanation: map['explanation'] as String,
    );
  }

  /// Converts this [QuizQuestion] to a SQLite-compatible map.
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'session_id': sessionId,
      'question': question,
      'options_json': jsonEncode(options),
      'correct_index': correctIndex,
      'explanation': explanation,
    };
  }

  /// Returns a copy with overridden fields.
  QuizQuestion copyWith({
    int? id,
    int? sessionId,
    String? question,
    List<String>? options,
    int? correctIndex,
    String? explanation,
  }) {
    return QuizQuestion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      question: question ?? this.question,
      options: options ?? this.options,
      correctIndex: correctIndex ?? this.correctIndex,
      explanation: explanation ?? this.explanation,
    );
  }
}
