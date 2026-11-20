import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

@pragma('vm:entry-point')
void _myakoRecorderForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_RecorderTaskHandler());
}

class _RecorderTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Snapshot of the live classroom recorder state.
class RecorderStateSnapshot {
  const RecorderStateSnapshot({
    this.isRecording = false,
    this.isPaused = false,
    this.elapsedMs = 0,
    this.normalizedAmplitude = 0.0,
    this.outputPath,
  });

  final bool isRecording;
  final bool isPaused;
  final int elapsedMs;
  final double normalizedAmplitude;
  final String? outputPath;

  RecorderStateSnapshot copyWith({
    bool? isRecording,
    bool? isPaused,
    int? elapsedMs,
    double? normalizedAmplitude,
    String? outputPath,
  }) {
    return RecorderStateSnapshot(
      isRecording: isRecording ?? this.isRecording,
      isPaused: isPaused ?? this.isPaused,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      normalizedAmplitude: normalizedAmplitude ?? this.normalizedAmplitude,
      outputPath: outputPath ?? this.outputPath,
    );
  }
}

/// Output metadata returned when stopping a recording session.
class RecordingResult {
  const RecordingResult({
    required this.audioPath,
    required this.durationMs,
  });

  final String audioPath;
  final int durationMs;
}

/// Offline stream-to-disk AAC/M4A recorder backed by an Android Foreground
/// Service (`microphone`) so Android Go does not kill long classroom recordings.
class LectureRecorderService extends ChangeNotifier {
  LectureRecorderService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  /// AAC-LC 64 kbps @ 16 kHz Mono (~25–28 MB per hour of lecture speech).
  static const RecordConfig classroomRecordConfig = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 64000,
    sampleRate: 16000,
    numChannels: 1,
    autoGain: true,
    noiseSuppress: true,
  );

  final AudioRecorder _recorder;
  final Stopwatch _stopwatch = Stopwatch();

  Timer? _tickTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  RecorderStateSnapshot _snapshot = const RecorderStateSnapshot();
  String _activeTitle = 'Rekaman Kuliah';
  int _lastNotifiedSecond = -1;
  bool _foregroundInitialized = false;

  RecorderStateSnapshot get snapshot => _snapshot;
  bool get isRecording => _snapshot.isRecording;
  bool get isPaused => _snapshot.isPaused;
  int get elapsedMs => _stopwatch.elapsedMilliseconds;

  /// Checks and requests microphone (plus notification on Android 13+) permission.
  Future<bool> hasMicrophonePermission() async {
    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        return await _recorder.hasPermission();
      }
      // Best-effort notification permission for foreground recording status.
      try {
        await Permission.notification.request();
      } catch (_) {}
      return true;
    } catch (_) {
      return _recorder.hasPermission();
    }
  }

  /// Starts streaming AAC/M4A audio to app-private sandbox storage and launches
  /// the Android microphone foreground service.
  Future<String> startRecording({required String sessionTitle}) async {
    if (_snapshot.isRecording) {
      throw StateError('Perekaman sudah berjalan.');
    }

    final permitted = await hasMicrophonePermission();
    if (!permitted) {
      throw StateError('Izin mikrofon ditolak.');
    }

    _activeTitle =
        sessionTitle.trim().isEmpty ? 'Rekaman Kuliah' : sessionTitle.trim();

    final docsDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(p.join(docsDir.path, 'recordings'));
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }

    final outputPath = p.join(
      recordingsDir.path,
      'lecture_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );

    await _startForegroundService();

    await _recorder.start(classroomRecordConfig, path: outputPath);

    _stopwatch
      ..reset()
      ..start();
    _lastNotifiedSecond = -1;
    _snapshot = RecorderStateSnapshot(
      isRecording: true,
      isPaused: false,
      elapsedMs: 0,
      normalizedAmplitude: 0.0,
      outputPath: outputPath,
    );
    notifyListeners();

    _startTimers();
    return outputPath;
  }

  /// Pauses active recording while keeping the foreground notification visible.
  Future<void> pauseRecording() async {
    if (!_snapshot.isRecording || _snapshot.isPaused) return;
    await _recorder.pause();
    _stopwatch.stop();
    _snapshot = _snapshot.copyWith(
      isPaused: true,
      elapsedMs: _stopwatch.elapsedMilliseconds,
      normalizedAmplitude: 0.0,
    );
    notifyListeners();
    await _updateForegroundNotification(isPaused: true);
  }

  /// Resumes a paused recording session.
  Future<void> resumeRecording() async {
    if (!_snapshot.isRecording || !_snapshot.isPaused) return;
    await _recorder.resume();
    _stopwatch.start();
    _snapshot = _snapshot.copyWith(
      isPaused: false,
      elapsedMs: _stopwatch.elapsedMilliseconds,
    );
    notifyListeners();
    await _updateForegroundNotification(isPaused: false);
  }

  /// Stops recording, shuts down the foreground service, and returns the saved file.
  Future<RecordingResult?> stopRecording() async {
    if (!_snapshot.isRecording) return null;

    _stopTimers();
    _stopwatch.stop();
    final finalDuration = _stopwatch.elapsedMilliseconds;
    final expectedPath = _snapshot.outputPath;

    final stoppedPath = await _recorder.stop();
    await _stopForegroundService();

    final resolvedPath = (stoppedPath != null && stoppedPath.isNotEmpty)
        ? stoppedPath
        : (expectedPath ?? '');

    _snapshot = const RecorderStateSnapshot();
    notifyListeners();

    if (resolvedPath.isEmpty) return null;
    return RecordingResult(audioPath: resolvedPath, durationMs: finalDuration);
  }

  /// Discards the active recording and removes any partially written audio file.
  Future<void> cancelRecording() async {
    _stopTimers();
    _stopwatch
      ..stop()
      ..reset();

    final expectedPath = _snapshot.outputPath;
    try {
      await _recorder.cancel();
    } catch (_) {
      // Ignore if recorder wasn't active.
    }
    await _stopForegroundService();

    if (expectedPath != null && expectedPath.isNotEmpty) {
      try {
        final file = File(expectedPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    _snapshot = const RecorderStateSnapshot();
    notifyListeners();
  }

  void _startTimers() {
    _stopTimers();

    _tickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_snapshot.isRecording || _snapshot.isPaused) return;
      final ms = _stopwatch.elapsedMilliseconds;
      _snapshot = _snapshot.copyWith(elapsedMs: ms);
      notifyListeners();

      final currentSec = ms ~/ 1000;
      if (currentSec != _lastNotifiedSecond && currentSec % 5 == 0) {
        _lastNotifiedSecond = currentSec;
        _updateForegroundNotification(isPaused: false);
      }
    });

    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 160))
        .listen((amp) {
      if (!_snapshot.isRecording || _snapshot.isPaused) return;
      // Map dBFS (-55..0) into normalized [0.0..1.0].
      final normalized = ((amp.current + 55.0) / 55.0).clamp(0.05, 1.0);
      _snapshot = _snapshot.copyWith(normalizedAmplitude: normalized);
      notifyListeners();
    });
  }

  void _stopTimers() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  Future<void> _startForegroundService() async {
    try {
      if (!_foregroundInitialized) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'myako_lecture_recorder',
            channelName: 'Perekam Kuliah Myako',
            channelDescription:
                'Menjaga rekaman suara kuliah tetap aktif saat layar HP terkunci.',
            channelImportance: NotificationChannelImportance.LOW,
            priority: NotificationPriority.LOW,
            onlyAlertOnce: true,
          ),
          iosNotificationOptions: const IOSNotificationOptions(
            showNotification: false,
            playSound: false,
          ),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            autoRunOnBoot: false,
            allowWakeLock: true,
            allowWifiLock: false,
          ),
        );
        _foregroundInitialized = true;
      }

      if (await FlutterForegroundTask.isRunningService) {
        await _updateForegroundNotification(isPaused: false);
        return;
      }

      await FlutterForegroundTask.startService(
        serviceId: 2048,
        serviceTypes: const [ForegroundServiceTypes.microphone],
        notificationTitle: 'Merekam: $_activeTitle',
        notificationText: '00:00 • Offline hemat memori',
        callback: _myakoRecorderForegroundCallback,
      );
    } catch (_) {
      // Safe fallback when running on platforms/tests without Android foreground service.
    }
  }

  Future<void> _updateForegroundNotification({required bool isPaused}) async {
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      final formatted = formatDurationMs(_stopwatch.elapsedMilliseconds);
      await FlutterForegroundTask.updateService(
        notificationTitle: isPaused
            ? 'Dijeda: $_activeTitle'
            : 'Merekam: $_activeTitle',
        notificationText: isPaused
            ? '$formatted • Rekaman dijeda'
            : '$formatted • Offline hemat memori',
      );
    } catch (_) {}
  }

  Future<void> _stopForegroundService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  /// Formats milliseconds into `MM:SS` or `HH:MM:SS`.
  static String formatDurationMs(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 864000);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  void dispose() {
    _stopTimers();
    _recorder.dispose();
    super.dispose();
  }
}
