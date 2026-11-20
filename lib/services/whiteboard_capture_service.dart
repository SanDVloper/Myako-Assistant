import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/session_repository.dart';
import '../models/session_annotation.dart';

/// Handles timestamped text notes, bookmarks, and compressed whiteboard/slide
/// photos (< 250 KB, max 1280 px) bound to a lecture session's timeline.
class WhiteboardCaptureService {
  WhiteboardCaptureService(
    this._sessionRepository, {
    ImagePicker? imagePicker,
  }) : _imagePicker = imagePicker ?? ImagePicker();

  final SessionRepository _sessionRepository;
  final ImagePicker _imagePicker;

  /// Captures a whiteboard/slide photo from [source], compresses it for Redmi A2
  /// storage & Gemini Vision efficiency, deletes the temp file, and saves it.
  ///
  /// Returns `null` if the user cancels camera/gallery capture.
  Future<SessionAnnotation?> captureAndSavePhoto({
    required int sessionId,
    required int timestampMs,
    required ImageSource source,
    String? caption,
  }) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      requestFullMetadata: false,
    );
    if (picked == null) return null;

    final docsDir = await getApplicationDocumentsDirectory();
    final whiteboardsDir = Directory(p.join(docsDir.path, 'whiteboards'));
    if (!await whiteboardsDir.exists()) {
      await whiteboardsDir.create(recursive: true);
    }

    final targetPath = p.join(
      whiteboardsDir.path,
      'wb_${sessionId}_${timestampMs}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    final savedPath = await _compressPhoto(
      sourcePath: picked.path,
      targetPath: targetPath,
    );

    // Clean up temporary camera/gallery cache file to protect Redmi A2 storage.
    if (picked.path != savedPath) {
      try {
        final tempFile = File(picked.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }

    final trimmedCaption = caption?.trim();
    return _sessionRepository.addAnnotation(
      SessionAnnotation(
        sessionId: sessionId,
        type: AnnotationType.photo.value,
        timestampMs: timestampMs,
        contentText: (trimmedCaption == null || trimmedCaption.isEmpty)
            ? null
            : trimmedCaption,
        imagePath: savedPath,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Adds a timestamped text note to [sessionId].
  Future<SessionAnnotation> addQuickTextNote({
    required int sessionId,
    required int timestampMs,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Catatan tidak boleh kosong.');
    }
    return _sessionRepository.addAnnotation(
      SessionAnnotation(
        sessionId: sessionId,
        type: AnnotationType.textNote.value,
        timestampMs: timestampMs,
        contentText: trimmed,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Adds a timestamped bookmark to highlight important exam hints or topics.
  Future<SessionAnnotation> addBookmark({
    required int sessionId,
    required int timestampMs,
    String? label,
  }) async {
    final trimmed = label?.trim();
    return _sessionRepository.addAnnotation(
      SessionAnnotation(
        sessionId: sessionId,
        type: AnnotationType.bookmark.value,
        timestampMs: timestampMs,
        contentText: (trimmed == null || trimmed.isEmpty)
            ? 'Momen Penting (Perlu Review)'
            : trimmed,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<String> _compressPhoto({
    required String sourcePath,
    required String targetPath,
  }) async {
    try {
      final compressed = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        minWidth: 1280,
        minHeight: 1280,
        quality: 75,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (compressed != null && await File(compressed.path).exists()) {
        return compressed.path;
      }
    } catch (_) {
      // Fallback to direct copy if native compressor fails or is unavailable.
    }

    final fallback = await File(sourcePath).copy(targetPath);
    return fallback.path;
  }
}
