import 'dart:typed_data';

/// A timestamped transcript segment with an optional Float32 embedding vector.
class TranscriptSegment {
  const TranscriptSegment({
    this.id,
    required this.sessionId,
    required this.startMs,
    required this.endMs,
    required this.textContent,
    this.embedding,
  });

  final int? id;
  final int sessionId;
  final int startMs;
  final int endMs;
  final String textContent;
  final Float32List? embedding;

  /// Serializes a [Float32List] into a compact [Uint8List] BLOB for SQLite storage.
  static Uint8List? embeddingToBlob(Float32List? vector) {
    if (vector == null || vector.isEmpty) return null;
    // Copy into an aligned ByteData buffer for cross-architecture safety on ARM.
    final byteData = ByteData(vector.length * Float32List.bytesPerElement);
    for (var i = 0; i < vector.length; i++) {
      byteData.setFloat32(i * 4, vector[i], Endian.little);
    }
    return byteData.buffer.asUint8List();
  }

  /// Deserializes a SQLite [Uint8List] BLOB back into a [Float32List] safely.
  static Float32List? blobToEmbedding(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty || bytes.lengthInBytes % 4 != 0) {
      return null;
    }
    final byteData = ByteData.sublistView(bytes);
    final length = bytes.lengthInBytes ~/ 4;
    final vector = Float32List(length);
    for (var i = 0; i < length; i++) {
      vector[i] = byteData.getFloat32(i * 4, Endian.little);
    }
    return vector;
  }

  /// Creates a [TranscriptSegment] from a SQLite row map.
  factory TranscriptSegment.fromMap(Map<String, Object?> map) {
    final rawBlob = map['embedding'] as Uint8List?;
    return TranscriptSegment(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      startMs: map['start_ms'] as int,
      endMs: map['end_ms'] as int,
      textContent: map['text_content'] as String,
      embedding: blobToEmbedding(rawBlob),
    );
  }

  /// Converts this [TranscriptSegment] to a SQLite-compatible map.
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'session_id': sessionId,
      'start_ms': startMs,
      'end_ms': endMs,
      'text_content': textContent,
      'embedding': embeddingToBlob(embedding),
    };
  }

  /// Returns a copy with overridden fields.
  TranscriptSegment copyWith({
    int? id,
    int? sessionId,
    int? startMs,
    int? endMs,
    String? textContent,
    Float32List? embedding,
  }) {
    return TranscriptSegment(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      textContent: textContent ?? this.textContent,
      embedding: embedding ?? this.embedding,
    );
  }
}
