import 'package:flutter/material.dart';
import '../models/canvas_info.dart';

class CanvasOverlay extends StatelessWidget {
  final CanvasInfo canvas;

  const CanvasOverlay({super.key, required this.canvas});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('CANVAS',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              if (canvas.autoRefill)
                const Text('auto-refill',
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 4),
          for (final t in canvas.trays) _row(t),
        ],
      ),
    );
  }

  Widget _row(CanvasTray t) {
    final active = canvas.isActive(t);
    final label = t.loaded
        ? [if (t.type.isNotEmpty) t.type, if (t.name != t.type) t.name]
            .join(' · ')
        : 'Empty';
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: active ? Colors.greenAccent : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Text('${t.trayId + 1}',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 6),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.loaded && t.colorValue != null
                  ? Color(t.colorValue!)
                  : Colors.transparent,
              border: Border.all(color: Colors.white38),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.loaded ? Colors.white : Colors.white38,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
