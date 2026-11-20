import 'dart:convert';

import '../models/flashcard.dart';
import '../models/quiz_question.dart';
import '../models/transcript_segment.dart';

/// Technical/academic term and its Indonesian definition extracted by AI.
class GlossaryTerm {
  const GlossaryTerm({
    required this.term,
    required this.definition,
  });

  final String term;
  final String definition;

  factory GlossaryTerm.fromMap(Map<String, dynamic> map) {
    return GlossaryTerm(
      term: (map['term'] as String? ?? '').trim(),
      definition: (map['definition'] as String? ?? '').trim(),
    );
  }

  Map<String, String> toMap() => {
        'term': term,
        'definition': definition,
      };
}

/// Structured output parsed from Gemini / Groq multimodal JSON response.
class ParsedLectureAiResult {
  const ParsedLectureAiResult({
    required this.summaryTldr,
    required this.summaryPoints,
    required this.whiteboardSynthesis,
    required this.glossary,
    required this.actionItems,
    required this.segments,
    required this.flashcards,
    required this.quizzes,
  });

  final String summaryTldr;
  final List<String> summaryPoints;
  final String whiteboardSynthesis;
  final List<GlossaryTerm> glossary;
  final List<String> actionItems;
  final List<TranscriptSegment> segments;
  final List<Flashcard> flashcards;
  final List<QuizQuestion> quizzes;
}

/// Defensive parser for AI JSON output with shared JSON list decoders for UI.
class AiResponseParser {
  AiResponseParser._();

  /// Parses [rawResponse] JSON into [ParsedLectureAiResult] for [sessionId].
  static ParsedLectureAiResult parse(
    String rawResponse, {
    required int sessionId,
  }) {
    final cleanedJson = _extractJsonObject(rawResponse);
    final decoded = jsonDecode(cleanedJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respons AI bukan objek JSON yang valid.');
    }

    final summaryTldr = (decoded['summary_tldr'] as String? ?? '').trim();
    final summaryPoints = _parseStringList(decoded['summary_points']);
    final whiteboardSynthesis =
        (decoded['whiteboard_synthesis'] as String? ?? '').trim();
    final actionItems = _parseStringList(decoded['action_items']);

    final glossary = <GlossaryTerm>[];
    final rawGlossary = decoded['glossary'];
    if (rawGlossary is List) {
      for (final item in rawGlossary) {
        if (item is Map<String, dynamic>) {
          final term = GlossaryTerm.fromMap(item);
          if (term.term.isNotEmpty) {
            glossary.add(term);
          }
        }
      }
    }

    final segments = <TranscriptSegment>[];
    final rawSegments = decoded['transcript_segments'];
    if (rawSegments is List) {
      for (final item in rawSegments) {
        if (item is Map<String, dynamic>) {
          final text = (item['text'] as String? ?? '').trim();
          if (text.isEmpty) continue;
          final startMs = (item['start_ms'] as num?)?.toInt() ?? 0;
          final rawEndMs = (item['end_ms'] as num?)?.toInt() ?? (startMs + 30000);
          final endMs = rawEndMs >= startMs ? rawEndMs : startMs;
          segments.add(
            TranscriptSegment(
              sessionId: sessionId,
              startMs: startMs < 0 ? 0 : startMs,
              endMs: endMs < 0 ? 0 : endMs,
              textContent: text,
            ),
          );
        }
      }
    }

    final flashcards = <Flashcard>[];
    final rawCards = decoded['flashcards'];
    if (rawCards is List) {
      for (final item in rawCards) {
        if (item is Map<String, dynamic>) {
          final front = (item['front'] as String? ?? '').trim();
          final back = (item['back'] as String? ?? '').trim();
          if (front.isNotEmpty && back.isNotEmpty) {
            flashcards.add(
              Flashcard(
                sessionId: sessionId,
                frontQuestion: front,
                backAnswer: back,
              ),
            );
          }
        }
      }
    }

    final quizzes = <QuizQuestion>[];
    final rawQuizzes = decoded['quiz_questions'];
    if (rawQuizzes is List) {
      for (final item in rawQuizzes) {
        if (item is Map<String, dynamic>) {
          final question = (item['question'] as String? ?? '').trim();
          final options = _parseStringList(item['options']);
          if (question.isEmpty || options.length < 2) continue;
          final rawIndex = (item['correct_index'] as num?)?.toInt() ?? 0;
          final clampedIndex = rawIndex.clamp(0, options.length - 1);
          final explanation = (item['explanation'] as String? ?? '').trim();
          quizzes.add(
            QuizQuestion(
              sessionId: sessionId,
              question: question,
              options: options,
              correctIndex: clampedIndex,
              explanation: explanation.isEmpty
                  ? 'Lihat kembali rangkuman materi kuliah.'
                  : explanation,
            ),
          );
        }
      }
    }

    return ParsedLectureAiResult(
      summaryTldr: summaryTldr.isEmpty
          ? 'Rangkuman berhasil dibuat. Lihat poin materi dan transkrip.'
          : summaryTldr,
      summaryPoints: summaryPoints,
      whiteboardSynthesis: whiteboardSynthesis,
      glossary: glossary,
      actionItems: actionItems,
      segments: segments,
      flashcards: flashcards,
      quizzes: quizzes,
    );
  }

  /// Decodes a persisted JSON string array safely into a list of strings.
  static List<String> decodeStringList(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(jsonStr);
      return _parseStringList(decoded);
    } catch (_) {
      return const [];
    }
  }

  /// Decodes a persisted glossary JSON string safely into [GlossaryTerm] items.
  static List<GlossaryTerm> decodeGlossary(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(GlossaryTerm.fromMap)
          .where((g) => g.term.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  static String _extractJsonObject(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
      text = text.trim();
    }
    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace > firstBrace) {
      return text.substring(firstBrace, lastBrace + 1);
    }
    return text;
  }
}
