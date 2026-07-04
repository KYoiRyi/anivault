import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:anivault/ui/ani_glass_theme.dart';

class CinematicEdgeBar extends StatefulWidget {
  final Player player;
  final Player? previewPlayer;
  final VideoController? previewController;

  const CinematicEdgeBar({
    super.key,
    required this.player,
    this.previewPlayer,
    this.previewController,
  });

  @override
  State<CinematicEdgeBar> createState() => _CinematicEdgeBarState();
}

class _CinematicEdgeBarState extends State<CinematicEdgeBar> {
  bool _isDragging = false;
  bool _isHovering = false;
  double _dragProgress = 0.0;
  double _dragX = 0.0;
  DateTime _lastSeekTime = DateTime.fromMillisecondsSinceEpoch(0);

  void _updateProgress(Offset localPosition, double width) {
    double newProgress = localPosition.dx / width;
    newProgress = newProgress.clamp(0.0, 1.0);
    setState(() {
      _dragProgress = newProgress;
      _dragX = localPosition.dx.clamp(0.0, width);
    });
  }

  void _throttledSeek(Duration target) {
    final now = DateTime.now();
    if (now.difference(_lastSeekTime).inMilliseconds > 180) {
      widget.player.seek(target);
      _lastSeekTime = now;
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = _isHovering || _isDragging ? 28.0 : 12.0;

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

          final effectiveProgress = _isDragging
              ? _dragProgress
              : actualProgress;
          final targetMillis = (effectiveProgress * total.inMilliseconds)
              .toInt();

          return LayoutBuilder(
            builder: (context, constraints) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Volumetric Glass Scrub Tooltip
                    if (_isDragging)
                      Positioned(
                        left: (_dragX - 168.0 / 2).clamp(
                          8.0,
                          constraints.maxWidth - 168.0 - 8.0,
                        ),
                        bottom: height + 16,
                        child: SizedBox(
                          width: 168.0,
                          child: GlassCard(
                            useOwnLayer: true,
                            quality: AniGlassTheme.quality,
                            settings: AniGlassTheme.playerPanelFor(context),
                            padding: const EdgeInsets.all(4),
                            shape: const LiquidRoundedSuperellipse(
                              borderRadius: 16,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.previewController != null)
                                  SizedBox(
                                    width: 160,
                                    height: 90,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Video(
                                        controller: widget.previewController!,
                                        controls: NoVideoControls,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Text(
                                  _formatDuration(
                                    Duration(milliseconds: targetMillis),
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Progress Bar Track
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (details) {
                        setState(() => _isDragging = true);
                        _updateProgress(
                          details.localPosition,
                          constraints.maxWidth,
                        );
                        if (widget.previewPlayer != null) {
                          widget.previewPlayer!.seek(
                            Duration(milliseconds: targetMillis),
                          );
                        } else {
                          _throttledSeek(Duration(milliseconds: targetMillis));
                        }
                      },
                      onHorizontalDragUpdate: (details) {
                        _updateProgress(
                          details.localPosition,
                          constraints.maxWidth,
                        );
                        if (widget.previewPlayer != null) {
                          widget.previewPlayer!.seek(
                            Duration(milliseconds: targetMillis),
                          );
                        } else {
                          _throttledSeek(Duration(milliseconds: targetMillis));
                        }
                      },
                      onHorizontalDragEnd: (details) async {
                        final target = Duration(milliseconds: targetMillis);
                        await widget.player.seek(target);
                        if (mounted) {
                          setState(() => _isDragging = false);
                        }
                      },
                      onTapDown: (details) {
                        _updateProgress(
                          details.localPosition,
                          constraints.maxWidth,
                        );
                        widget.player.seek(
                          Duration(milliseconds: targetMillis),
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        height: height,
                        width: double.infinity,
                        child: GlassCard(
                          useOwnLayer: true,
                          quality: AniGlassTheme.quality,
                          settings: AniGlassTheme.playerPanelFor(context),
                          padding: EdgeInsets.zero,
                          shape: const LiquidRoundedSuperellipse(
                            borderRadius: 8,
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.bottomLeft,
                            children: [
                              // Dark transparent background strip inside GlassCard
                              Container(
                                width: double.infinity,
                                height: double.infinity,
                                color: Colors.black.withValues(alpha: 0.15),
                              ),

                              // Volumetric Light Strip (Progress)
                              AnimatedContainer(
                                duration: _isDragging
                                    ? Duration.zero
                                    : const Duration(milliseconds: 150),
                                curve: Curves.easeOutCubic,
                                width: constraints.maxWidth * effectiveProgress,
                                height: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.white, Color(0xFFE2F0FF)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: 0.45,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, -6),
                                      spreadRadius: 1,
                                    ),
                                    BoxShadow(
                                      color: const Color(
                                        0xFF4A90E2,
                                      ).withValues(alpha: 0.4),
                                      blurRadius: 32,
                                      offset: const Offset(0, -12),
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                // Inner surface reflection
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    height: 1.5,
                                    width: double.infinity,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
