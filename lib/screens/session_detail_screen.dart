import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/course.dart';
import '../models/flashcard.dart';
import '../models/lecture_session.dart';
import '../models/quiz_question.dart';
import '../models/session_annotation.dart';
import '../models/transcript_segment.dart';
import '../providers/app_providers.dart';
import '../services/ai_response_parser.dart';
import '../services/lecture_recorder_service.dart';
import '../widgets/synced_audio_player_bar.dart';
import 'flashcard_study_screen.dart';
import 'quiz_runner_screen.dart';
import 'settings_screen.dart';

/// Workspace screen for a lecture session displaying AI summaries,
/// audio-synced transcripts & whiteboard photos, and study flashcards/quizzes.
class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.initialSession,
    this.course,
    this.initialSeekMs,
  });

  final LectureSession initialSession;
  final Course? course;
  final int? initialSeekMs;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final SyncedAudioPlayerController _playerController =
      SyncedAudioPlayerController();

  bool _isProcessingAi = false;
  String _progressMessage = '';
  String? _localAiError;

  int get _sessionId => widget.initialSession.id!;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (widget.initialSeekMs != null) {
      _tabController.index = 1;
    }
    _initAudio();
  }

  Future<void> _initAudio() async {
    await _playerController.loadFile(
      widget.initialSession.audioPath,
      fallbackDurationMs: widget.initialSession.durationMs,
    );
    if (widget.initialSeekMs != null && _playerController.isLoaded) {
      await _playerController.seekToMs(widget.initialSeekMs!, autoPlay: true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _playerController.dispose();
    super.dispose();
  }

  Future<void> _runAiProcessing(LectureSession session) async {
    if (_isProcessingAi) return;
    final repo = ref.read(sessionRepositoryProvider);

    setState(() {
      _isProcessingAi = true;
      _progressMessage = 'Menyiapkan data sesi kuliah...';
      _localAiError = null;
    });

    try {
      await repo.updateSessionAiStatus(
        sessionId: _sessionId,
        status: 'processing',
      );
      ref.invalidate(sessionByIdProvider(_sessionId));

      final annotations = await repo.getAnnotationsBySession(_sessionId);
      final rawJson = await ref
          .read(aiLectureProcessorServiceProvider)
          .processSession(
            session: session,
            annotations: annotations,
            courseName: widget.course?.name,
            onProgress: (msg) {
              if (mounted) {
                setState(() => _progressMessage = msg);
              }
            },
          );

      if (mounted) {
        setState(() => _progressMessage = 'Menyimpan rangkuman & kuis ke SQLite...');
      }

      final parsed = AiResponseParser.parse(rawJson, sessionId: _sessionId);
      await repo.saveAiProcessingResult(sessionId: _sessionId, result: parsed);

      // Best-effort semantic indexing so local Cosine Similarity search works.
      try {
        final savedSegments =
            await repo.getTranscriptSegmentsBySession(_sessionId);
        if (savedSegments.isNotEmpty) {
          if (mounted) {
            setState(
              () => _progressMessage = 'Mengindeks vektor Semantic Search...',
            );
          }
          final vectors = await ref
              .read(semanticEmbeddingServiceProvider)
              .embedTextsBatch(
                savedSegments
                    .map((s) => s.textContent)
                    .toList(growable: false),
              );
          final map = <int, Float32List>{};
          for (var i = 0; i < savedSegments.length && i < vectors.length; i++) {
            final segId = savedSegments[i].id;
            final vec = vectors[i];
            if (segId != null && vec != null) {
              map[segId] = vec;
            }
          }
          if (map.isNotEmpty) {
            await repo.updateSegmentEmbeddings(map);
          }
        }
      } catch (_) {
        // Keep AI transcript & summary intact even if embedding quota fails.
      }

      ref.invalidate(sessionByIdProvider(_sessionId));
      ref.invalidate(sessionTranscriptProvider(_sessionId));
      ref.invalidate(sessionFlashcardsProvider(_sessionId));
      ref.invalidate(sessionQuizzesProvider(_sessionId));
      ref.invalidate(courseSessionsProvider(session.courseId));
      ref.invalidate(coursesProvider);

      if (mounted) {
        setState(() => _isProcessingAi = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Rangkuman, transkrip, flashcard & kuis berhasil dibuat!',
            ),
          ),
        );
      }
    } catch (e) {
      final message = e.toString().replaceFirst('Bad state: ', '');
      await repo.updateSessionAiStatus(
        sessionId: _sessionId,
        status: 'failed',
        errorMessage: message,
      );
      ref.invalidate(sessionByIdProvider(_sessionId));
      ref.invalidate(courseSessionsProvider(session.courseId));

      if (mounted) {
        setState(() {
          _isProcessingAi = false;
          _localAiError = message;
        });
      }
    }
  }

  Future<void> _addNoteAtCurrentTime() async {
    final timestampMs = _playerController.positionMs;
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Tambah Catatan (${LectureRecorderService.formatDurationMs(timestampMs)})',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Catat penjelasan dosen di menit ini...',
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
            sessionId: _sessionId,
            timestampMs: timestampMs,
            text: controller.text.trim(),
          );
      ref.invalidate(sessionAnnotationsProvider(_sessionId));
    }
    controller.dispose();
  }

  Future<void> _addPhotoAtCurrentTime() async {
    final timestampMs = _playerController.positionMs;
    final created =
        await ref.read(whiteboardCaptureServiceProvider).captureAndSavePhoto(
              sessionId: _sessionId,
              timestampMs: timestampMs,
              source: ImageSource.gallery,
            );
    if (created != null) {
      ref.invalidate(sessionAnnotationsProvider(_sessionId));
      ref.invalidate(storageUsageBytesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionByIdProvider(_sessionId));
    final session = sessionAsync.value ?? widget.initialSession;
    final annotationsAsync = ref.watch(sessionAnnotationsProvider(_sessionId));
    final transcriptAsync = ref.watch(sessionTranscriptProvider(_sessionId));
    final flashcardsAsync = ref.watch(sessionFlashcardsProvider(_sessionId));
    final quizzesAsync = ref.watch(sessionQuizzesProvider(_sessionId));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              DateFormat('dd MMM yyyy, HH:mm').format(session.recordedAt),
              style: const TextStyle(fontSize: 11.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: session.statusEnum == AiProcessingStatus.completed
                ? 'Proses Ulang AI'
                : 'Proses dengan AI',
            onPressed: _isProcessingAi ? null : () => _runAiProcessing(session),
            icon: const Icon(Icons.auto_awesome),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Rangkuman'),
            Tab(text: 'Transkrip & Foto'),
            Tab(text: 'Flashcard & Kuis'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_isProcessingAi) _buildProgressBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSummaryTab(session),
                _buildTranscriptTab(annotationsAsync, transcriptAsync),
                _buildStudyPreviewTab(flashcardsAsync, quizzesAsync),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SyncedAudioPlayerBar(controller: _playerController),
    );
  }

  Widget _buildProgressBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colorScheme.primary.withValues(alpha: 0.14),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _progressMessage,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Rangkuman Terstruktur
  // ---------------------------------------------------------------------------

  Widget _buildSummaryTab(LectureSession session) {
    final colorScheme = Theme.of(context).colorScheme;
    final errorMsg = _localAiError ?? session.aiErrorMessage;

    if (session.statusEnum != AiProcessingStatus.completed) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (errorMsg != null && errorMsg.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline, color: colorScheme.error),
                        const SizedBox(width: 8),
                        const Text(
                          'Pemrosesan AI Gagal',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(errorMsg, style: const TextStyle(fontSize: 12.5)),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('Periksa API Key di Pengaturan'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 48,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Siap Diproses dengan AI',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Saat terhubung ke internet/Wi-Fi, AI akan mengubah rekaman suara dosen + foto papan tulis menjadi transkrip ber-timestamp, rangkuman, glosarium, flashcard, dan kuis.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        _isProcessingAi ? null : () => _runAiProcessing(session),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Proses dengan AI Sekarang'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final points = AiResponseParser.decodeStringList(session.summaryPointsJson);
    final actionItems = AiResponseParser.decodeStringList(session.actionItemsJson);
    final glossary = AiResponseParser.decodeGlossary(session.glossaryJson);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummarySectionCard(
          icon: Icons.summarize_outlined,
          title: 'Ringkasan Eksekutif (TL;DR)',
          child: Text(
            session.summaryTldr ?? '-',
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
        ),
        if (points.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSummarySectionCard(
            icon: Icons.format_list_bulleted,
            title: 'Poin-Poin Materi Utama',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: points
                  .map(
                    (pt) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '•  ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              pt,
                              style: const TextStyle(fontSize: 13.5, height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
        if (session.whiteboardSynthesis != null &&
            session.whiteboardSynthesis!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSummarySectionCard(
            icon: Icons.draw_outlined,
            title: 'Sintesis Papan Tulis & Slide',
            child: Text(
              session.whiteboardSynthesis!,
              style: const TextStyle(fontSize: 13.5, height: 1.5),
            ),
          ),
        ],
        if (actionItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSummarySectionCard(
            icon: Icons.assignment_turned_in_outlined,
            title: 'Info Tugas & Ujian',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: actionItems
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
        if (glossary.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSummarySectionCard(
            icon: Icons.menu_book_outlined,
            title: 'Glosarium Istilah Teknis',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: glossary
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context)
                              .style
                              .copyWith(fontSize: 13.5, height: 1.4),
                          children: [
                            TextSpan(
                              text: '${entry.term}: ',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.primary,
                              ),
                            ),
                            TextSpan(text: entry.definition),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummarySectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Transkrip & Foto Sinkron
  // ---------------------------------------------------------------------------

  Widget _buildTranscriptTab(
    AsyncValue<List<SessionAnnotation>> annotationsAsync,
    AsyncValue<List<TranscriptSegment>> transcriptAsync,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addNoteAtCurrentTime,
                  icon: const Icon(Icons.note_add_outlined, size: 17),
                  label: const Text('Catatan', style: TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addPhotoAtCurrentTime,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 17),
                  label: const Text('Foto Slide', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ),
        annotationsAsync.maybeWhen(
          data: (annotations) {
            if (annotations.isEmpty) return const SizedBox.shrink();
            return SizedBox(
              height: 92,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                scrollDirection: Axis.horizontal,
                itemCount: annotations.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) => _AnnotationMiniCard(
                  annotation: annotations[index],
                  onSeek: () => _playerController.seekToMs(
                    annotations[index].timestampMs,
                  ),
                  onPreviewPhoto: (path) => _showPhotoDialog(path),
                ),
              ),
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),
        Expanded(
          child: transcriptAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Gagal memuat transkrip: $err')),
            data: (segments) {
              if (segments.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Transkrip ber-timestamp akan muncul di sini setelah sesi diproses dengan AI. Ketuk segmen nanti untuk memutar audio di detik tersebut.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }

              return ListenableBuilder(
                listenable: _playerController,
                builder: (_, _) {
                  final pos = _playerController.positionMs;
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: segments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final seg = segments[index];
                      final isActive = _playerController.isLoaded &&
                          pos >= seg.startMs &&
                          pos <= seg.endMs;
                      final timeLabel = LectureRecorderService.formatDurationMs(
                        seg.startMs,
                      );

                      return Card(
                        color: isActive
                            ? colorScheme.primary.withValues(alpha: 0.14)
                            : null,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _playerController.seekToMs(seg.startMs),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? colorScheme.primary
                                        : colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    timeLabel,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: isActive
                                          ? colorScheme.onPrimary
                                          : colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    seg.textContent,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Flashcard & Kuis Preview (Connected to Interactive Runners in Part 4)
  // ---------------------------------------------------------------------------

  Widget _buildStudyPreviewTab(
    AsyncValue<List<Flashcard>> flashcardsAsync,
    AsyncValue<List<QuizQuestion>> quizzesAsync,
  ) {
    final flashcards = flashcardsAsync.value ?? const [];
    final quizzes = quizzesAsync.value ?? const [];
    final colorScheme = Theme.of(context).colorScheme;

    if (flashcards.isEmpty && quizzes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Flashcard dan soal kuis otomatis akan tampil di sini setelah sesi diproses dengan AI.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final mastered = flashcards.where((c) => c.masteryLevel == 2).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.style_outlined, color: colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${flashcards.length} Flashcard',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            '$mastered sudah paham • ${flashcards.length - mastered} perlu diulang',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: flashcards.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => FlashcardStudyScreen(
                                title: 'Flashcard Sesi',
                                initialCards: flashcards,
                                singleSessionId: _sessionId,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Mulai Latihan Flashcard'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.quiz_outlined, color: colorScheme.secondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${quizzes.length} Soal Kuis Pilihan Ganda',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'Latihan soal lengkap dengan skor dan pembahasan',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: quizzes.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => QuizRunnerScreen(
                                title: 'Kuis Sesi',
                                questions: quizzes,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('Mulai Kuis Singkat'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (flashcards.isNotEmpty) ...[
          const Text(
            'Daftar Kartu Tanya-Jawab',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          ...flashcards.map(
            (card) {
              final (badgeText, badgeColor) = switch (card.masteryLevel) {
                2 => ('Paham', colorScheme.primary),
                1 => ('Perlu Ulang', Colors.amber),
                _ => ('Baru', colorScheme.onSurfaceVariant),
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                card.frontQuestion,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                badgeText,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: badgeColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          card.backAnswer,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Future<void> _showPhotoDialog(String imagePath) async {
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

class _AnnotationMiniCard extends StatelessWidget {
  const _AnnotationMiniCard({
    required this.annotation,
    required this.onSeek,
    required this.onPreviewPhoto,
  });

  final SessionAnnotation annotation;
  final VoidCallback onSeek;
  final ValueChanged<String> onPreviewPhoto;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final time = LectureRecorderService.formatDurationMs(annotation.timestampMs);
    final isPhoto =
        annotation.typeEnum == AnnotationType.photo && annotation.imagePath != null;

    return SizedBox(
      width: isPhoto ? 132 : 176,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            onSeek();
            if (isPhoto) {
              onPreviewPhoto(annotation.imagePath!);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: isPhoto
                ? Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(annotation.imagePath!),
                          width: 48,
                          height: 60,
                          cacheWidth: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              time,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Papan Tulis',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(
                            annotation.typeEnum == AnnotationType.bookmark
                                ? Icons.bookmark_outline
                                : Icons.notes,
                            size: 14,
                            color: annotation.typeEnum == AnnotationType.bookmark
                                ? Colors.amber
                                : colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            time,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        annotation.contentText ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
