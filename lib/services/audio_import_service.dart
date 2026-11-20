import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/session_repository.dart';
import '../models/lecture_session.dart';

/// Imports external lecture audio files (`.m4a`, `.mp3`, `.wav`, `.ogg`, `.aac`)
/// into the app-private sandbox without loading whole files into Redmi A2 RAM.
class AudioImportService {
  AudioImportService(this._sessionRepository);

  static const List<String> supportedExtensions = [
    'm4a',
    'mp3',
    'wav',
    'ogg',
    'aac',
  ];

  final SessionRepository _sessionRepository;

  /// Opens the Android file picker, copies the selected audio into app-private
  /// storage, probes duration safely, and creates a pending [LectureSession].
  ///
  /// Returns `null` if the user cancels file selection.
  Future<LectureSession?> pickAndImportAudio({
    required int courseId,
    String? customTitle,
  }) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Pilih Rekaman Audio Kuliah',
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );

    if (picked == null) return null;

    final sourcePath = picked.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw StateError('Lokasi file audio tidak dapat dibaca oleh sistem.');
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('File audio tidak ditemukan di penyimpanan.');
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(p.join(docsDir.path, 'recordings'));
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }

    final sanitizedName = _sanitizeFileName(picked.name);
    final targetPath = p.join(
      recordingsDir.path,
      'import_${DateTime.now().millisecondsSinceEpoch}_$sanitizedName',
    );

    // Copy directly on disk to avoid buffering large 1-2h files into RAM.
    await sourceFile.copy(targetPath);

    final durationMs = await _probeDurationMs(targetPath);
    final sessionTitle = _resolveTitle(customTitle, picked.name);

    return _sessionRepository.createSession(
      LectureSession(
        courseId: courseId,
        title: sessionTitle,
        recordedAt: DateTime.now(),
        durationMs: durationMs,
        audioPath: targetPath,
        isImported: true,
        aiStatus: 'pending',
      ),
    );
  }

  Future<int> _probeDurationMs(String audioPath) async {
    final player = AudioPlayer();
    try {
      final duration = await player
          .setFilePath(audioPath)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      return duration?.inMilliseconds ?? 0;
    } catch (_) {
      return 0;
    } finally {
      await player.dispose();
    }
  }

  String _sanitizeFileName(String rawName) {
    final base = p.basename(rawName).trim();
    final sanitized = base.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return sanitized.isEmpty ? 'audio.m4a' : sanitized;
  }

  String _resolveTitle(String? customTitle, String fileName) {
    final trimmed = customTitle?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    final withoutExt = p.basenameWithoutExtension(fileName).trim();
    final cleaned = withoutExt.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    return cleaned.isEmpty ? 'Audio Impor' : cleaned;
  }
}
