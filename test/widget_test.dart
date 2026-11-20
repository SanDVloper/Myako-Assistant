import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myako/core/security/secure_key_storage.dart';
import 'package:myako/data/app_database.dart';
import 'package:myako/data/course_repository.dart';
import 'package:myako/main.dart';
import 'package:myako/models/transcript_segment.dart';
import 'package:myako/providers/app_providers.dart';
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
