import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Result of verifying an AI provider API key over HTTPS.
class ApiVerifyResult {
  const ApiVerifyResult({required this.isValid, required this.message});

  final bool isValid;
  final String message;
}

/// Encrypted on-device storage for API keys and security-sensitive preferences
/// backed by Android Keystore (`flutter_secure_storage`).
class SecureKeyStorage {
  SecureKeyStorage({
    FlutterSecureStorage? storage,
    Dio? dio,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: true,
                migrateWithBackup: false,
              ),
            ),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
              ),
            );

  static const String _geminiKeyStorageKey = 'myako_gemini_api_key';
  static const String _groqKeyStorageKey = 'myako_groq_api_key';
  static const String _preferredEngineKey = 'myako_preferred_ai_engine';
  static const String _themeModeKey = 'myako_theme_mode';

  final FlutterSecureStorage _storage;
  final Dio _dio;

  // ---------------------------------------------------------------------------
  // API Key Read / Write / Delete
  // ---------------------------------------------------------------------------

  Future<String?> getGeminiApiKey() => _storage.read(key: _geminiKeyStorageKey);

  Future<void> saveGeminiApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await deleteGeminiApiKey();
      return;
    }
    await _storage.write(key: _geminiKeyStorageKey, value: trimmed);
  }

  Future<void> deleteGeminiApiKey() =>
      _storage.delete(key: _geminiKeyStorageKey);

  Future<String?> getGroqApiKey() => _storage.read(key: _groqKeyStorageKey);

  Future<void> saveGroqApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await deleteGroqApiKey();
      return;
    }
    await _storage.write(key: _groqKeyStorageKey, value: trimmed);
  }

  Future<void> deleteGroqApiKey() => _storage.delete(key: _groqKeyStorageKey);

  Future<String> getPreferredEngine() async {
    final value = await _storage.read(key: _preferredEngineKey);
    return value == 'groq' ? 'groq' : 'gemini';
  }

  Future<void> savePreferredEngine(String engine) async {
    final normalized = engine == 'groq' ? 'groq' : 'gemini';
    await _storage.write(key: _preferredEngineKey, value: normalized);
  }

  Future<String?> getSavedThemeMode() => _storage.read(key: _themeModeKey);

  Future<void> saveThemeMode(String mode) =>
      _storage.write(key: _themeModeKey, value: mode);

  /// Masks an API key for safe display in the UI (e.g., `AIza••••••9XyZ`).
  static String maskApiKey(String? rawKey) {
    if (rawKey == null || rawKey.trim().isEmpty) return '';
    final key = rawKey.trim();
    if (key.length <= 8) {
      return '••••••••';
    }
    final prefix = key.substring(0, 4);
    final suffix = key.substring(key.length - 4);
    return '$prefix••••••$suffix';
  }

  // ---------------------------------------------------------------------------
  // HTTPS Key Verification (API key passed strictly via HTTP headers)
  // ---------------------------------------------------------------------------

  /// Validates a Google Gemini API key via HTTPS header `x-goog-api-key`
  /// without ever putting the secret in URL query strings or error logs.
  Future<ApiVerifyResult> verifyGeminiApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      return const ApiVerifyResult(
        isValid: false,
        message: 'API Key Gemini belum diisi.',
      );
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://generativelanguage.googleapis.com/v1beta/models',
        options: Options(
          headers: {'x-goog-api-key': trimmed},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        return const ApiVerifyResult(
          isValid: true,
          message: 'Koneksi Gemini API berhasil terverifikasi (HTTPS).',
        );
      }

      if (response.statusCode == 400 ||
          response.statusCode == 401 ||
          response.statusCode == 403) {
        return const ApiVerifyResult(
          isValid: false,
          message: 'API Key Gemini tidak valid atau akses ditolak.',
        );
      }

      return ApiVerifyResult(
        isValid: false,
        message: 'Server Gemini merespons kode ${response.statusCode ?? '-'}.',
      );
    } on DioException catch (e) {
      return ApiVerifyResult(
        isValid: false,
        message: _sanitizeError(
          'Gagal menghubungi server Gemini (${e.type.name}). Periksa koneksi internet.',
          trimmed,
        ),
      );
    } catch (_) {
      return const ApiVerifyResult(
        isValid: false,
        message: 'Terjadi kesalahan saat menguji koneksi Gemini API.',
      );
    }
  }

  /// Validates a Groq API key via HTTPS Bearer header.
  Future<ApiVerifyResult> verifyGroqApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      return const ApiVerifyResult(
        isValid: false,
        message: 'API Key Groq belum diisi.',
      );
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.groq.com/openai/v1/models',
        options: Options(
          headers: {'Authorization': 'Bearer $trimmed'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        return const ApiVerifyResult(
          isValid: true,
          message: 'Koneksi Groq API berhasil terverifikasi (HTTPS).',
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const ApiVerifyResult(
          isValid: false,
          message: 'API Key Groq tidak valid atau ditolak.',
        );
      }

      return ApiVerifyResult(
        isValid: false,
        message: 'Server Groq merespons kode ${response.statusCode ?? '-'}.',
      );
    } on DioException catch (e) {
      return ApiVerifyResult(
        isValid: false,
        message: _sanitizeError(
          'Gagal menghubungi server Groq (${e.type.name}). Periksa koneksi internet.',
          trimmed,
        ),
      );
    } catch (_) {
      return const ApiVerifyResult(
        isValid: false,
        message: 'Terjadi kesalahan saat menguji koneksi Groq API.',
      );
    }
  }

  String _sanitizeError(String message, String secret) {
    if (secret.isEmpty) return message;
    return message.replaceAll(secret, '[REDACTED]');
  }
}
