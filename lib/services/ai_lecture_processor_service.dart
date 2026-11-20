import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/security/secure_key_storage.dart';
import '../models/lecture_session.dart';
import '../models/session_annotation.dart';
import 'lecture_recorder_service.dart';

/// Multimodal AI processor connecting offline lecture audio, compressed
/// whiteboard photos, and manual quick notes to Gemini 2.5 Flash or Groq API.
class AiLectureProcessorService {
  AiLectureProcessorService(
    this._keyStorage, {
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 5),
                sendTimeout: const Duration(minutes: 5),
              ),
            );

  static const String _geminiBaseUrl = 'https://generativelanguage.googleapis.com';
  static const String _groqBaseUrl = 'https://api.groq.com/openai/v1';

  final SecureKeyStorage _keyStorage;
  final Dio _dio;

  /// Processes [session] and its [annotations] using the configured AI engine
  /// and returns the raw JSON string conforming to the Myako schema.
  Future<String> processSession({
    required LectureSession session,
    required List<SessionAnnotation> annotations,
    String? courseName,
    void Function(String stepMessage)? onProgress,
  }) async {
    final audioFile = File(session.audioPath);
    if (session.audioPath.isEmpty || !await audioFile.exists()) {
      throw StateError('File audio rekaman tidak ditemukan di perangkat.');
    }

    final preferredEngine = await _keyStorage.getPreferredEngine();
    final geminiKey = (await _keyStorage.getGeminiApiKey())?.trim() ?? '';
    final groqKey = (await _keyStorage.getGroqApiKey())?.trim() ?? '';

    final useGroq =
        (preferredEngine == 'groq' && groqKey.isNotEmpty) ||
            (geminiKey.isEmpty && groqKey.isNotEmpty);

    if (useGroq) {
      return _processWithGroq(
        apiKey: groqKey,
        session: session,
        audioFile: audioFile,
        annotations: annotations,
        courseName: courseName,
        onProgress: onProgress,
      );
    }

    if (geminiKey.isEmpty) {
      throw StateError(
        'API Key Gemini belum diatur. Buka Pengaturan & Keamanan untuk mengisi API Key.',
      );
    }

    return _processWithGemini(
      apiKey: geminiKey,
      session: session,
      audioFile: audioFile,
      annotations: annotations,
      courseName: courseName,
      onProgress: onProgress,
    );
  }

  // ---------------------------------------------------------------------------
  // Google Gemini 2.5 Flash Multimodal Pipeline
  // ---------------------------------------------------------------------------

  Future<String> _processWithGemini({
    required String apiKey,
    required LectureSession session,
    required File audioFile,
    required List<SessionAnnotation> annotations,
    String? courseName,
    void Function(String stepMessage)? onProgress,
  }) async {
    String? remoteFileName;
    try {
      onProgress?.call('Mengunggah audio kuliah (streaming dari disk)...');
      final mimeType = _detectAudioMimeType(audioFile.path);
      final uploaded = await _uploadAudioViaGeminiFilesApi(
        apiKey: apiKey,
        audioFile: audioFile,
        mimeType: mimeType,
        displayName: 'myako_session_${session.id ?? 0}',
      );

      remoteFileName = uploaded.name;
      onProgress?.call('Menyiapkan audio di server Gemini...');
      final activeUri = await _waitForGeminiFileActive(
        apiKey: apiKey,
        fileName: uploaded.name,
        initialUri: uploaded.uri,
      );

      onProgress?.call('Menganalisis suara dosen, foto papan tulis & rangkuman...');
      final parts = await _buildGeminiParts(
        audioMimeType: mimeType,
        audioFileUri: activeUri,
        session: session,
        annotations: annotations,
        courseName: courseName,
      );

      final response = await _dio.post<Map<String, dynamic>>(
        '$_geminiBaseUrl/v1beta/models/gemini-2.5-flash:generateContent',
        options: Options(
          headers: {
            'x-goog-api-key': apiKey,
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
        data: {
          'contents': [
            {'role': 'user', 'parts': parts},
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'temperature': 0.2,
          },
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        final msg = _extractApiError(response.data) ??
            'Gemini merespons kode ${response.statusCode ?? '-'}';
        throw StateError(_sanitizeSecrets(msg, [apiKey]));
      }

      return _extractGeminiText(response.data!);
    } on DioException catch (e) {
      final serverMsg = _extractApiError(e.response?.data);
      throw StateError(
        _sanitizeSecrets(
          serverMsg ?? 'Koneksi ke Gemini terputus (${e.type.name}).',
          [apiKey],
        ),
      );
    } finally {
      if (remoteFileName != null && remoteFileName.isNotEmpty) {
        await _deleteGeminiRemoteFile(apiKey: apiKey, fileName: remoteFileName);
      }
    }
  }

  Future<({String name, String uri})> _uploadAudioViaGeminiFilesApi({
    required String apiKey,
    required File audioFile,
    required String mimeType,
    required String displayName,
  }) async {
    final fileLength = await audioFile.length();

    // 1. Initiate resumable upload session.
    final startResponse = await _dio.post<dynamic>(
      '$_geminiBaseUrl/upload/v1beta/files',
      options: Options(
        headers: {
          'x-goog-api-key': apiKey,
          'X-Goog-Upload-Protocol': 'resumable',
          'X-Goog-Upload-Command': 'start',
          'X-Goog-Upload-Header-Content-Length': fileLength.toString(),
          'X-Goog-Upload-Header-Content-Type': mimeType,
          'Content-Type': 'application/json',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
      data: {
        'file': {'display_name': displayName},
      },
    );

    if (startResponse.statusCode != 200) {
      throw StateError(
        _sanitizeSecrets(
          'Gagal memulai unggahan audio (HTTP ${startResponse.statusCode}).',
          [apiKey],
        ),
      );
    }

    final uploadUrl = startResponse.headers.value('x-goog-upload-url');
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw StateError('URL unggahan resumable Gemini tidak ditemukan.');
    }

    // 2. Stream bytes directly from disk without buffering entire file in RAM.
    final uploadResponse = await _dio.post<Map<String, dynamic>>(
      uploadUrl,
      options: Options(
        headers: {
          'Content-Length': fileLength.toString(),
          'X-Goog-Upload-Offset': '0',
          'X-Goog-Upload-Command': 'upload, finalize',
          'Content-Type': mimeType,
        },
        validateStatus: (status) => status != null && status < 500,
      ),
      data: audioFile.openRead(),
    );

    if (uploadResponse.statusCode != 200 || uploadResponse.data == null) {
      throw StateError(
        _sanitizeSecrets(
          'Gagal mengunggah file audio (HTTP ${uploadResponse.statusCode}).',
          [apiKey],
        ),
      );
    }

    final fileObj =
        uploadResponse.data!['file'] as Map<String, dynamic>? ?? const {};
    final name = fileObj['name'] as String? ?? '';
    final uri = fileObj['uri'] as String? ?? '';
    if (name.isEmpty || uri.isEmpty) {
      throw StateError('Metadata file Gemini tidak lengkap.');
    }
    return (name: name, uri: uri);
  }

  Future<String> _waitForGeminiFileActive({
    required String apiKey,
    required String fileName,
    required String initialUri,
  }) async {
    for (var attempt = 0; attempt < 24; attempt++) {
      final resp = await _dio.get<Map<String, dynamic>>(
        '$_geminiBaseUrl/v1beta/$fileName',
        options: Options(
          headers: {'x-goog-api-key': apiKey},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final data = resp.data;
      if (resp.statusCode == 200 && data != null) {
        final state = data['state'] as String? ?? '';
        final uri = data['uri'] as String? ?? initialUri;
        if (state == 'ACTIVE' || state.isEmpty) {
          return uri;
        }
        if (state == 'FAILED') {
          throw StateError('Pemrosesan file audio di server Gemini gagal.');
        }
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return initialUri;
  }

  Future<List<Map<String, dynamic>>> _buildGeminiParts({
    required String audioMimeType,
    required String audioFileUri,
    required LectureSession session,
    required List<SessionAnnotation> annotations,
    String? courseName,
  }) async {
    final parts = <Map<String, dynamic>>[
      {
        'text': _buildMultimodalPrompt(
          session: session,
          annotations: annotations,
          courseName: courseName,
        ),
      },
      {
        'file_data': {
          'mime_type': audioMimeType,
          'file_uri': audioFileUri,
        },
      },
    ];

    // Attach up to 6 compressed whiteboard photos (< 250 KB each) for Gemini Vision.
    final photos = annotations
        .where(
          (a) =>
              a.typeEnum == AnnotationType.photo &&
              a.imagePath != null &&
              a.imagePath!.isNotEmpty,
        )
        .take(6);

    for (final photo in photos) {
      final file = File(photo.imagePath!);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final timeLabel =
          LectureRecorderService.formatDurationMs(photo.timestampMs);
      parts.add({
        'text': 'Foto papan tulis / slide diambil pada menit $timeLabel:',
      });
      parts.add({
        'inline_data': {
          'mime_type': 'image/jpeg',
          'data': base64Encode(bytes),
        },
      });
    }

    return parts;
  }

  Future<void> _deleteGeminiRemoteFile({
    required String apiKey,
    required String fileName,
  }) async {
    try {
      await _dio.delete<void>(
        '$_geminiBaseUrl/v1beta/$fileName',
        options: Options(headers: {'x-goog-api-key': apiKey}),
      );
    } catch (_) {
      // Best-effort remote cleanup.
    }
  }

  // ---------------------------------------------------------------------------
  // Groq Fallback Pipeline (Whisper Large v3 Turbo + Llama 3.3 70B)
  // ---------------------------------------------------------------------------

  Future<String> _processWithGroq({
    required String apiKey,
    required LectureSession session,
    required File audioFile,
    required List<SessionAnnotation> annotations,
    String? courseName,
    void Function(String stepMessage)? onProgress,
  }) async {
    try {
      final sizeBytes = await audioFile.length();
      if (sizeBytes > 24 * 1024 * 1024) {
        throw StateError(
          'Ukuran file > 24 MB. Gunakan Gemini 2.5 Flash untuk audio kuliah berdurasi panjang.',
        );
      }

      onProgress?.call('Mentranskripsi audio lewat Groq Whisper...');
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          audioFile.path,
          filename: p.basename(audioFile.path),
        ),
        'model': 'whisper-large-v3-turbo',
        'response_format': 'verbose_json',
        'language': 'id',
      });

      final whisperResp = await _dio.post<Map<String, dynamic>>(
        '$_groqBaseUrl/audio/transcriptions',
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          validateStatus: (status) => status != null && status < 500,
        ),
        data: formData,
      );

      if (whisperResp.statusCode != 200 || whisperResp.data == null) {
        final msg = _extractApiError(whisperResp.data) ??
            'Groq Whisper merespons kode ${whisperResp.statusCode ?? '-'}';
        throw StateError(_sanitizeSecrets(msg, [apiKey]));
      }

      final rawSegments =
          whisperResp.data!['segments'] as List<dynamic>? ?? const [];
      final formattedTranscript = StringBuffer();
      for (final item in rawSegments) {
        if (item is Map<String, dynamic>) {
          final startMs = ((item['start'] as num?)?.toDouble() ?? 0) * 1000;
          final endMs = ((item['end'] as num?)?.toDouble() ?? 0) * 1000;
          final text = (item['text'] as String? ?? '').trim();
          if (text.isNotEmpty) {
            formattedTranscript.writeln(
              '[${startMs.round()}-${endMs.round()}] $text',
            );
          }
        }
      }
      if (formattedTranscript.isEmpty) {
        formattedTranscript.writeln(whisperResp.data!['text'] ?? '');
      }

      onProgress?.call('Menyusun rangkuman, flashcard & kuis lewat Groq...');
      final prompt = '''
${_buildMultimodalPrompt(session: session, annotations: annotations, courseName: courseName)}

Berikut hasil transkrip audio dengan rentang [start_ms-end_ms]:
${formattedTranscript.toString()}
''';

      final chatResp = await _dio.post<Map<String, dynamic>>(
        '$_groqBaseUrl/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
        data: {
          'model': 'llama-3.3-70b-versatile',
          'temperature': 0.2,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content':
                  'Kamu adalah asisten catatan kuliah Indonesia yang mengembalikan JSON valid saja.',
            },
            {'role': 'user', 'content': prompt},
          ],
        },
      );

      if (chatResp.statusCode != 200 || chatResp.data == null) {
        final msg = _extractApiError(chatResp.data) ??
            'Groq LLM merespons kode ${chatResp.statusCode ?? '-'}';
        throw StateError(_sanitizeSecrets(msg, [apiKey]));
      }

      final choices = chatResp.data!['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) {
        throw StateError('Groq tidak mengembalikan respons teks.');
      }
      final message =
          (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String? ?? '';
      if (content.trim().isEmpty) {
        throw StateError('Respons JSON Groq kosong.');
      }
      return content;
    } on DioException catch (e) {
      final serverMsg = _extractApiError(e.response?.data);
      throw StateError(
        _sanitizeSecrets(
          serverMsg ?? 'Koneksi ke Groq terputus (${e.type.name}).',
          [apiKey],
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Prompt & Helpers
  // ---------------------------------------------------------------------------

  String _buildMultimodalPrompt({
    required LectureSession session,
    required List<SessionAnnotation> annotations,
    String? courseName,
  }) {
    final notesBuffer = StringBuffer();
    for (final item in annotations) {
      if (item.typeEnum == AnnotationType.photo) continue;
      final time = LectureRecorderService.formatDurationMs(item.timestampMs);
      final prefix =
          item.typeEnum == AnnotationType.bookmark ? 'BOOKMARK' : 'CATATAN';
      notesBuffer.writeln('- [$time] ($prefix): ${item.contentText ?? ''}');
    }

    final manualContext = notesBuffer.isEmpty
        ? 'Tidak ada catatan ketik manual.'
        : notesBuffer.toString();

    return '''
Kamu adalah asisten catatan kuliah pintar untuk mahasiswa Indonesia.
Mata Kuliah: ${courseName ?? 'Umum'}
Judul Sesi: ${session.title}

KONTEKS BAHASA:
- Dosen mengajar dalam Bahasa Indonesia yang bercampur istilah teknis/akademik Bahasa Inggris (code-switching). Pertahankan ejaan istilah teknis Bahasa Inggris secara akurat (contoh: polymorphism, supply chain, cash flow, neural network, normalisasi).
- Gabungkan penjelasan lisan dari audio, isi teks/diagram/rumus dari foto papan tulis (jika dilampirkan), serta catatan manual mahasiswa di bawah ini.

CATATAN MANUAL & BOOKMARK MAHASISWA:
$manualContext

ATURAN OUTPUT:
Kembalikan HANYA 1 objek JSON valid (tanpa teks tambahan di luar JSON) dengan struktur persis berikut:
{
  "summary_tldr": "Ringkasan eksekutif 2-4 kalimat inti kuliah hari ini.",
  "summary_points": [
    "Poin utama 1 beserta penjelasan konsepnya",
    "Poin utama 2 beserta penjelasan konsepnya"
  ],
  "whiteboard_synthesis": "Penjelasan isi foto papan tulis/slide dan kaitannya dengan penjelasan dosen. Jika tidak ada foto papan tulis, tulis ringkasan visual/konsep kunci.",
  "glossary": [
    {"term": "Istilah Teknis", "definition": "Definisi ringkas dalam Bahasa Indonesia"}
  ],
  "action_items": [
    "Info tugas, deadline, atau kisi-kisi ujian yang disebut dosen (kosongkan array jika tidak ada)"
  ],
  "transcript_segments": [
    {"start_ms": 0, "end_ms": 30000, "text": "Transkrip rapi per segmen waktu (~30-60 detik atau per topik)."}
  ],
  "flashcards": [
    {"front": "Pertanyaan / istilah untuk dihafal", "back": "Jawaban ringkas dan jelas"}
  ],
  "quiz_questions": [
    {
      "question": "Soal pilihan ganda berbasis materi kuliah",
      "options": ["Opsi A", "Opsi B", "Opsi C", "Opsi D"],
      "correct_index": 0,
      "explanation": "Pembahasan singkat mengapa opsi tersebut benar."
    }
  ]
}
Pastikan menghasilkan minimal 5 flashcard dan 5 soal kuis jika materi audio mencukupi.
''';
  }

  String _extractGeminiText(Map<String, dynamic> body) {
    final candidates = body['candidates'] as List<dynamic>? ?? const [];
    if (candidates.isEmpty) {
      throw StateError('Gemini tidak mengembalikan kandidat respons.');
    }
    final content =
        (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>? ?? const [];
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map<String, dynamic> && part['text'] is String) {
        buffer.write(part['text'] as String);
      }
    }
    final result = buffer.toString().trim();
    if (result.isEmpty) {
      throw StateError('Respons teks dari Gemini kosong.');
    }
    return result;
  }

  String _detectAudioMimeType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return switch (ext) {
      '.mp3' => 'audio/mpeg',
      '.wav' => 'audio/wav',
      '.ogg' => 'audio/ogg',
      '.aac' => 'audio/aac',
      _ => 'audio/mp4',
    };
  }

  String? _extractApiError(dynamic data) {
    if (data is Map<String, dynamic>) {
      final err = data['error'];
      if (err is Map<String, dynamic> && err['message'] is String) {
        return err['message'] as String;
      }
      if (data['message'] is String) {
        return data['message'] as String;
      }
    }
    return null;
  }

  String _sanitizeSecrets(String message, List<String> secrets) {
    var sanitized = message;
    for (final secret in secrets) {
      if (secret.isNotEmpty) {
        sanitized = sanitized.replaceAll(secret, '[REDACTED]');
      }
    }
    return sanitized;
  }
}
