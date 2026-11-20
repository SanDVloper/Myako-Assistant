import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Singleton SQLite database manager storing Myako lecture notes inside the
/// app-private sandbox directory (`getDatabasesPath()`).
class AppDatabase {
  AppDatabase._internal([this._databasePathOverride]);

  static const String databaseFileName = 'myako_secure_notes.db';
  static const int databaseVersion = 1;

  static AppDatabase instance = AppDatabase._internal();

  /// Creates an isolated instance for unit tests (e.g., in-memory FFI DB).
  factory AppDatabase.forTesting({String? databasePath}) {
    return AppDatabase._internal(databasePath ?? inMemoryDatabasePath);
  }

  final String? _databasePathOverride;
  Database? _db;

  /// Returns an initialized SQLite [Database] instance.
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = _databasePathOverride ??
        p.join(await getDatabasesPath(), databaseFileName);

    return openDatabase(
      path,
      version: databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE semesters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE courses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        semester_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        lecturer_name TEXT,
        color_hex TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (semester_id) REFERENCES semesters (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE lecture_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        audio_path TEXT NOT NULL,
        is_imported INTEGER NOT NULL DEFAULT 0,
        ai_status TEXT NOT NULL DEFAULT 'pending',
        ai_error_message TEXT,
        summary_tldr TEXT,
        summary_points_json TEXT,
        whiteboard_synthesis TEXT,
        glossary_json TEXT,
        action_items_json TEXT,
        FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE session_annotations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        timestamp_ms INTEGER NOT NULL,
        content_text TEXT,
        image_path TEXT,
        ai_vision_notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES lecture_sessions (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE transcript_segments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL,
        text_content TEXT NOT NULL,
        embedding BLOB,
        FOREIGN KEY (session_id) REFERENCES lecture_sessions (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE flashcards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        front_question TEXT NOT NULL,
        back_answer TEXT NOT NULL,
        mastery_level INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES lecture_sessions (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE quiz_questions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        question TEXT NOT NULL,
        options_json TEXT NOT NULL,
        correct_index INTEGER NOT NULL,
        explanation TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES lecture_sessions (id) ON DELETE CASCADE
      )
    ''');

    // Performance indexes for low-RAM Redmi A2 queries.
    await db.execute(
      'CREATE INDEX idx_courses_semester ON courses(semester_id)',
    );
    await db.execute(
      'CREATE INDEX idx_sessions_course ON lecture_sessions(course_id)',
    );
    await db.execute(
      'CREATE INDEX idx_annotations_session ON session_annotations(session_id, timestamp_ms)',
    );
    await db.execute(
      'CREATE INDEX idx_segments_session ON transcript_segments(session_id, start_ms)',
    );
    await db.execute(
      'CREATE INDEX idx_flashcards_session ON flashcards(session_id)',
    );
    await db.execute(
      'CREATE INDEX idx_quizzes_session ON quiz_questions(session_id)',
    );

    // Seed default active semester so user can create courses immediately.
    await db.insert('semesters', {
      'name': 'Semester Ganjil 2026/2027',
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Closes the open SQLite database connection if open.
  Future<void> close() async {
    final db = _db;
    if (db != null && db.isOpen) {
      await db.close();
      _db = null;
    }
  }
}
