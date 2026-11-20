import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/secure_key_storage.dart';
import '../data/app_database.dart';
import '../data/course_repository.dart';
import '../data/session_repository.dart';
import '../models/course.dart';
import '../models/flashcard.dart';
import '../models/lecture_session.dart';
import '../models/quiz_question.dart';
import '../models/semester.dart';
import '../models/session_annotation.dart';
import '../models/transcript_segment.dart';
import '../services/ai_lecture_processor_service.dart';
import '../services/audio_import_service.dart';
import '../services/semantic_embedding_service.dart';
import '../services/semantic_search_service.dart';
import '../services/whiteboard_capture_service.dart';

/// Singleton database provider.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

/// Repository provider for Semesters, Courses, and local storage stats.
final courseRepositoryProvider = Provider<CourseRepository>((ref) {
  return CourseRepository(ref.watch(appDatabaseProvider));
});

/// Repository provider for Lecture Sessions and Timestamped Annotations.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(ref.watch(appDatabaseProvider));
});

/// Service provider for importing external lecture audio files.
final audioImportServiceProvider = Provider<AudioImportService>((ref) {
  return AudioImportService(ref.watch(sessionRepositoryProvider));
});

/// Service provider for compressed whiteboard captures and quick notes.
final whiteboardCaptureServiceProvider =
    Provider<WhiteboardCaptureService>((ref) {
  return WhiteboardCaptureService(ref.watch(sessionRepositoryProvider));
});

/// Encrypted key storage provider backed by Android Keystore.
final secureKeyStorageProvider = Provider<SecureKeyStorage>((ref) {
  return SecureKeyStorage();
});

// -----------------------------------------------------------------------------
// Theme Mode State (Dark Mode Default)
// -----------------------------------------------------------------------------

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadSavedTheme();
    return ThemeMode.dark;
  }

  Future<void> _loadSavedTheme() async {
    try {
      final saved =
          await ref.read(secureKeyStorageProvider).getSavedThemeMode();
      if (saved == 'light') {
        state = ThemeMode.light;
      } else if (saved == 'dark') {
        state = ThemeMode.dark;
      }
    } catch (_) {
      // Keep default ThemeMode.dark if secure storage is unavailable (e.g. unit tests).
    }
  }

  Future<void> setDarkMode(bool isDark) async {
    final target = isDark ? ThemeMode.dark : ThemeMode.light;
    state = target;
    try {
      await ref
          .read(secureKeyStorageProvider)
          .saveThemeMode(isDark ? 'dark' : 'light');
    } catch (_) {
      // Ignore persistence error when running outside device platform channel.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

// -----------------------------------------------------------------------------
// API Key Configuration State (Never exposes raw keys unnecessarily in UI state)
// -----------------------------------------------------------------------------

class ApiKeyConfigState {
  const ApiKeyConfigState({
    this.hasGeminiKey = false,
    this.hasGroqKey = false,
    this.maskedGeminiKey = '',
    this.maskedGroqKey = '',
    this.preferredEngine = 'gemini',
  });

  final bool hasGeminiKey;
  final bool hasGroqKey;
  final String maskedGeminiKey;
  final String maskedGroqKey;
  final String preferredEngine;

  bool get hasAnyKey => hasGeminiKey || hasGroqKey;
}

class ApiKeyConfigNotifier extends AsyncNotifier<ApiKeyConfigState> {
  @override
  Future<ApiKeyConfigState> build() => _loadState();

  Future<ApiKeyConfigState> _loadState() async {
    final storage = ref.read(secureKeyStorageProvider);
    final gemini = await storage.getGeminiApiKey();
    final groq = await storage.getGroqApiKey();
    final engine = await storage.getPreferredEngine();

    final hasGemini = gemini != null && gemini.trim().isNotEmpty;
    final hasGroq = groq != null && groq.trim().isNotEmpty;

    return ApiKeyConfigState(
      hasGeminiKey: hasGemini,
      hasGroqKey: hasGroq,
      maskedGeminiKey: SecureKeyStorage.maskApiKey(gemini),
      maskedGroqKey: SecureKeyStorage.maskApiKey(groq),
      preferredEngine: engine,
    );
  }

  Future<void> saveGeminiKey(String key) async {
    await ref.read(secureKeyStorageProvider).saveGeminiApiKey(key);
    state = AsyncData(await _loadState());
  }

  Future<void> deleteGeminiKey() async {
    await ref.read(secureKeyStorageProvider).deleteGeminiApiKey();
    state = AsyncData(await _loadState());
  }

  Future<void> saveGroqKey(String key) async {
    await ref.read(secureKeyStorageProvider).saveGroqApiKey(key);
    state = AsyncData(await _loadState());
  }

  Future<void> deleteGroqKey() async {
    await ref.read(secureKeyStorageProvider).deleteGroqApiKey();
    state = AsyncData(await _loadState());
  }

  Future<void> setPreferredEngine(String engine) async {
    await ref.read(secureKeyStorageProvider).savePreferredEngine(engine);
    state = AsyncData(await _loadState());
  }
}

final apiKeyConfigProvider =
    AsyncNotifierProvider<ApiKeyConfigNotifier, ApiKeyConfigState>(
  ApiKeyConfigNotifier.new,
);

// -----------------------------------------------------------------------------
// Semesters & Courses State
// -----------------------------------------------------------------------------

class SemestersNotifier extends AsyncNotifier<List<Semester>> {
  @override
  Future<List<Semester>> build() {
    return ref.read(courseRepositoryProvider).getSemesters();
  }

  Future<void> createSemester(String name) async {
    await ref.read(courseRepositoryProvider).createSemester(name);
    ref.invalidateSelf();
    ref.invalidate(coursesProvider);
  }

  Future<void> renameSemester(Semester semester, String newName) async {
    await ref
        .read(courseRepositoryProvider)
        .updateSemester(semester.copyWith(name: newName));
    ref.invalidateSelf();
  }

  Future<void> selectSemester(int semesterId) async {
    await ref.read(courseRepositoryProvider).setActiveSemester(semesterId);
    ref.invalidateSelf();
    ref.invalidate(coursesProvider);
  }

  Future<void> deleteSemester(int semesterId) async {
    await ref.read(courseRepositoryProvider).deleteSemester(semesterId);
    ref.invalidateSelf();
    ref.invalidate(coursesProvider);
    ref.invalidate(storageUsageBytesProvider);
  }
}

final semestersProvider =
    AsyncNotifierProvider<SemestersNotifier, List<Semester>>(
  SemestersNotifier.new,
);

/// Currently active semester derived from [semestersProvider].
final activeSemesterProvider = Provider<Semester?>((ref) {
  final semesters = ref.watch(semestersProvider).value ?? const [];
  if (semesters.isEmpty) return null;
  for (final s in semesters) {
    if (s.isActive) return s;
  }
  return semesters.first;
});

class CoursesNotifier extends AsyncNotifier<List<Course>> {
  @override
  Future<List<Course>> build() async {
    final semesters = await ref.watch(semestersProvider.future);
    if (semesters.isEmpty) return const [];
    final active = semesters.firstWhere(
      (s) => s.isActive,
      orElse: () => semesters.first,
    );
    if (active.id == null) return const [];
    return ref.read(courseRepositoryProvider).getCoursesBySemester(active.id!);
  }

  Future<void> createCourse({
    required int semesterId,
    required String name,
    String? lecturerName,
    required String colorHex,
  }) async {
    await ref.read(courseRepositoryProvider).createCourse(
          semesterId: semesterId,
          name: name,
          lecturerName: lecturerName,
          colorHex: colorHex,
        );
    ref.invalidateSelf();
  }

  Future<void> updateCourse(Course course) async {
    await ref.read(courseRepositoryProvider).updateCourse(course);
    ref.invalidateSelf();
  }

  Future<void> deleteCourse(int courseId) async {
    await ref.read(courseRepositoryProvider).deleteCourse(courseId);
    ref.invalidateSelf();
    ref.invalidate(storageUsageBytesProvider);
  }
}

final coursesProvider = AsyncNotifierProvider<CoursesNotifier, List<Course>>(
  CoursesNotifier.new,
);

/// Total private app storage used by SQLite DB, audio files, and photos.
final storageUsageBytesProvider = FutureProvider<int>((ref) {
  return ref.read(courseRepositoryProvider).calculateLocalStorageUsageBytes();
});

/// Lecture sessions belonging to a specific course ID.
final courseSessionsProvider =
    FutureProvider.family<List<LectureSession>, int>((ref, courseId) {
  return ref.read(sessionRepositoryProvider).getSessionsByCourse(courseId);
});

/// Timestamped annotations belonging to a specific session ID.
final sessionAnnotationsProvider =
    FutureProvider.family<List<SessionAnnotation>, int>((ref, sessionId) {
  return ref.read(sessionRepositoryProvider).getAnnotationsBySession(sessionId);
});

/// Multimodal AI processor service (Gemini 2.5 Flash / Groq).
final aiLectureProcessorServiceProvider =
    Provider<AiLectureProcessorService>((ref) {
  return AiLectureProcessorService(ref.watch(secureKeyStorageProvider));
});

/// Single lecture session record by ID.
final sessionByIdProvider =
    FutureProvider.family<LectureSession?, int>((ref, sessionId) {
  return ref.read(sessionRepositoryProvider).getSessionById(sessionId);
});

/// Transcript segments belonging to a specific session ID.
final sessionTranscriptProvider =
    FutureProvider.family<List<TranscriptSegment>, int>((ref, sessionId) {
  return ref
      .read(sessionRepositoryProvider)
      .getTranscriptSegmentsBySession(sessionId);
});

/// Study flashcards belonging to a specific session ID.
final sessionFlashcardsProvider =
    FutureProvider.family<List<Flashcard>, int>((ref, sessionId) {
  return ref.read(sessionRepositoryProvider).getFlashcardsBySession(sessionId);
});

/// Multiple-choice quiz questions belonging to a specific session ID.
final sessionQuizzesProvider =
    FutureProvider.family<List<QuizQuestion>, int>((ref, sessionId) {
  return ref
      .read(sessionRepositoryProvider)
      .getQuizQuestionsBySession(sessionId);
});

/// Service generating compact Float32 embeddings via `text-embedding-004`.
final semanticEmbeddingServiceProvider =
    Provider<SemanticEmbeddingService>((ref) {
  return SemanticEmbeddingService(ref.watch(secureKeyStorageProvider));
});

/// Local Cosine Similarity search service with offline keyword fallback.
final semanticSearchServiceProvider = Provider<SemanticSearchService>((ref) {
  return SemanticSearchService(
    ref.watch(sessionRepositoryProvider),
    ref.watch(semanticEmbeddingServiceProvider),
  );
});
