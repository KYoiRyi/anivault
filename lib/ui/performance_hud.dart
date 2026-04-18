import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

class PerformanceHUD extends StatefulWidget {
  final Player player;
  
  const PerformanceHUD({super.key, required this.player});

  @override
  State<PerformanceHUD> createState() => _PerformanceHUDState();
}

class _PerformanceHUDState extends State<PerformanceHUD> {
  Timer? _timer;
  double _memMB = 0.0;
  int _uiFps = 60;
  int _framesRendered = 0;
  String _videoFps = '-.--';
  
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      try {
        final platform = widget.player.platform;
        String vfFpsStr = '-.--';
        if (platform is NativePlayer) {
          final res = await platform.getProperty('estimated-vf-fps');
          if (res.isNotEmpty) {
            final parsed = double.tryParse(res);
            if (parsed != null) vfFpsStr = parsed.toStringAsFixed(2);
          }
        }
        if (mounted) {
          setState(() {
            _memMB = ProcessInfo.currentRss / (1024 * 1024);
            _uiFps = _framesRendered;
            _framesRendered = 0;
            _videoFps = vfFpsStr;
          });
        }
      } catch (e) {
        // Ignored
      }
    });

    WidgetsBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    _framesRendered += timings.length;
  }
  
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.0),
            ),
            child: StreamBuilder<VideoParams>(
              stream: widget.player.stream.videoParams,
              builder: (context, snapshot) {
                final vp = snapshot.data ?? widget.player.state.videoParams;
                final res = vp.w != null ? '${vp.w}x${vp.h}' : 'Unknown';

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speed_rounded, color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'SYSTEM TELEMETRY',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StatRow(label: 'RAM Use', value: '${_memMB.toStringAsFixed(1)} MB'),
                    const SizedBox(height: 6),
                    _StatRow(label: 'Video Res', value: res),
                    const SizedBox(height: 6),
                    _StatRow(label: 'V-FPS (Real)', value: _videoFps),
                    const SizedBox(height: 6),
                    _StatRow(label: 'UI-FPS', value: '$_uiFps'),
                    const SizedBox(height: 6),
                    _StatRow(label: 'Decoder', value: 'D3D11VA (Zero-Copy)'),
                    const SizedBox(height: 6),
                    _StatRow(label: 'Backend', value: 'MediaKit / GPU-NEXT'),
                  ],
                );
              },
            ),
          ),
        ),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            fontFamily: 'Consolas', // Monospace hint
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'Consolas',
          ),
        ),
      ],
    );
  }
}
