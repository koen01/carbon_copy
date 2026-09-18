import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Looks up a Centauri Carbon 2's serial number over UDP, which is required
/// to build its MQTT topic names. The printer listens on port 52700 and
/// replies to method 7000 with a JSON blob containing `sn`.
class DiscoveryService {
  static Future<String?> discoverSerial(
    String host, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.send(
        utf8.encode(jsonEncode({'id': 0, 'method': 7000})),
        InternetAddress(host),
        52700,
      );

      final completer = Completer<String?>();
      final sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        try {
          final data =
              jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
          final sn = _findSerial(data);
          if (sn != null && !completer.isCompleted) {
            completer.complete(sn);
          }
        } catch (_) {
          // ignore malformed packets
        }
      });

      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
      await sub.cancel();
      return result;
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  static String? _findSerial(Map<String, dynamic> data) {
    for (final key in const ['sn', 'Sn', 'SN', 'serial', 'serial_number']) {
      final v = data[key];
      if (v is String && v.isNotEmpty) return v;
    }
    final nested = data['data'];
    if (nested is Map) {
      return _findSerial(nested.cast<String, dynamic>());
    }
    return null;
  }
}
