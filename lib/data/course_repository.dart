import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/course.dart';
import '../models/semester.dart';
import 'app_database.dart';

/// Repository managing [Semester] and [Course] records and local storage stats.
class CourseRepository {
  CourseRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<Database> get _db => _appDatabase.database;

  // ---------------------------------------------------------------------------
  // Semester CRUD
  // ---------------------------------------------------------------------------

  /// Returns all semesters ordered with the active semester first.
  Future<List<Semester>> getSemesters() async {
    final db = await _db;
    final rows = await db.query(
      'semesters',
      orderBy: 'is_active DESC, id DESC',
    );
    return rows.map(Semester.fromMap).toList(growable: false);
  }

  /// Returns the currently active semester, or the latest one if none is marked.
  Future<Semester?> getActiveSemester() async {
    final db = await _db;
    final rows = await db.query(
      'semesters',
      orderBy: 'is_active DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Semester.fromMap(rows.first);
  }

  /// Creates a new semester and optionally marks it active.
  Future<Semester> createSemester(String name, {bool makeActive = true}) async {
    final db = await _db;
    final now = DateTime.now();
    return db.transaction((txn) async {
      if (makeActive) {
        await txn.update('semesters', {'is_active': 0});
      }
      final id = await txn.insert('semesters', {
        'name': name.trim(),
        'is_active': makeActive ? 1 : 0,
        'created_at': now.toIso8601String(),
      });
      return Semester(
        id: id,
        name: name.trim(),
        isActive: makeActive,
        createdAt: now,
      );
    });
  }

  /// Updates an existing semester's name.
  Future<void> updateSemester(Semester semester) async {
    if (semester.id == null) return;
    final db = await _db;
    await db.update(
      'semesters',
      {'name': semester.name.trim()},
      where: 'id = ?',
      whereArgs: [semester.id],
    );
  }

  /// Marks [semesterId] as the sole active semester.
  Future<void> setActiveSemester(int semesterId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('semesters', {'is_active': 0});
      await txn.update(
        'semesters',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [semesterId],
      );
    });
  }

  /// Deletes a semester along with its courses and orphaned media files.
  Future<void> deleteSemester(int semesterId) async {
    final db = await _db;
    final mediaPaths = await _collectMediaPathsForSemester(db, semesterId);
    await db.delete('semesters', where: 'id = ?', whereArgs: [semesterId]);
    await _deleteLocalFiles(mediaPaths);

    // Ensure one remaining semester becomes active if any exist.
    final remaining = await db.query('semesters', orderBy: 'id DESC', limit: 1);
    if (remaining.isNotEmpty && (remaining.first['is_active'] as int?) != 1) {
      await db.update(
        'semesters',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [remaining.first['id']],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Course CRUD
  // ---------------------------------------------------------------------------

  /// Returns all courses in [semesterId] with aggregated study/session counts.
  Future<List<Course>> getCoursesBySemester(int semesterId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        c.*,
        (SELECT COUNT(*) FROM lecture_sessions ls WHERE ls.course_id = c.id) AS session_count,
        (SELECT COUNT(*) FROM lecture_sessions ls WHERE ls.course_id = c.id AND ls.ai_status != 'completed') AS pending_session_count,
        (SELECT COUNT(*) FROM flashcards f
          INNER JOIN lecture_sessions ls ON ls.id = f.session_id
          WHERE ls.course_id = c.id) AS flashcard_count,
        (SELECT COUNT(*) FROM quiz_questions q
          INNER JOIN lecture_sessions ls ON ls.id = q.session_id
          WHERE ls.course_id = c.id) AS quiz_count
      FROM courses c
      WHERE c.semester_id = ?
      ORDER BY c.id DESC
    ''', [semesterId]);
    return rows.map(Course.fromMap).toList(growable: false);
  }

  /// Inserts a new [Course] and returns it with its assigned database ID.
  Future<Course> createCourse({
    required int semesterId,
    required String name,
    String? lecturerName,
    required String colorHex,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    final trimmedLecturer = lecturerName?.trim();
    final course = Course(
      semesterId: semesterId,
      name: name.trim(),
      lecturerName:
          (trimmedLecturer == null || trimmedLecturer.isEmpty) ? null : trimmedLecturer,
      colorHex: colorHex,
      createdAt: now,
    );
    final id = await db.insert('courses', course.toMap());
    return course.copyWith(id: id);
  }

  /// Updates mutable attributes of an existing [Course].
  Future<void> updateCourse(Course course) async {
    if (course.id == null) return;
    final db = await _db;
    final trimmedLecturer = course.lecturerName?.trim();
    await db.update(
      'courses',
      {
        'name': course.name.trim(),
        'lecturer_name':
            (trimmedLecturer == null || trimmedLecturer.isEmpty) ? null : trimmedLecturer,
        'color_hex': course.colorHex,
      },
      where: 'id = ?',
      whereArgs: [course.id],
    );
  }

  /// Deletes a course and cleans up any associated audio/image files on disk.
  Future<void> deleteCourse(int courseId) async {
    final db = await _db;
    final mediaPaths = await _collectMediaPathsForCourse(db, courseId);
    await db.delete('courses', where: 'id = ?', whereArgs: [courseId]);
    await _deleteLocalFiles(mediaPaths);
  }

  // ---------------------------------------------------------------------------
  // Private App Storage Inspection & Cleanup
  // ---------------------------------------------------------------------------

  /// Calculates total bytes used by the local SQLite database and private media folders.
  Future<int> calculateLocalStorageUsageBytes() async {
    var totalBytes = 0;

    try {
      final dbPath = p.join(
        await getDatabasesPath(),
        AppDatabase.databaseFileName,
      );
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        totalBytes += await dbFile.length();
      }
    } catch (_) {
      // Ignore if running in an environment without path_provider/sqflite disk DB.
    }

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      for (final folderName in const ['recordings', 'whiteboards']) {
        final dir = Directory(p.join(docsDir.path, folderName));
        if (await dir.exists()) {
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              totalBytes += await entity.length();
            }
          }
        }
      }
    } catch (_) {
      // Ignore storage inspection failure on unsupported platforms.
    }

    return totalBytes;
  }

  Future<List<String>> _collectMediaPathsForSemester(
    Database db,
    int semesterId,
  ) async {
    final rows = await db.rawQuery('''
      SELECT ls.audio_path AS file_path
      FROM lecture_sessions ls
      INNER JOIN courses c ON c.id = ls.course_id
      WHERE c.semester_id = ? AND ls.audio_path != ''
      UNION ALL
      SELECT sa.image_path AS file_path
      FROM session_annotations sa
      INNER JOIN lecture_sessions ls ON ls.id = sa.session_id
      INNER JOIN courses c ON c.id = ls.course_id
      WHERE c.semester_id = ? AND sa.image_path IS NOT NULL AND sa.image_path != ''
    ''', [semesterId, semesterId]);

    return rows
        .map((row) => row['file_path'] as String?)
        .whereType<String>()
        .toList(growable: false);
  }

  Future<List<String>> _collectMediaPathsForCourse(
    Database db,
    int courseId,
  ) async {
    final rows = await db.rawQuery('''
      SELECT audio_path AS file_path
      FROM lecture_sessions
      WHERE course_id = ? AND audio_path != ''
      UNION ALL
      SELECT sa.image_path AS file_path
      FROM session_annotations sa
      INNER JOIN lecture_sessions ls ON ls.id = sa.session_id
      WHERE ls.course_id = ? AND sa.image_path IS NOT NULL AND sa.image_path != ''
    ''', [courseId, courseId]);

    return rows
        .map((row) => row['file_path'] as String?)
        .whereType<String>()
        .toList(growable: false);
  }

  Future<void> _deleteLocalFiles(List<String> paths) async {
    for (final path in paths) {
      if (path.isEmpty) continue;
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Best-effort file cleanup; DB row is already deleted.
      }
    }
  }
}
