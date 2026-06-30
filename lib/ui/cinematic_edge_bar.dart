import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class CinematicEdgeBar extends StatefulWidget {
  final Player player;

  const CinematicEdgeBar({super.key, required this.player});

  @override
  State<CinematicEdgeBar> createState() => _CinematicEdgeBarState();
}

class _CinematicEdgeBarState extends State<CinematicEdgeBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.position,
      builder: (context, positionSnapshot) {
        final pos = positionSnapshot.data ?? Duration.zero;
        final total = widget.player.state.duration;
        final totalMs = total.inMilliseconds.toDouble();

        double sliderValue = 0.0;
        if (totalMs > 0) {
          sliderValue = pos.inMilliseconds.toDouble().clamp(0.0, totalMs);
        }

        final displayValue = _isDragging ? _dragValue : sliderValue;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: GlassSlider(
            useOwnLayer: true,
            value: displayValue.clamp(0.0, totalMs > 0 ? totalMs : 1.0),
            min: 0.0,
            max: totalMs > 0 ? totalMs : 1.0,
            activeColor: Colors.white,
            thumbColor: Colors.white,
            trackHeight: 6.0,
            thumbRadius: 10.0,
            onChangeStart: (val) {
              setState(() {
                _isDragging = true;
                _dragValue = val;
              });
            },
            onChanged: (val) {
              setState(() {
                _dragValue = val;
              });
            },
            onChangeEnd: (val) {
              setState(() {
                _isDragging = false;
              });
              widget.player.seek(Duration(milliseconds: val.toInt()));
            },
          ),
        );
      },
    );
  }
}
