import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/canvas_info.dart';
import '../models/printer_state.dart';

/// Talks to an Elegoo Centauri Carbon 2 over its LAN-only protocol: MQTT
/// 3.1.1, with the printer itself acting as the broker on port 1883.
///
/// Reconstructed from reverse-engineered community docs (no official spec),
/// so message shapes are matched defensively. Method numbers (1001/1002 status,
/// 2005 canvas, 1045 thumbnail, ...) and delta-merge behaviour follow
/// https://github.com/runnane/elegoo-web/blob/main/src/printer-state.ts Every raw payload is also
/// pushed onto [consoleStream] as a debug log so mismatches are visible.
class CentauriService {
  final String host;
  final String accessCode;
  final String serialNumber;

  MqttServerClient? _client;
  String? _clientId;
  int _msgId = 1;
  bool _registered = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _statusRefreshTimer;
  Timer? _registerFallbackTimer;
  bool _disposed = false;
  bool _suspended = false;

  final _stateController = StreamController<PrinterState>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _consoleController = StreamController<String>.broadcast();
  final _canvasController = StreamController<CanvasInfo?>.broadcast();
  final Map<String, dynamic> _accumulated = {};

  Stream<PrinterState> get stateStream => _stateController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get consoleStream => _consoleController.stream;
  Stream<CanvasInfo?> get canvasStream => _canvasController.stream;

  CentauriService({
    required this.host,
    required this.accessCode,
    required this.serialNumber,
  });

  String get _requestTopic => 'elegoo/$serialNumber/$_clientId/api_request';
  String get _responseTopic => 'elegoo/$serialNumber/$_clientId/api_response';
  String get _statusTopic => 'elegoo/$serialNumber/api_status';
  String get _registerTopic => 'elegoo/$serialNumber/api_register';

  static const _knownStatusKeys = {
    'machine_status',
    'print_status',
    'extruder',
    'heater_bed',
    'ztemperature_sensor',
    'sub_status',
    'fans',
    'gcode_move_inf',
    'toolhead',
  };

  void connect() {
    if (_disposed || _suspended) return;
    _registered = false;
    _clientId = _genId('0cli');
    final client = MqttServerClient(host, _clientId!);
    client.port = 1883;
    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.autoReconnect = false;
    client.onDisconnected = () => _scheduleReconnect();
    client.setProtocolV311();
    _client = client;

    client.connect('elegoo', accessCode).then((_) {
      if (_disposed || _suspended) return;
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        _scheduleReconnect();
        return;
      }
      _onConnected(client);
    }).catchError((_) {
      _scheduleReconnect();
    });
  }

  void _onConnected(MqttServerClient client) {
    _connectionController.add(true);
    client.updates!.listen(_onMessage, onError: (_) => _scheduleReconnect());

    final requestId = _genId('req');
    client.subscribe(
      'elegoo/$serialNumber/$requestId/register_response',
      MqttQos.atMostOnce,
    );
    client.subscribe(_statusTopic, MqttQos.atMostOnce);
    client.subscribe(_responseTopic, MqttQos.atMostOnce);

    _publish({'client_id': _clientId, 'request_id': requestId},
        topic: _registerTopic);

    _registerFallbackTimer?.cancel();
    _registerFallbackTimer =
        Timer(const Duration(milliseconds: 900), _afterRegistered);
  }

  void _afterRegistered() {
    if (_registered || _client == null) return;
    _registered = true;

    _publish({'id': _msgId++, 'method': 1001, 'params': {}}); // attributes
    _publish({'id': _msgId++, 'method': 1002, 'params': {}}); // full status
    _publish({'id': _msgId++, 'method': 2005, 'params': {}}); // canvas info
    _publish({
      'id': _msgId++,
      'method': 1042,
      'params': {'enable': true},
    }); // enable camera

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _publish({'type': 'PING'}),
    );
    _statusRefreshTimer?.cancel();
    _statusRefreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) {
        _publish({'id': _msgId++, 'method': 1002, 'params': {}});
        _publish({'id': _msgId++, 'method': 2005, 'params': {}});
      },
    );
  }

  /// Requests the printer stop the current print (used by the e-stop
  /// button). Fire-and-forget, matching the panic-button intent.
  void stopPrint() {
    _publish({'id': _msgId++, 'method': 1022, 'params': {}});
  }

  void _publish(Map<String, dynamic> msg, {String? topic}) {
    final client = _client;
    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(msg));
      client.publishMessage(
        topic ?? _requestTopic,
        MqttQos.atMostOnce,
        builder.payload!,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final m in messages) {
      final publish = m.payload as MqttPublishMessage;
      final raw =
          MqttPublishPayload.bytesToStringAsString(publish.payload.message);
      _consoleController.add(_truncate(raw));

      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final map = decoded.cast<String, dynamic>();

        if (m.topic.endsWith('/register_response')) {
          if (map['error'] == 'ok') _afterRegistered();
          continue;
        }

        final canvas = _extractCanvas(map);
        if (canvas != null) {
          _canvasController.add(CanvasInfo.fromJson(canvas));
          continue;
        }

        final payload = _extractStatusPayload(map);
        if (payload != null) {
          _merge(payload);
          _stateController.add(PrinterState.fromCentauri(_accumulated));
        }
      } catch (_) {
        // ignore malformed payloads
      }
    }
  }

  Map<String, dynamic>? _extractCanvas(Map<String, dynamic> data) {
    for (final candidate in [data, data['result'], data['data']]) {
      if (candidate is Map && candidate['canvas_info'] is Map) {
        return (candidate['canvas_info'] as Map).cast<String, dynamic>();
      }
    }
    return null;
  }

  Map<String, dynamic>? _extractStatusPayload(Map<String, dynamic> data) {
    for (final candidate in [
      data,
      data['status'],
      data['data'],
      data['result']
    ]) {
      if (candidate is Map) {
        final m = candidate.cast<String, dynamic>();
        if (m.keys.any(_knownStatusKeys.contains)) return m;
      }
    }
    return null;
  }

  void _merge(Map<String, dynamic> incoming) {
    incoming.forEach((key, value) {
      if (value is Map) {
        final existing = _accumulated[key];
        if (existing is Map) {
          _accumulated[key] = {
            ...existing.cast<String, dynamic>(),
            ...value.cast<String, dynamic>(),
          };
        } else {
          _accumulated[key] = value.cast<String, dynamic>();
        }
      } else {
        _accumulated[key] = value;
      }
    });
  }

  void _scheduleReconnect() {
    if (_disposed || _suspended) return;
    _connectionController.add(false);
    _cancelTimers();
    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  /// Tear down the connection and timers while the app is backgrounded,
  /// without closing the streams. [resume] reconnects.
  void suspend() {
    if (_disposed || _suspended) return;
    _suspended = true;
    _cancelTimers();
    _client?.disconnect();
    _client = null;
    _connectionController.add(false);
  }

  void resume() {
    if (_disposed || !_suspended) return;
    _suspended = false;
    connect();
  }

  void _cancelTimers() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _statusRefreshTimer?.cancel();
    _registerFallbackTimer?.cancel();
  }

  static String _truncate(String s) => s.length > 220 ? s.substring(0, 220) : s;

  static String _genId(String prefix) {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16);
    return '$prefix$time$rand';
  }

  void dispose() {
    _disposed = true;
    _cancelTimers();
    _client?.disconnect();
    _stateController.close();
    _canvasController.close();
    _connectionController.close();
    _consoleController.close();
  }
}
