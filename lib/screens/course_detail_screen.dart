import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../models/course.dart';
import '../models/lecture_session.dart';
import '../providers/app_providers.dart';
import '../services/lecture_recorder_service.dart';
import 'class_recorder_screen.dart';
import 'session_detail_screen.dart';

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
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SessionDetailScreen(
          initialSession: session,
          course: course,
        ),
      ),
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
