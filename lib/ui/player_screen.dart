import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/shader_service.dart';
import 'package:anivault/ui/cinematic_edge_bar.dart';
import 'package:anivault/ui/performance_hud.dart';

enum MetalFXPreset { quality, balanced, performance }

class PlayerScreen extends StatefulWidget {
  final String videoPath;
  final String title;

  const PlayerScreen({super.key, required this.videoPath, required this.title});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<dynamic>? _logSubscription;

  bool _showControls = true;
  double _scale = 1.0;
  bool _isAnime4KEnabled = true;
  String _currentModelKey = 'Balanced';
  bool _showHUD = false;
  bool _useMetalFX = false;
  MetalFXPreset _metalFXPreset = MetalFXPreset.balanced;
  bool _isReconfiguring = false;
  String? _loadError;

  bool get _supportsMetalFX => Platform.isIOS || Platform.isMacOS;

  Player get _activePlayer => _player!;
  String _getDynamicShaderPath() {
    if (_useMetalFX) return '';
    return ShaderService().getShaderPath(_currentModelKey) ?? '';
  }

  double get _metalFXScale {
    switch (_metalFXPreset) {
      case MetalFXPreset.quality:
        return 0.77;
      case MetalFXPreset.balanced:
        return 0.67;
      case MetalFXPreset.performance:
        return 0.50;
    }
  }

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    _initializePlayback();
  }

  Future<void> _initializePlayback({
    Duration? resumePosition,
    bool autoplay = true,
  }) async {
    final previousPlayer = _player;
    final previousSubscription = _logSubscription;

    if (mounted) {
      setState(() {
        _loadError = null;
      });
    } else {
      _loadError = null;
    }

    final nextPlayer = Player(
      configuration: const PlayerConfiguration(vo: 'gpu-next'),
    );
    final nextController = VideoController(
      nextPlayer,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: !_useMetalFX,
        enableMetalFX: _useMetalFX,
        metalFXScale: _metalFXScale,
      ),
    );

    _logSubscription = nextPlayer.stream.log.listen((event) {
      LoggerService().log('[MPV] [${event.level}]: ${event.text}');
    });

    if (mounted) {
      setState(() {
        _player = nextPlayer;
        _controller = nextController;
      });
    } else {
      _player = nextPlayer;
      _controller = nextController;
    }

    try {
      await _applyVideoConfig(nextPlayer);
      await nextPlayer
          .open(Media(widget.videoPath))
          .timeout(const Duration(seconds: 20));
      if (resumePosition != null && resumePosition > Duration.zero) {
        await nextPlayer.seek(resumePosition);
      }
      if (autoplay) {
        nextPlayer.play();
      }
    } catch (e) {
      LoggerService().log('[Player ERROR] Failed to initialize playback: $e');
      debugPrint('Media load error: $e');
      if (mounted) {
        setState(() {
          _loadError = e.toString();
        });
      } else {
        _loadError = e.toString();
      }
    } finally {
      unawaited(previousSubscription?.cancel());
      unawaited(previousPlayer?.dispose());
    }
  }

  Future<void> _applyVideoConfig(Player targetPlayer) async {
    try {
      final nativePlayer = targetPlayer.platform as NativePlayer;
      final shaderPath = _getDynamicShaderPath();

      await nativePlayer.setProperty(
        'hwdec',
        _useMetalFX ? 'auto-copy' : (_isAnime4KEnabled ? 'auto-copy' : 'auto'),
      );
      await nativePlayer.setProperty('glsl-shaders', shaderPath);

      LoggerService().log(
        _useMetalFX
            ? '[MetalFX] enabled preset=${_metalFXPreset.name} scale=${_metalFXScale.toStringAsFixed(2)}'
            : '[Shader] Anime4K=${_isAnime4KEnabled ? _currentModelKey : 'off'}',
      );
    } catch (e) {
      LoggerService().log('[Player ERROR] Failed to apply video config: $e');
    }
  }

  Future<void> _reconfigurePlayback() async {
    if (_player == null || _isReconfiguring) return;
    setState(() => _isReconfiguring = true);
    final position = _activePlayer.state.position;
    final wasPlaying = _activePlayer.state.playing;
    try {
      await _initializePlayback(resumePosition: position, autoplay: wasPlaying);
    } finally {
      if (mounted) {
        setState(() => _isReconfiguring = false);
      } else {
        _isReconfiguring = false;
      }
    }
  }

  Future<void> _enterFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }

  Future<void> _applyAnime4KConfig() async {
    if (_player == null) return;
    await _applyVideoConfig(_activePlayer);
    if (!_activePlayer.state.playing) {
      _activePlayer.seek(_activePlayer.state.position);
    }
  }

  void _showVideoSettings() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.center,
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                  child: Container(
                    width: 460,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1A000000),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _useMetalFX
                              ? Colors.lightBlueAccent.withValues(alpha: 0.14)
                              : _currentModelKey == 'Extreme' &&
                                    _isAnime4KEnabled
                              ? Colors.redAccent.withValues(alpha: 0.15)
                              : Colors.black12,
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Video Enhancement',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_supportsMetalFX) ...[
                            SwitchListTile(
                              title: const Text(
                                'MetalFX upscale',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: const Text(
                                'Apple GPU spatial upscaling using MetalFX.',
                              ),
                              value: _useMetalFX,
                              activeThumbColor: Colors.lightBlueAccent,
                              secondary: const Icon(Icons.auto_fix_high),
                              onChanged: (value) async {
                                setDialogState(() => _useMetalFX = value);
                                setState(() {
                                  _useMetalFX = value;
                                  if (value) {
                                    _isAnime4KEnabled = false;
                                  }
                                });
                                await _reconfigurePlayback();
                              },
                            ),
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: _useMetalFX ? 1.0 : 0.35,
                              child: IgnorePointer(
                                ignoring: !_useMetalFX,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 8,
                                  ),
                                  child: SegmentedButton<MetalFXPreset>(
                                    showSelectedIcon: false,
                                    segments: const [
                                      ButtonSegment(
                                        value: MetalFXPreset.quality,
                                        label: Text('Quality'),
                                      ),
                                      ButtonSegment(
                                        value: MetalFXPreset.balanced,
                                        label: Text('Balanced'),
                                      ),
                                      ButtonSegment(
                                        value: MetalFXPreset.performance,
                                        label: Text('Performance'),
                                      ),
                                    ],
                                    selected: {_metalFXPreset},
                                    style: ButtonStyle(
                                      backgroundColor:
                                          WidgetStateProperty.resolveWith((
                                            states,
                                          ) {
                                            if (states.contains(
                                              WidgetState.selected,
                                            )) {
                                              return Colors.lightBlueAccent
                                                  .withValues(alpha: 0.35);
                                            }
                                            return Colors.transparent;
                                          }),
                                    ),
                                    onSelectionChanged: (values) async {
                                      final preset = values.first;
                                      setDialogState(
                                        () => _metalFXPreset = preset,
                                      );
                                      setState(() => _metalFXPreset = preset);
                                      await _reconfigurePlayback();
                                    },
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.lightBlueAccent.withValues(
                                  alpha: 0.08,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.lightBlueAccent.withValues(
                                    alpha: 0.18,
                                  ),
                                ),
                              ),
                              child: const Text(
                                'MetalFX uses a lower internal render size and upscales it on Apple GPUs. It is available only on supported Apple OS and hardware.',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ],
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _useMetalFX ? 0.35 : 1.0,
                            child: IgnorePointer(
                              ignoring: _useMetalFX,
                              child: Column(
                                children: [
                                  SwitchListTile(
                                    title: const Text(
                                      'Anime4K upscaling',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _useMetalFX
                                          ? 'Disabled while MetalFX is active.'
                                          : 'Sharper playback for anime video',
                                    ),
                                    value: _isAnime4KEnabled,
                                    activeThumbColor:
                                        _currentModelKey == 'Extreme'
                                        ? Colors.redAccent
                                        : Theme.of(context).colorScheme.primary,
                                    secondary: const Icon(Icons.auto_awesome),
                                    onChanged: (val) async {
                                      setDialogState(
                                        () => _isAnime4KEnabled = val,
                                      );
                                      setState(() => _isAnime4KEnabled = val);
                                      await _applyAnime4KConfig();
                                    },
                                  ),
                                  AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: _isAnime4KEnabled ? 1.0 : 0.3,
                                    child: IgnorePointer(
                                      ignoring: !_isAnime4KEnabled,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 24,
                                          horizontal: 8,
                                        ),
                                        child: SegmentedButton<String>(
                                          showSelectedIcon: false,
                                          segments: const [
                                            ButtonSegment(
                                              value: 'Speed',
                                              label: Text('Speed'),
                                            ),
                                            ButtonSegment(
                                              value: 'Balanced',
                                              label: Text('Balanced'),
                                            ),
                                            ButtonSegment(
                                              value: 'Quality',
                                              label: Text('Quality'),
                                            ),
                                            ButtonSegment(
                                              value: 'Extreme',
                                              label: Text('Max'),
                                            ),
                                          ],
                                          selected: {_currentModelKey},
                                          style: ButtonStyle(
                                            backgroundColor:
                                                WidgetStateProperty.resolveWith(
                                                  (states) {
                                                    if (states.contains(
                                                      WidgetState.selected,
                                                    )) {
                                                      return _currentModelKey ==
                                                              'Extreme'
                                                          ? Colors
                                                                .redAccent
                                                                .shade700
                                                          : Theme.of(context)
                                                                .colorScheme
                                                                .primary;
                                                    }
                                                    return Colors.transparent;
                                                  },
                                                ),
                                          ),
                                          onSelectionChanged:
                                              (newSelection) async {
                                                setDialogState(() {
                                                  _currentModelKey =
                                                      newSelection.first;
                                                });
                                                setState(() {
                                                  _currentModelKey =
                                                      newSelection.first;
                                                });
                                                await _applyAnime4KConfig();
                                              },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SwitchListTile(
                            title: const Text(
                              'Performance overlay',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: const Text('Show playback stats'),
                            value: _showHUD,
                            activeThumbColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            secondary: const Icon(Icons.memory_rounded),
                            onChanged: (val) {
                              setDialogState(() => _showHUD = val);
                              setState(() => _showHUD = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutBack,
          ).value,
          child: Opacity(opacity: anim1.value, child: child),
        );
      },
    );
  }

  @override
  void dispose() {
    _exitFullscreen();
    _logSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final controller = _controller;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (player == null || controller == null)
            Center(
              child: _loadError == null
                  ? const CircularProgressIndicator()
                  : _PlayerError(
                      message: _loadError!,
                      onRetry: () => _initializePlayback(autoplay: true),
                    ),
            )
          else
            Transform.scale(
              scale: _scale,
              child: Video(controller: controller, controls: NoVideoControls),
            ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
            onDoubleTap: () {
              final active = _player;
              if (active == null) return;
              final pos = active.state.position;
              active.seek(pos + const Duration(seconds: 10));
            },
            onScaleUpdate: (details) {
              setState(() {
                _scale = details.scale.clamp(1.0, 3.0);
              });
            },
            child: const SizedBox.expand(),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            opacity: _showControls ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Stack(
                children: [
                  Positioned(
                    top: 40,
                    left: 24,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: InkWell(
                            onTap: _showVideoSettings,
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 48,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Icon(
                                _useMetalFX
                                    ? Icons.auto_fix_high
                                    : Icons.layers_rounded,
                                color: Colors.white70,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (player != null)
                    Align(
                      alignment: Alignment.center,
                      child: StreamBuilder<bool>(
                        stream: player.stream.playing,
                        builder: (context, playing) {
                          final isPlaying = playing.data ?? false;
                          return FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.all(24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.8),
                            ),
                            onPressed: () => player.playOrPause(),
                            child: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 64,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          );
                        },
                      ),
                    ),
                  if (player != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        top: false,
                        child: CinematicEdgeBar(player: player),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_showHUD && player != null)
            Positioned(
              top: 100,
              left: 24,
              child: PerformanceHUD(player: player),
            ),
          if (_isReconfiguring)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.24),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayerError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _PlayerError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            'Playback failed to initialize.',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
