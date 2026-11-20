/// Type of timestamped annotation captured during a lecture session.
enum AnnotationType {
  textNote('text_note'),
  photo('photo'),
  bookmark('bookmark');

  const AnnotationType(this.value);
  final String value;

  static AnnotationType fromString(String raw) {
    return AnnotationType.values.firstWhere(
      (t) => t.value == raw,
      orElse: () => AnnotationType.textNote,
    );
  }
}

/// Timestamped text note, compressed whiteboard photo, or bookmark.
class SessionAnnotation {
  const SessionAnnotation({
    this.id,
    required this.sessionId,
    required this.type,
    required this.timestampMs,
    this.contentText,
    this.imagePath,
    this.aiVisionNotes,
    required this.createdAt,
  });

  final int? id;
  final int sessionId;
  final String type;
  final int timestampMs;
  final String? contentText;
  final String? imagePath;
  final String? aiVisionNotes;
  final DateTime createdAt;

  AnnotationType get typeEnum => AnnotationType.fromString(type);

  /// Creates a [SessionAnnotation] from a SQLite row map.
  factory SessionAnnotation.fromMap(Map<String, Object?> map) {
    return SessionAnnotation(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      type: map['type'] as String,
      timestampMs: map['timestamp_ms'] as int,
      contentText: map['content_text'] as String?,
      imagePath: map['image_path'] as String?,
      aiVisionNotes: map['ai_vision_notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Converts this [SessionAnnotation] to a SQLite-compatible map.
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'session_id': sessionId,
      'type': type,
      'timestamp_ms': timestampMs,
      'content_text': contentText,
      'image_path': imagePath,
      'ai_vision_notes': aiVisionNotes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Returns a copy with overridden fields.
  SessionAnnotation copyWith({
    int? id,
    int? sessionId,
    String? type,
    int? timestampMs,
    String? contentText,
    String? imagePath,
    String? aiVisionNotes,
    DateTime? createdAt,
  }) {
    return SessionAnnotation(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      type: type ?? this.type,
      timestampMs: timestampMs ?? this.timestampMs,
      contentText: contentText ?? this.contentText,
      imagePath: imagePath ?? this.imagePath,
      aiVisionNotes: aiVisionNotes ?? this.aiVisionNotes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
