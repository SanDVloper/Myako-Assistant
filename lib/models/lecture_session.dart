/// Processing lifecycle state for a recorded or imported lecture session.
enum AiProcessingStatus {
  pending('pending'),
  processing('processing'),
  completed('completed'),
  failed('failed');

  const AiProcessingStatus(this.value);
  final String value;

  static AiProcessingStatus fromString(String raw) {
    return AiProcessingStatus.values.firstWhere(
      (status) => status.value == raw,
      orElse: () => AiProcessingStatus.pending,
    );
  }
}

/// Represents a single lecture recording or imported audio session.
class LectureSession {
  const LectureSession({
    this.id,
    required this.courseId,
    required this.title,
    required this.recordedAt,
    this.durationMs = 0,
    required this.audioPath,
    this.isImported = false,
    this.aiStatus = 'pending',
    this.aiErrorMessage,
    this.summaryTldr,
    this.summaryPointsJson,
    this.whiteboardSynthesis,
    this.glossaryJson,
    this.actionItemsJson,
  });

  final int? id;
  final int courseId;
  final String title;
  final DateTime recordedAt;
  final int durationMs;
  final String audioPath;
  final bool isImported;
  final String aiStatus;
  final String? aiErrorMessage;
  final String? summaryTldr;
  final String? summaryPointsJson;
  final String? whiteboardSynthesis;
  final String? glossaryJson;
  final String? actionItemsJson;

  AiProcessingStatus get statusEnum => AiProcessingStatus.fromString(aiStatus);

  /// Creates a [LectureSession] from a SQLite row map.
  factory LectureSession.fromMap(Map<String, Object?> map) {
    return LectureSession(
      id: map['id'] as int?,
      courseId: map['course_id'] as int,
      title: map['title'] as String,
      recordedAt: DateTime.parse(map['recorded_at'] as String),
      durationMs: (map['duration_ms'] as int?) ?? 0,
      audioPath: map['audio_path'] as String,
      isImported: (map['is_imported'] as int? ?? 0) == 1,
      aiStatus: (map['ai_status'] as String?) ?? 'pending',
      aiErrorMessage: map['ai_error_message'] as String?,
      summaryTldr: map['summary_tldr'] as String?,
      summaryPointsJson: map['summary_points_json'] as String?,
      whiteboardSynthesis: map['whiteboard_synthesis'] as String?,
      glossaryJson: map['glossary_json'] as String?,
      actionItemsJson: map['action_items_json'] as String?,
    );
  }

  /// Converts this [LectureSession] to a SQLite-compatible map.
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'course_id': courseId,
      'title': title,
      'recorded_at': recordedAt.toIso8601String(),
      'duration_ms': durationMs,
      'audio_path': audioPath,
      'is_imported': isImported ? 1 : 0,
      'ai_status': aiStatus,
      'ai_error_message': aiErrorMessage,
      'summary_tldr': summaryTldr,
      'summary_points_json': summaryPointsJson,
      'whiteboard_synthesis': whiteboardSynthesis,
      'glossary_json': glossaryJson,
      'action_items_json': actionItemsJson,
    };
  }

  /// Returns a copy with overridden fields.
  LectureSession copyWith({
    int? id,
    int? courseId,
    String? title,
    DateTime? recordedAt,
    int? durationMs,
    String? audioPath,
    bool? isImported,
    String? aiStatus,
    String? aiErrorMessage,
    String? summaryTldr,
    String? summaryPointsJson,
    String? whiteboardSynthesis,
    String? glossaryJson,
    String? actionItemsJson,
  }) {
    return LectureSession(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      title: title ?? this.title,
      recordedAt: recordedAt ?? this.recordedAt,
      durationMs: durationMs ?? this.durationMs,
      audioPath: audioPath ?? this.audioPath,
      isImported: isImported ?? this.isImported,
      aiStatus: aiStatus ?? this.aiStatus,
      aiErrorMessage: aiErrorMessage ?? this.aiErrorMessage,
      summaryTldr: summaryTldr ?? this.summaryTldr,
      summaryPointsJson: summaryPointsJson ?? this.summaryPointsJson,
      whiteboardSynthesis: whiteboardSynthesis ?? this.whiteboardSynthesis,
      glossaryJson: glossaryJson ?? this.glossaryJson,
      actionItemsJson: actionItemsJson ?? this.actionItemsJson,
    );
  }
}
