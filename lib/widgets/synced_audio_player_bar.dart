import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/lecture_recorder_service.dart';

/// Controller wrapping `just_audio`'s [AudioPlayer] with accurate timestamp seek
/// and playback speed control for lecture audio playback.
class SyncedAudioPlayerController extends ChangeNotifier {
  SyncedAudioPlayerController({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  static const List<double> speedOptions = [1.0, 1.25, 1.5, 2.0];

  final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  bool _isLoaded = false;
  bool _isPlaying = false;
  int _positionMs = 0;
  int _durationMs = 0;
  int _speedIndex = 0;
  String? _loadError;
  bool _disposed = false;

  bool get isLoaded => _isLoaded;
  bool get isPlaying => _isPlaying;
  int get positionMs => _positionMs;
  int get durationMs => _durationMs;
  double get playbackSpeed => speedOptions[_speedIndex];
  String? get loadError => _loadError;

  /// Loads [audioPath] from app-private storage into the player.
  Future<void> loadFile(String audioPath, {int fallbackDurationMs = 0}) async {
    if (_disposed) return;

    _durationMs = fallbackDurationMs > 0 ? fallbackDurationMs : 0;
    _loadError = null;
    _isLoaded = false;
    notifyListeners();

    if (audioPath.isEmpty || !await File(audioPath).exists()) {
      _loadError = 'File audio tidak ditemukan di penyimpanan perangkat.';
      notifyListeners();
      return;
    }

    try {
      _attachStreams();
      final detected = await _player.setFilePath(audioPath);
      if (_disposed) return;

      if (detected != null && detected.inMilliseconds > 0) {
        _durationMs = detected.inMilliseconds;
      }
      _isLoaded = true;
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      _loadError = 'Pemutar audio tidak dapat membuka format file ini.';
      notifyListeners();
    }
  }

  void _attachStreams() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();

    _stateSub = _player.playerStateStream.listen((state) {
      if (_disposed) return;
      if (state.processingState == ProcessingState.completed) {
        _isPlaying = false;
        _positionMs = _durationMs;
        _player.pause();
        _player.seek(Duration.zero);
        notifyListeners();
        return;
      }
      if (_isPlaying != state.playing) {
        _isPlaying = state.playing;
        notifyListeners();
      }
    });

    _positionSub = _player.positionStream.listen((pos) {
      if (_disposed) return;
      final ms = pos.inMilliseconds;
      if ((ms - _positionMs).abs() >= 200 || ms == 0) {
        _positionMs = ms;
        notifyListeners();
      }
    });

    _durationSub = _player.durationStream.listen((dur) {
      if (_disposed || dur == null) return;
      if (dur.inMilliseconds > 0 && dur.inMilliseconds != _durationMs) {
        _durationMs = dur.inMilliseconds;
        notifyListeners();
      }
    });
  }

  Future<void> togglePlayPause() async {
    if (!_isLoaded) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  /// Seeks directly to [targetMs] (used when tapping transcript segments or photos).
  Future<void> seekToMs(int targetMs, {bool autoPlay = true}) async {
    if (!_isLoaded) return;
    final maxMs = _durationMs > 0 ? _durationMs : targetMs;
    final clamped = targetMs.clamp(0, maxMs);
    _positionMs = clamped;
    notifyListeners();

    await _player.seek(Duration(milliseconds: clamped));
    if (autoPlay && !_isPlaying) {
      await _player.play();
    }
  }

  Future<void> skipRelativeMs(int deltaMs) async {
    await seekToMs(_positionMs + deltaMs, autoPlay: false);
  }

  Future<void> cycleSpeed() async {
    _speedIndex = (_speedIndex + 1) % speedOptions.length;
    final nextSpeed = speedOptions[_speedIndex];
    notifyListeners();
    if (_isLoaded) {
      await _player.setSpeed(nextSpeed);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}

/// Pinned bottom audio player widget synchronized with transcript and photos.
class SyncedAudioPlayerBar extends StatelessWidget {
  const SyncedAudioPlayerBar({
    super.key,
    required this.controller,
  });

  final SyncedAudioPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final durationMs = controller.durationMs;
        final positionMs =
            durationMs > 0 ? controller.positionMs.clamp(0, durationMs) : 0;

        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: controller.loadError != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.volume_off_outlined,
                          size: 18,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            controller.loadError!,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            LectureRecorderService.formatDurationMs(positionMs),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                              ),
                              child: Slider(
                                value: positionMs.toDouble(),
                                max: (durationMs > 0 ? durationMs : 1).toDouble(),
                                onChanged: controller.isLoaded
                                    ? (val) => controller.seekToMs(
                                          val.round(),
                                          autoPlay: false,
                                        )
                                    : null,
                              ),
                            ),
                          ),
                          Text(
                            LectureRecorderService.formatDurationMs(durationMs),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ActionChip(
                            label: Text(
                              '${controller.playbackSpeed}x',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: controller.isLoaded
                                ? controller.cycleSpeed
                                : null,
                          ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Mundur 10 detik',
                                icon: const Icon(Icons.replay_10),
                                onPressed: controller.isLoaded
                                    ? () => controller.skipRelativeMs(-10000)
                                    : null,
                              ),
                              FilledButton(
                                onPressed: controller.isLoaded
                                    ? controller.togglePlayPause
                                    : null,
                                style: FilledButton.styleFrom(
                                  shape: const CircleBorder(),
                                  padding: const EdgeInsets.all(10),
                                ),
                                child: Icon(
                                  controller.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Maju 10 detik',
                                icon: const Icon(Icons.forward_10),
                                onPressed: controller.isLoaded
                                    ? () => controller.skipRelativeMs(10000)
                                    : null,
                              ),
                            ],
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
