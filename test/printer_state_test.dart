import 'package:flutter_test/flutter_test.dart';
import 'package:carbon_copy/models/printer_state.dart';

// Payload captured from a Centauri Carbon 2 mid-print.
Map<String, dynamic> _printing(
        {int subStatus = 2075, String state = 'printing'}) =>
    {
      'machine_status': {'progress': 68, 'status': 2, 'sub_status': subStatus},
      'print_status': {
        'current_layer': 87,
        'filename': 'x.gcode',
        'print_duration': 1116,
        'remaining_time_sec': 525,
        'state': state,
        'total_duration': 1402,
      },
    };

void main() {
  test('printing with the known sub_status', () {
    final s = PrinterState.fromCentauri(_printing());
    expect(s.state, 'printing');
    expect(s.progress, closeTo(0.68, 1e-9));
  });

  test('printing is still detected when sub_status is unknown', () {
    expect(PrinterState.fromCentauri(_printing(subStatus: 9999)).state,
        'printing');
    expect(
        PrinterState.fromCentauri(_printing(subStatus: 9999, state: '')).state,
        'printing');
  });

  test('idle printer is standby', () {
    final s = PrinterState.fromCentauri({
      'machine_status': {'progress': 0, 'status': 1, 'sub_status': 0},
      'print_status': {'state': ''},
    });
    expect(s.state, 'standby');
  });
}
