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

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
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
  late final AnimationController _glassSweepController;

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
    _glassSweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
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
      for (final rawLine in subtitle) {
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
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.center,
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                final viewSize = MediaQuery.sizeOf(context);
                final panelWidth = math.min(
                  math.max(viewSize.width - 32, 280.0),
                  560.0,
                );
                final panelMaxHeight = math.max(viewSize.height - 48, 280.0);

                return SizedBox(
                  width: panelWidth,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: panelMaxHeight),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GlassCard(
                          useOwnLayer: true,
                          quality: GlassQuality.standard,
                          settings: RecommendedGlassSettings.playerPanel,
                          clipBehavior: Clip.antiAlias,
                          padding: EdgeInsets.zero,
                          shape: const LiquidRoundedSuperellipse(
                            borderRadius: 42,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(42),
                            child: Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                Positioned.fill(
                                  child: ColoredBox(
                                    color: Colors.black.withValues(alpha: 0.08),
                                  ),
                                ),
                                SingleChildScrollView(
                                  clipBehavior: Clip.hardEdge,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      20,
                                      24,
                                      24,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Player Settings',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.94,
                                              ),
                                              fontSize: 24,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                        GlassButton.custom(
                                          width: 40,
                                          height: 40,
                                          glowColor: const Color(0xFF8FEAFF),
                                          glowOpacity: 0.5,
                                          glowBlurRadius: 18,
                                          interactionScale: 1.08,
                                          stretch: 0.75,
                                          shape: const LiquidOval(),
                                          onTap: () =>
                                              Navigator.of(context).pop(),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            color: Colors.white,
                                            size: 19,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    _glassSettingsSection(
                                    icon: Icons.auto_awesome_rounded,
                                    title: 'Video Quality',
                                    subtitle: 'AI upscaling engine',
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Upscaling',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w300,
                                              ),
                                            ),
                                            GlassSwitch(
                                              useOwnLayer: true,
                                              value: _isEnhancementEnabled,
                                              onChanged: (val) {
                                                setDialogState(
                                                  () => _isEnhancementEnabled =
                                                      val,
                                                );
                                                setState(
                                                  () => _isEnhancementEnabled =
                                                      val,
                                                );
                                                _applyEnhancementConfig();
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        AnimatedOpacity(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          opacity:
                                              _isEnhancementEnabled ? 1.0 : 0.3,
                                          child: IgnorePointer(
                                            ignoring: !_isEnhancementEnabled,
                                            child: Column(
                                              children: [
                                                GlassSegmentedControl(
                                                  useOwnLayer: true,
                                                  height: 42,
                                                  borderRadius: 100,
                                                  selectedTextStyle:
                                                      _selectedPillTextStyle,
                                                  unselectedTextStyle:
                                                      _pillTextStyle,
                                                  indicatorSettings:
                                                      RecommendedGlassSettings
                                                          .playerHighlight,
                                                  interactionBehavior:
                                                      GlassInteractionBehavior
                                                          .full,
                                                  glowColor: const Color(
                                                    0xFF8FEAFF,
                                                  ),
                                                  glowRadius: 2.0,
                                                  segments: const [
                                                    GlassSegment(
                                                      label: 'Anime4K',
                                                      icon: Icon(
                                                        Icons.bolt_rounded,
                                                        size: 16,
                                                      ),
                                                    ),
                                                    GlassSegment(
                                                      label: 'ArtCNN',
                                                      icon: Icon(
                                                        Icons.memory_rounded,
                                                        size: 16,
                                                      ),
                                                    ),
                                                  ],
                                                  selectedIndex:
                                                      _currentEngine ==
                                                          'Anime4K'
                                                      ? 0
                                                      : 1,
                                                  onSegmentSelected: (index) {
                                                    final engine = index == 0
                                                        ? 'Anime4K'
                                                        : 'ArtCNN';
                                                    setDialogState(
                                                      () => _currentEngine =
                                                          engine,
                                                    );
                                                    setState(
                                                      () => _currentEngine =
                                                          engine,
                                                    );
                                                    _applyEnhancementConfig();
                                                  },
                                                ),
                                                const SizedBox(height: 12),
                                                if (_currentEngine == 'Anime4K')
                                                  GlassSegmentedControl(
                                                    useOwnLayer: true,
                                                    height: 42,
                                                    borderRadius: 100,
                                                    selectedTextStyle:
                                                        _selectedPillTextStyle,
                                                    unselectedTextStyle:
                                                        _pillTextStyle,
                                                    indicatorSettings:
                                                        RecommendedGlassSettings
                                                            .playerHighlight,
                                                    interactionBehavior:
                                                        GlassInteractionBehavior
                                                            .full,
                                                    glowColor: const Color(
                                                      0xFFFF9AF2,
                                                    ),
                                                    glowRadius: 2.0,
                                                    segments: const [
                                                      GlassSegment(
                                                        label: 'Speed',
                                                      ),
                                                      GlassSegment(
                                                        label: 'Balanced',
                                                      ),
                                                      GlassSegment(
                                                        label: 'Quality',
                                                      ),
                                                      GlassSegment(label: 'Max'),
                                                    ],
                                                    selectedIndex:
                                                        switch (_currentModelKey) {
                                                          'Speed' => 0,
                                                          'Balanced' => 1,
                                                          'Quality' => 2,
                                                          'Extreme' => 3,
                                                          _ => 1,
                                                        },
                                                    onSegmentSelected: (index) {
                                                      final modelKey =
                                                          switch (index) {
                                                            0 => 'Speed',
                                                            1 => 'Balanced',
                                                            2 => 'Quality',
                                                            3 => 'Extreme',
                                                            _ => 'Balanced',
                                                          };
                                                      setDialogState(
                                                        () => _currentModelKey =
                                                            modelKey,
                                                      );
                                                      setState(
                                                        () => _currentModelKey =
                                                            modelKey,
                                                      );
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
                                  _glassSettingsSection(
                                    icon: Icons.subtitles_rounded,
                                    title: 'Subtitles',
                                    subtitle: 'Thin default type and placement',
                                    child: Column(
                                      children: [
                                        _settingsSliderRow(
                                          label: 'Font Size',
                                          value: _subtitleSize,
                                          min: 12,
                                          max: 48,
                                          onChanged: (val) {
                                            setDialogState(
                                              () => _subtitleSize = val,
                                            );
                                            setState(() => _subtitleSize = val);
                                            _saveSubtitleSettings();
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        _settingsSliderRow(
                                          label: 'Vertical',
                                          value: _subtitlePosition,
                                          min: 8,
                                          max: 160,
                                          onChanged: (val) {
                                            setDialogState(
                                              () => _subtitlePosition = val,
                                            );
                                            setState(
                                              () => _subtitlePosition = val,
                                            );
                                            _saveSubtitleSettings();
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        _settingsSliderRow(
                                          label: 'Backdrop',
                                          value: _subtitleBgOpacity,
                                          min: 0,
                                          max: 1,
                                          onChanged: (val) {
                                            setDialogState(
                                              () => _subtitleBgOpacity = val,
                                            );
                                            setState(
                                              () => _subtitleBgOpacity = val,
                                            );
                                            _saveSubtitleSettings();
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Font',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w300,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                SizedBox(
                                                  width: constraints.maxWidth,
                                                  height: 42,
                                                  child: GlassSegmentedControl(
                                                    useOwnLayer: true,
                                                    borderRadius: 100,
                                                    indicatorSettings:
                                                        RecommendedGlassSettings
                                                            .playerHighlight,
                                                    interactionBehavior:
                                                        GlassInteractionBehavior
                                                            .full,
                                                    glowColor: const Color(
                                                      0xFF8FEAFF,
                                                    ),
                                                    glowRadius: 2.0,
                                                    selectedTextStyle:
                                                        _selectedPillTextStyle,
                                                    unselectedTextStyle:
                                                        _pillTextStyle,
                                                    segments: const [
                                                      GlassSegment(
                                                        label: 'Default',
                                                      ),
                                                      GlassSegment(
                                                        label: 'Courier',
                                                      ),
                                                      GlassSegment(
                                                        label: 'Consolas',
                                                      ),
                                                      GlassSegment(
                                                        label: 'Roboto',
                                                      ),
                                                    ],
                                                    selectedIndex:
                                                        switch (_subtitleFontFamily) {
                                                          'Default' => 0,
                                                          'Courier' => 1,
                                                          'Consolas' => 2,
                                                          'Roboto' => 3,
                                                          _ => 0,
                                                        },
                                                    onSegmentSelected: (index) {
                                                      final font =
                                                          switch (index) {
                                                            0 => 'Default',
                                                            1 => 'Courier',
                                                            2 => 'Consolas',
                                                            3 => 'Roboto',
                                                            _ => 'Default',
                                                          };
                                                      setDialogState(
                                                        () =>
                                                            _subtitleFontFamily =
                                                                font,
                                                      );
                                                      setState(
                                                        () =>
                                                            _subtitleFontFamily =
                                                                font,
                                                      );
                                                      _saveSubtitleSettings();
                                                    },
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: GlassButton.custom(
                                            height: 42,
                                            glowColor: Colors.white,
                                            glowOpacity: 0.45,
                                            glowBlurRadius: 16,
                                            interactionScale: 1.06,
                                            stretch: 0.7,
                                            shape:
                                                const LiquidRoundedSuperellipse(
                                                  borderRadius: 100,
                                                ),
                                            onTap: () {
                                              setDialogState(() {
                                                _resetSubtitleSettings();
                                              });
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 18,
                                              ),
                                              child: Text(
                                                'Reset Subtitles',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w300,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _glassSettingsSection(
                                    icon: Icons.monitor_heart_rounded,
                                    title: 'Performance HUD',
                                    subtitle: 'Playback telemetry overlay',
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Show HUD',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w300,
                                          ),
                                        ),
                                        GlassSwitch(
                                          useOwnLayer: true,
                                          value: _showHUD,
                                          onChanged: (val) {
                                            setDialogState(
                                              () => _showHUD = val,
                                            );
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
                              ],
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _glassSweepController,
                              builder: (context, _) {
                                return CustomPaint(
                                  painter: _LiquidGlassSweepPainter(
                                    progress: _glassSweepController.value,
                                  ),
                                );
                              },
                            ),
                          ),
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
        final curved = CurvedAnimation(
          parent: anim1,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return Transform.scale(
          scale: 0.96 + curved.value * 0.04,
          child: Opacity(opacity: anim1.value, child: child),
        );
      },
    );
  }

  Widget _glassSettingsSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return GlassCard(
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: RecommendedGlassSettings.playerSection,
      padding: const EdgeInsets.all(16),
      shape: const LiquidRoundedSuperellipse(borderRadius: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlassButton.custom(
                width: 42,
                height: 42,
                shape: const LiquidOval(),
                onTap: () {},
                enabled: false,
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.56),
                        fontSize: 11,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _settingsSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
        Expanded(
          child: GlassSlider(
            useOwnLayer: true,
            settings: RecommendedGlassSettings.playerHighlight,
            glowColor: const Color(0xFF8FEAFF),
            glowRadius: 2.0,
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  static const TextStyle _pillTextStyle = TextStyle(
    color: Colors.white70,
    fontSize: 12,
    fontWeight: FontWeight.w300,
  );

  static const TextStyle _selectedPillTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );
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
    _glassSweepController.dispose();
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
                  fontWeight: _subtitleFontFamily == 'Default'
                      ? FontWeight.w300
                      : FontWeight.w500,
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

  Widget _buildGlassWarmupLayer() {
    return Positioned(
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.01,
          child: SizedBox(
            width: 2,
            height: 2,
            child: AdaptiveLiquidGlassLayer(
              settings: RecommendedGlassSettings.playerPanel,
              quality: GlassQuality.standard,
              child: GlassCard(
                useOwnLayer: false,
                settings: RecommendedGlassSettings.playerPanel,
                padding: EdgeInsets.zero,
                shape: const LiquidOval(),
                child: const SizedBox.expand(),
              ),
            ),
          ),
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

            _buildGlassWarmupLayer(),

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
                        GlassButton.custom(
                          useOwnLayer: false,
                          width: 48,
                          height: 48,
                          settings: RecommendedGlassSettings.playerHighlight,
                          interactionScale: 1.08,
                          stretch: 0.75,
                          glowColor: const Color(0xFF8FEAFF),
                          glowOpacity: 0.45,
                          glowBlurRadius: 18,
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
                      child: GlassButton.custom(
                        useOwnLayer: false,
                        width: 56,
                        height: 56,
                        settings: RecommendedGlassSettings.playerHighlight,
                        interactionScale: 1.08,
                        stretch: 0.75,
                        glowColor: const Color(0xFFFF9AF2),
                        glowOpacity: 0.45,
                        glowBlurRadius: 18,
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
                        return GlassButton.custom(
                          useOwnLayer: false,
                          width: 96,
                          height: 96,
                          settings: RecommendedGlassSettings.playerHighlight,
                          interactionScale: 1.05,
                          stretch: 0.6,
                          glowColor: Colors.white,
                          glowOpacity: 0.42,
                          glowBlurRadius: 24,
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

class _LiquidGlassSweepPainter extends CustomPainter {
  const _LiquidGlassSweepPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final panelRect = Offset.zero & size;
    final panelRRect = RRect.fromRectAndRadius(
      panelRect,
      const Radius.circular(42),
    );

    // Colors sourced from the actual liquid_glass_widgets shader
    // (liquid_glass_final_render.frag) — the glass widget renders these at its
    // edges via chromatic aberration + Fresnel rim lighting:
    //   - glassColor base = Color(0x3DFFFFFF) (white, ~24% alpha — the
    //     kBottomBarGlassDefaults.glassColor used by GlassTabBar.bottom)
    //   - Spectral RGB from chromatic aberration dispersion (see shader:
    //     vec2 redOffset  = displacement * (1.0 + dispersionStrength);
    //     vec2 blueOffset = displacement * (1.0 - dispersionStrength);)
    //     → pure Red on one rim edge, pure Green at center, pure Blue on
    //     the other rim edge. This is the iridescent rainbow fringe that
    //     produces the iOS 26 "subtle white + prism" rim look.
    //   - Fresnel rim = Color(0xFFFFFFFF) (the shader's
    //     (1.0 - normalZ) * edgeFactor * 0.12 white specular boost)
    const Color glassBase = Color(0x3DFFFFFF);   // kBottomBarGlassDefaults.glassColor
    const Color glassRed = Color(0xFFFF0000);    // chromatic aberration R rim (high-end spectrum)
    const Color glassGreen = Color(0xFF00FF00);  // chromatic aberration G center
    const Color glassBlue = Color(0xFF0000FF);   // chromatic aberration B rim (low-end spectrum)
    const Color glassWhite = Color(0xFFFFFFFF);  // Fresnel specular highlight

    // Outer glow — soft luminous halo matching the glass surface edge
    final glowPaint = Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          glassRed.withValues(alpha: 0.28),
          glassBase.withValues(alpha: 0.32),
          glassGreen.withValues(alpha: 0.24),
          glassBase.withValues(alpha: 0.30),
          glassBlue.withValues(alpha: 0.28),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(panelRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRRect(panelRRect.deflate(3), glowPaint);

    // Ambient rim — chromatic aberration iridescent prism fringe (the
    // "glass RGB" — full spectral Red→Green→Blue split across the rim)
    final ambientRimPaint = Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          glassRed.withValues(alpha: 0.72),
          glassWhite.withValues(alpha: 0.18),
          glassGreen.withValues(alpha: 0.50),
          glassWhite.withValues(alpha: 0.18),
          glassBlue.withValues(alpha: 0.68),
          glassRed.withValues(alpha: 0.42),
        ],
        stops: const [0.0, 0.18, 0.38, 0.58, 0.78, 1.0],
      ).createShader(panelRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawRRect(panelRRect.deflate(0.8), ambientRimPaint);

    // Inner white Fresnel rim — matches glass widget's white specular boost
    final innerRimPaint = Paint()
      ..blendMode = BlendMode.screen
      ..color = glassWhite.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    canvas.drawRRect(panelRRect.deflate(2.2), innerRimPaint);

    // Animated sweep rim — rotating iridescent prism fringe (Red→Green→Blue)
    final movingRimPaint = Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          glassRed.withValues(alpha: 0.48),
          glassWhite.withValues(alpha: 0.20),
          glassBlue.withValues(alpha: 0.44),
        ],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(panelRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawRRect(panelRRect.deflate(1.4), movingRimPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassSweepPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}


class RecommendedGlassSettings {
  static const playerPanel = LiquidGlassSettings(
    blur: 5,
    thickness: 36,
    glassColor: Colors.transparent,
    lightAngle: 0.7 * math.pi,
    lightIntensity: 1.75,
    ambientStrength: 0.0,
    saturation: 1.28,
    refractiveIndex: 1.5,
    chromaticAberration: 0.28,
    glowIntensity: 0.52,
    specularSharpness: GlassSpecularSharpness.medium,
  );

  static const playerSection = LiquidGlassSettings(
    blur: 3,
    thickness: 32,
    glassColor: Colors.transparent,
    lightAngle: 0.7 * math.pi,
    lightIntensity: 2.05,
    ambientStrength: 0,
    saturation: 1.32,
    refractiveIndex: 1.56,
    chromaticAberration: 0.22,
    glowIntensity: 0.68,
    specularSharpness: GlassSpecularSharpness.sharp,
  );

  static const playerHighlight = LiquidGlassSettings(
    blur: 0,
    thickness: 32,
    glassColor: Colors.transparent,
    lightAngle: 0.7 * math.pi,
    lightIntensity: 3.4,
    ambientStrength: 0.0,
    saturation: 1.35,
    refractiveIndex: 1.68,
    chromaticAberration: 0.55,
    glowIntensity: 1.45,
    specularSharpness: GlassSpecularSharpness.sharp,
  );

  static const standard = LiquidGlassSettings(
    blur: 4,
    thickness: 10,
    glassColor: Color.fromRGBO(255, 255, 255, 0.08),
    lightAngle: 0.75 * math.pi,
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
    lightAngle: 0.75 * math.pi,
    lightIntensity: 0.7,
    ambientStrength: 0.3,
    saturation: 0.0,
    refractiveIndex: 0.7,
    chromaticAberration: 0.0,
  );

  static const surface = LiquidGlassSettings(
    blur: 20, // Deep heavy frost
    thickness: 15, // Volumetric edge rim
    glassColor: Color.fromRGBO(255, 255, 255, 0.25), // Strong misty translucent white
    lightAngle: 0.75 * math.pi,
    lightIntensity: 1.5, // Brighter highlight glow
    ambientStrength: 0.4,
    saturation: 1.2,
    refractiveIndex: 1.3, // Bold prominent rim highlights
    chromaticAberration: 0.01,
  );
}
