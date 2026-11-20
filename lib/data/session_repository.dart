import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../models/lecture_session.dart';
import '../models/session_annotation.dart';
import 'app_database.dart';

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
