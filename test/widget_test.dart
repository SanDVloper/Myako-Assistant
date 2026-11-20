import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myako/core/security/secure_key_storage.dart';
import 'package:myako/data/app_database.dart';
import 'package:myako/data/course_repository.dart';
import 'package:myako/data/session_repository.dart';
import 'package:myako/main.dart';
import 'package:myako/models/flashcard.dart';
import 'package:myako/models/lecture_session.dart';
import 'package:myako/models/quiz_question.dart';
import 'package:myako/models/session_annotation.dart';
import 'package:myako/models/transcript_segment.dart';
import 'package:myako/providers/app_providers.dart';
import 'package:myako/screens/flashcard_study_screen.dart';
import 'package:myako/screens/quiz_runner_screen.dart';
import 'package:myako/services/ai_response_parser.dart';
import 'package:myako/services/lecture_recorder_service.dart';
import 'package:myako/services/semantic_embedding_service.dart';
import 'package:myako/services/semantic_search_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _InMemorySecureKeyStorage extends SecureKeyStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> getGeminiApiKey() async => _store['gemini'];

  @override
  Future<void> saveGeminiApiKey(String apiKey) async {
    _store['gemini'] = apiKey.trim();
  }

  @override
  Future<void> deleteGeminiApiKey() async {
    _store.remove('gemini');
  }

  @override
  Future<String?> getGroqApiKey() async => _store['groq'];

  @override
  Future<void> saveGroqApiKey(String apiKey) async {
    _store['groq'] = apiKey.trim();
  }

  @override
  Future<void> deleteGroqApiKey() async {
    _store.remove('groq');
  }

  @override
  Future<String> getPreferredEngine() async => _store['engine'] ?? 'gemini';

  @override
  Future<void> savePreferredEngine(String engine) async {
    _store['engine'] = engine;
  }

  @override
  Future<String?> getSavedThemeMode() async => _store['theme'];

  @override
  Future<void> saveThemeMode(String mode) async {
    _store['theme'] = mode;
  }
}

class _FakeSemanticEmbeddingService extends SemanticEmbeddingService {
  _FakeSemanticEmbeddingService(super.keyStorage, {this.queryVector});

  final Float32List? queryVector;

  @override
  Future<Float32List?> embedQuery(String query) async => queryVector;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Data security & serialization unit tests', () {
    test('SecureKeyStorage.maskApiKey masks secrets safely', () {
      expect(SecureKeyStorage.maskApiKey(null), '');
      expect(SecureKeyStorage.maskApiKey('   '), '');
      expect(SecureKeyStorage.maskApiKey('short'), '••••••••');
      expect(
        SecureKeyStorage.maskApiKey('AIzaSyDummyKeyValue1234'),
        'AIza••••••1234',
      );
    });

    test('TranscriptSegment Float32 BLOB round-trip handles unaligned views', () {
      final original = Float32List.fromList([0.25, -0.5, 0.75, 1.0]);
      final blob = TranscriptSegment.embeddingToBlob(original);
      expect(blob, isNotNull);
      expect(blob!.lengthInBytes, 16);

      // Force a non-4-byte-aligned sublist view to ensure ARM alignment safety.
      final padded = Uint8List(blob.length + 1);
      padded.setRange(1, padded.length, blob);
      final unalignedView = Uint8List.sublistView(padded, 1);

      final restored = TranscriptSegment.blobToEmbedding(unalignedView);
      expect(restored, isNotNull);
      expect(restored!.length, 4);
      for (var i = 0; i < original.length; i++) {
        expect(restored[i], closeTo(original[i], 1e-6));
      }
    });
  });

  group('SQLite schema & CourseRepository tests', () {
    late AppDatabase testDb;
    late CourseRepository repo;

    setUp(() async {
      testDb = AppDatabase.forTesting(databasePath: inMemoryDatabasePath);
      repo = CourseRepository(testDb);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('Database creates all 7 tables and seeds initial semester', () async {
      final db = await testDb.database;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );
      final tableNames = tables.map((r) => r['name'] as String).toSet();

      expect(tableNames, {
        'semesters',
        'courses',
        'lecture_sessions',
        'session_annotations',
        'transcript_segments',
        'flashcards',
        'quiz_questions',
      });

      final active = await repo.getActiveSemester();
      expect(active, isNotNull);
      expect(active!.name, 'Semester Ganjil 2026/2027');
    });

    test('Course CRUD and foreign key cascade delete work properly', () async {
      final active = await repo.getActiveSemester();
      final semesterId = active!.id!;

      final created = await repo.createCourse(
        semesterId: semesterId,
        name: 'Struktur Data',
        lecturerName: 'Pak Budi',
        colorHex: '#10B981',
      );
      expect(created.id, isNotNull);

      var courses = await repo.getCoursesBySemester(semesterId);
      expect(courses.length, 1);
      expect(courses.first.name, 'Struktur Data');
      expect(courses.first.lecturerName, 'Pak Budi');

      await repo.updateCourse(
        created.copyWith(name: 'Algoritma & Struktur Data'),
      );
      courses = await repo.getCoursesBySemester(semesterId);
      expect(courses.first.name, 'Algoritma & Struktur Data');

      await repo.deleteCourse(created.id!);
      courses = await repo.getCoursesBySemester(semesterId);
      expect(courses, isEmpty);
    });

    test('SessionRepository CRUD and chronological annotations work properly',
        () async {
      final sessionRepo = SessionRepository(testDb);
      final active = await repo.getActiveSemester();
      final course = await repo.createCourse(
        semesterId: active!.id!,
        name: 'Basis Data',
        colorHex: '#38BDF8',
      );

      final session = await sessionRepo.createSession(
        LectureSession(
          courseId: course.id!,
          title: 'Pertemuan 1',
          recordedAt: DateTime(2026, 11, 20, 9, 0),
          durationMs: 0,
          audioPath: '',
        ),
      );
      expect(session.id, isNotNull);

      await sessionRepo.updateSessionAfterRecording(
        sessionId: session.id!,
        durationMs: 185000,
        audioPath: 'recordings/test_lecture.m4a',
        title: 'Pertemuan 1 - ERD',
      );

      final updated = await sessionRepo.getSessionById(session.id!);
      expect(updated, isNotNull);
      expect(updated!.durationMs, 185000);
      expect(updated.title, 'Pertemuan 1 - ERD');

      // Add out-of-order annotations and verify chronological timestamp sort.
      await sessionRepo.addAnnotation(
        SessionAnnotation(
          sessionId: session.id!,
          type: AnnotationType.bookmark.value,
          timestampMs: 90000,
          contentText: 'Keluar di UTS',
          createdAt: DateTime(2026, 11, 20, 9, 1),
        ),
      );
      await sessionRepo.addAnnotation(
        SessionAnnotation(
          sessionId: session.id!,
          type: AnnotationType.textNote.value,
          timestampMs: 15000,
          contentText: 'Definisi Primary Key',
          createdAt: DateTime(2026, 11, 20, 9, 0),
        ),
      );
      await sessionRepo.addAnnotation(
        SessionAnnotation(
          sessionId: session.id!,
          type: AnnotationType.photo.value,
          timestampMs: 45000,
          imagePath: 'whiteboards/wb_sample.jpg',
          createdAt: DateTime(2026, 11, 20, 9, 0),
        ),
      );

      final annotations =
          await sessionRepo.getAnnotationsBySession(session.id!);
      expect(annotations.length, 3);
      expect(annotations[0].typeEnum, AnnotationType.textNote);
      expect(annotations[1].typeEnum, AnnotationType.photo);
      expect(annotations[2].typeEnum, AnnotationType.bookmark);

      await sessionRepo.deleteAnnotation(annotations[1].id!);
      final remaining = await sessionRepo.getAnnotationsBySession(session.id!);
      expect(remaining.length, 2);

      await sessionRepo.deleteSession(session.id!);
      final sessionsAfterDelete =
          await sessionRepo.getSessionsByCourse(course.id!);
      expect(sessionsAfterDelete, isEmpty);
    });

    test('LectureRecorderService.formatDurationMs formats MM:SS and HH:MM:SS',
        () {
      expect(LectureRecorderService.formatDurationMs(0), '00:00');
      expect(LectureRecorderService.formatDurationMs(65000), '01:05');
      expect(LectureRecorderService.formatDurationMs(3661000), '01:01:01');
    });

    test('AiResponseParser parses markdown-wrapped JSON and persists to SQLite',
        () async {
      final sessionRepo = SessionRepository(testDb);
      final active = await repo.getActiveSemester();
      final course = await repo.createCourse(
        semesterId: active!.id!,
        name: 'Sistem Operasi',
        colorHex: '#A78BFA',
      );
      final session = await sessionRepo.createSession(
        LectureSession(
          courseId: course.id!,
          title: 'Deadlock & Semaphore',
          recordedAt: DateTime(2026, 11, 20, 10, 0),
          durationMs: 120000,
          audioPath: 'recordings/os.m4a',
        ),
      );

      const rawAiResponse = '''
```json
{
  "summary_tldr": "Membahas empat syarat terjadinya deadlock dan pencegahannya memakai semaphore.",
  "summary_points": [
    "Mutual Exclusion dan Hold and Wait memicu deadlock.",
    "Banker algorithm mencegah unsafe state."
  ],
  "whiteboard_synthesis": "Diagram resource allocation graph pada papan tulis memperlihatkan siklus P1 -> R1 -> P2.",
  "glossary": [
    {"term": "Deadlock", "definition": "Kondisi saling tunggu permanen antar proses."}
  ],
  "action_items": [
    "Kumpulkan tugas sinkronisasi minggu depan."
  ],
  "transcript_segments": [
    {"start_ms": 0, "end_ms": 30000, "text": "Hari ini kita membahas deadlock pada sistem operasi."},
    {"start_ms": 30000, "end_ms": 60000, "text": "Empat kondisi Coffman harus terpenuhi bersamaan."}
  ],
  "flashcards": [
    {"front": "Apa fungsi Semaphore?", "back": "Mengontrol akses resource bersama oleh banyak thread."}
  ],
  "quiz_questions": [
    {
      "question": "Manakah syarat terjadinya deadlock?",
      "options": ["Circular Wait", "Round Robin", "Paging", "Caching"],
      "correct_index": 0,
      "explanation": "Circular Wait adalah salah satu dari 4 kondisi Coffman."
    }
  ]
}
```
''';

      final parsed =
          AiResponseParser.parse(rawAiResponse, sessionId: session.id!);
      expect(parsed.summaryPoints.length, 2);
      expect(parsed.glossary.single.term, 'Deadlock');
      expect(parsed.segments.length, 2);
      expect(parsed.flashcards.single.frontQuestion, 'Apa fungsi Semaphore?');
      expect(parsed.quizzes.single.correctIndex, 0);

      await sessionRepo.saveAiProcessingResult(
        sessionId: session.id!,
        result: parsed,
      );

      final updatedSession = await sessionRepo.getSessionById(session.id!);
      expect(updatedSession!.statusEnum, AiProcessingStatus.completed);
      expect(
        AiResponseParser.decodeGlossary(updatedSession.glossaryJson)
            .single
            .term,
        'Deadlock',
      );
      expect(
        (await sessionRepo.getTranscriptSegmentsBySession(session.id!)).length,
        2,
      );
      expect(
        (await sessionRepo.getFlashcardsBySession(session.id!)).length,
        1,
      );
      expect(
        (await sessionRepo.getQuizQuestionsBySession(session.id!)).length,
        1,
      );
    });

    test(
        'Multi-session UTS/UAS queries and flashcard mastery update work properly',
        () async {
      final sessionRepo = SessionRepository(testDb);
      final active = await repo.getActiveSemester();
      final course = await repo.createCourse(
        semesterId: active!.id!,
        name: 'Jaringan Komputer',
        colorHex: '#10B981',
      );
      final s1 = await sessionRepo.createSession(
        LectureSession(
          courseId: course.id!,
          title: 'Pertemuan 1',
          recordedAt: DateTime(2026, 11, 20),
          audioPath: 'recordings/j1.m4a',
        ),
      );
      final s2 = await sessionRepo.createSession(
        LectureSession(
          courseId: course.id!,
          title: 'Pertemuan 2',
          recordedAt: DateTime(2026, 11, 21),
          audioPath: 'recordings/j2.m4a',
        ),
      );

      await sessionRepo.saveAiProcessingResult(
        sessionId: s1.id!,
        result: ParsedLectureAiResult(
          summaryTldr: 'OSI',
          summaryPoints: const [],
          whiteboardSynthesis: '',
          glossary: const [],
          actionItems: const [],
          segments: const [],
          flashcards: [
            Flashcard(
              sessionId: s1.id!,
              frontQuestion: 'Layer 3 OSI?',
              backAnswer: 'Network Layer',
            ),
          ],
          quizzes: [
            QuizQuestion(
              sessionId: s1.id!,
              question: 'Protokol Layer 3?',
              options: const ['IP', 'TCP', 'HTTP', 'ARP'],
              correctIndex: 0,
              explanation: 'IP bekerja di Network Layer.',
            ),
          ],
        ),
      );
      await sessionRepo.saveAiProcessingResult(
        sessionId: s2.id!,
        result: ParsedLectureAiResult(
          summaryTldr: 'TCP',
          summaryPoints: const [],
          whiteboardSynthesis: '',
          glossary: const [],
          actionItems: const [],
          segments: const [],
          flashcards: [
            Flashcard(
              sessionId: s2.id!,
              frontQuestion: 'TCP handshake?',
              backAnswer: 'SYN, SYN-ACK, ACK',
            ),
          ],
          quizzes: [
            QuizQuestion(
              sessionId: s2.id!,
              question: 'Port HTTPS?',
              options: const ['80', '443', '22', '53'],
              correctIndex: 1,
              explanation: 'HTTPS berjalan di port 443.',
            ),
          ],
        ),
      );

      final combinedCards =
          await sessionRepo.getFlashcardsBySessionIds([s1.id!, s2.id!]);
      expect(combinedCards.length, 2);

      final combinedQuizzes =
          await sessionRepo.getQuizQuestionsBySessionIds([s1.id!, s2.id!]);
      expect(combinedQuizzes.length, 2);

      await sessionRepo.updateFlashcardMastery(
        flashcardId: combinedCards.first.id!,
        masteryLevel: 2,
      );
      final updatedCards = await sessionRepo.getFlashcardsBySession(s1.id!);
      expect(updatedCards.single.masteryLevel, 2);
    });

    test(
        'SemanticSearchService computes cosine similarity, ranks vectors, and falls back offline',
        () async {
      // Pure math checks.
      final v1 = Float32List.fromList([1.0, 0.0, 0.0]);
      final v2 = Float32List.fromList([1.0, 0.0, 0.0]);
      final vOrth = Float32List.fromList([0.0, 1.0, 0.0]);
      final vShort = Float32List.fromList([1.0, 0.0]);
      final vZero = Float32List.fromList([0.0, 0.0, 0.0]);

      expect(SemanticSearchService.cosineSimilarity(v1, v2), closeTo(1.0, 1e-6));
      expect(SemanticSearchService.cosineSimilarity(v1, vOrth), closeTo(0.0, 1e-6));
      expect(SemanticSearchService.cosineSimilarity(v1, vShort), 0.0);
      expect(SemanticSearchService.cosineSimilarity(v1, vZero), 0.0);

      final sessionRepo = SessionRepository(testDb);
      final active = await repo.getActiveSemester();
      final course = await repo.createCourse(
        semesterId: active!.id!,
        name: 'Biologi Sel',
        colorHex: '#10B981',
      );
      final session = await sessionRepo.createSession(
        LectureSession(
          courseId: course.id!,
          title: 'Pembelahan Sel',
          recordedAt: DateTime(2026, 11, 20, 8, 0),
          audioPath: 'recordings/bio.m4a',
        ),
      );

      await sessionRepo.saveAiProcessingResult(
        sessionId: session.id!,
        result: ParsedLectureAiResult(
          summaryTldr: 'Perbedaan mitosis dan meiosis pada sel eukariotik.',
          summaryPoints: const ['Mitosis menghasilkan 2 sel identik'],
          whiteboardSynthesis: '',
          glossary: const [],
          actionItems: const [],
          segments: [
            TranscriptSegment(
              sessionId: session.id!,
              startMs: 10000,
              endMs: 40000,
              textContent: 'Mitosis terjadi pada sel somatik untuk pertumbuhan.',
            ),
            TranscriptSegment(
              sessionId: session.id!,
              startMs: 40000,
              endMs: 70000,
              textContent: 'Fotosintesis membutuhkan klorofil dan cahaya matahari.',
            ),
          ],
          flashcards: const [],
          quizzes: const [],
        ),
      );

      final savedSegments =
          await sessionRepo.getTranscriptSegmentsBySession(session.id!);
      await sessionRepo.updateSegmentEmbeddings({
        savedSegments[0].id!: Float32List.fromList([0.95, 0.05, 0.0]),
        savedSegments[1].id!: Float32List.fromList([0.0, 1.0, 0.0]),
      });

      final searchable = await sessionRepo.getSearchableSegments();
      expect(searchable.length, 2);
      expect(searchable.first.courseName, 'Biologi Sel');

      // 1. Vector similarity ranking.
      final vectorSearch = SemanticSearchService(
        sessionRepo,
        _FakeSemanticEmbeddingService(
          _InMemorySecureKeyStorage(),
          queryVector: Float32List.fromList([1.0, 0.0, 0.0]),
        ),
      );
      final vectorRes = await vectorSearch.search(
        query: 'pembelahan sel tubuh',
      );
      expect(vectorRes.usedSemanticVectors, isTrue);
      expect(vectorRes.hits.length, 1);
      expect(vectorRes.hits.first.segment.startMs, 10000);

      // 2. Offline lexical fallback when embedding query returns null.
      final offlineSearch = SemanticSearchService(
        sessionRepo,
        _FakeSemanticEmbeddingService(
          _InMemorySecureKeyStorage(),
          queryVector: null,
        ),
      );
      final offlineRes = await offlineSearch.search(
        query: 'klorofil cahaya',
      );
      expect(offlineRes.usedSemanticVectors, isFalse);
      expect(offlineRes.hits.length, 1);
      expect(offlineRes.hits.first.segment.startMs, 40000);
    });
  });

  testWidgets('FlashcardStudyScreen flips card and QuizRunnerScreen grades answer',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: FlashcardStudyScreen(
            title: 'Latihan Kartu',
            initialCards: const [
              Flashcard(
                sessionId: 1,
                frontQuestion: 'Apa itu Polymorphism?',
                backAnswer: 'Kemampuan objek mengambil banyak bentuk.',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Apa itu Polymorphism?'), findsOneWidget);
    expect(find.text('Kemampuan objek mengambil banyak bentuk.'), findsNothing);

    await tester.tap(find.text('Apa itu Polymorphism?'));
    await tester.pumpAndSettle();

    expect(find.text('Kemampuan objek mengambil banyak bentuk.'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: QuizRunnerScreen(
          title: 'Kuis Uji',
          questions: [
            QuizQuestion(
              sessionId: 1,
              question: 'Kompleksitas binary search?',
              options: ['O(n)', 'O(log n)', 'O(n^2)', 'O(1)'],
              correctIndex: 1,
              explanation: 'Binary search membagi ruang pencarian menjadi dua tiap langkah.',
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('O(log n)'));
    await tester.pumpAndSettle();

    expect(find.text('Pembahasan'), findsOneWidget);
    expect(find.text('Benar: 1'), findsOneWidget);

    await tester.tap(find.text('Lihat Skor Akhir'));
    await tester.pumpAndSettle();

    expect(find.text('100'), findsOneWidget);
    expect(find.text('Sangat Siap Ujian'), findsOneWidget);
  });

  testWidgets('MyakoApp renders HomeScreen in Dark Mode by default',
      (tester) async {
    final testDb = AppDatabase.forTesting(databasePath: inMemoryDatabasePath);
    final fakeSecureStorage = _InMemorySecureKeyStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(testDb),
          secureKeyStorageProvider.overrideWithValue(fakeSecureStorage),
        ],
        child: const MyakoApp(),
      ),
    );

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();

    expect(find.text('Myako'), findsOneWidget);
    expect(find.text('Semester Ganjil 2026/2027'), findsOneWidget);
    expect(find.text('Tambah Mata Kuliah Pertama'), findsOneWidget);
    expect(find.text('Atur Key'), findsOneWidget);

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.dark);

    // Navigate to SettingsScreen and verify security overview appears.
    await tester.tap(find.byTooltip('Pengaturan & Keamanan'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();

    expect(find.text('Perlindungan Data Lokal & API Key'), findsOneWidget);
    expect(find.text('Google Gemini API Key (Utama)'), findsOneWidget);

    await tester.runAsync(() => testDb.close());
  });
}
