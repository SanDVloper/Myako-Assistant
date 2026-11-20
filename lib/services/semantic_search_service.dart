import 'dart:math' as math;
import 'dart:typed_data';

import '../data/session_repository.dart';
import '../models/lecture_session.dart';
import '../models/transcript_segment.dart';
import 'semantic_embedding_service.dart';

/// Single matched lecture segment produced by [SemanticSearchService].
class SemanticSearchHit {
  const SemanticSearchHit({
    required this.segment,
    required this.session,
    required this.courseName,
    required this.courseColorHex,
    required this.score,
    required this.isSemanticMatch,
  });

  final TranscriptSegment segment;
  final LectureSession session;
  final String courseName;
  final String courseColorHex;
  final double score;
  final bool isSemanticMatch;
}

/// Aggregated search results along with whether vector embeddings were used.
class SemanticSearchResponse {
  const SemanticSearchResponse({
    required this.hits,
    required this.usedSemanticVectors,
  });

  final List<SemanticSearchHit> hits;
  final bool usedSemanticVectors;
}

/// Local Cosine Similarity search over SQLite Float32 embedding BLOBs with
/// automatic offline multi-token keyword fallback.
class SemanticSearchService {
  SemanticSearchService(
    this._sessionRepository,
    this._embeddingService,
  );

  final SessionRepository _sessionRepository;
  final SemanticEmbeddingService _embeddingService;

  /// Computes normalized Cosine Similarity in `[-1.0, 1.0]`.
  static double cosineSimilarity(Float32List a, Float32List b) {
    if (a.isEmpty || a.length != b.length) return 0.0;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      final va = a[i];
      final vb = b[i];
      dot += va * vb;
      normA += va * va;
      normB += vb * vb;
    }
    if (normA <= 0.0 || normB <= 0.0) return 0.0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  /// Searches all locally stored lecture segments (optionally scoped to [courseId]).
  Future<SemanticSearchResponse> search({
    required String query,
    int? courseId,
    int limit = 25,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const SemanticSearchResponse(hits: [], usedSemanticVectors: false);
    }

    final records = await _sessionRepository.getSearchableSegments(
      courseId: courseId,
    );
    if (records.isEmpty) {
      return const SemanticSearchResponse(hits: [], usedSemanticVectors: false);
    }

    final queryTokens = _tokenize(normalizedQuery);
    final hasAnyEmbedding = records.any((r) => r.segment.embedding != null);
    final queryVector = hasAnyEmbedding
        ? await _embeddingService.embedQuery(normalizedQuery)
        : null;

    final hits = <SemanticSearchHit>[];
    final usedVectors = queryVector != null;

    for (final rec in records) {
      final lexical = _lexicalScore(
        normalizedQuery: normalizedQuery,
        queryTokens: queryTokens,
        record: rec,
      );

      final segEmbedding = rec.segment.embedding;
      if (usedVectors && segEmbedding != null) {
        final sim = cosineSimilarity(queryVector, segEmbedding);
        final combined = (sim + (lexical * 0.12)).clamp(0.0, 1.0);
        if (sim >= 0.22 || lexical > 0.0) {
          hits.add(
            SemanticSearchHit(
              segment: rec.segment,
              session: rec.session,
              courseName: rec.courseName,
              courseColorHex: rec.courseColorHex,
              score: combined,
              isSemanticMatch: true,
            ),
          );
        }
      } else if (lexical > 0.0) {
        hits.add(
          SemanticSearchHit(
            segment: rec.segment,
            session: rec.session,
            courseName: rec.courseName,
            courseColorHex: rec.courseColorHex,
            score: lexical,
            isSemanticMatch: false,
          ),
        );
      }
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    final capped = hits.length > limit ? hits.sublist(0, limit) : hits;

    return SemanticSearchResponse(
      hits: capped,
      usedSemanticVectors: usedVectors,
    );
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u00c0-\u024f]+'))
        .where((token) => token.length >= 2)
        .toSet()
        .toList(growable: false);
  }

  double _lexicalScore({
    required String normalizedQuery,
    required List<String> queryTokens,
    required SearchableSegmentRecord record,
  }) {
    final segLower = record.segment.textContent.toLowerCase();
    final titleLower = record.session.title.toLowerCase();
    final tldrLower = (record.session.summaryTldr ?? '').toLowerCase();
    final queryLower = normalizedQuery.toLowerCase();

    if (queryTokens.isEmpty) {
      return segLower.contains(queryLower) ? 1.0 : 0.0;
    }

    var matched = 0;
    for (final token in queryTokens) {
      if (segLower.contains(token) ||
          titleLower.contains(token) ||
          tldrLower.contains(token)) {
        matched++;
      }
    }

    if (matched == 0) return 0.0;
    var score = matched / queryTokens.length;
    if (segLower.contains(queryLower)) {
      score = (score + 0.25).clamp(0.0, 1.0);
    }
    return score;
  }
}
