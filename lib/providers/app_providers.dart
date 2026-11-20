import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/secure_key_storage.dart';
import '../data/app_database.dart';
import '../data/course_repository.dart';
import '../models/course.dart';
import '../models/semester.dart';

/// Singleton database provider.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

/// Repository provider for Semesters, Courses, and local storage stats.
final courseRepositoryProvider = Provider<CourseRepository>((ref) {
  return CourseRepository(ref.watch(appDatabaseProvider));
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
