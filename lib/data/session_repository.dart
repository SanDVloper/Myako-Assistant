import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../models/flashcard.dart';
import '../models/lecture_session.dart';
import '../models/quiz_question.dart';
import '../models/session_annotation.dart';
import '../models/transcript_segment.dart';
import '../services/ai_response_parser.dart';
import 'app_database.dart';

/// Joined transcript segment with parent session and course metadata for search.
class SearchableSegmentRecord {
  const SearchableSegmentRecord({
    required this.segment,
    required this.session,
    required this.courseName,
    required this.courseColorHex,
  });

  final TranscriptSegment segment;
  final LectureSession session;
  final String courseName;
  final String courseColorHex;
}

/// Repository managing [LectureSession] and timestamped [SessionAnnotation] records.
class SessionRepository {
  SessionRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<Database> get _db => _appDatabase.database;

  // ---------------------------------------------------------------------------
  // Lecture Session CRUD
  // ---------------------------------------------------------------------------

  /// Inserts a new [LectureSession] and returns it with its assigned ID.
  Future<LectureSession> createSession(LectureSession session) async {
    final db = await _db;
    final id = await db.insert('lecture_sessions', session.toMap());
    return session.copyWith(id: id);
  }

  /// Returns all sessions for [courseId], newest first.
  Future<List<LectureSession>> getSessionsByCourse(int courseId) async {
    final db = await _db;
    final rows = await db.query(
      'lecture_sessions',
      where: 'course_id = ?',
      whereArgs: [courseId],
      orderBy: 'id DESC',
    );
    return rows.map(LectureSession.fromMap).toList(growable: false);
  }

  /// Fetches a single [LectureSession] by [sessionId], or null if missing.
  Future<LectureSession?> getSessionById(int sessionId) async {
    final db = await _db;
    final rows = await db.query(
      'lecture_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LectureSession.fromMap(rows.first);
  }

  /// Updates recording metadata once classroom recording completes.
  Future<void> updateSessionAfterRecording({
    required int sessionId,
    required int durationMs,
    required String audioPath,
    String? title,
  }) async {
    final db = await _db;
    final values = <String, Object?>{
      'duration_ms': durationMs,
      'audio_path': audioPath,
    };
    if (title != null && title.trim().isNotEmpty) {
      values['title'] = title.trim();
    }
    await db.update(
      'lecture_sessions',
      values,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Renames an existing lecture session.
  Future<void> updateSessionTitle(int sessionId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final db = await _db;
    await db.update(
      'lecture_sessions',
      {'title': trimmed},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Deletes a lecture session and cleans up its local audio & annotation photos.
  Future<void> deleteSession(int sessionId) async {
    final db = await _db;
    final sessionRows = await db.query(
      'lecture_sessions',
      columns: ['audio_path'],
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    final annotationRows = await db.query(
      'session_annotations',
      columns: ['image_path'],
      where: "session_id = ? AND image_path IS NOT NULL AND image_path != ''",
      whereArgs: [sessionId],
    );

    await db.delete(
      'lecture_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );

    if (sessionRows.isNotEmpty) {
      await _deleteFileIfExists(sessionRows.first['audio_path'] as String?);
    }
    for (final row in annotationRows) {
      await _deleteFileIfExists(row['image_path'] as String?);
    }
  }

  // ---------------------------------------------------------------------------
  // Timestamped Annotations (Quick Notes, Whiteboard Photos, Bookmarks)
  // ---------------------------------------------------------------------------

  /// Persists a timestamped [SessionAnnotation] and returns it with its ID.
  Future<SessionAnnotation> addAnnotation(SessionAnnotation annotation) async {
    final db = await _db;
    final id = await db.insert('session_annotations', annotation.toMap());
    return annotation.copyWith(id: id);
  }

  /// Lists all annotations for [sessionId] sorted chronologically by timestamp.
  Future<List<SessionAnnotation>> getAnnotationsBySession(int sessionId) async {
    final db = await _db;
    final rows = await db.query(
      'session_annotations',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp_ms ASC, id ASC',
    );
    return rows.map(SessionAnnotation.fromMap).toList(growable: false);
  }

  /// Deletes an annotation row and its associated compressed photo file if any.
  Future<void> deleteAnnotation(int annotationId) async {
    final db = await _db;
    final rows = await db.query(
      'session_annotations',
      columns: ['image_path'],
      where: 'id = ?',
      whereArgs: [annotationId],
      limit: 1,
    );
    await db.delete(
      'session_annotations',
      where: 'id = ?',
      whereArgs: [annotationId],
    );
    if (rows.isNotEmpty) {
      await _deleteFileIfExists(rows.first['image_path'] as String?);
    }
  }

  // ---------------------------------------------------------------------------
  // AI Multimodal Results (Transcript, Summary, Flashcards, Quizzes)
  // ---------------------------------------------------------------------------

  /// Updates the AI lifecycle state (`pending` | `processing` | `completed` | `failed`).
  Future<void> updateSessionAiStatus({
    required int sessionId,
    required String status,
    String? errorMessage,
  }) async {
    final db = await _db;
    await db.update(
      'lecture_sessions',
      {
        'ai_status': status,
        'ai_error_message': errorMessage,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Atomically stores parsed AI summary, segments, flashcards, and quizzes.
  Future<void> saveAiProcessingResult({
    required int sessionId,
    required ParsedLectureAiResult result,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        'lecture_sessions',
        {
          'ai_status': 'completed',
          'ai_error_message': null,
          'summary_tldr': result.summaryTldr,
          'summary_points_json': jsonEncode(result.summaryPoints),
          'whiteboard_synthesis': result.whiteboardSynthesis,
          'glossary_json': jsonEncode(
            result.glossary.map((g) => g.toMap()).toList(growable: false),
          ),
          'action_items_json': jsonEncode(result.actionItems),
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      await txn.delete(
        'transcript_segments',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      await txn.delete(
        'flashcards',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      await txn.delete(
        'quiz_questions',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );

      final batch = txn.batch();
      for (final seg in result.segments) {
        batch.insert('transcript_segments', seg.copyWith(sessionId: sessionId).toMap());
      }
      for (final card in result.flashcards) {
        batch.insert('flashcards', card.copyWith(sessionId: sessionId).toMap());
      }
      for (final quiz in result.quizzes) {
        batch.insert('quiz_questions', quiz.copyWith(sessionId: sessionId).toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  /// Returns transcript segments for [sessionId] ordered chronologically.
  Future<List<TranscriptSegment>> getTranscriptSegmentsBySession(
    int sessionId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'transcript_segments',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'start_ms ASC, id ASC',
    );
    return rows.map(TranscriptSegment.fromMap).toList(growable: false);
  }

  /// Returns flashcards belonging to [sessionId].
  Future<List<Flashcard>> getFlashcardsBySession(int sessionId) async {
    final db = await _db;
    final rows = await db.query(
      'flashcards',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
    return rows.map(Flashcard.fromMap).toList(growable: false);
  }

  /// Returns combined flashcards across multiple [sessionIds] for UTS/UAS prep.
  Future<List<Flashcard>> getFlashcardsBySessionIds(List<int> sessionIds) async {
    if (sessionIds.isEmpty) return const [];
    final db = await _db;
    final placeholders = List.filled(sessionIds.length, '?').join(', ');
    final rows = await db.query(
      'flashcards',
      where: 'session_id IN ($placeholders)',
      whereArgs: sessionIds,
      orderBy: 'id ASC',
    );
    return rows.map(Flashcard.fromMap).toList(growable: false);
  }

  /// Updates mastery level (`0`: baru, `1`: perlu ulang, `2`: sudah paham).
  Future<void> updateFlashcardMastery({
    required int flashcardId,
    required int masteryLevel,
  }) async {
    final db = await _db;
    await db.update(
      'flashcards',
      {'mastery_level': masteryLevel},
      where: 'id = ?',
      whereArgs: [flashcardId],
    );
  }

  /// Returns multiple-choice quiz questions belonging to [sessionId].
  Future<List<QuizQuestion>> getQuizQuestionsBySession(int sessionId) async {
    final db = await _db;
    final rows = await db.query(
      'quiz_questions',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
    return rows.map(QuizQuestion.fromMap).toList(growable: false);
  }

  /// Returns combined quiz questions across multiple [sessionIds] for UTS/UAS prep.
  Future<List<QuizQuestion>> getQuizQuestionsBySessionIds(
    List<int> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return const [];
    final db = await _db;
    final placeholders = List.filled(sessionIds.length, '?').join(', ');
    final rows = await db.query(
      'quiz_questions',
      where: 'session_id IN ($placeholders)',
      whereArgs: sessionIds,
      orderBy: 'id ASC',
    );
    return rows.map(QuizQuestion.fromMap).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Semantic Embedding Storage & Search Queries
  // ---------------------------------------------------------------------------

  /// Persists compact Float32 embedding BLOBs for processed transcript segments.
  Future<void> updateSegmentEmbeddings(
    Map<int, Float32List> embeddingsBySegmentId,
  ) async {
    if (embeddingsBySegmentId.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final entry in embeddingsBySegmentId.entries) {
      final blob = TranscriptSegment.embeddingToBlob(entry.value);
      if (blob == null) continue;
      batch.update(
        'transcript_segments',
        {'embedding': blob},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Fetches all searchable transcript segments joined with session & course info.
  Future<List<SearchableSegmentRecord>> getSearchableSegments({
    int? courseId,
  }) async {
    final db = await _db;
    final whereClause = courseId != null ? 'WHERE ls.course_id = ?' : '';
    final args = courseId != null ? <Object?>[courseId] : const <Object?>[];

    final rows = await db.rawQuery('''
      SELECT
        ls.*,
        c.name AS course_name,
        c.color_hex AS course_color_hex,
        ts.id AS seg_id,
        ts.session_id AS seg_session_id,
        ts.start_ms AS seg_start_ms,
        ts.end_ms AS seg_end_ms,
        ts.text_content AS seg_text_content,
        ts.embedding AS seg_embedding
      FROM transcript_segments ts
      INNER JOIN lecture_sessions ls ON ls.id = ts.session_id
      INNER JOIN courses c ON c.id = ls.course_id
      $whereClause
      ORDER BY ls.id DESC, ts.start_ms ASC
    ''', args);

    return rows.map((row) {
      final session = LectureSession.fromMap(row);
      final segment = TranscriptSegment(
        id: row['seg_id'] as int?,
        sessionId: row['seg_session_id'] as int,
        startMs: row['seg_start_ms'] as int,
        endMs: row['seg_end_ms'] as int,
        textContent: row['seg_text_content'] as String,
        embedding:
            TranscriptSegment.blobToEmbedding(row['seg_embedding'] as Uint8List?),
      );
      return SearchableSegmentRecord(
        segment: segment,
        session: session,
        courseName: row['course_name'] as String,
        courseColorHex: row['course_color_hex'] as String,
      );
    }).toList(growable: false);
  }

  Future<void> _deleteFileIfExists(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort local cleanup after DB deletion.
    }
  }
}
