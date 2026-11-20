import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../providers/app_providers.dart';
import 'class_recorder_screen.dart';
import 'course_detail_screen.dart';
import 'settings_screen.dart';

/// Main dashboard displaying semantic search bar, active semester, and courses.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semestersAsync = ref.watch(semestersProvider);
    final coursesAsync = ref.watch(coursesProvider);
    final activeSemester = ref.watch(activeSemesterProvider);
    final apiConfigAsync = ref.watch(apiKeyConfigProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Myako',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
            Text(
              'Smart Lecture Notes',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          apiConfigAsync.maybeWhen(
            data: (config) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                avatar: Icon(
                  config.hasAnyKey
                      ? Icons.verified_user
                      : Icons.vpn_key_outlined,
                  size: 16,
                  color: config.hasAnyKey ? colorScheme.primary : Colors.amber,
                ),
                label: Text(
                  config.hasAnyKey ? 'AI Siap' : 'Atur Key',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _openSettings(context),
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: 'Pengaturan & Keamanan',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _buildSearchBanner(context, colorScheme),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _buildSemesterHeader(
              context,
              ref,
              semestersAsync,
              activeSemester,
            ),
          ),
          Expanded(
            child: coursesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Gagal memuat mata kuliah: $err'),
                ),
              ),
              data: (courses) {
                if (courses.isEmpty) {
                  return _buildEmptyCoursesState(
                    context,
                    ref,
                    activeSemester,
                    colorScheme,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: courses.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _CourseCard(
                    course: courses[index],
                    onEdit: () => _showCourseDialog(
                      context,
                      ref,
                      semesterId: courses[index].semesterId,
                      existing: courses[index],
                    ),
                    onDelete: () =>
                        _confirmDeleteCourse(context, ref, courses[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildQuickActionBar(
        context,
        ref,
        coursesAsync.value ?? const [],
        activeSemester,
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  Widget _buildSearchBanner(BuildContext context, ColorScheme colorScheme) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Pencarian berbasis makna (Semantic Search) aktif setelah rekaman diproses AI.',
                ),
              ),
            );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.search, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tanya materi kuliahmu (Semantic Search)...',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSemesterHeader(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Semester>> semestersAsync,
    Semester? activeSemester,
  ) {
    final semesters = semestersAsync.value ?? const [];

    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: semesters.isEmpty
                ? null
                : () => _showSemesterSheet(context, ref, semesters),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      activeSemester?.name ?? 'Memuat Semester...',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down, size: 18),
                ],
              ),
            ),
          ),
        ),
        if (activeSemester?.id != null)
          FilledButton.tonalIcon(
            onPressed: () => _showCourseDialog(
              context,
              ref,
              semesterId: activeSemester!.id!,
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Mata Kuliah'),
          ),
      ],
    );
  }

  Widget _buildEmptyCoursesState(
    BuildContext context,
    WidgetRef ref,
    Semester? activeSemester,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 56,
              color: colorScheme.primary.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 12),
            const Text(
              'Belum ada Mata Kuliah',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Buat mata kuliah dulu untuk mengelompokkan rekaman suara dosen, foto papan tulis, dan latihan ujian.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (activeSemester?.id != null)
              FilledButton.icon(
                onPressed: () => _showCourseDialog(
                  context,
                  ref,
                  semesterId: activeSemester!.id!,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Tambah Mata Kuliah Pertama'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionBar(
    BuildContext context,
    WidgetRef ref,
    List<Course> courses,
    Semester? activeSemester,
  ) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _handleQuickLectureAction(
                  context,
                  ref,
                  courses,
                  activeSemester,
                  isRecord: false,
                ),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Upload Audio'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => _handleQuickLectureAction(
                  context,
                  ref,
                  courses,
                  activeSemester,
                  isRecord: true,
                ),
                icon: const Icon(Icons.mic_none_rounded),
                label: const Text('Mulai Rekam Kuliah'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleQuickLectureAction(
    BuildContext context,
    WidgetRef ref,
    List<Course> courses,
    Semester? activeSemester, {
    required bool isRecord,
  }) async {
    if (courses.isEmpty) {
      if (activeSemester?.id != null) {
        await _showCourseDialog(
          context,
          ref,
          semesterId: activeSemester!.id!,
        );
      }
      return;
    }

    Course? selectedCourse;
    if (courses.length == 1) {
      selectedCourse = courses.first;
    } else {
      selectedCourse = await _pickCourseForAction(
        context,
        courses,
        title: isRecord ? 'Pilih Mata Kuliah untuk Direkam' : 'Impor Audio ke Mata Kuliah',
      );
    }

    if (selectedCourse == null || selectedCourse.id == null || !context.mounted) {
      return;
    }

    if (isRecord) {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ClassRecorderScreen(course: selectedCourse!),
        ),
      );
      return;
    }

    try {
      final created = await ref
          .read(audioImportServiceProvider)
          .pickAndImportAudio(courseId: selectedCourse.id!);
      if (created != null && context.mounted) {
        ref.invalidate(courseSessionsProvider(selectedCourse.id!));
        ref.invalidate(coursesProvider);
        ref.invalidate(storageUsageBytesProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio "${created.title}" berhasil diimpor.')),
        );
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => CourseDetailScreen(course: selectedCourse!),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengimpor audio: $e')),
        );
      }
    }
  }

  Future<Course?> _pickCourseForAction(
    BuildContext context,
    List<Course> courses, {
    required String title,
  }) async {
    return showModalBottomSheet<Course>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: courses.length,
                itemBuilder: (_, index) {
                  final course = courses[index];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 8,
                      backgroundColor: AppTheme.parseHexColor(course.colorHex),
                    ),
                    title: Text(course.name),
                    subtitle: course.lecturerName != null
                        ? Text(course.lecturerName!)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, course),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Semester Management Modal
  // ---------------------------------------------------------------------------

  Future<void> _showSemesterSheet(
    BuildContext context,
    WidgetRef ref,
    List<Semester> semesters,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Pilih Semester',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showCreateSemesterDialog(context, ref);
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Baru'),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: semesters.length,
                    itemBuilder: (_, index) {
                      final semester = semesters[index];
                      return ListTile(
                        leading: Icon(
                          semester.isActive
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        title: Text(semester.name),
                        onTap: () {
                          if (semester.id != null) {
                            ref
                                .read(semestersProvider.notifier)
                                .selectSemester(semester.id!);
                          }
                          Navigator.pop(sheetContext);
                        },
                        trailing: semesters.length > 1
                            ? IconButton(
                                tooltip: 'Hapus Semester',
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  _confirmDeleteSemester(
                                    context,
                                    ref,
                                    semester,
                                  );
                                },
                              )
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCreateSemesterDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tambah Semester'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama Semester',
            hintText: 'Misal: Semester Genap 2026/2027',
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
      await ref
          .read(semestersProvider.notifier)
          .createSemester(controller.text.trim());
    }
    controller.dispose();
  }

  Future<void> _confirmDeleteSemester(
    BuildContext context,
    WidgetRef ref,
    Semester semester,
  ) async {
    if (semester.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Semester?'),
        content: Text(
          'Semua mata kuliah, rekaman audio, dan catatan di "${semester.name}" akan ikut terhapus permanen.',
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
      await ref.read(semestersProvider.notifier).deleteSemester(semester.id!);
    }
  }

  // ---------------------------------------------------------------------------
  // Course CRUD Dialogs
  // ---------------------------------------------------------------------------

  Future<void> _showCourseDialog(
    BuildContext context,
    WidgetRef ref, {
    required int semesterId,
    Course? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final lecturerController =
        TextEditingController(text: existing?.lecturerName ?? '');
    var selectedHex =
        existing?.colorHex ?? AppTheme.coursePaletteHexes.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Tambah Mata Kuliah' : 'Ubah Mata Kuliah'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nama Mata Kuliah',
                    hintText: 'Misal: Algoritma & Struktur Data',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lecturerController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Dosen (Opsional)',
                    hintText: 'Misal: Dr. Budi Santoso',
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Warna Label',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppTheme.coursePaletteHexes.map((hex) {
                    final selected = hex == selectedHex;
                    final color = AppTheme.parseHexColor(hex);
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedHex = hex),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  width: 2.5,
                                )
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && nameController.text.trim().isNotEmpty) {
      final notifier = ref.read(coursesProvider.notifier);
      if (existing == null) {
        await notifier.createCourse(
          semesterId: semesterId,
          name: nameController.text,
          lecturerName: lecturerController.text,
          colorHex: selectedHex,
        );
      } else {
        await notifier.updateCourse(
          existing.copyWith(
            name: nameController.text,
            lecturerName: lecturerController.text,
            colorHex: selectedHex,
          ),
        );
      }
    }

    nameController.dispose();
    lecturerController.dispose();
  }

  Future<void> _confirmDeleteCourse(
    BuildContext context,
    WidgetRef ref,
    Course course,
  ) async {
    if (course.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Mata Kuliah?'),
        content: Text(
          'Hapus "${course.name}" beserta seluruh rekaman suara dan catatan kuliah di dalamnya?',
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
      await ref.read(coursesProvider.notifier).deleteCourse(course.id!);
    }
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.onEdit,
    required this.onDelete,
  });

  final Course course;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.parseHexColor(course.colorHex);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CourseDetailScreen(course: course),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 54,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
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
                        course.lecturerName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        course.lecturerName!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _StatBadge(
                          icon: Icons.mic_none,
                          label: '${course.sessionCount} Sesi',
                        ),
                        if (course.pendingSessionCount > 0)
                          _StatBadge(
                            icon: Icons.hourglass_bottom,
                            label: '${course.pendingSessionCount} Belum AI',
                            color: Colors.amber,
                          ),
                        _StatBadge(
                          icon: Icons.style_outlined,
                          label: '${course.flashcardCount} Kartu',
                        ),
                        _StatBadge(
                          icon: Icons.quiz_outlined,
                          label: '${course.quizCount} Kuis',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Ubah')),
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

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: effectiveColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: effectiveColor),
        ),
      ],
    );
  }
}
