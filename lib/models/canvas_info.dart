class CanvasTray {
  final int canvasId;
  final int trayId;
  final String brand;
  final String type;
  final String name;
  final int? colorValue;
  final bool loaded;

  const CanvasTray({
    required this.canvasId,
    required this.trayId,
    required this.brand,
    required this.type,
    required this.name,
    required this.colorValue,
    required this.loaded,
  });
}

class CanvasInfo {
  final int activeCanvasId;
  final int activeTrayId;
  final bool autoRefill;
  final List<CanvasTray> trays;

  const CanvasInfo({
    required this.activeCanvasId,
    required this.activeTrayId,
    required this.autoRefill,
    required this.trays,
  });

  bool isActive(CanvasTray t) =>
      t.canvasId == activeCanvasId && t.trayId == activeTrayId;

  /// Parses the `canvas_info` object (method 2005 result). Returns null when
  /// no canvas is connected.
  static CanvasInfo? fromJson(Map<String, dynamic> json) {
    final trays = <CanvasTray>[];
    for (final c in (json['canvas_list'] as List? ?? const [])) {
      if (c is! Map || c['connected'] == 0) continue;
      final canvasId = (c['canvas_id'] as num?)?.toInt() ?? 0;
      for (final t in (c['tray_list'] as List? ?? const [])) {
        if (t is! Map) continue;
        trays.add(CanvasTray(
          canvasId: canvasId,
          trayId: (t['tray_id'] as num?)?.toInt() ?? trays.length,
          brand: t['brand'] as String? ?? '',
          type: t['filament_type'] as String? ?? '',
          name: t['filament_name'] as String? ?? '',
          colorValue: _parseColor(t['filament_color'] as String?),
          loaded: t['status'] == 1 || t['status'] == 2, // 2 = currently feeding
        ));
      }
    }
    if (trays.isEmpty) return null;
    return CanvasInfo(
      activeCanvasId: (json['active_canvas_id'] as num?)?.toInt() ?? -1,
      activeTrayId: (json['active_tray_id'] as num?)?.toInt() ?? -1,
      autoRefill: json['auto_refill'] == true,
      trays: trays,
    );
  }

  static int? _parseColor(String? hex) {
    if (hex == null) return null;
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : 0xFF000000 | v;
  }
}
