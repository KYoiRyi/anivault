import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'dart:ui';

class CinematicEdgeBar extends StatefulWidget {
  final Player player;

  const CinematicEdgeBar({super.key, required this.player});

  @override
  State<CinematicEdgeBar> createState() => _CinematicEdgeBarState();
}

class _CinematicEdgeBarState extends State<CinematicEdgeBar> {
  bool _isDragging = false;
  bool _isHovering = false;
  double _dragProgress = 0.0;

  void _updateProgress(Offset localPosition, double width) {
    double newProgress = localPosition.dx / width;
    newProgress = newProgress.clamp(0.0, 1.0);
    setState(() {
      _dragProgress = newProgress;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Increased base height for mobile touch targets
    final height = _isHovering || _isDragging ? 32.0 : 12.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: StreamBuilder<Duration>(
        stream: widget.player.stream.position,
        builder: (context, position) {
          final pos = position.data ?? Duration.zero;
          final total = widget.player.state.duration;

          double actualProgress = 0.0;
          if (total.inMilliseconds > 0) {
            actualProgress = pos.inMilliseconds / total.inMilliseconds;
            actualProgress = actualProgress.clamp(0.0, 1.0);
          }

          final effectiveProgress = _isDragging ? _dragProgress : actualProgress;

          return LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) {
                  setState(() => _isDragging = true);
                  _updateProgress(details.localPosition, constraints.maxWidth);
                },
                onHorizontalDragUpdate: (details) {
                  _updateProgress(details.localPosition, constraints.maxWidth);
                },
                onHorizontalDragEnd: (details) {
                  setState(() => _isDragging = false);
                  final targetMillis = (_dragProgress * total.inMilliseconds).toInt();
                  widget.player.seek(Duration(milliseconds: targetMillis));
                },
                onTapDown: (details) {
                  _updateProgress(details.localPosition, constraints.maxWidth);
                  final targetMillis = (_dragProgress * total.inMilliseconds).toInt();
                  widget.player.seek(Duration(milliseconds: targetMillis));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  height: height,
                  width: double.infinity,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomLeft,
                    children: [
                      // Dark transparent background strip
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.black.withValues(alpha: 0.2),
                      ),
                      
                      // Volumetric Light Strip (Progress)
                      AnimatedContainer(
                        duration: _isDragging ? Duration.zero : const Duration(milliseconds: 150),
                        curve: Curves.easeOutCubic,
                        width: constraints.maxWidth * effectiveProgress,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.9),
                              Colors.white.withValues(alpha: 0.6),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.4),
                              blurRadius: 20,
                              offset: const Offset(0, -10), // Glow upwards into the video!
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: const Color(0xFF4A90E2).withValues(alpha: 0.3), // Cyan/Blueish tint
                              blurRadius: 40,
                              offset: const Offset(0, -20),
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        // Inner surface reflection at the very top edge
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            height: 1.5,
                            width: double.infinity,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
