import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/flashcard.dart';
import '../providers/app_providers.dart';

/// Interactive flip-card study screen with SQLite mastery persistence.
class FlashcardStudyScreen extends ConsumerStatefulWidget {
  const FlashcardStudyScreen({
    super.key,
    required this.title,
    required this.initialCards,
    this.singleSessionId,
  });

  final String title;
  final List<Flashcard> initialCards;
  final int? singleSessionId;

  @override
  ConsumerState<FlashcardStudyScreen> createState() =>
      _FlashcardStudyScreenState();
}

class _FlashcardStudyScreenState extends ConsumerState<FlashcardStudyScreen> {
  late List<Flashcard> _allCards;
  late List<Flashcard> _activeDeck;
  bool _onlyReviewNeeded = false;
  int _currentIndex = 0;
  bool _showAnswer = false;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _allCards = List<Flashcard>.from(widget.initialCards);
    _rebuildDeck(resetIndex: true);
  }

  void _rebuildDeck({required bool resetIndex}) {
    _activeDeck = _onlyReviewNeeded
        ? _allCards.where((c) => c.masteryLevel != 2).toList()
        : List<Flashcard>.from(_allCards);
    if (resetIndex) {
      _currentIndex = 0;
      _showAnswer = false;
      _isCompleted = _activeDeck.isEmpty;
    }
  }

  void _shuffleDeck() {
    setState(() {
      _activeDeck.shuffle();
      _currentIndex = 0;
      _showAnswer = false;
      _isCompleted = _activeDeck.isEmpty;
    });
  }

  void _toggleFilter(bool reviewOnly) {
    setState(() {
      _onlyReviewNeeded = reviewOnly;
      _rebuildDeck(resetIndex: true);
    });
  }

  Future<void> _rateCurrentCard(int masteryLevel) async {
    if (_activeDeck.isEmpty || _currentIndex >= _activeDeck.length) return;
    final current = _activeDeck[_currentIndex];
    final updated = current.copyWith(masteryLevel: masteryLevel);

    if (current.id != null) {
      await ref.read(sessionRepositoryProvider).updateFlashcardMastery(
            flashcardId: current.id!,
            masteryLevel: masteryLevel,
          );
      if (widget.singleSessionId != null) {
        ref.invalidate(sessionFlashcardsProvider(widget.singleSessionId!));
      }
    }

    if (!mounted) return;
    setState(() {
      final allIdx = _allCards.indexWhere(
        (c) => c.id != null ? c.id == current.id : identical(c, current),
      );
      if (allIdx != -1) {
        _allCards[allIdx] = updated;
      }
      _activeDeck[_currentIndex] = updated;

      if (_currentIndex + 1 >= _activeDeck.length) {
        _isCompleted = true;
        _showAnswer = false;
      } else {
        _currentIndex++;
        _showAnswer = false;
      }
    });
  }

  void _restartDeck({required bool onlyNeedReview}) {
    setState(() {
      _onlyReviewNeeded = onlyNeedReview;
      _rebuildDeck(resetIndex: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final masteredCount = _allCards.where((c) => c.masteryLevel == 2).length;
    final repeatCount = _allCards.where((c) => c.masteryLevel == 1).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Acak Urutan Kartu',
            icon: const Icon(Icons.shuffle),
            onPressed: _activeDeck.length > 1 ? _shuffleDeck : null,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: Text('Semua (${_allCards.length})'),
                  selected: !_onlyReviewNeeded,
                  onSelected: (_) => _toggleFilter(false),
                ),
                ChoiceChip(
                  label: Text(
                    'Perlu Ulang (${_allCards.where((c) => c.masteryLevel != 2).length})',
                  ),
                  selected: _onlyReviewNeeded,
                  onSelected: (_) => _toggleFilter(true),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MasteryPill(
                  icon: Icons.check_circle_outline,
                  label: 'Paham: $masteredCount',
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                _MasteryPill(
                  icon: Icons.refresh,
                  label: 'Ulang: $repeatCount',
                  color: Colors.amber,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_isCompleted && _activeDeck.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Kartu ${_currentIndex + 1} / ${_activeDeck.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    _showAnswer ? 'Sisi Jawaban' : 'Ketuk kartu untuk balik',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: (_currentIndex + 1) / _activeDeck.length,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _buildFlipCard(_activeDeck[_currentIndex], colorScheme),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rateCurrentCard(1),
                      icon: const Icon(Icons.refresh, color: Colors.amber),
                      label: const Text('Perlu Ulang'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _rateCurrentCard(2),
                      icon: const Icon(Icons.check),
                      label: const Text('Sudah Paham'),
                    ),
                  ),
                ],
              ),
            ] else
              Expanded(
                child: _buildCompletedView(
                  masteredCount: masteredCount,
                  repeatCount:
                      _allCards.where((c) => c.masteryLevel != 2).length,
                  colorScheme: colorScheme,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlipCard(Flashcard card, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => setState(() => _showAnswer = !_showAnswer),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Card(
          key: ValueKey<String>('${card.id ?? _currentIndex}_$_showAnswer'),
          color: _showAnswer
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surface,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _showAnswer
                        ? colorScheme.primary.withValues(alpha: 0.2)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _showAnswer ? 'JAWABAN / KONSEP' : 'PERTANYAAN / ISTILAH',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: _showAnswer
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      _showAnswer ? card.backAnswer : card.frontQuestion,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: _showAnswer ? 16 : 18.5,
                        fontWeight:
                            _showAnswer ? FontWeight.w500 : FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _showAnswer
                          ? 'Ketuk untuk lihat pertanyaan'
                          : 'Ketuk untuk lihat jawaban',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedView({
    required int masteredCount,
    required int repeatCount,
    required ColorScheme colorScheme,
  }) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                repeatCount == 0
                    ? Icons.emoji_events_outlined
                    : Icons.done_all_outlined,
                size: 56,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                _allCards.isEmpty
                    ? 'Belum Ada Flashcard'
                    : repeatCount == 0
                        ? 'Semua Kartu Sudah Dikuasai!'
                        : 'Sesi Flashcard Selesai',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Sudah paham: $masteredCount • Masih perlu diulang: $repeatCount',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              if (repeatCount > 0)
                FilledButton.icon(
                  onPressed: () => _restartDeck(onlyNeedReview: true),
                  icon: const Icon(Icons.refresh),
                  label: Text('Ulangi $repeatCount Kartu Belum Hafal'),
                ),
              if (repeatCount > 0) const SizedBox(height: 8),
              if (_allCards.isNotEmpty)
                OutlinedButton(
                  onPressed: () => _restartDeck(onlyNeedReview: false),
                  child: const Text('Mulai Ulang Semua Kartu'),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Kembali'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasteryPill extends StatelessWidget {
  const _MasteryPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
