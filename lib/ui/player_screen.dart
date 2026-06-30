import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:anivault/ui/cinematic_edge_bar.dart';
import 'package:anivault/ui/performance_hud.dart';
import 'package:anivault/services/shader_service.dart';
import 'package:anivault/services/ffi_engine.dart';
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
  late VideoController controller;
  // Swapped to Anime4K: ArtCNN uses Compute Shaders incompatible with media_kit's vo=libmpv D3D11 layer.
  // Anime4K uses standard fragment shaders, perfectly compatible with our SuperSampling frame buffer trick!
  bool _showControls = true;
  double _scale = 1.0;
  bool _isEnhancementEnabled = true;
  String _currentEngine = 'Anime4K';
  String _currentModelKey = 'Balanced';
  bool _isHwAccelerated = true;
  bool _showHUD = false;

  String _getDynamicShaderPath() {
    return ShaderService().getShaderPath(_currentModelKey) ?? '';
  }

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    controller = VideoController(player); // Default creates HW accelerated controller
    _isHwAccelerated = true;
    player.stream.log.listen((event) {
      LoggerService().log('[MPV] [${event.level}]: ${event.text}');
    });

    Future.microtask(() async {
      try {
        final nativePlayer = player.platform as NativePlayer;
        
        // --- Windows Native Hang Prevention ---
        // Disable youtube-dl hook which causes "ytdl_hook: scraping" to block endlessly on some SMB streams.
        await nativePlayer.setProperty('ytdl', 'no');
        // Impose a strict native network timeout to gracefully fail rather than deadlocking the Windows C++ loop.
        await nativePlayer.setProperty('network-timeout', '10');

        // MUST use 'auto-copy' so the hardware decoder transfers the CVPixelBuffer/d3d11 back to system RAM to allow Fragment Shaders to hook it!
        await nativePlayer.setProperty(
          'hwdec',
          _isEnhancementEnabled ? 'auto-copy' : 'auto',
        );
        await nativePlayer.setProperty(
          'glsl-shaders',
          _isEnhancementEnabled && _currentEngine == 'Anime4K' ? _getDynamicShaderPath() : '',
        );

        // Open provided video file with Dart UI timeout feedback
        try {
          await player.open(Media(widget.videoPath)).timeout(
            const Duration(seconds: 12),
          );
          player.play();
        } on TimeoutException {
          LoggerService().log('[Player Error] Timed out waiting for media info.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to load video: Network timed out.')),
            );
            Navigator.of(context).pop();
          }
        }
      } catch (e) {
        debugPrint('Media load error: $e');
      }
    });
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

  Future<void> _applyEnhancementConfig() async {
    try {
      final nativePlayer = player.platform as NativePlayer;

      if (_currentEngine == 'Anime4K') {
        // Disable ArtCNN native C++ hook globally
        FFIEngine().setPipelineHookEnabled(false);
        
        // Ensure Hardware Acceleration is enabled for Native GLSL GPU-Next
        if (!_isHwAccelerated) {
          controller = VideoController(player, configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true));
          _isHwAccelerated = true;
        }
        
        await nativePlayer.setProperty(
          'hwdec',
          _isEnhancementEnabled ? 'auto-copy' : 'auto',
        );
        await nativePlayer.setProperty(
          'glsl-shaders',
          _isEnhancementEnabled ? _getDynamicShaderPath() : '',
        );
      } else if (_currentEngine == 'ArtCNN') {
        await nativePlayer.setProperty('glsl-shaders', '');
        
        if (_isEnhancementEnabled) {
          final artCnnModelPath = ShaderService().artCnnPath;
          
          // Recreate VideoController and FORCE Software rendering to allow Memory interop for the C++ Native Hook!
          if (_isHwAccelerated) {
            controller = VideoController(player, configuration: const VideoControllerConfiguration(enableHardwareAcceleration: false));
            _isHwAccelerated = false;
          }

          // Initialize ONNX CoreML/DirectML Session in Native Rust Core concurrently
          FFIEngine().initializeArtCNN(artCnnModelPath);

          // Enable C++ pipeline hook in media_kit_video
          FFIEngine().setPipelineHookEnabled(true);
        } else {
          FFIEngine().setPipelineHookEnabled(false);
          // Restore HW acceleration if enhancement is fully turned off
          if (!_isHwAccelerated) {
            controller = VideoController(player, configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true));
            _isHwAccelerated = true;
          }
          await nativePlayer.setProperty('hwdec', 'auto');
        }
      }

      // Force dirty frame redraw if video is paused
      if (!player.state.playing) {
        player.seek(player.state.position);
      }
    } catch (e) {
      debugPrint('Error toggling enhancement: $e');
    }
  }

    void _showVideoSettings() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.center,
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                return SizedBox(
                  width: 440,
                  child: GlassCard(
                    useOwnLayer: true,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    shape: const LiquidRoundedSuperellipse(borderRadius: 24),
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
                        const SizedBox(height: 28),
                        // Master Toggle Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Video Enhancement',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'AI Neural Network Upscaling Engine',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                            GlassSwitch(
                              useOwnLayer: true,
                              value: _isEnhancementEnabled,
                              onChanged: (val) {
                                setDialogState(() => _isEnhancementEnabled = val);
                                setState(() => _isEnhancementEnabled = val);
                                _applyEnhancementConfig();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Engine Selection Toggle
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _isEnhancementEnabled ? 1.0 : 0.3,
                          child: IgnorePointer(
                            ignoring: !_isEnhancementEnabled,
                            child: GlassSegmentedControl(
                              useOwnLayer: true,
                              segments: const [
                                GlassSegment(
                                  label: 'Anime4K',
                                  icon: Icon(Icons.bolt_rounded, size: 16),
                                ),
                                GlassSegment(
                                  label: 'ArtCNN',
                                  icon: Icon(Icons.memory_rounded, size: 16),
                                ),
                              ],
                              selectedIndex: _currentEngine == 'Anime4K' ? 0 : 1,
                              onSegmentSelected: (index) {
                                final engine = index == 0 ? 'Anime4K' : 'ArtCNN';
                                setDialogState(() => _currentEngine = engine);
                                setState(() => _currentEngine = engine);
                                _applyEnhancementConfig();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Quality presets
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _isEnhancementEnabled && _currentEngine == 'Anime4K' ? 1.0 : 0.3,
                          child: IgnorePointer(
                            ignoring: !_isEnhancementEnabled || _currentEngine != 'Anime4K',
                            child: GlassSegmentedControl(
                              useOwnLayer: true,
                              segments: const [
                                GlassSegment(label: 'Speed'),
                                GlassSegment(label: 'Balanced'),
                                GlassSegment(label: 'Quality'),
                                GlassSegment(label: 'Max'),
                              ],
                              selectedIndex: switch (_currentModelKey) {
                                'Speed' => 0,
                                'Balanced' => 1,
                                'Quality' => 2,
                                'Extreme' => 3,
                                _ => 1,
                              },
                              onSegmentSelected: (index) {
                                final modelKey = switch (index) {
                                  0 => 'Speed',
                                  1 => 'Balanced',
                                  2 => 'Quality',
                                  3 => 'Extreme',
                                  _ => 'Balanced',
                                };
                                setDialogState(() => _currentModelKey = modelKey);
                                setState(() => _currentModelKey = modelKey);
                                _applyEnhancementConfig();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // HUD Toggle Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Performance overlay',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Show playback stats',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                            GlassSwitch(
                              useOwnLayer: true,
                              value: _showHUD,
                              onChanged: (val) {
                                setDialogState(() => _showHUD = val);
                                setState(() => _showHUD = val);
                              },
                            ),
                          ],
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
    _exitFullscreen();
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
                      child: GlassCard(
                        useOwnLayer: true,
                        padding: EdgeInsets.zero,
                        shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                        child: InkWell(
                          onTap: _showVideoSettings,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 48,
                            ),
                            child: const Icon(
                              Icons.layers_rounded,
                              color: Colors.white,
                              size: 28,
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
                        return GlassButton(
                          shape: const LiquidRoundedSuperellipse(borderRadius: 36),
                          padding: const EdgeInsets.all(24),
                          onTap: () => player.playOrPause(),
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 64,
                            color: Colors.white,
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
