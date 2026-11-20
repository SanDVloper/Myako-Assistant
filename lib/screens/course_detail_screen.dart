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
import 'class_recorder_screen.dart';

/// Displays all recorded and imported lecture sessions for a [Course].
class CourseDetailScreen extends ConsumerWidget {
  const CourseDetailScreen({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courseId = course.id;
    if (courseId == null) {
      return const Scaffold(
        body: Center(child: Text('Mata kuliah tidak valid.')),
      );
    }

    final sessionsAsync = ref.watch(courseSessionsProvider(courseId));
    final colorScheme = Theme.of(context).colorScheme;
    final accent = AppTheme.parseHexColor(course.colorHex);

    return Scaffold(
      appBar: AppBar(
        title: Text(course.name),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _buildCourseHeaderCard(context, ref, accent, colorScheme),
          ),
          Expanded(
            child: sessionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Gagal memuat sesi kuliah: $err'),
                ),
              ),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return _buildEmptySessions(context, ref, colorScheme);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => _SessionCard(
                    session: sessions[index],
                    onTap: () => _openSessionPreview(
                      context,
                      ref,
                      sessions[index],
                    ),
                    onRename: () => _renameSession(
                      context,
                      ref,
                      sessions[index],
                    ),
                    onDelete: () => _deleteSession(
                      context,
                      ref,
                      sessions[index],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseHeaderCard(
    BuildContext context,
    WidgetRef ref,
    Color accent,
    ColorScheme colorScheme,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15.5,
                        ),
                      ),
                      if (course.lecturerName != null &&
                          course.lecturerName!.isNotEmpty)
                        Text(
                          course.lecturerName!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _startRecording(context, ref),
                    icon: const Icon(Icons.mic_none_rounded, size: 18),
                    label: const Text('Rekam Baru'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _importAudio(context, ref),
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Impor Audio'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySessions(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.graphic_eq_outlined,
              size: 52,
              color: colorScheme.primary.withValues(alpha: 0.75),
            ),
            const SizedBox(height: 12),
            const Text(
              'Belum Ada Rekaman Pertemuan',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5),
            ),
            const SizedBox(height: 6),
            Text(
              'Rekam suara dosen langsung di kelas (100% offline) atau impor file rekaman audio dari perangkatmu.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startRecording(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ClassRecorderScreen(course: course),
      ),
    );
  }

  Future<void> _importAudio(BuildContext context, WidgetRef ref) async {
    final courseId = course.id;
    if (courseId == null) return;
    try {
      final created = await ref
          .read(audioImportServiceProvider)
          .pickAndImportAudio(courseId: courseId);
      if (created != null) {
        ref.invalidate(courseSessionsProvider(courseId));
        ref.invalidate(coursesProvider);
        ref.invalidate(storageUsageBytesProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Audio "${created.title}" berhasil diimpor.')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengimpor audio: $e')),
        );
      }
    }
  }

  Future<void> _openSessionPreview(
    BuildContext context,
    WidgetRef ref,
    LectureSession session,
  ) async {
    if (session.id == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SessionPreviewSheet(session: session),
    );
  }

  Future<void> _renameSession(
    BuildContext context,
    WidgetRef ref,
    LectureSession session,
  ) async {
    if (session.id == null) return;
    final controller = TextEditingController(text: session.title);
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ubah Judul Pertemuan'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Judul'),
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
      await ref
          .read(sessionRepositoryProvider)
          .updateSessionTitle(session.id!, updated.trim());
      ref.invalidate(courseSessionsProvider(course.id!));
    }
  }

  Future<void> _deleteSession(
    BuildContext context,
    WidgetRef ref,
    LectureSession session,
  ) async {
    if (session.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Rekaman?'),
        content: Text(
          'Hapus "${session.title}" beserta file audio dan foto papan tulisnya?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(sessionRepositoryProvider).deleteSession(session.id!);
      ref.invalidate(courseSessionsProvider(course.id!));
      ref.invalidate(coursesProvider);
      ref.invalidate(storageUsageBytesProvider);
    }
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final LectureSession session;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateText = DateFormat('dd MMM yyyy, HH:mm').format(session.recordedAt);
    final durationText =
        LectureRecorderService.formatDurationMs(session.durationMs);
    final status = session.statusEnum;

    final (statusLabel, statusColor) = switch (status) {
      AiProcessingStatus.completed => ('Siap Dipelajari', colorScheme.primary),
      AiProcessingStatus.processing => ('Memproses AI...', colorScheme.secondary),
      AiProcessingStatus.failed => ('Gagal AI', colorScheme.error),
      AiProcessingStatus.pending => ('Belum Diproses AI', Colors.amber),
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                session.isImported ? Icons.audio_file_outlined : Icons.mic_none,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$dateText • Durasi $durationText',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            session.isImported ? 'Audio Impor' : 'Rekaman Kelas',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') onRename();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Ubah Judul')),
                  PopupMenuItem(value: 'delete', child: Text('Hapus')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionPreviewSheet extends ConsumerWidget {
  const _SessionPreviewSheet({required this.session});

  final LectureSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = session.id!;
    final annotationsAsync = ref.watch(sessionAnnotationsProvider(sessionId));
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                session.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Durasi ${LectureRecorderService.formatDurationMs(session.durationMs)} • File lokal tersimpan aman',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addPostNote(context, ref, sessionId),
                      icon: const Icon(Icons.note_add_outlined, size: 18),
                      label: const Text('Tambah Catatan'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addPostPhoto(context, ref, sessionId),
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: const Text('Tambah Foto'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Pemrosesan AI Multimodal (Transkrip, Vision Papan Tulis, Rangkuman) & Audio Sync akan diaktifkan pada Part 3.',
                        ),
                      ),
                    );
                },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Proses dengan AI (Part 3)'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Anotasi & Foto Papan Tulis',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: annotationsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Text('Gagal memuat anotasi: $err'),
                  data: (items) {
                    if (items.isEmpty) {
                      return Center(
                        child: Text(
                          'Belum ada catatan manual atau foto papan tulis pada sesi ini.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final item = items[index];
                        final time = LectureRecorderService.formatDurationMs(
                          item.timestampMs,
                        );
                        return Card(
                          child: ListTile(
                            leading: item.typeEnum == AnnotationType.photo &&
                                    item.imagePath != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.file(
                                      File(item.imagePath!),
                                      width: 44,
                                      height: 44,
                                      cacheWidth: 120,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.image_not_supported),
                                    ),
                                  )
                                : Icon(
                                    item.typeEnum == AnnotationType.bookmark
                                        ? Icons.bookmark_outline
                                        : Icons.notes,
                                  ),
                            title: Text(
                              item.typeEnum == AnnotationType.photo
                                  ? (item.contentText ?? 'Foto Papan Tulis / Slide')
                                  : (item.contentText ?? ''),
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              'Menit $time',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addPostNote(
    BuildContext context,
    WidgetRef ref,
    int sessionId,
  ) async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tambah Catatan'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Tulis catatan tambahan untuk sesi ini...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (saved == true && controller.text.trim().isNotEmpty) {
      await ref.read(whiteboardCaptureServiceProvider).addQuickTextNote(
            sessionId: sessionId,
            timestampMs: 0,
            text: controller.text.trim(),
          );
      ref.invalidate(sessionAnnotationsProvider(sessionId));
    }
    controller.dispose();
  }

  Future<void> _addPostPhoto(
    BuildContext context,
    WidgetRef ref,
    int sessionId,
  ) async {
    final created =
        await ref.read(whiteboardCaptureServiceProvider).captureAndSavePhoto(
              sessionId: sessionId,
              timestampMs: 0,
              source: ImageSource.gallery,
            );
    if (created != null) {
      ref.invalidate(sessionAnnotationsProvider(sessionId));
      ref.invalidate(storageUsageBytesProvider);
    }
  }
}
