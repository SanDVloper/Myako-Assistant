import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../models/course.dart';
import '../models/lecture_session.dart';
import '../models/session_annotation.dart';
import '../providers/app_providers.dart';
import '../services/lecture_recorder_service.dart';

/// Distraction-free Dark Mode classroom recording screen with live timestamped
/// text notes, bookmarks, and compressed whiteboard photo capture.
class ClassRecorderScreen extends ConsumerStatefulWidget {
  const ClassRecorderScreen({super.key, required this.course});

  final Course course;

  @override
  ConsumerState<ClassRecorderScreen> createState() =>
      _ClassRecorderScreenState();
}

class _ClassRecorderScreenState extends ConsumerState<ClassRecorderScreen> {
  final LectureRecorderService _recorder = LectureRecorderService();
  final TextEditingController _noteController = TextEditingController();
  final List<double> _levelBars = List<double>.filled(16, 0.08);
  final List<SessionAnnotation> _annotations = [];

  int? _sessionId;
  late String _sessionTitle;
  bool _isInitializing = true;
  bool _isSaving = false;
  String? _startupError;
  int _lastSampleTickMs = 0;

  @override
  void initState() {
    super.initState();
    final formatted = DateFormat('dd MMM HH:mm').format(DateTime.now());
    _sessionTitle = '${widget.course.name} • $formatted';
    _recorder.addListener(_onRecorderChanged);
    _beginRecording();
  }

  @override
  void dispose() {
    _recorder.removeListener(_onRecorderChanged);
    _recorder.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onRecorderChanged() {
    if (!mounted) return;
    final snap = _recorder.snapshot;
    if (snap.isRecording &&
        !snap.isPaused &&
        (snap.elapsedMs - _lastSampleTickMs) >= 140) {
      _lastSampleTickMs = snap.elapsedMs;
      _levelBars.removeAt(0);
      _levelBars.add(snap.normalizedAmplitude.clamp(0.08, 1.0));
    }
    setState(() {});
  }

  Future<void> _beginRecording() async {
    try {
      final path = await _recorder.startRecording(sessionTitle: _sessionTitle);
      final courseId = widget.course.id;
      if (courseId != null) {
        final created = await ref.read(sessionRepositoryProvider).createSession(
              LectureSession(
                courseId: courseId,
                title: _sessionTitle,
                recordedAt: DateTime.now(),
                durationMs: 0,
                audioPath: path,
                isImported: false,
                aiStatus: 'pending',
              ),
            );
        _sessionId = created.id;
      }
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _startupError =
              'Tidak dapat memulai perekam suara. Pastikan izin mikrofon aktif.\n($e)';
        });
      }
    }
  }

  Future<void> _togglePauseResume() async {
    if (_recorder.isPaused) {
      await _recorder.resumeRecording();
    } else {
      await _recorder.pauseRecording();
    }
  }

  Future<void> _finishAndSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final result = await _recorder.stopRecording();
      if (_sessionId != null && result != null) {
        await ref.read(sessionRepositoryProvider).updateSessionAfterRecording(
              sessionId: _sessionId!,
              durationMs: result.durationMs,
              audioPath: result.audioPath,
              title: _sessionTitle,
            );
      }
      if (widget.course.id != null) {
        ref.invalidate(courseSessionsProvider(widget.course.id!));
      }
      ref.invalidate(coursesProvider);
      ref.invalidate(storageUsageBytesProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnack('Gagal menyimpan rekaman: $e');
      }
    }
  }

  Future<void> _discardRecording() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batalkan Rekaman?'),
        content: const Text(
          'Audio yang sedang direkam beserta catatan & foto pada sesi ini akan dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Lanjut Rekam'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus & Keluar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _recorder.cancelRecording();
    if (_sessionId != null) {
      await ref.read(sessionRepositoryProvider).deleteSession(_sessionId!);
    }
    if (widget.course.id != null) {
      ref.invalidate(courseSessionsProvider(widget.course.id!));
    }
    ref.invalidate(coursesProvider);
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _handleBackAttempt() async {
    if (!_recorder.isRecording) {
      if (mounted) Navigator.of(context).pop(false);
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rekaman Masih Berjalan'),
        content: const Text(
          'Apakah kamu ingin menyimpan rekaman kuliah ini sekarang?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'stay'),
            child: const Text('Lanjut Rekam'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('Batalkan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (action == 'save') {
      await _finishAndSave();
    } else if (action == 'discard') {
      await _discardRecording();
    }
  }

  Future<void> _editTitle() async {
    final controller = TextEditingController(text: _sessionTitle);
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Judul Pertemuan'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Misal: Pertemuan 4 - Normalisasi Basis Data',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (updated != null && updated.trim().isNotEmpty) {
      setState(() => _sessionTitle = updated.trim());
      if (_sessionId != null) {
        await ref
            .read(sessionRepositoryProvider)
            .updateSessionTitle(_sessionId!, _sessionTitle);
      }
    }
  }

  Future<void> _addQuickNote() async {
    final sessionId = _sessionId;
    final text = _noteController.text.trim();
    if (sessionId == null || text.isEmpty) return;

    final timestampMs = _recorder.elapsedMs;
    _noteController.clear();
    try {
      final created = await ref.read(whiteboardCaptureServiceProvider).addQuickTextNote(
            sessionId: sessionId,
            timestampMs: timestampMs,
            text: text,
          );
      if (mounted) {
        setState(() => _annotations.add(created));
      }
    } catch (e) {
      _showSnack('Gagal menambah catatan: $e');
    }
  }

  Future<void> _addBookmark() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final timestampMs = _recorder.elapsedMs;
    try {
      final created = await ref.read(whiteboardCaptureServiceProvider).addBookmark(
            sessionId: sessionId,
            timestampMs: timestampMs,
          );
      if (mounted) {
        setState(() => _annotations.add(created));
        _showSnack(
          'Ditandai pada ${LectureRecorderService.formatDurationMs(timestampMs)}',
        );
      }
    } catch (e) {
      _showSnack('Gagal menandai momen: $e');
    }
  }

  Future<void> _capturePhoto(ImageSource source) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final timestampMs = _recorder.elapsedMs;
    try {
      final created =
          await ref.read(whiteboardCaptureServiceProvider).captureAndSavePhoto(
                sessionId: sessionId,
                timestampMs: timestampMs,
                source: source,
              );
      if (created != null && mounted) {
        setState(() => _annotations.add(created));
        _showSnack(
          'Foto papan tulis dikompresi & ditautkan ke ${LectureRecorderService.formatDurationMs(timestampMs)}.',
        );
      }
    } catch (e) {
      _showSnack('Gagal mengambil foto: $e');
    }
  }

  Future<void> _deleteAnnotation(SessionAnnotation annotation) async {
    if (annotation.id == null) return;
    await ref.read(sessionRepositoryProvider).deleteAnnotation(annotation.id!);
    if (mounted) {
      setState(() => _annotations.removeWhere((a) => a.id == annotation.id));
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = AppTheme.parseHexColor(widget.course.colorHex);
    final snap = _recorder.snapshot;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBackAttempt();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBackAttempt,
          ),
          title: GestureDetector(
            onTap: _editTitle,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _sessionTitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.edit_outlined, size: 16),
              ],
            ),
          ),
          actions: [
            if (_recorder.isRecording)
              IconButton(
                tooltip: 'Batalkan Rekaman',
                icon: Icon(Icons.delete_outline, color: colorScheme.error),
                onPressed: _discardRecording,
              ),
          ],
        ),
        body: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : _startupError != null
                ? _buildErrorView(colorScheme)
                : Column(
                    children: [
                      _buildRecorderCard(snap, colorScheme),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                        child: Row(
                          children: [
                            const Icon(Icons.timeline, size: 17),
                            const SizedBox(width: 6),
                            Text(
                              'Catatan & Foto Saat Kuliah (${_annotations.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: _buildTimelineList(colorScheme)),
                      _buildBottomAnnotationComposer(colorScheme),
                    ],
                  ),
      ),
    );
  }

  Widget _buildErrorView(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_off_outlined, size: 52, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _startupError ?? 'Gagal memulai rekaman.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Kembali'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecorderCard(
    RecorderStateSnapshot snap,
    ColorScheme colorScheme,
  ) {
    final isPaused = snap.isPaused;
    final formattedTime = LectureRecorderService.formatDurationMs(snap.elapsedMs);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isPaused ? Colors.amber : colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isPaused
                        ? 'REKAMAN DIJEDA'
                        : 'MEREKAM OFFLINE (AAC 64kbps)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: isPaused ? Colors.amber : colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                formattedTime,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              RepaintBoundary(
                child: SizedBox(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: _levelBars.map((level) {
                      return Container(
                        width: 5,
                        height: 6 + (level * 28),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: isPaused
                              ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                              : colorScheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : _togglePauseResume,
                      icon: Icon(
                        isPaused ? Icons.play_arrow : Icons.pause,
                      ),
                      label: Text(isPaused ? 'Lanjutkan' : 'Jeda'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _finishAndSave,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.stop_circle_outlined),
                      label: const Text('Selesai & Simpan'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineList(ColorScheme colorScheme) {
    if (_annotations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Ketik catatan singkat, tandai momen ujian (Bookmark), atau foto papan tulis di bawah — semuanya otomatis tersinkron ke menit rekaman.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: _annotations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _annotations[_annotations.length - 1 - index];
        final timeBadge = LectureRecorderService.formatDurationMs(item.timestampMs);
        final type = item.typeEnum;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    timeBadge,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: type == AnnotationType.photo && item.imagePath != null
                      ? GestureDetector(
                          onTap: () => _showPhotoPreview(item.imagePath!),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(item.imagePath!),
                                  width: 64,
                                  height: 48,
                                  cacheWidth: 160,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.broken_image_outlined,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Foto Papan Tulis / Slide\n(Ketuk untuk perbesar)',
                                  style: TextStyle(fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              type == AnnotationType.bookmark
                                  ? Icons.bookmark_added_outlined
                                  : Icons.notes,
                              size: 17,
                              color: type == AnnotationType.bookmark
                                  ? Colors.amber
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.contentText ?? '',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                ),
                IconButton(
                  tooltip: 'Hapus',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _deleteAnnotation(item),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomAnnotationComposer(ColorScheme colorScheme) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _addQuickNote(),
                    decoration: const InputDecoration(
                      hintText: 'Catat poin cepat atau rumus...',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Simpan Catatan',
                  onPressed: _addQuickNote,
                  icon: const Icon(Icons.send_rounded, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _capturePhoto(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('Foto Papan', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _capturePhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Galeri', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addBookmark,
                    icon: const Icon(
                      Icons.bookmark_add_outlined,
                      size: 18,
                      color: Colors.amber,
                    ),
                    label: const Text('Tandai', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPhotoPreview(String imagePath) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                cacheWidth: 960,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }
}
