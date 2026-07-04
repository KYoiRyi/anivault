import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:anivault/ui/ani_glass_theme.dart';
import 'package:anivault/ui/cinematic_edge_bar.dart';
import 'package:anivault/ui/performance_hud.dart';
import 'package:anivault/services/shader_service.dart';
import 'package:anivault/services/ffi_engine.dart';
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/watch_history_service.dart';

class PlayerScreen extends StatefulWidget {
  final String videoPath;
  final String title;

  const PlayerScreen({super.key, required this.videoPath, required this.title});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late final Player player = Player(configuration: _playerConfiguration);
  late final Player previewPlayer = Player(configuration: _playerConfiguration);
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

  int _accumulatedSecondsWatched = 0;
  Timer? _progressSaveTimer;
  Timer? _watchTickTimer;
  final FocusNode _keyboardFocusNode = FocusNode();
  bool _isLocked = false;
  Offset? _lastDoubleTapPosition;
  double _gestureStartVolume = 100.0;
  double _gestureStartBrightness = 0.5;
  double _horizontalDragDx = 0;

  static PlayerConfiguration get _playerConfiguration {
    if (Platform.isIOS || Platform.isAndroid) {
      return const PlayerConfiguration();
    }
    return const PlayerConfiguration(vo: 'gpu-next');
  }

  String get _mediaResource {
    final file = File(widget.videoPath);
    if ((Platform.isIOS || Platform.isMacOS) && file.existsSync()) {
      return file.uri.toString();
    }
    return widget.videoPath;
  }

  // Subtitle custom settings
  double _subtitleSize =
      24.0; // Restoring default size (24.0) suitable for custom layout
  double _subtitlePosition =
      24.0; // Restoring default position (24.0) suitable for custom layout
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
    controller = VideoController(
      player,
    ); // Default creates HW accelerated controller
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

    _watchTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (player.state.playing &&
          player.state.position < player.state.duration) {
        _accumulatedSecondsWatched += 1;
      }
    });

    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _saveProgress();
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
          _isEnhancementEnabled && _currentEngine == 'Anime4K'
              ? _getDynamicShaderPath()
              : '',
        );

        // Configure player lossless audio properties
        await nativePlayer.setProperty('audio-format', 'float');
        await nativePlayer.setProperty('audio-channels', 'auto');
        await nativePlayer.setProperty('ad-lavc-ac3drc', '0');
        await nativePlayer.setProperty('audio-normalize-downmix', 'no');
        await nativePlayer.setProperty('resample-filter', 'soxr');
        await nativePlayer.setProperty('audio-resample-filter-size', '32');
        await nativePlayer.setProperty('audio-pitch-correction', 'no');

        // Open main player first to split the heavy startup loading workload
        await player
            .open(Media(_mediaResource), play: false)
            .timeout(const Duration(seconds: 12));

        // Wait for duration stream to emit a valid duration (> 0) indicating player has parsed the media
        await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 5));

        final prefs = await SharedPreferences.getInstance();
        final savedPos = prefs.getInt('pos_${widget.videoPath}') ?? 0;
        if (savedPos > 0) {
          await player.seek(Duration(milliseconds: savedPos));
        }
        player.play();
        _applySubtitleSettings();

        // Delay previewPlayer initialization to avoid video resource congestion & socket errors on SMB streams
        if (Platform.isIOS) return;
        Future.delayed(const Duration(milliseconds: 600), () async {
          if (!mounted) return;
          try {
            // Configure previewPlayer options (muted, hardware decoder auto, no shaders for instant seeking)
            await nativePreviewPlayer.setProperty('ytdl', 'no');
            await nativePreviewPlayer.setProperty('network-timeout', '10');
            await nativePreviewPlayer.setProperty('hwdec', 'auto');
            await previewPlayer.setVolume(0);
            await nativePreviewPlayer.setProperty('audio-format', 'float');
            await nativePreviewPlayer.setProperty('audio-channels', 'auto');
            await nativePreviewPlayer.setProperty('ad-lavc-ac3drc', '0');
            await nativePreviewPlayer.setProperty(
              'audio-normalize-downmix',
              'no',
            );
            await nativePreviewPlayer.setProperty('resample-filter', 'soxr');

            await previewPlayer
                .open(Media(_mediaResource), play: false)
                .timeout(const Duration(seconds: 8));
            await previewPlayer.stream.duration
                .firstWhere((d) => d > Duration.zero)
                .timeout(const Duration(seconds: 5));
            if (savedPos > 0) {
              await previewPlayer.seek(Duration(milliseconds: savedPos));
            }
            previewPlayer.pause();
          } catch (e) {
            debugPrint('Preview player background init error: $e');
          }
        });
      } on TimeoutException {
        LoggerService().log('[Player Error] Timed out waiting for media info.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load video: Network timed out.'),
            ),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        debugPrint('Media load error: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Play failed: $e')));
          Navigator.of(context).pop();
        }
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
          controller = VideoController(
            player,
            configuration: const VideoControllerConfiguration(
              enableHardwareAcceleration: true,
            ),
          );
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
            controller = VideoController(
              player,
              configuration: const VideoControllerConfiguration(
                enableHardwareAcceleration: false,
              ),
            );
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
            controller = VideoController(
              player,
              configuration: const VideoControllerConfiguration(
                enableHardwareAcceleration: true,
              ),
            );
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
    var pausedAtFull = false;
    GlassModalSheet.show(
      context: context,
      initialState: GlassSheetState.half,
      halfSize: 0.56,
      fullSize: 0.9,
      quality: GlassQuality.premium,
      settings: AniGlassTheme.playerPanelFor(context),
      barrierColor: Colors.black45,
      fillTransition: GlassFillTransition.instant,
      interactionScale: 1.01,
      stretch: 0.5,
      suppressInteractionOnChildren: true,
      onStateChanged: (state) {
        if (state == GlassSheetState.full && !pausedAtFull) {
          pausedAtFull = true;
          player.pause();
        } else if (state != GlassSheetState.full) {
          pausedAtFull = false;
        }
      },
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final scrollData = ScrollControllerProvider.of(context);
            return ListView(
              controller: scrollData?.controller,
              physics: scrollData?.physics,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Player Settings',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    GlassButton(
                      quality: GlassQuality.premium,
                      settings: AniGlassTheme.playerControlFor(context),
                      icon: const Icon(Icons.close_rounded),
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Pull the drawer to full height to pause playback.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 18),
                _glassSettingsSection(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Video Enhancement',
                  subtitle: 'Anime4K GLSL or ArtCNN native pipeline',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Anime4K / ArtCNN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          GlassSwitch(
                            quality: GlassQuality.premium,
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
                      const SizedBox(height: 14),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: _isEnhancementEnabled ? 1 : 0.35,
                        child: IgnorePointer(
                          ignoring: !_isEnhancementEnabled,
                          child: Column(
                            children: [
                              GlassSegmentedControl(
                                quality: GlassQuality.premium,
                                useOwnLayer: true,
                                height: 44,
                                borderRadius: 100,
                                selectedTextStyle: _selectedPillTextStyle,
                                unselectedTextStyle: _pillTextStyle,
                                indicatorSettings:
                                    AniGlassTheme.playerControlFor(context),
                                interactionBehavior:
                                    GlassInteractionBehavior.full,
                                glowColor: const Color(0xFF8FEAFF),
                                glowRadius: 2,
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
                                selectedIndex: _currentEngine == 'Anime4K'
                                    ? 0
                                    : 1,
                                onSegmentSelected: (index) {
                                  final engine = index == 0
                                      ? 'Anime4K'
                                      : 'ArtCNN';
                                  setDialogState(() => _currentEngine = engine);
                                  setState(() => _currentEngine = engine);
                                  _applyEnhancementConfig();
                                },
                              ),
                              const SizedBox(height: 12),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                child: _currentEngine == 'Anime4K'
                                    ? GlassSegmentedControl(
                                        key: const ValueKey('anime4k-models'),
                                        quality: GlassQuality.premium,
                                        useOwnLayer: true,
                                        height: 44,
                                        borderRadius: 100,
                                        selectedTextStyle:
                                            _selectedPillTextStyle,
                                        unselectedTextStyle: _pillTextStyle,
                                        indicatorSettings:
                                            AniGlassTheme.playerControlFor(
                                              context,
                                            ),
                                        interactionBehavior:
                                            GlassInteractionBehavior.full,
                                        glowColor: const Color(0xFFFF9AF2),
                                        glowRadius: 2,
                                        segments: const [
                                          GlassSegment(label: 'Speed'),
                                          GlassSegment(label: 'Balanced'),
                                          GlassSegment(label: 'Quality'),
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
                                          final modelKey = switch (index) {
                                            0 => 'Speed',
                                            1 => 'Balanced',
                                            2 => 'Quality',
                                            3 => 'Extreme',
                                            _ => 'Balanced',
                                          };
                                          setDialogState(
                                            () => _currentModelKey = modelKey,
                                          );
                                          setState(
                                            () => _currentModelKey = modelKey,
                                          );
                                          _applyEnhancementConfig();
                                        },
                                      )
                                    : const Text(
                                        'ArtCNN uses the native FFI pipeline and disables GLSL shaders.',
                                        key: ValueKey('artcnn-note'),
                                        style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _glassSettingsSection(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Audio',
                  subtitle: 'High quality EAC3 output and track selection',
                  child: _buildAudioTrackSelector(),
                ),
                const SizedBox(height: 14),
                _glassSettingsSection(
                  icon: Icons.subtitles_rounded,
                  title: 'Subtitles',
                  subtitle: 'Flutter overlay layout and typography',
                  child: Column(
                    children: [
                      _buildSubtitleTrackSelector(),
                      const SizedBox(height: 14),
                      _settingsSliderRow(
                        label: 'Font Size',
                        value: _subtitleSize,
                        min: 12,
                        max: 48,
                        onChanged: (val) {
                          setDialogState(() => _subtitleSize = val);
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
                          setDialogState(() => _subtitlePosition = val);
                          setState(() => _subtitlePosition = val);
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
                          setDialogState(() => _subtitleBgOpacity = val);
                          setState(() => _subtitleBgOpacity = val);
                          _saveSubtitleSettings();
                        },
                      ),
                      const SizedBox(height: 14),
                      GlassSegmentedControl(
                        quality: GlassQuality.premium,
                        useOwnLayer: true,
                        height: 44,
                        borderRadius: 100,
                        selectedTextStyle: _selectedPillTextStyle,
                        unselectedTextStyle: _pillTextStyle,
                        indicatorSettings: AniGlassTheme.playerControlFor(
                          context,
                        ),
                        segments: const [
                          GlassSegment(label: 'Default'),
                          GlassSegment(label: 'Courier'),
                          GlassSegment(label: 'Consolas'),
                          GlassSegment(label: 'Roboto'),
                        ],
                        selectedIndex: switch (_subtitleFontFamily) {
                          'Courier' => 1,
                          'Consolas' => 2,
                          'Roboto' => 3,
                          _ => 0,
                        },
                        onSegmentSelected: (index) {
                          final font = switch (index) {
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
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GlassButton.custom(
                          quality: GlassQuality.premium,
                          settings: AniGlassTheme.playerControlFor(context),
                          shape: const LiquidRoundedSuperellipse(
                            borderRadius: 100,
                          ),
                          onTap: () {
                            _resetSubtitleSettings();
                            setDialogState(() {});
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Text(
                              'Reset Subtitles',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _glassSettingsSection(
                  icon: Icons.monitor_heart_rounded,
                  title: 'Performance HUD',
                  subtitle: 'Playback telemetry overlay',
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Show HUD',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      GlassSwitch(
                        quality: GlassQuality.premium,
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
            );
          },
        );
      },
    );
  }

  // ignore: unused_element
  void _showLegacyVideoSettings() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black26, // Elegant translucent barrier tint
      transitionDuration: const Duration(milliseconds: 350),
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
                  520.0,
                );
                // Keep the menu short, centered, and don't occupy full screen height
                final panelMaxHeight = math.min(viewSize.height * 0.72, 460.0);

                return SizedBox(
                  width: panelWidth,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: panelMaxHeight),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GlassCard(
                          settings: RecommendedGlassSettings.playerPanel,
                          padding: EdgeInsets.zero,
                          shape: const LiquidRoundedSuperellipse(
                            borderRadius: 42,
                          ),
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
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
                                            settings: RecommendedGlassSettings
                                                .playerHighlight,
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
                                                  MainAxisAlignment
                                                      .spaceBetween,
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
                                                      () =>
                                                          _isEnhancementEnabled =
                                                              val,
                                                    );
                                                    setState(
                                                      () =>
                                                          _isEnhancementEnabled =
                                                              val,
                                                    );
                                                    _applyEnhancementConfig();
                                                  },
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            AnimatedOpacity(
                                              duration: const Duration(
                                                milliseconds: 200,
                                              ),
                                              opacity: _isEnhancementEnabled
                                                  ? 1.0
                                                  : 0.3,
                                              child: IgnorePointer(
                                                ignoring:
                                                    !_isEnhancementEnabled,
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
                                                            Icons
                                                                .memory_rounded,
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
                                                        final engine =
                                                            index == 0
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
                                                    if (_currentEngine ==
                                                        'Anime4K')
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
                                                          GlassSegment(
                                                            label: 'Max',
                                                          ),
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
                                                            () =>
                                                                _currentModelKey =
                                                                    modelKey,
                                                          );
                                                          setState(
                                                            () =>
                                                                _currentModelKey =
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
                                        subtitle:
                                            'Thin default type and placement',
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
                                                setState(
                                                  () => _subtitleSize = val,
                                                );
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
                                                  () =>
                                                      _subtitleBgOpacity = val,
                                                );
                                                setState(
                                                  () =>
                                                      _subtitleBgOpacity = val,
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
                                                        fontWeight:
                                                            FontWeight.w300,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    SizedBox(
                                                      width:
                                                          constraints.maxWidth,
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
                                                settings:
                                                    RecommendedGlassSettings
                                                        .playerHighlight,
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
                                                      fontWeight:
                                                          FontWeight.w300,
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
        // Slide up slightly from bottom-center. No Opacity to prevent off-screen buffer white flashes
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.22),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutQuart)),
          child: child,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
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
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.56),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
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
            useOwnLayer: false, // Share the parent dialog's glass layer
            quality: GlassQuality
                .premium, // Force premium native BackdropFilter to prevent any blur/low-res capture issues
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

  Widget _buildAudioTrackSelector() {
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, tracksSnapshot) {
        return StreamBuilder<Track>(
          stream: player.stream.track,
          initialData: player.state.track,
          builder: (context, trackSnapshot) {
            final tracks =
                tracksSnapshot.data?.audio ?? player.state.tracks.audio;
            final selected =
                trackSnapshot.data?.audio ?? player.state.track.audio;
            return _trackSelectorButton(
              icon: Icons.graphic_eq_rounded,
              label: _trackLabel(selected, fallback: 'Auto audio'),
              onTap: () => _showAudioTrackPicker(tracks),
            );
          },
        );
      },
    );
  }

  Widget _buildSubtitleTrackSelector() {
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, tracksSnapshot) {
        return StreamBuilder<Track>(
          stream: player.stream.track,
          initialData: player.state.track,
          builder: (context, trackSnapshot) {
            final tracks =
                tracksSnapshot.data?.subtitle ?? player.state.tracks.subtitle;
            final selected =
                trackSnapshot.data?.subtitle ?? player.state.track.subtitle;
            return _trackSelectorButton(
              icon: Icons.closed_caption_rounded,
              label: _trackLabel(selected, fallback: 'Auto subtitles'),
              onTap: () => _showSubtitleTrackPicker(tracks),
            );
          },
        );
      },
    );
  }

  Widget _trackSelectorButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GlassButton.custom(
      quality: GlassQuality.premium,
      settings: AniGlassTheme.playerControlFor(context),
      shape: const LiquidRoundedSuperellipse(borderRadius: 100),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  String _trackLabel(dynamic track, {required String fallback}) {
    final id = track.id as String? ?? '';
    if (id == 'no') return 'Off';
    if (id == 'auto') return fallback;
    final parts = <String>[
      if ((track.title as String?)?.trim().isNotEmpty == true)
        (track.title as String).trim(),
      if ((track.language as String?)?.trim().isNotEmpty == true)
        (track.language as String).trim(),
      if ((track.codec as String?)?.trim().isNotEmpty == true)
        (track.codec as String).trim().toUpperCase(),
      if (track.channelscount != null) '${track.channelscount}ch',
    ];
    return parts.isEmpty ? 'Track $id' : parts.join(' · ');
  }

  void _showAudioTrackPicker(List<AudioTrack> tracks) {
    _showTrackPicker(
      title: 'Audio Track',
      tracks: tracks,
      selectedId: player.state.track.audio.id,
      labelFor: (track) => _trackLabel(track, fallback: 'Auto audio'),
      onSelect: (track) async {
        await player.setAudioTrack(track);
        if (mounted) setState(() {});
      },
    );
  }

  void _showSubtitleTrackPicker(List<SubtitleTrack> tracks) {
    _showTrackPicker(
      title: 'Subtitle Track',
      tracks: tracks,
      selectedId: player.state.track.subtitle.id,
      labelFor: (track) => _trackLabel(track, fallback: 'Auto subtitles'),
      onSelect: (track) async {
        await player.setSubtitleTrack(track);
        if (mounted) setState(() {});
      },
    );
  }

  void _showTrackPicker<T>({
    required String title,
    required List<T> tracks,
    required String selectedId,
    required String Function(T track) labelFor,
    required Future<void> Function(T track) onSelect,
  }) {
    GlassModalSheet.show(
      context: context,
      initialState: GlassSheetState.peek,
      peekSize: 0.36,
      halfSize: 0.5,
      fullSize: 0.72,
      quality: GlassQuality.premium,
      settings: AniGlassTheme.playerPanelFor(context),
      barrierColor: Colors.black38,
      fillTransition: GlassFillTransition.instant,
      builder: (context) {
        final scrollData = ScrollControllerProvider.of(context);
        return ListView(
          controller: scrollData?.controller,
          physics: scrollData?.physics,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            for (final track in tracks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassButton.custom(
                  quality: GlassQuality.premium,
                  settings: AniGlassTheme.playerControlFor(context),
                  shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                  onTap: () async {
                    await onSelect(track);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (track as dynamic).id == selectedId
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            labelFor(track),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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
  void _saveProgress() {
    final posMs = player.state.position.inMilliseconds;
    final durationMs = player.state.duration.inMilliseconds;
    if (posMs > 0 && durationMs > 0) {
      WatchHistoryService().saveWatchProgress(
        videoPath: widget.videoPath,
        progressMs: posMs,
        durationMs: durationMs,
        secondsWatched: _accumulatedSecondsWatched,
      );
      _accumulatedSecondsWatched = 0;
    }
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    _watchTickTimer?.cancel();
    _saveProgress();

    // Save position one last time immediately on dispose
    final posMs = player.state.position.inMilliseconds;
    if (posMs > 0) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('pos_${widget.videoPath}', posMs);
      });
    }

    _exitFullscreen();
    ScreenBrightness.instance.resetApplicationScreenBrightness();
    _keyboardFocusNode.dispose();
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
                  fontFamily: _subtitleFontFamily == 'Default'
                      ? null
                      : _subtitleFontFamily,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassSlider(
                  quality: GlassQuality.premium,
                  settings: RecommendedGlassSettings.playerHighlight,
                  value: 0.5,
                  min: 0,
                  max: 1,
                  onChanged: _noopSlider,
                ),
                const SizedBox(height: 12),
                GlassSwitch(value: false, onChanged: _noopSwitch),
                const SizedBox(height: 12),
                GlassSegmentedControl(
                  segments: const [
                    GlassSegment(label: 'A'),
                    GlassSegment(label: 'B'),
                  ],
                  selectedIndex: 0,
                  onSegmentSelected: _noopSeg,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _noopSlider(double v) {}
  void _noopSwitch(bool v) {}
  void _noopSeg(int v) {}

  void _toggleControls() {
    if (_isLocked) return;
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      _showControls = !_isLocked;
    });
  }

  void _handleDoubleTap() {
    if (_isLocked) return;
    final position = _lastDoubleTapPosition;
    final width = MediaQuery.sizeOf(context).width;
    if (position == null || width <= 0) {
      player.playOrPause();
      return;
    }
    if (position.dx < width * 0.38) {
      _seekRelative(const Duration(seconds: -10));
    } else if (position.dx > width * 0.62) {
      _seekRelative(const Duration(seconds: 10));
    } else {
      player.playOrPause();
    }
  }

  void _seekRelative(Duration delta) {
    final duration = player.state.duration;
    final current = player.state.position;
    var next = current + delta;
    if (next < Duration.zero) next = Duration.zero;
    if (duration > Duration.zero && next > duration) next = duration;
    player.seek(next);
    previewPlayer.seek(next);
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (_isLocked) return;
    _horizontalDragDx = 0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (_isLocked) return;
    _horizontalDragDx += details.delta.dx;
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_isLocked) return;
    final seconds = (_horizontalDragDx / 8).round().clamp(-90, 90);
    if (seconds != 0) {
      _seekRelative(Duration(seconds: seconds));
    }
    _horizontalDragDx = 0;
  }

  Future<void> _handleVerticalDragStart(DragStartDetails details) async {
    if (_isLocked) return;
    _gestureStartVolume = player.state.volume;
    try {
      _gestureStartBrightness = await ScreenBrightness.instance.application;
    } catch (_) {
      _gestureStartBrightness = 0.5;
    }
  }

  Future<void> _handleVerticalDragUpdate(DragUpdateDetails details) async {
    if (_isLocked) return;
    final size = MediaQuery.sizeOf(context);
    final delta = -details.primaryDelta! / math.max(size.height, 1);
    if (details.localPosition.dx < size.width / 2) {
      final next = (_gestureStartBrightness + delta).clamp(0.02, 1.0);
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(next);
      } catch (e) {
        LoggerService().log('[Player] Brightness gesture failed: $e');
      }
    } else {
      final next = (_gestureStartVolume + delta * 120).clamp(0.0, 100.0);
      player.setVolume(next);
      previewPlayer.setVolume(0);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (!_isLocked) player.playOrPause();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && !_isLocked) {
      _seekRelative(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight && !_isLocked) {
      _seekRelative(const Duration(seconds: 10));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: GlassPage(
        background: Transform.scale(
          scale: _scale,
          child: Video(
            controller: controller,
            controls: NoVideoControls,
            subtitleViewConfiguration: const SubtitleViewConfiguration(
              visible: false,
            ),
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Focus(
            autofocus: true,
            focusNode: _keyboardFocusNode,
            onKeyEvent: _handleKeyEvent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 2. Gesture Detector Layer
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTapDown: (details) {
                    _lastDoubleTapPosition = details.localPosition;
                  },
                  onTap: _toggleControls,
                  onDoubleTap: _handleDoubleTap,
                  onHorizontalDragStart: _handleHorizontalDragStart,
                  onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                  onHorizontalDragEnd: _handleHorizontalDragEnd,
                  onVerticalDragStart: _handleVerticalDragStart,
                  onVerticalDragUpdate: _handleVerticalDragUpdate,
                  onScaleUpdate: (details) {
                    if (_isLocked) return;
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
                                settings:
                                    RecommendedGlassSettings.playerHighlight,
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
                              settings:
                                  RecommendedGlassSettings.playerHighlight,
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

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: GlassButton.custom(
                              useOwnLayer: false,
                              width: 56,
                              height: 56,
                              settings:
                                  RecommendedGlassSettings.playerHighlight,
                              interactionScale: 1.08,
                              stretch: 0.75,
                              glowColor: const Color(0xFF8FEAFF),
                              glowOpacity: 0.45,
                              glowBlurRadius: 18,
                              shape: const LiquidOval(),
                              onTap: _toggleLock,
                              child: const Icon(
                                Icons.lock_rounded,
                                color: Colors.white,
                                size: 26,
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
                                settings:
                                    RecommendedGlassSettings.playerHighlight,
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
                    top: 96,
                    left: 16,
                    right: 16,
                    child: PerformanceHUD(
                      player: player,
                      controller: controller,
                    ),
                  ),
                if (_isLocked)
                  Center(
                    child: GlassButton.custom(
                      useOwnLayer: false,
                      width: 104,
                      height: 104,
                      settings: RecommendedGlassSettings.playerHighlight,
                      interactionScale: 1.04,
                      stretch: 0.55,
                      glowColor: Colors.white,
                      glowOpacity: 0.42,
                      glowBlurRadius: 22,
                      shape: const LiquidOval(),
                      onTap: _toggleLock,
                      child: const Icon(
                        Icons.lock_open_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RecommendedGlassSettings {
  static const playerPanel = LiquidGlassSettings(
    blur: 10, // Lighter frosted Gaussian blur
    thickness: 12, // Subtle and elegant boundary highlight rim
    shadowElevation: 2.0,
    glassColor: Color(
      0x0DFFFFFF,
    ), // Transparent frosted white tint (5% opacity)
    lightAngle: 0.75 * math.pi,
    lightIntensity: 0.8,
    ambientStrength:
        0.1, // Minimal ambient wash to keep it almost fully transparent
    saturation: 1.1,
    refractiveIndex: 1.1,
    chromaticAberration: 0.0, // Sharp text readability
    specularSharpness: GlassSpecularSharpness.medium,
  );

  static const playerSection = LiquidGlassSettings(
    blur: 0, // Inherits root layer's blur
    thickness: 14, // Delicate section highlight rim
    shadowElevation: 2.0,
    glassColor: Colors.transparent,
    lightAngle: 0.7 * math.pi,
    lightIntensity: 1.5,
    ambientStrength: 0.0,
    saturation: 1.32,
    refractiveIndex: 1.2,
    chromaticAberration: 0.0, // Sharp text readability
    glowIntensity: 0.4,
    specularSharpness: GlassSpecularSharpness.sharp,
  );

  static const playerHighlight = LiquidGlassSettings(
    blur: 0,
    thickness: 8, // Refined thin highlight rim for small slider thumbs
    shadowElevation: 2.0,
    glassColor: Colors.transparent,
    lightAngle: 0.7 * math.pi,
    lightIntensity: 1.5,
    ambientStrength: 0.0,
    saturation: 1.35,
    refractiveIndex: 1.2,
    chromaticAberration: 0.0, // Sharp highlights without dispersion fringing
    glowIntensity: 0.6,
    specularSharpness: GlassSpecularSharpness.sharp,
  );

  static const standard = LiquidGlassSettings(
    blur: 4,
    thickness: 10,
    shadowElevation: 2.0,
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
    shadowElevation: 2.0,
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
    shadowElevation: 2.0,
    glassColor: Color.fromRGBO(
      255,
      255,
      255,
      0.25,
    ), // Strong misty translucent white
    lightAngle: 0.75 * math.pi,
    lightIntensity: 1.5, // Brighter highlight glow
    ambientStrength: 0.4,
    saturation: 1.2,
    refractiveIndex: 1.3, // Bold prominent rim highlights
    chromaticAberration: 0.01,
  );
}
