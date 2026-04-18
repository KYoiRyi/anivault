import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

class GlassmorphismPlayerControls extends StatelessWidget {
  final Player player;
  
  const GlassmorphismPlayerControls({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0),
        child: Container(
          height: 90,
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(32.0),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 30,
                spreadRadius: -10,
                offset: const Offset(0, 20),
              )
            ]
          ),
          child: Row(
            children: [
              // Play/Pause Button
              StreamBuilder<bool>(
                stream: player.stream.playing,
                builder: (context, playing) {
                  final isPlaying = playing.data ?? false;
                  return _PremiumButton(
                    onTap: () => player.playOrPause(),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeInCirc,
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                          scale: animation,
                          child: FadeTransition(opacity: animation, child: child),
                        );
                      },
                      child: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key: ValueKey<bool>(isPlaying),
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 24),
              
              // Volumetric 3D Progress Bar
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: player.stream.position,
                  builder: (context, position) {
                    final pos = position.data ?? Duration.zero;
                    final total = player.state.duration;
                    
                    double progress = 0.0;
                    if (total.inMilliseconds > 0) {
                      progress = pos.inMilliseconds / total.inMilliseconds;
                      progress = progress.clamp(0.0, 1.0);
                    }
                    
                    return VolumetricProgressBar(
                      progress: progress,
                      onSeek: (newProgress) {
                        final targetMillis = (newProgress * total.inMilliseconds).toInt();
                        player.seek(Duration(milliseconds: targetMillis));
                      },
                    );
                  },
                ),
              ),
              
              const SizedBox(width: 24),
              // Settings Button
              _PremiumButton(
                onTap: () {
                  player.seek(Duration.zero);
                },
                child: const Icon(
                  Icons.settings_backup_restore_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PremiumButton({required this.child, required this.onTap});

  @override
  State<_PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<_PremiumButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(_isPressed ? 0.9 : 1.0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: _isPressed ? 0.2 : 0.0),
        ),
        child: widget.child,
      ),
    );
  }
}

class VolumetricProgressBar extends StatefulWidget {
  final double progress;
  final ValueChanged<double> onSeek;

  const VolumetricProgressBar({super.key, required this.progress, required this.onSeek});

  @override
  State<VolumetricProgressBar> createState() => _VolumetricProgressBarState();
}

class _VolumetricProgressBarState extends State<VolumetricProgressBar> {
  bool _isDragging = false;
  double _dragProgress = 0.0;

  void _updateProgress(Offset localPosition, Size size) {
    double newProgress = localPosition.dx / size.width;
    newProgress = newProgress.clamp(0.0, 1.0);
    setState(() {
      _dragProgress = newProgress;
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = _isDragging ? _dragProgress : widget.progress;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            setState(() => _isDragging = true);
            _updateProgress(details.localPosition, constraints.biggest);
          },
          onHorizontalDragUpdate: (details) {
            _updateProgress(details.localPosition, constraints.biggest);
          },
          onHorizontalDragEnd: (details) {
            setState(() => _isDragging = false);
            widget.onSeek(_dragProgress);
          },
          onTapDown: (details) {
            _updateProgress(details.localPosition, constraints.biggest);
            widget.onSeek(_dragProgress);
          },
          child: Container(
            height: 40, // Expanded hit area
            alignment: Alignment.center,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                // 1. Dark Beveled Track (The groove)
                Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    color: Colors.black.withValues(alpha: 0.3),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.5), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.15),
                        offset: const Offset(0, 1),
                        blurRadius: 1,
                      )
                    ],
                  ),
                ),
                
                // 2. The Volumetric Glowing Fluid (Progress Fill)
                AnimatedContainer(
                  duration: _isDragging ? Duration.zero : const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  height: 14,
                  width: constraints.maxWidth * effectiveProgress,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.95),
                        Colors.white.withValues(alpha: 0.75),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                        offset: const Offset(0, 0),
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: _isDragging ? 0.3 : 0.0),
                        blurRadius: 20,
                        spreadRadius: 6,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  // Inner bright highlight to simulate fluid surface reflection
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
