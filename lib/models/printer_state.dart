class PrinterState {
  final String state;
  final String? filename;
  final double progress;
  final double printDuration;
  final double totalDuration;
  final double? estimatedTotalTime;
  final double extruderTemp;
  final double extruderTarget;
  final double extruderPower;
  final double bedTemp;
  final double bedTarget;
  final double bedPower;
  final double? chamberTemp;
  // Fan speeds as 0-100 percent; null when the printer didn't report them.
  final double? modelFanPct;
  final double? auxFanPct;
  final double? caseFanPct;
  final String? message;
  final double speed; // mm/s
  final double speedFactor; // multiplier (1.0 = 100%)
  final double extrudeFactor;
  final int? currentLayer;
  final int? totalLayer;

  PrinterState({
    required this.state,
    this.filename,
    required this.progress,
    required this.printDuration,
    required this.totalDuration,
    this.estimatedTotalTime,
    required this.extruderTemp,
    required this.extruderTarget,
    this.extruderPower = 0.0,
    required this.bedTemp,
    required this.bedTarget,
    this.bedPower = 0.0,
    this.chamberTemp,
    this.modelFanPct,
    this.auxFanPct,
    this.caseFanPct,
    this.message,
    this.speed = 0.0,
    this.speedFactor = 1.0,
    this.extrudeFactor = 1.0,
    this.currentLayer,
    this.totalLayer,
  });

  factory PrinterState.idle() => PrinterState(
        state: 'standby',
        progress: 0,
        printDuration: 0,
        totalDuration: 0,
        extruderTemp: 0,
        extruderTarget: 0,
        bedTemp: 0,
        bedTarget: 0,
      );

  /// Builds state from the merged CC2 status map (see [CentauriService]).
  /// Status-code mapping is reconstructed from reverse-engineered community
  /// docs, not an official spec — verify against the debug overlay if a
  /// printer state ever looks wrong.
  factory PrinterState.fromCentauri(Map<String, dynamic> status) {
    Map<String, dynamic> sub(String k) =>
        (status[k] as Map?)?.cast<String, dynamic>() ?? const {};

    final printStatus = sub('print_status');
    final extruder = sub('extruder');
    final heaterBed = sub('heater_bed');
    final machineStatus = sub('machine_status');
    final chamber = sub('ztemperature_sensor');
    final fans = sub('fans');

    // Fan speeds are reported on a 0-255 scale.
    double? fanPct(String key) {
      final speed = ((fans[key] as Map?)?['speed'] as num?)?.toDouble();
      return speed == null ? null : (speed / 255 * 100).clamp(0.0, 100.0);
    }

    final subStatus = (status['sub_status'] as num?)?.toInt() ??
        (machineStatus['sub_status'] as num?)?.toInt();

    final currentLayer = (printStatus['current_layer'] as num?)?.toInt();
    final totalLayer = (printStatus['total_layer'] as num?)?.toInt();
    final printDuration =
        (printStatus['print_duration'] as num?)?.toDouble() ?? 0.0;
    final totalDuration =
        (printStatus['total_duration'] as num?)?.toDouble() ?? 0.0;
    final remainingSec =
        (printStatus['remaining_time_sec'] as num?)?.toDouble();

    // machine_status.progress (0-100) is what the printer's own screen shows;
    // total_duration is not the estimated total, so it only serves as a
    // fallback.
    final reportedProgress = (machineStatus['progress'] as num?)?.toDouble();

    double progress = 0.0;
    if (reportedProgress != null) {
      progress = reportedProgress / 100;
    } else if (totalDuration > 0) {
      progress = printDuration / totalDuration;
    } else if (currentLayer != null && totalLayer != null && totalLayer > 0) {
      progress = currentLayer / totalLayer;
    } else if (remainingSec != null && remainingSec >= 0 && printDuration > 0) {
      final total = printDuration + remainingSec;
      if (total > 0) progress = printDuration / total;
    }
    progress = progress.clamp(0.0, 1.0);

    double? estimatedTotalTime;
    if (remainingSec != null && remainingSec >= 0) {
      estimatedTotalTime = printDuration + remainingSec;
    } else if (progress > 0.005 && printDuration > 5) {
      estimatedTotalTime = printDuration / progress;
    }

    final extruderTarget = (extruder['target'] as num?)?.toDouble() ?? 0.0;
    final bedTarget = (heaterBed['target'] as num?)?.toDouble() ?? 0.0;

    return PrinterState(
      state: _mapState(
        printState: (printStatus['state'] as String?) ?? '',
        machineState: (machineStatus['status'] as num?)?.toInt(),
        subStatus: subStatus,
        progress: progress,
      ),
      filename: (printStatus['filename'] as String?)?.isEmpty == true
          ? null
          : printStatus['filename'] as String?,
      progress: progress,
      printDuration: printDuration,
      totalDuration: totalDuration,
      estimatedTotalTime: estimatedTotalTime,
      extruderTemp: (extruder['temperature'] as num?)?.toDouble() ?? 0.0,
      extruderTarget: extruderTarget,
      extruderPower: extruderTarget > 0 ? 1.0 : 0.0,
      bedTemp: (heaterBed['temperature'] as num?)?.toDouble() ?? 0.0,
      bedTarget: bedTarget,
      bedPower: bedTarget > 0 ? 1.0 : 0.0,
      chamberTemp: (chamber['temperature'] as num?)?.toDouble(),
      modelFanPct: fanPct('fan'),
      auxFanPct: fanPct('aux_fan'),
      caseFanPct: fanPct('box_fan'),
      currentLayer: currentLayer,
      totalLayer: totalLayer,
    );
  }

  // Prefers print_status.state (a plain string) and machine_status.status
  // (2 = printing) over the sub_status code table, which is incomplete: an
  // unknown sub_status used to make an active print show as 'standby'.
  static String _mapState({
    required String printState,
    required int? machineState,
    required int? subStatus,
    required double progress,
  }) {
    switch (printState.toLowerCase()) {
      case 'printing':
        return 'printing';
      case 'paused':
      case 'pausing':
        return 'paused';
      case 'stopped':
      case 'stopping':
      case 'cancelled':
      case 'canceled':
        return 'cancelled';
      case 'complete':
      case 'completed':
      case 'finished':
        return 'complete';
      case 'error':
        return 'error';
    }
    if (machineState == 2) return 'printing';
    switch (subStatus) {
      case 1045: // preheating
      case 2075: // printing
        return 'printing';
      case 2502:
        return 'paused';
      case 2504:
        return 'cancelled';
    }
    if (subStatus != null && progress >= 0.999) return 'complete';
    return 'standby';
  }

  String get formatElapsed => _fmt(printDuration);

  String get formatRemaining {
    if (estimatedTotalTime == null) return '--:--';
    final remaining = estimatedTotalTime! - printDuration;
    return remaining < 0 ? '00:00' : _fmt(remaining);
  }

  String get etaWallClock {
    if (estimatedTotalTime == null) return '';
    final remaining = estimatedTotalTime! - printDuration;
    if (remaining <= 0) return '';
    final eta = DateTime.now().add(Duration(seconds: remaining.round()));
    return '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
  }

  static String _fmt(double seconds) {
    final d = Duration(seconds: seconds.round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}
