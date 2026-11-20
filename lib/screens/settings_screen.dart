import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/security/secure_key_storage.dart';
import '../providers/app_providers.dart';

/// Settings screen for API key encryption, theme toggle, and Redmi A2 optimization.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _geminiController = TextEditingController();
  final _groqController = TextEditingController();

  bool _obscureGemini = true;
  bool _obscureGroq = true;
  bool _isTestingGemini = false;
  bool _isTestingGroq = false;
  ApiVerifyResult? _geminiVerifyResult;
  ApiVerifyResult? _groqVerifyResult;
  bool? _isBatteryUnrestricted;

  @override
  void initState() {
    super.initState();
    _checkBatteryOptimizationStatus();
  }

  @override
  void dispose() {
    _geminiController.dispose();
    _groqController.dispose();
    super.dispose();
  }

  Future<void> _checkBatteryOptimizationStatus() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (mounted) {
        setState(() => _isBatteryUnrestricted = status.isGranted);
      }
    } catch (_) {
      // Ignored on platforms without Android battery optimization APIs.
    }
  }

  Future<void> _requestBatteryUnrestricted() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      if (!mounted) return;
      setState(() => _isBatteryUnrestricted = status.isGranted);
      if (!status.isGranted) {
        _showSnack(
          'Buka Pengaturan HP > Baterai > Myako > Pilih "Tidak dibatasi" agar rekaman tidak mati saat layar terkunci.',
        );
      }
    } catch (_) {
      _showSnack(
        'Atur izin baterai secara manual di Pengaturan Android > Aplikasi > Myako.',
      );
    }
  }

  Future<void> _saveKey({
    required bool isGemini,
    required TextEditingController controller,
  }) async {
    final text = controller.text.trim();
    if (text.isEmpty) {
      _showSnack('Masukkan API Key terlebih dahulu.');
      return;
    }
    final notifier = ref.read(apiKeyConfigProvider.notifier);
    if (isGemini) {
      await notifier.saveGeminiKey(text);
    } else {
      await notifier.saveGroqKey(text);
    }
    controller.clear();
    if (mounted) {
      _showSnack(
        isGemini
            ? 'API Key Gemini disimpan terenkripsi di Android Keystore.'
            : 'API Key Groq disimpan terenkripsi di Android Keystore.',
      );
    }
  }

  Future<void> _deleteKey({required bool isGemini}) async {
    final notifier = ref.read(apiKeyConfigProvider.notifier);
    if (isGemini) {
      await notifier.deleteGeminiKey();
      setState(() => _geminiVerifyResult = null);
    } else {
      await notifier.deleteGroqKey();
      setState(() => _groqVerifyResult = null);
    }
    if (mounted) {
      _showSnack(
        isGemini ? 'API Key Gemini dihapus.' : 'API Key Groq dihapus.',
      );
    }
  }

  Future<void> _testApiKey({required bool isGemini}) async {
    final storage = ref.read(secureKeyStorageProvider);
    final typed =
        (isGemini ? _geminiController.text : _groqController.text).trim();
    final keyToTest = typed.isNotEmpty
        ? typed
        : (isGemini
                ? await storage.getGeminiApiKey()
                : await storage.getGroqApiKey()) ??
            '';

    if (!mounted) return;
    setState(() {
      if (isGemini) {
        _isTestingGemini = true;
      } else {
        _isTestingGroq = true;
      }
    });

    final result = isGemini
        ? await storage.verifyGeminiApiKey(keyToTest)
        : await storage.verifyGroqApiKey(keyToTest);

    if (!mounted) return;
    setState(() {
      if (isGemini) {
        _isTestingGemini = false;
        _geminiVerifyResult = result;
      } else {
        _isTestingGroq = false;
        _groqVerifyResult = result;
      }
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final apiConfigAsync = ref.watch(apiKeyConfigProvider);
    final storageAsync = ref.watch(storageUsageBytesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan & Keamanan'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSecurityOverviewCard(colorScheme),
          const SizedBox(height: 16),
          apiConfigAsync.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (err, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Gagal memuat konfigurasi kunci: $err'),
              ),
            ),
            data: (config) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEngineSelectorCard(config, colorScheme),
                const SizedBox(height: 16),
                _buildApiKeyCard(
                  title: 'Google Gemini API Key (Utama)',
                  subtitle:
                      'Dipakai untuk transkripsi multimodal, analisis foto papan tulis, rangkuman, kuis, dan semantic search.',
                  hasStoredKey: config.hasGeminiKey,
                  maskedKey: config.maskedGeminiKey,
                  hintText: 'Tempel Gemini API Key (AQ... / AIza...)',
                  controller: _geminiController,
                  obscureText: _obscureGemini,
                  isTesting: _isTestingGemini,
                  verifyResult: _geminiVerifyResult,
                  onToggleObscure: () =>
                      setState(() => _obscureGemini = !_obscureGemini),
                  onSave: () =>
                      _saveKey(isGemini: true, controller: _geminiController),
                  onDelete: () => _deleteKey(isGemini: true),
                  onTest: () => _testApiKey(isGemini: true),
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 16),
                _buildApiKeyCard(
                  title: 'Groq API Key (Opsional)',
                  subtitle:
                      'Alternatif cepat untuk transkripsi Whisper + ringkasan teks.',
                  hasStoredKey: config.hasGroqKey,
                  maskedKey: config.maskedGroqKey,
                  hintText: 'Tempel Groq API Key (gsk_...)',
                  controller: _groqController,
                  obscureText: _obscureGroq,
                  isTesting: _isTestingGroq,
                  verifyResult: _groqVerifyResult,
                  onToggleObscure: () =>
                      setState(() => _obscureGroq = !_obscureGroq),
                  onSave: () =>
                      _saveKey(isGemini: false, controller: _groqController),
                  onDelete: () => _deleteKey(isGemini: false),
                  onTest: () => _testApiKey(isGemini: false),
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              title: const Text('Mode Gelap (Dark Mode)'),
              subtitle: const Text(
                'Disarankan untuk Redmi A2 agar hemat baterai dan tidak menyilaukan di kelas.',
              ),
              secondary: Icon(
                themeMode == ThemeMode.dark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
              ),
              value: themeMode == ThemeMode.dark,
              onChanged: (value) =>
                  ref.read(themeModeProvider.notifier).setDarkMode(value),
            ),
          ),
          const SizedBox(height: 16),
          _buildRedmiOptimizationCard(storageAsync, colorScheme),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSecurityOverviewCard(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_user_outlined, color: colorScheme.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Perlindungan Data Lokal & API Key',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• API Key dienkripsi memakai Android Keystore.\n'
                    '• Rekaman audio, foto, dan SQLite tersimpan di sandbox privat aplikasi.\n'
                    '• Backup cloud otomatis & traffic HTTP tanpa enkripsi (cleartext) dinonaktifkan.',
                    style: TextStyle(fontSize: 13, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineSelectorCard(
    ApiKeyConfigState config,
    ColorScheme colorScheme,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mesin AI Pilihan',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'gemini',
                  label: Text('Gemini 3.8 Flash'),
                  icon: Icon(Icons.auto_awesome),
                ),
                ButtonSegment(
                  value: 'groq',
                  label: Text('Groq API'),
                  icon: Icon(Icons.bolt),
                ),
              ],
              selected: {config.preferredEngine},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  ref
                      .read(apiKeyConfigProvider.notifier)
                      .setPreferredEngine(selection.first);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeyCard({
    required String title,
    required String subtitle,
    required bool hasStoredKey,
    required String maskedKey,
    required String hintText,
    required TextEditingController controller,
    required bool obscureText,
    required bool isTesting,
    required ApiVerifyResult? verifyResult,
    required VoidCallback onToggleObscure,
    required VoidCallback onSave,
    required VoidCallback onDelete,
    required VoidCallback onTest,
    required ColorScheme colorScheme,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasStoredKey
                        ? colorScheme.primary.withValues(alpha: 0.16)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hasStoredKey ? 'Tersimpan' : 'Belum Diisi',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: hasStoredKey
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (hasStoredKey) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.vpn_key_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Kunci aktif: $maskedKey',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: obscureText,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: hintText,
                suffixIcon: IconButton(
                  tooltip: obscureText ? 'Tampilkan' : 'Sembunyikan',
                  icon: Icon(
                    obscureText
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan'),
                ),
                OutlinedButton.icon(
                  onPressed: isTesting ? null : onTest,
                  icon: isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Tes Koneksi'),
                ),
                if (hasStoredKey)
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: colorScheme.error,
                    ),
                    label: Text(
                      'Hapus',
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
              ],
            ),
            if (verifyResult != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: verifyResult.isValid
                      ? colorScheme.primary.withValues(alpha: 0.14)
                      : colorScheme.error.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      verifyResult.isValid
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 18,
                      color: verifyResult.isValid
                          ? colorScheme.primary
                          : colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        verifyResult.message,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRedmiOptimizationCard(
    AsyncValue<int> storageAsync,
    ColorScheme colorScheme,
  ) {
    final unrestricted = _isBatteryUnrestricted ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Optimasi Redmi A2 (Android Go)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.sd_storage_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: storageAsync.when(
                    data: (bytes) => Text(
                      'Pemakaian penyimpanan lokal: ${_formatBytes(bytes)}',
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    loading: () => const Text('Menghitung penyimpanan...'),
                    error: (_, _) =>
                        const Text('Tidak dapat membaca ukuran penyimpanan.'),
                  ),
                ),
                IconButton(
                  tooltip: 'Muat ulang',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => ref.invalidate(storageUsageBytesProvider),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  unrestricted
                      ? Icons.battery_charging_full
                      : Icons.battery_alert_outlined,
                  size: 20,
                  color: unrestricted ? colorScheme.primary : Colors.amber,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        unrestricted
                            ? 'Baterai Tidak Dibatasi (Siap Rekam Lama)'
                            : 'Izinkan Jalan di Latar Belakang',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mencegah Android Go menghentikan rekaman suara saat layar HP dimatikan di meja kelas.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _requestBatteryUnrestricted,
                        child: Text(
                          unrestricted
                              ? 'Cek Status Izin Baterai'
                              : 'Aktifkan Baterai Tanpa Batas',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.memory_outlined, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Kosongkan cache gambar dari RAM bila HP terasa penuh.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    PaintingBinding.instance.imageCache.clear();
                    PaintingBinding.instance.imageCache.clearLiveImages();
                    _showSnack('Cache gambar di RAM berhasil dibersihkan.');
                  },
                  child: const Text('Bersihkan Cache RAM'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
