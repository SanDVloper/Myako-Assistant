import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/course.dart';
import '../models/lecture_session.dart';
import '../providers/app_providers.dart';
import 'flashcard_study_screen.dart';
import 'quiz_runner_screen.dart';

/// Multi-session UTS / UAS exam preparation screen combining flashcards and
/// multiple-choice quiz questions across selected lecture sessions.
class ExamPrepScreen extends ConsumerStatefulWidget {
  const ExamPrepScreen({
    super.key,
    required this.course,
    required this.sessions,
  });

  final Course course;
  final List<LectureSession> sessions;

  @override
  ConsumerState<ExamPrepScreen> createState() => _ExamPrepScreenState();
}

class _ExamPrepScreenState extends ConsumerState<ExamPrepScreen> {
  late final List<LectureSession> _orderedSessions;
  final Set<int> _selectedIds = {};
  bool _shuffleItems = true;
  int? _maxQuizCount; // null = Semua
  bool _isLoadingLaunch = false;

  @override
  void initState() {
    super.initState();
    // Order chronologically so Pertemuan 1..7 map cleanly to Paket UTS and 8..14 to Paket UAS.
    _orderedSessions = List<LectureSession>.from(widget.sessions)
      ..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));

    // Pre-select completed sessions by default.
    for (final s in _orderedSessions) {
      if (s.id != null && s.statusEnum == AiProcessingStatus.completed) {
        _selectedIds.add(s.id!);
      }
    }
  }

  void _selectPresetRange(int startIndex, int endExclusive) {
    setState(() {
      _selectedIds.clear();
      final end = endExclusive.clamp(0, _orderedSessions.length);
      for (var i = startIndex; i < end; i++) {
        final id = _orderedSessions[i].id;
        if (id != null) {
          _selectedIds.add(id);
        }
      }
    });
  }

  Future<void> _launchFlashcards() async {
    if (_selectedIds.isEmpty || _isLoadingLaunch) return;
    setState(() => _isLoadingLaunch = true);

    try {
      final cards = await ref
          .read(sessionRepositoryProvider)
          .getFlashcardsBySessionIds(_selectedIds.toList(growable: false));

      if (!mounted) return;
      setState(() => _isLoadingLaunch = false);

      if (cards.isEmpty) {
        _showSnack(
          'Pertemuan yang dipilih belum memiliki flashcard. Proses sesi dengan AI terlebih dahulu.',
        );
        return;
      }

      final prepared = List.of(cards);
      if (_shuffleItems) prepared.shuffle();

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => FlashcardStudyScreen(
            title: 'Flashcard UTS/UAS • ${widget.course.name}',
            initialCards: prepared,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLaunch = false);
        _showSnack('Gagal memuat flashcard gabungan: $e');
      }
    }
  }

  Future<void> _launchQuiz() async {
    if (_selectedIds.isEmpty || _isLoadingLaunch) return;
    setState(() => _isLoadingLaunch = true);

    try {
      final questions = await ref
          .read(sessionRepositoryProvider)
          .getQuizQuestionsBySessionIds(_selectedIds.toList(growable: false));

      if (!mounted) return;
      setState(() => _isLoadingLaunch = false);

      if (questions.isEmpty) {
        _showSnack(
          'Pertemuan yang dipilih belum memiliki soal kuis. Proses sesi dengan AI terlebih dahulu.',
        );
        return;
      }

      var prepared = List.of(questions);
      if (_shuffleItems) prepared.shuffle();
      if (_maxQuizCount != null && prepared.length > _maxQuizCount!) {
        prepared = prepared.take(_maxQuizCount!).toList(growable: false);
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => QuizRunnerScreen(
            title: 'Simulasi UTS/UAS • ${widget.course.name}',
            questions: prepared,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLaunch = false);
        _showSnack('Gagal memuat soal UTS/UAS: $e');
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mode Persiapan UTS / UAS',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              widget.course.name,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: const Text('Semua'),
                  onPressed: () =>
                      _selectPresetRange(0, _orderedSessions.length),
                ),
                ActionChip(
                  label: const Text('Paket UTS (1–7)'),
                  onPressed: () => _selectPresetRange(0, 7),
                ),
                ActionChip(
                  label: const Text('Paket UAS (8–14)'),
                  onPressed: _orderedSessions.length > 7
                      ? () => _selectPresetRange(7, 14)
                      : null,
                ),
                ActionChip(
                  label: const Text('Reset'),
                  onPressed: () => setState(_selectedIds.clear),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Column(
                children: [
                  SwitchListTile(
                    dense: true,
                    title: const Text('Acak Urutan Soal & Kartu'),
                    value: _shuffleItems,
                    onChanged: (v) => setState(() => _shuffleItems = v),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: Row(
                      children: [
                        const Text(
                          'Jumlah Soal Kuis:',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [null, 10, 20, 30].map((limit) {
                                final selected = _maxQuizCount == limit;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(
                                      limit == null ? 'Semua' : '$limit',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    selected: selected,
                                    onSelected: (_) =>
                                        setState(() => _maxQuizCount = limit),
                                  ),
                                );
                              }).toList(growable: false),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              'Pilih Pertemuan (${_selectedIds.length} / ${_orderedSessions.length} dipilih)',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ),
          Expanded(
            child: _orderedSessions.isEmpty
                ? Center(
                    child: Text(
                      'Belum ada sesi kuliah di mata kuliah ini.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _orderedSessions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final session = _orderedSessions[index];
                      final sessionId = session.id;
                      final checked =
                          sessionId != null && _selectedIds.contains(sessionId);
                      final isReady =
                          session.statusEnum == AiProcessingStatus.completed;

                      return Card(
                        child: CheckboxListTile(
                          value: checked,
                          onChanged: sessionId == null
                              ? null
                              : (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedIds.add(sessionId);
                                    } else {
                                      _selectedIds.remove(sessionId);
                                    }
                                  });
                                },
                          title: Text(
                            'Pertemuan ${index + 1}: ${session.title}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            '${DateFormat('dd MMM yyyy').format(session.recordedAt)} • ${isReady ? 'AI Siap' : 'Belum diproses AI'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isReady
                                  ? colorScheme.primary
                                  : Colors.amber,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _selectedIds.isEmpty || _isLoadingLaunch
                          ? null
                          : _launchFlashcards,
                  icon: const Icon(Icons.style_outlined, size: 18),
                  label: const Text('Flashcard Gabungan'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _selectedIds.isEmpty || _isLoadingLaunch
                          ? null
                          : _launchQuiz,
                  icon: const Icon(Icons.quiz_outlined, size: 18),
                  label: const Text('Simulasi Kuis UTS/UAS'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
