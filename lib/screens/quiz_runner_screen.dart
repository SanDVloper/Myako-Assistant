import 'package:flutter/material.dart';

import '../models/quiz_question.dart';

/// Interactive multiple-choice quiz screen with instant explanation and score review.
class QuizRunnerScreen extends StatefulWidget {
  const QuizRunnerScreen({
    super.key,
    required this.title,
    required this.questions,
  });

  final String title;
  final List<QuizQuestion> questions;

  @override
  State<QuizRunnerScreen> createState() => _QuizRunnerScreenState();
}

class _QuizRunnerScreenState extends State<QuizRunnerScreen> {
  static const List<String> _optionLabels = ['A', 'B', 'C', 'D', 'E', 'F'];

  late List<QuizQuestion> _activeQuestions;
  late List<int?> _selectedAnswers;
  int _currentIndex = 0;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _initQuiz(shuffle: false);
  }

  void _initQuiz({required bool shuffle}) {
    _activeQuestions = List<QuizQuestion>.from(widget.questions);
    if (shuffle) {
      _activeQuestions.shuffle();
    }
    _selectedAnswers = List<int?>.filled(_activeQuestions.length, null);
    _currentIndex = 0;
    _isFinished = _activeQuestions.isEmpty;
  }

  int get _correctCount {
    var count = 0;
    for (var i = 0; i < _activeQuestions.length; i++) {
      if (_selectedAnswers[i] == _activeQuestions[i].correctIndex) {
        count++;
      }
    }
    return count;
  }

  void _selectOption(int optionIndex) {
    if (_selectedAnswers[_currentIndex] != null) return;
    setState(() {
      _selectedAnswers[_currentIndex] = optionIndex;
    });
  }

  void _nextQuestion() {
    setState(() {
      if (_currentIndex + 1 >= _activeQuestions.length) {
        _isFinished = true;
      } else {
        _currentIndex++;
      }
    });
  }

  void _retryShuffled() {
    setState(() => _initQuiz(shuffle: true));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: _activeQuestions.isEmpty
          ? const Center(child: Text('Belum ada soal kuis untuk sesi ini.'))
          : _isFinished
              ? _buildResultView(colorScheme)
              : _buildQuestionView(colorScheme),
    );
  }

  Widget _buildQuestionView(ColorScheme colorScheme) {
    final question = _activeQuestions[_currentIndex];
    final selectedIndex = _selectedAnswers[_currentIndex];
    final hasAnswered = selectedIndex != null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Soal ${_currentIndex + 1} / ${_activeQuestions.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              Text(
                'Benar: $_correctCount',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (_currentIndex + 1) / _activeQuestions.length,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      question.question,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...List.generate(question.options.length, (optIdx) {
                  final label = optIdx < _optionLabels.length
                      ? _optionLabels[optIdx]
                      : '${optIdx + 1}';
                  final isCorrectOption = optIdx == question.correctIndex;
                  final isSelectedOption = optIdx == selectedIndex;

                  Color? cardColor;
                  Color borderColor = Theme.of(context).dividerColor;
                  IconData? trailingIcon;
                  Color? trailingColor;

                  if (hasAnswered) {
                    if (isCorrectOption) {
                      cardColor = colorScheme.primary.withValues(alpha: 0.16);
                      borderColor = colorScheme.primary;
                      trailingIcon = Icons.check_circle;
                      trailingColor = colorScheme.primary;
                    } else if (isSelectedOption) {
                      cardColor = colorScheme.error.withValues(alpha: 0.16);
                      borderColor = colorScheme.error;
                      trailingIcon = Icons.cancel;
                      trailingColor = colorScheme.error;
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      color: cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: borderColor, width: 1.2),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: hasAnswered ? null : () => _selectOption(optIdx),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 13,
                                backgroundColor:
                                    colorScheme.surfaceContainerHighest,
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  question.options[optIdx],
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              if (trailingIcon != null) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  trailingIcon,
                                  color: trailingColor,
                                  size: 20,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                if (hasAnswered) ...[
                  const SizedBox(height: 6),
                  Card(
                    color: colorScheme.secondary.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                size: 18,
                                color: colorScheme.secondary,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Pembahasan',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            question.explanation,
                            style: const TextStyle(fontSize: 13, height: 1.45),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: hasAnswered ? _nextQuestion : null,
            icon: Icon(
              _currentIndex + 1 >= _activeQuestions.length
                  ? Icons.flag_outlined
                  : Icons.arrow_forward,
            ),
            label: Text(
              _currentIndex + 1 >= _activeQuestions.length
                  ? 'Lihat Skor Akhir'
                  : 'Soal Berikutnya',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultView(ColorScheme colorScheme) {
    final total = _activeQuestions.length;
    final correct = _correctCount;
    final score = total > 0 ? ((correct * 100) / total).round() : 0;

    final String readinessText;
    final Color readinessColor;
    if (score >= 80) {
      readinessText = 'Sangat Siap Ujian';
      readinessColor = colorScheme.primary;
    } else if (score >= 60) {
      readinessText = 'Cukup Baik, Review Lagi';
      readinessColor = Colors.amber;
    } else {
      readinessText = 'Perlu Pelajari Ulang Materi';
      readinessColor = colorScheme.error;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: readinessColor,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: readinessColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    readinessText,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: readinessColor,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Benar $correct dari $total soal',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _retryShuffled,
                        icon: const Icon(Icons.shuffle, size: 18),
                        label: const Text('Coba Lagi (Acak Soal)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Selesai'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Pembahasan Seluruh Soal',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 10),
        ...List.generate(_activeQuestions.length, (i) {
          final q = _activeQuestions[i];
          final chosen = _selectedAnswers[i];
          final isRight = chosen == q.correctIndex;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isRight ? Icons.check_circle : Icons.cancel,
                          size: 18,
                          color: isRight ? colorScheme.primary : colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${i + 1}. ${q.question}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Jawaban benar: ${q.options[q.correctIndex]}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                    if (!isRight &&
                        chosen != null &&
                        chosen >= 0 &&
                        chosen < q.options.length)
                      Text(
                        'Pilihanmu: ${q.options[chosen]}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      q.explanation,
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
        }),
      ],
    );
  }
}
