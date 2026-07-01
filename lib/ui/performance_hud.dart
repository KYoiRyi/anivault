import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PerformanceHUD extends StatefulWidget {
  final Player player;
  final VideoController? controller;

  const PerformanceHUD({super.key, required this.player, this.controller});

  @override
  State<PerformanceHUD> createState() => _PerformanceHUDState();
}

class _PerformanceHUDState extends State<PerformanceHUD> {
  static const _mpvProperties = [
    'vo',
    'current-vo',
    'hwdec',
    'hwdec-current',
    'hwdec-codecs',
    'video-codec',
    'video-codec-name',
    'video-codec-profile',
    'video-format',
    'video-out-params',
    'width',
    'height',
    'dwidth',
    'dheight',
    'container-fps',
    'estimated-vf-fps',
    'display-fps',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'mistimed-frame-count',
    'vsync-ratio',
    'estimated-display-fps',
    'video-bitrate',
    'packet-video-bitrate',
    'glsl-shaders',
    'vf',
    'gpu-api',
    'gpu-context',
    'opengl-backend',
    'd3d11-exclusive-fs',
    'spirv-compiler',
    'scale',
    'cscale',
    'dscale',
    'tscale',
    'interpolation',
    'video-sync',
    'video-timing-offset',
  ];

  final _recentTimings = Queue<FrameTiming>();
  Timer? _timer;
  double _rssMB = 0;
  int _framesReported = 0;
  int _uiFps = 0;
  double _avgBuildMs = 0;
  double _avgRasterMs = 0;
  double _p95TotalMs = 0;
  Map<String, String> _mpv = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    _sample();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
  }

  void _onTimings(List<FrameTiming> timings) {
    _framesReported += timings.length;
    for (final timing in timings) {
      _recentTimings.addLast(timing);
      while (_recentTimings.length > 180) {
        _recentTimings.removeFirst();
      }
    }
  }

  Future<void> _sample() async {
    final mpv = await _readMpvProperties();
    if (!mounted) return;

    final buildTimes = _recentTimings
        .map((t) => t.buildDuration.inMicroseconds / 1000.0)
        .toList();
    final rasterTimes = _recentTimings
        .map((t) => t.rasterDuration.inMicroseconds / 1000.0)
        .toList();
    final totalTimes =
        _recentTimings.map((t) => t.totalSpan.inMicroseconds / 1000.0).toList()
          ..sort();

    setState(() {
      _rssMB = ProcessInfo.currentRss / (1024 * 1024);
      _uiFps = _framesReported;
      _framesReported = 0;
      _avgBuildMs = _average(buildTimes);
      _avgRasterMs = _average(rasterTimes);
      _p95TotalMs = totalTimes.isEmpty
          ? 0
          : totalTimes[((totalTimes.length - 1) * 0.95).round()];
      _mpv = mpv;
    });
  }

  Future<Map<String, String>> _readMpvProperties() async {
    final platform = widget.player.platform;
    if (platform is! NativePlayer) {
      return const {'media_kit.platform': 'non-native player'};
    }

    final values = <String, String>{};
    for (final property in _mpvProperties) {
      values[property] = await _getMpvProperty(platform, property);
    }
    return values;
  }

  Future<String> _getMpvProperty(NativePlayer player, String property) async {
    try {
      final value = await player
          .getProperty(property)
          .timeout(const Duration(milliseconds: 180));
      if (value.trim().isEmpty) return 'empty';
      return value;
    } catch (_) {
      return 'unavailable';
    }
  }

  double _average(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeWidth = (media.size.width - media.padding.horizontal - 32).clamp(
      240.0,
      double.infinity,
    );
    final safeHeight = (media.size.height - media.padding.vertical - 48).clamp(
      260.0,
      double.infinity,
    );
    final panelWidth = safeWidth.clamp(300.0, 1480.0);
    final panelHeight = safeHeight.clamp(420.0, 900.0);
    final vp = widget.player.state.videoParams;
    final textureId = widget.controller?.id.value;
    final textureRect = widget.controller?.rect.value;
    final controllerImpl = widget.controller?.notifier.value;
    final config = controllerImpl?.configuration;
    final hwdecCurrent = _v('hwdec-current');
    final decodeMode = _decodeMode(
      requested: _v('hwdec'),
      current: hwdecCurrent,
      hwAccel: config?.enableHardwareAcceleration,
    );
    final renderMode = _renderMode(config?.enableHardwareAcceleration);
    final pipelineRows = <Widget>[
      _SectionTitle(
        icon: Icons.precision_manufacturing_rounded,
        label: 'IMAGE API / PIPELINE',
      ),
      _StatRow(label: 'decode mode', value: decodeMode),
      _StatRow(label: 'render mode', value: renderMode),
      ..._pipelineRows().map((row) => _StatRow(label: row.$1, value: row.$2)),
      _StatRow(label: 'mpv vo', value: _v('vo')),
      _StatRow(label: 'current vo', value: _v('current-vo')),
      _StatRow(label: 'gpu api', value: _v('gpu-api')),
      _StatRow(label: 'gpu context', value: _v('gpu-context')),
      _StatRow(label: 'opengl backend', value: _v('opengl-backend')),
      _StatRow(label: 'iOS collect', value: _iosCollectability()),
      _StatRow(
        label: 'texture id',
        value: textureId?.toString() ?? 'unavailable',
      ),
      _StatRow(label: 'texture rect', value: _formatRect(textureRect)),
      _StatRow(
        label: 'controller',
        value: controllerImpl.runtimeType.toString(),
      ),
      _StatRow(
        label: 'cfg hw accel',
        value: '${config?.enableHardwareAcceleration ?? 'unknown'}',
      ),
    ];
    final frameRows = <Widget>[
      _SectionTitle(
        icon: Icons.speed_rounded,
        label: 'VIDEO FPS / FRAME STATS',
      ),
      _StatRow(label: 'UI frames/s', value: '$_uiFps'),
      _StatRow(
        label: 'build avg',
        value: '${_avgBuildMs.toStringAsFixed(2)} ms',
      ),
      _StatRow(
        label: 'raster avg',
        value: '${_avgRasterMs.toStringAsFixed(2)} ms',
      ),
      _StatRow(
        label: 'total p95',
        value: '${_p95TotalMs.toStringAsFixed(2)} ms',
      ),
      _StatRow(
        label: 'scheduler phase',
        value: SchedulerBinding.instance.schedulerPhase.name,
      ),
      _StatRow(label: 'container fps', value: _v('container-fps')),
      _StatRow(label: 'estimated vf fps', value: _v('estimated-vf-fps')),
      _StatRow(label: 'display fps', value: _v('display-fps')),
      _StatRow(label: 'est display fps', value: _v('estimated-display-fps')),
      _StatRow(label: 'frame drops', value: _v('frame-drop-count')),
      _StatRow(label: 'decoder drops', value: _v('decoder-frame-drop-count')),
      _StatRow(label: 'mistimed', value: _v('mistimed-frame-count')),
      _StatRow(label: 'vsync ratio', value: _v('vsync-ratio')),
    ];
    final decodeRows = <Widget>[
      _SectionTitle(
        icon: Icons.movie_filter_rounded,
        label: 'VIDEO DECODE / FILTERS',
      ),
      _StatRow(label: 'hwdec', value: _v('hwdec')),
      _StatRow(label: 'hwdec current', value: _v('hwdec-current')),
      _StatRow(label: 'hwdec codecs', value: _v('hwdec-codecs')),
      _StatRow(label: 'codec', value: _v('video-codec')),
      _StatRow(label: 'codec name', value: _v('video-codec-name')),
      _StatRow(label: 'codec profile', value: _v('video-codec-profile')),
      _StatRow(label: 'pix fmt', value: _v('video-format')),
      _StatRow(label: 'out params', value: _v('video-out-params')),
      _StatRow(label: 'coded size', value: '${_v('width')}x${_v('height')}'),
      _StatRow(
        label: 'display size',
        value: '${_v('dwidth')}x${_v('dheight')}',
      ),
      _StatRow(label: 'glsl shaders', value: _v('glsl-shaders')),
      _StatRow(label: 'vf chain', value: _v('vf')),
    ];
    final renderRows = <Widget>[
      _SectionTitle(icon: Icons.tune_rounded, label: 'RENDER PARAMETERS'),
      _StatRow(label: 'scale', value: _v('scale')),
      _StatRow(label: 'cscale', value: _v('cscale')),
      _StatRow(label: 'dscale', value: _v('dscale')),
      _StatRow(label: 'tscale', value: _v('tscale')),
      _StatRow(label: 'interpolation', value: _v('interpolation')),
      _StatRow(label: 'video sync', value: _v('video-sync')),
      _StatRow(label: 'timing offset', value: _v('video-timing-offset')),
      _StatRow(label: 'video bitrate', value: _v('video-bitrate')),
      _StatRow(label: 'packet bitrate', value: _v('packet-video-bitrate')),
    ];
    final systemRows = <Widget>[
      _SectionTitle(icon: Icons.memory_rounded, label: 'SYSTEM SNAPSHOT'),
      _StatRow(label: 'OS', value: Platform.operatingSystem),
      _StatRow(label: 'CPU cores', value: '${Platform.numberOfProcessors}'),
      _StatRow(label: 'Dart', value: Platform.version.split(' ').first),
      _StatRow(label: 'RSS', value: '${_rssMB.toStringAsFixed(1)} MB'),
      _StatRow(label: 'cfg vo', value: config?.vo ?? 'platform default'),
      _StatRow(label: 'cfg hwdec', value: config?.hwdec ?? 'platform default'),
      _StatRow(label: 'cfg scale', value: '${config?.scale ?? 'unknown'}'),
      _StatRow(
        label: 'cfg size',
        value: '${config?.width ?? 'auto'}x${config?.height ?? 'auto'}',
      ),
      _StatRow(label: 'playing', value: '${widget.player.state.playing}'),
      _StatRow(label: 'buffering', value: '${widget.player.state.buffering}'),
      _StatRow(
        label: 'state params',
        value: vp.w != null ? '${vp.w}x${vp.h}' : 'unknown',
      ),
    ];
    final content = panelWidth >= 1180
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _HudColumn(children: pipelineRows)),
              const SizedBox(width: 18),
              Expanded(
                child: _HudColumn(
                  children: [...frameRows, _gap, ...decodeRows],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _HudColumn(
                  children: [...renderRows, _gap, ...systemRows],
                ),
              ),
            ],
          )
        : panelWidth >= 760
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _HudColumn(
                  children: [...pipelineRows, _gap, ...frameRows],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _HudColumn(
                  children: [
                    ...decodeRows,
                    _gap,
                    ...renderRows,
                    _gap,
                    ...systemRows,
                  ],
                ),
              ),
            ],
          )
        : _HudColumn(
            children: [
              ...pipelineRows,
              _gap,
              ...frameRows,
              _gap,
              ...decodeRows,
              _gap,
              ...renderRows,
              _gap,
              ...systemRows,
            ],
          );

    return GlassCard(
      useOwnLayer: true,
      width: panelWidth,
      padding: const EdgeInsets.all(16),
      shape: const LiquidRoundedSuperellipse(borderRadius: 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: panelHeight),
        child: SingleChildScrollView(child: content),
      ),
    );
  }

  String _v(String key) => _mpv[key] ?? 'pending';

  String _decodeMode({
    required String requested,
    required String current,
    required bool? hwAccel,
  }) {
    if (hwAccel == false) {
      return 'software decode/render requested by VideoController';
    }
    final normalized = current.trim().toLowerCase();
    if (normalized.isNotEmpty &&
        normalized != 'empty' &&
        normalized != 'no' &&
        normalized != 'unavailable' &&
        normalized != 'pending') {
      return 'hardware decode active: $current';
    }
    if (requested == 'auto' || requested == 'auto-copy') {
      return 'hardware decode requested: $requested; active decoder not reported by mpv';
    }
    return 'decode state not reported by mpv';
  }

  String _renderMode(bool? hwAccel) {
    if (Platform.isWindows) {
      return hwAccel == false
          ? 'software path: MPV_RENDER_API_TYPE_SW -> rgb0 pixel buffer -> Flutter texture'
          : 'hardware path: mpv OpenGL render context -> ANGLE/EGL surface -> OpenGL FBO -> Flutter texture';
    }
    if (Platform.isIOS) {
      return hwAccel == false
          ? 'SW texture: MPV_RENDER_API_TYPE_SW -> CVPixelBuffer'
          : 'HW texture: OpenGLES + CVOpenGLESTextureCache -> FlutterTexture';
    }
    if (Platform.isMacOS) {
      return hwAccel == false
          ? 'SW texture: MPV_RENDER_API_TYPE_SW -> CVPixelBuffer'
          : 'HW texture: OpenGL + CVOpenGLTextureCache -> FlutterTexture';
    }
    return hwAccel == false ? 'software texture path' : 'hardware texture path';
  }

  String _iosCollectability() {
    if (Platform.isIOS) {
      return 'available in app: NativePlayer mpv properties + VideoController texture/config; exact HW API inferred from media_kit_video iOS source';
    }
    return 'confirmed for iOS: same Dart NativePlayer/VideoController probes; missing mpv fields print unavailable';
  }

  String _formatRect(Rect? rect) {
    if (rect == null) return 'unavailable';
    return '${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)} @ ${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)}';
  }

  List<(String, String)> _pipelineRows() {
    if (Platform.isWindows) {
      return const [
        ('platform focus', 'Windows'),
        ('Flutter path', 'TextureRegistrar + MarkTextureFrameAvailable'),
        ('media_kit_video', 'VideoOutput.cc / ThreadPool'),
        ('HW render API', 'mpv_render_context + MPV_RENDER_API_TYPE_OPENGL'),
        ('HW bridge', 'ANGLE/EGL surface + OpenGL FBO'),
        ('SW fallback', 'MPV_RENDER_API_TYPE_SW + rgb0 pixel buffer'),
        ('SW max buffer', '1920x1080 RGBA allocation'),
        ('custom hook', 'ArtCNN may mutate SW pixel buffer when enabled'),
      ];
    }
    if (Platform.isIOS || Platform.isMacOS) {
      final platform = Platform.isIOS ? 'iOS' : 'macOS';
      final hwApi = Platform.isIOS
          ? 'MPV_RENDER_API_TYPE_OPENGL + OpenGLES'
          : 'MPV_RENDER_API_TYPE_OPENGL + OpenGL';
      final hwTexture = Platform.isIOS
          ? 'TextureHW + CVOpenGLESTextureCache + FlutterTexture'
          : 'TextureHW + CVOpenGLTextureCache + FlutterTexture';
      return [
        ('platform focus', platform),
        ('Flutter path', 'FlutterTextureRegistry + textureFrameAvailable'),
        ('media_kit_video', 'VideoOutput.swift + worker queue'),
        ('HW render API', hwApi),
        ('HW texture', hwTexture),
        ('SW texture', 'SafeResizableTexture(TextureSW)'),
        ('SW render API', 'MPV_RENDER_API_TYPE_SW + CVPixelBuffer'),
        ('SW format', 'bgr0'),
        ('simulator', 'forces SW when OpenGL ES HW path is incompatible'),
      ];
    }
    return const [
      ('platform focus', 'not Windows/iOS'),
      (
        'pipeline',
        'query mpv properties above; plugin details not specialized',
      ),
    ];
  }
}

const _gap = SizedBox(height: 8);

String _softBreak(String value) {
  return value
      .replaceAll('->', '->\u200B')
      .replaceAll('_', '_\u200B')
      .replaceAll('/', '/\u200B')
      .replaceAll('+', '+\u200B')
      .replaceAll(';', ';\u200B')
      .replaceAll(',', ',\u200B')
      .replaceAll(' ', ' \u200B');
}

class _HudColumn extends StatelessWidget {
  final List<Widget> children;

  const _HudColumn({required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 15),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidth = constraints.maxWidth < 420 ? 112.0 : 142.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(
                  label,
                  softWrap: true,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Consolas',
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _softBreak(value),
                  textAlign: TextAlign.left,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.8,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Consolas',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
