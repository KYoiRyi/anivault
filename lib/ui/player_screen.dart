import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
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
  late final Player previewPlayer = Player(
    configuration: const PlayerConfiguration(vo: 'gpu-next'),
  );
  late VideoController controller;
  late VideoController previewController;
  // Swapped to Anime4K: ArtCNN uses Compute Shaders incompatible with media_kit's vo=libmpv D3D11 layer.
  // Anime4K uses standard fragment shaders, perfectly compatible with our SuperSampling frame buffer trick!
  bool _showControls = true;
  double _scale = 1.0;
  bool _isEnhancementEnabled = true;
  String _currentEngine = 'Anime4K';
  String _currentModelKey = 'Balanced';
  bool _isHwAccelerated = true;
  bool _showHUD = false;

  // Subtitle custom settings
  double _subtitleSize = 24.0; // Restoring default size (24.0) suitable for custom layout
  double _subtitlePosition = 24.0; // Restoring default position (24.0) suitable for custom layout
  double _subtitleBgOpacity = 0.0;
  String _subtitleFontFamily = 'Default';
  List<String> _activeSubtitles = [];



  Future<void> _loadSubtitleSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _subtitleSize = prefs.getDouble('sub_size') ?? 24.0;
      _subtitlePosition = prefs.getDouble('sub_position') ?? 24.0;
      _subtitleBgOpacity = prefs.getDouble('sub_opacity') ?? 0.0;
      _subtitleFontFamily = prefs.getString('sub_font') ?? 'Default';
    });
  }

  Future<void> _saveSubtitleSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('sub_size', _subtitleSize);
    await prefs.setDouble('sub_position', _subtitlePosition);
    await prefs.setDouble('sub_opacity', _subtitleBgOpacity);
    await prefs.setString('sub_font', _subtitleFontFamily);
  }

  void _resetSubtitleSettings() {
    setState(() {
      _subtitleSize = 24.0;
      _subtitlePosition = 24.0;
      _subtitleBgOpacity = 0.0;
      _subtitleFontFamily = 'Default';
    });
    _saveSubtitleSettings();
  }

  Future<void> _applySubtitleSettings() async {
    // Subtitles are rendered customly in Flutter layout to handle multiple speakers and sign coordinate overlap perfectly.
  }

  String _getDynamicShaderPath() {
    return ShaderService().getShaderPath(_currentModelKey) ?? '';
  }

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    controller = VideoController(player); // Default creates HW accelerated controller
    previewController = VideoController(previewPlayer);
    _isHwAccelerated = true;
    player.stream.log.listen((event) {
      LoggerService().log('[MPV] [${event.level}]: ${event.text}');
    });

    _loadSubtitleSettings();

    // Listen to subtitle stream and parse active lines (filtering duplicates, sorting, stripping ASS tags)
    player.stream.subtitle.listen((subtitle) {
      final uniqueLines = <String>{};
      for (final rawLine in subtitle.text) {
        final cleanLine = rawLine.replaceAll(RegExp(r'\{[^}]*\}'), '').trim();
        if (cleanLine.isNotEmpty) {
          uniqueLines.add(cleanLine);
        }
      }
      if (mounted) {
        setState(() {
          _activeSubtitles = uniqueLines.toList();
        });
      }
    });

    // Listen to position stream to store current position in real-time directly to SharedPreferences
    player.stream.position.listen((pos) {
      final posMs = pos.inMilliseconds;
      if (posMs > 0) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setInt('pos_${widget.videoPath}', posMs);
        });
      }
    });

    Future.microtask(() async {
      try {
        final nativePlayer = player.platform as NativePlayer;
        final nativePreviewPlayer = previewPlayer.platform as NativePlayer;
        
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

        // Configure player lossless audio properties
        await nativePlayer.setProperty('audio-format', 'float');
        await nativePlayer.setProperty('audio-channels', 'auto-safe');
        await nativePlayer.setProperty('resample-filter', 'soxr');
        await nativePlayer.setProperty('audio-pitch-correction', 'no');

        // Configure previewPlayer options (muted, hardware decoder auto, no shaders for instant seeking)
        await nativePreviewPlayer.setProperty('ytdl', 'no');
        await nativePreviewPlayer.setProperty('network-timeout', '10');
        await nativePreviewPlayer.setProperty('hwdec', 'auto');
        await previewPlayer.setVolume(0);
        await nativePreviewPlayer.setProperty('audio-format', 'float');
        await nativePreviewPlayer.setProperty('audio-channels', 'auto-safe');
        await nativePreviewPlayer.setProperty('resample-filter', 'soxr');

        // Open provided video file with Dart UI timeout feedback
        try {
          await player.open(Media(widget.videoPath), play: false).timeout(
            const Duration(seconds: 12),
          );
          await previewPlayer.open(Media(widget.videoPath), play: false).timeout(
            const Duration(seconds: 12),
          );

          // Wait for duration stream to emit a valid duration (> 0) indicating player has parsed the media
          await player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 5));
          await previewPlayer.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 5));
          
          final prefs = await SharedPreferences.getInstance();
          final savedPos = prefs.getInt('pos_${widget.videoPath}') ?? 0;
          if (savedPos > 0) {
            await player.seek(Duration(milliseconds: savedPos));
            await previewPlayer.seek(Duration(milliseconds: savedPos));
          }
          player.play();
          previewPlayer.pause();
          _applySubtitleSettings();
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
                  width: 500,
                  child: AdaptiveLiquidGlassLayer(
                    settings: RecommendedGlassSettings.surface,
                    child: GlassCard(
                      padding: const EdgeInsets.all(24),
                      shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Center(
                              child: Text(
                                'Player Settings',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Section 1: Video Enhancement Card
                            const Text(
                              'Video Quality Enhancement',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'AI Video Upscaling',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                              color: Colors.white,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'AI Neural Upscaling Engine',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white54,
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
                                  const SizedBox(height: 16),
                                  AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: _isEnhancementEnabled ? 1.0 : 0.3,
                                    child: IgnorePointer(
                                      ignoring: !_isEnhancementEnabled,
                                      child: Column(
                                        children: [
                                          GlassSegmentedControl(
                                            useOwnLayer: true,
                                            height: 40.0,
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
                                          const SizedBox(height: 12),
                                          if (_currentEngine == 'Anime4K')
                                            GlassSegmentedControl(
                                              useOwnLayer: true,
                                              height: 40.0,
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
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Section 2: Subtitle Customization Card
                            const Text(
                              'Custom Subtitle Settings',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Column(
                                children: [
                                  // Subtitle Size Slider
                                  Row(
                                    children: [
                                      const SizedBox(width: 110, child: Text('Font Size', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
                                      Expanded(
                                        child: GlassSlider(
                                          useOwnLayer: true,
                                          value: _subtitleSize,
                                          min: 12.0,
                                          max: 48.0,
                                          onChanged: (val) {
                                            setDialogState(() => _subtitleSize = val);
                                            setState(() => _subtitleSize = val);
                                            _saveSubtitleSettings();
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Subtitle Position Slider (上下移动)
                                  Row(
                                    children: [
                                      const SizedBox(width: 110, child: Text('Vertical Position', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
                                      Expanded(
                                        child: GlassSlider(
                                          useOwnLayer: true,
                                          value: _subtitlePosition,
                                          min: 8.0,
                                          max: 160.0,
                                          onChanged: (val) {
                                            setDialogState(() => _subtitlePosition = val);
                                            setState(() => _subtitlePosition = val);
                                            _saveSubtitleSettings();
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Subtitle Background Opacity Slider
                                  Row(
                                    children: [
                                      const SizedBox(width: 110, child: Text('Background Box', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
                                      Expanded(
                                        child: GlassSlider(
                                          useOwnLayer: true,
                                          value: _subtitleBgOpacity,
                                          min: 0.0,
                                          max: 1.0,
                                          onChanged: (val) {
                                            setDialogState(() => _subtitleBgOpacity = val);
                                            setState(() => _subtitleBgOpacity = val);
                                            _saveSubtitleSettings();
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // Subtitle Font Family Selector
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Font Family', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                                      SizedBox(
                                        width: 280,
                                        height: 38,
                                        child: GlassSegmentedControl(
                                          useOwnLayer: true,
                                          segments: const [
                                            GlassSegment(label: 'Default'),
                                            GlassSegment(label: 'Courier'),
                                            GlassSegment(label: 'Consolas'),
                                            GlassSegment(label: 'Roboto'),
                                          ],
                                          selectedIndex: switch (_subtitleFontFamily) {
                                            'Default' => 0,
                                            'Courier' => 1,
                                            'Consolas' => 2,
                                            'Roboto' => 3,
                                            _ => 0,
                                          },
                                          onSegmentSelected: (index) {
                                            final font = switch (index) {
                                              0 => 'Default',
                                              1 => 'Courier',
                                              2 => 'Consolas',
                                              3 => 'Roboto',
                                              _ => 'Default',
                                            };
                                            setDialogState(() => _subtitleFontFamily = font);
                                            setState(() => _subtitleFontFamily = font);
                                            _saveSubtitleSettings();
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: GlassButton.custom(
                                      shape: const LiquidRoundedSuperellipse(borderRadius: 10),
                                      onTap: () {
                                        setDialogState(() {
                                          _resetSubtitleSettings();
                                        });
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        child: Text('Reset Subtitles', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Section 3: Performance HUD Card
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Performance HUD',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Show playback telemetry stats',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.white54,
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
                            ),
                          ],
                        ),
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
    // Save position one last time immediately on dispose
    final posMs = player.state.position.inMilliseconds;
    if (posMs > 0) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('pos_${widget.videoPath}', posMs);
      });
    }

    _exitFullscreen();
    player.dispose();
    previewPlayer.dispose();
    super.dispose();
  }

  Widget _buildSubtitleOverlay() {
    return Positioned(
      bottom: _subtitlePosition,
      left: 32,
      right: 32,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _activeSubtitles.map((subText) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: _subtitleBgOpacity),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                subText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _subtitleSize,
                  fontFamily: _subtitleFontFamily == 'Default' ? null : _subtitleFontFamily,
                  fontWeight: FontWeight.bold,
                  shadows: const [
                    Shadow(
                      blurRadius: 4.0,
                      color: Colors.black,
                      offset: Offset(2.0, 2.0),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      background: Transform.scale(
        scale: _scale,
        child: Video(
          controller: controller,
          controls: NoVideoControls,
          subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
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

            // Custom Subtitle Overlay Layer (always visible over video)
            _buildSubtitleOverlay(),

            // 3. Floating Floating Controls Island
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              opacity: _showControls ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Stack(
                  children: [
                  // Top left back button & Title (Round liquid glass button)
                  Positioned(
                    top: 40,
                    left: 24,
                    child: Row(
                      children: [
                        GlassButton(
                          useOwnLayer: true,
                          width: 48,
                          height: 48,
                          shape: const LiquidOval(),
                          onTap: () => Navigator.of(context).pop(),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 18,
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

                  // Center Right Floating Settings Button (Round liquid glass button)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: GlassButton(
                        useOwnLayer: true,
                        width: 56,
                        height: 56,
                        shape: const LiquidOval(),
                        onTap: _showVideoSettings,
                        child: const Icon(
                          Icons.layers_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),

                  // Center Play/Pause Floating Island (Round liquid glass button)
                  Align(
                    alignment: Alignment.center,
                    child: StreamBuilder<bool>(
                      stream: player.stream.playing,
                      builder: (context, playing) {
                        final isPlaying = playing.data ?? false;
                        return GlassButton(
                          useOwnLayer: true,
                          width: 96,
                          height: 96,
                          shape: const LiquidOval(),
                          onTap: () => player.playOrPause(),
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 48,
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
                      child: CinematicEdgeBar(
                        player: player,
                        previewPlayer: previewPlayer,
                        previewController: previewController,
                      ),
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
      ),
    );
  }
}


class RecommendedGlassSettings {
  static const standard = LiquidGlassSettings(
    blur: 4,
    thickness: 10,
    glassColor: Color.fromRGBO(255, 255, 255, 0.08),
    lightAngle: 0.75 * math.pi, // 135° — upper-left, matches iOS 26
    lightIntensity: 0.7,
    ambientStrength: 0,
    saturation: 1.2,
    refractiveIndex: 1.2,
    chromaticAberration: 0.01,
    specularSharpness: GlassSpecularSharpness.medium,
  );

  static const interactive = LiquidGlassSettings(
    blur: 10,
    thickness: 10,
    glassColor: Color.fromRGBO(255, 255, 255, 0.2),
    lightAngle: 0.75 * math.pi, // 135° — upper-left, matches iOS 26
    lightIntensity: 0.7,
    ambientStrength: 0.3,
    saturation: 0.0,
    refractiveIndex: 0.7,
    chromaticAberration: 0.0,
  );

  static const surface = LiquidGlassSettings(
    blur: 10,
    thickness: 10,
    glassColor: Color.fromRGBO(255, 255, 255, 0.2),
    lightAngle: 0.75 * math.pi, // 135° — upper-left, matches iOS 26
    lightIntensity: 0.7,
    ambientStrength: 0.3,
    saturation: 1.2,
    refractiveIndex: 1.15,
    chromaticAberration: 0.0,
  );
}