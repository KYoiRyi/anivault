import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:anivault/ui/cinematic_edge_bar.dart';
import 'package:anivault/ui/performance_hud.dart';
import 'package:anivault/services/shader_service.dart';
import 'package:anivault/services/logger_service.dart';

class PlayerScreen extends StatefulWidget {
  final String videoPath;
  final String title;

  const PlayerScreen({super.key, required this.videoPath, required this.title});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player = Player(
    configuration: const PlayerConfiguration(vo: 'gpu-next'),
  );
  late final VideoController controller = VideoController(player);
  // Swapped to Anime4K: ArtCNN uses Compute Shaders incompatible with media_kit's vo=libmpv D3D11 layer.
  // Anime4K uses standard fragment shaders, perfectly compatible with our SuperSampling frame buffer trick!
  bool _showControls = true;
  double _scale = 1.0;
  bool _isAnime4KEnabled = true;
  String _currentModelKey = 'Balanced';
  bool _showHUD = false;

  String _getDynamicShaderPath() {
    return ShaderService().getShaderPath(_currentModelKey) ?? '';
  }

  @override
  void initState() {
    super.initState();
    player.stream.log.listen((event) {
      LoggerService().log('[MPV] [${event.level}]: ${event.text}');
    });

    Future.microtask(() async {
      try {
        final nativePlayer = player.platform as NativePlayer;
        // MUST use 'auto-copy' so the hardware decoder transfers the CVPixelBuffer/d3d11 back to system RAM to allow Fragment Shaders to hook it!
        await nativePlayer.setProperty(
          'hwdec',
          _isAnime4KEnabled ? 'auto-copy' : 'auto',
        );
        await nativePlayer.setProperty(
          'glsl-shaders',
          _isAnime4KEnabled ? _getDynamicShaderPath() : '',
        );

        // Open provided video file
        await player.open(Media(widget.videoPath));
        player.play();
      } catch (e) {
        debugPrint('Media load error: $e');
      }
    });
  }

  Future<void> _applyAnime4KConfig() async {
    try {
      final nativePlayer = player.platform as NativePlayer;
      await nativePlayer.setProperty(
        'hwdec',
        _isAnime4KEnabled ? 'auto-copy' : 'auto',
      );
      await nativePlayer.setProperty(
        'glsl-shaders',
        _isAnime4KEnabled ? _getDynamicShaderPath() : '',
      );

      // Force dirty frame redraw if video is paused
      if (!player.state.playing) {
        player.seek(player.state.position);
      }
    } catch (e) {
      debugPrint('Error toggling Anime4K: $e');
    }
  }

  void _showVideoSettings() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.3), // gentle darkening
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
                    width: 440,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(
                        0x1A000000,
                      ), // Hex 1A = 10% opacity black
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              _currentModelKey == 'Extreme' && _isAnime4KEnabled
                              ? Colors.redAccent.withValues(alpha: 0.15)
                              : Colors.black12,
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
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
                        const SizedBox(height: 32),
                        // Master Toggle
                        SwitchListTile(
                          title: const Text(
                            'Anime4K upscaling',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: const Text(
                            'Sharper playback for anime video',
                          ),
                          value: _isAnime4KEnabled,
                          activeThumbColor: _currentModelKey == 'Extreme'
                              ? Colors.redAccent
                              : Theme.of(context).colorScheme.primary,
                          secondary: const Icon(Icons.auto_awesome),
                          onChanged: (val) {
                            setDialogState(() => _isAnime4KEnabled = val);
                            setState(() => _isAnime4KEnabled = val);
                            _applyAnime4KConfig();
                          },
                        ),
                        // Quality presets
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
                                    label: Text(
                                      'Speed',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: 'Balanced',
                                    label: Text(
                                      'Balanced',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: 'Quality',
                                    label: Text(
                                      'Quality',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: 'Extreme',
                                    label: Text(
                                      'Max',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                                selected: {_currentModelKey},
                                style: ButtonStyle(
                                  backgroundColor:
                                      WidgetStateProperty.resolveWith((states) {
                                        if (states.contains(
                                          WidgetState.selected,
                                        )) {
                                          return _currentModelKey == 'Extreme'
                                              ? Colors.redAccent.shade700
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.primary;
                                        }
                                        return Colors.transparent;
                                      }),
                                ),
                                onSelectionChanged: (Set<String> newSelection) {
                                  setDialogState(() {
                                    _currentModelKey = newSelection.first;
                                  });
                                  setState(() {
                                    _currentModelKey = newSelection.first;
                                  });
                                  _applyAnime4KConfig();
                                },
                              ),
                            ),
                          ),
                        ),
                        // HUD Toggle
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
    player.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. mpv Video Texture Layer
          Transform.scale(
            scale: _scale,
            child: Video(controller: controller, controls: NoVideoControls),
          ),

          // 2. Gesture Detector Layer
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
            onDoubleTap: () {
              final pos = player.state.position;
              player.seek(pos + const Duration(seconds: 10));
            },
            onScaleUpdate: (details) {
              setState(() {
                _scale = details.scale.clamp(1.0, 3.0);
              });
            },
            child: const SizedBox.expand(),
          ),

          // 3. Floating Floating Controls Island
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            opacity: _showControls ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Stack(
                children: [
                  // Top left back button & Title
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

                  // Center Right Floating Settings Pill
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
                              child: const Icon(
                                Icons.layers_rounded,
                                color: Colors.white70,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Center Play/Pause Floating Island
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

                  // 4. Cinematic Edge Bar (Edge-to-Edge)
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

          // 5. Performance HUD (Independent from controls but over video)
          if (_showHUD)
            Positioned(
              top: 100,
              left: 24,
              child: PerformanceHUD(player: player),
            ),
        ],
      ),
    );
  }
}
