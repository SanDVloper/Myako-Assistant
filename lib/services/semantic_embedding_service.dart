import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/security/secure_key_storage.dart';

/// Generates compact 256-dimensional Float32 embeddings via Gemini
/// `text-embedding-004` (~1 KB per segment) for local Cosine Similarity search.
class SemanticEmbeddingService {
  SemanticEmbeddingService(
    this._keyStorage, {
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
              ),
            );

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004';
  static const int outputDimensions = 256;
  static const int _batchSize = 50;

  final SecureKeyStorage _keyStorage;
  final Dio _dio;

  /// Generates a query vector (`RETRIEVAL_QUERY`) for [query].
  /// Returns `null` gracefully if no Gemini key is stored or when offline.
  Future<Float32List?> embedQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    final apiKey = (await _keyStorage.getGeminiApiKey())?.trim() ?? '';
    if (apiKey.isEmpty) return null;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_baseUrl:embedContent',
        options: Options(
          headers: {
            'x-goog-api-key': apiKey,
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
        data: {
          'model': 'models/text-embedding-004',
          'taskType': 'RETRIEVAL_QUERY',
          'outputDimensionality': outputDimensions,
          'content': {
            'parts': [
              {'text': trimmed},
            ],
          },
        },
      );

      if (response.statusCode != 200 || response.data == null) return null;
      final embedding =
          response.data!['embedding'] as Map<String, dynamic>? ?? const {};
      return _toFloat32(embedding['values']);
    } catch (_) {
      return null;
    }
  }

  /// Generates document vectors (`RETRIEVAL_DOCUMENT`) in chunks of 50 texts.
  /// Returns a list aligned with [texts]; entries are `null` on offline/failure.
  Future<List<Float32List?>> embedTextsBatch(List<String> texts) async {
    if (texts.isEmpty) return const [];

    final apiKey = (await _keyStorage.getGeminiApiKey())?.trim() ?? '';
    if (apiKey.isEmpty) {
      return List<Float32List?>.filled(texts.length, null);
    }

    final results = List<Float32List?>.filled(texts.length, null);

    for (var start = 0; start < texts.length; start += _batchSize) {
      final end = (start + _batchSize).clamp(0, texts.length);
      final chunk = texts.sublist(start, end);

      try {
        final requests = chunk
            .map(
              (text) => {
                'model': 'models/text-embedding-004',
                'taskType': 'RETRIEVAL_DOCUMENT',
                'outputDimensionality': outputDimensions,
                'content': {
                  'parts': [
                    {'text': text},
                  ],
                },
              },
            )
            .toList(growable: false);

        final response = await _dio.post<Map<String, dynamic>>(
          '$_baseUrl:batchEmbedContents',
          options: Options(
            headers: {
              'x-goog-api-key': apiKey,
              'Content-Type': 'application/json',
            },
            validateStatus: (status) => status != null && status < 500,
          ),
          data: {'requests': requests},
        );

        if (response.statusCode == 200 && response.data != null) {
          final embeddings =
              response.data!['embeddings'] as List<dynamic>? ?? const [];
          for (var i = 0; i < embeddings.length && (start + i) < end; i++) {
            final item = embeddings[i];
            if (item is Map<String, dynamic>) {
              results[start + i] = _toFloat32(item['values']);
            }
          }
        }
      } catch (_) {
        // Leave chunk entries as null so lexical fallback still indexes the text.
      }
    }

    return results;
  }

  Float32List? _toFloat32(dynamic rawValues) {
    if (rawValues is! List || rawValues.isEmpty) return null;
    final vector = Float32List(rawValues.length);
    for (var i = 0; i < rawValues.length; i++) {
      vector[i] = (rawValues[i] as num).toDouble();
    }
    return vector;
  }
}
