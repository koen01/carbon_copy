import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import '../models/printer_state.dart';
import '../services/centauri_service.dart';
import 'estop_button.dart';
import 'info_overlay.dart';

class PrinterPane extends StatefulWidget {
  final String host;
  final String accessCode;
  final String serialNumber;
  final bool compact;
  final bool showOverlay;
  final bool showConsole;
  final bool eStopEnabled;
  final int eStopHoldMs;
  final VoidCallback onSettings;
  final FocusNode? settingsFocusNode;
  final VoidCallback? onTap;
  final VoidCallback? onToggleOverlay;
  final VoidCallback? onBackToSplit;

  const PrinterPane({
    super.key,
    required this.host,
    required this.accessCode,
    required this.serialNumber,
    required this.compact,
    required this.showOverlay,
    required this.showConsole,
    this.eStopEnabled = true,
    this.eStopHoldMs = 1500,
    required this.onSettings,
    this.settingsFocusNode,
    this.onTap,
    this.onToggleOverlay,
    this.onBackToSplit,
  });

  @override
  State<PrinterPane> createState() => _PrinterPaneState();
}

class _PrinterPaneState extends State<PrinterPane> with WidgetsBindingObserver {
  CentauriService? _service;
  PrinterState _state = PrinterState.idle();
  bool _connected = false;
  final List<String> _consoleLines = [];
  final TransformationController _transform = TransformationController();
  bool _eStopDialogOpen = false;
  // Bumped on every (re)connect; keys the Mjpeg widget so the stream
  // restarts after the printer comes back from a disconnect.
  int _feedEpoch = 0;

  String get _webcamUrl => 'http://${widget.host}:8080/?action=stream';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _service?.suspend();
      case AppLifecycleState.resumed:
        _service?.resume();
      default:
        break;
    }
  }

  @override
  void didUpdateWidget(PrinterPane old) {
    super.didUpdateWidget(old);
    if (old.host != widget.host ||
        old.accessCode != widget.accessCode ||
        old.serialNumber != widget.serialNumber) {
      setState(() => _consoleLines.clear());
      _transform.value = Matrix4.identity();
      _connect();
    }
  }

  void _connect() {
    _service?.dispose();
    if (widget.host.isEmpty || widget.serialNumber.isEmpty) {
      _service = null;
      return;
    }
    final svc = CentauriService(
      host: widget.host,
      accessCode: widget.accessCode,
      serialNumber: widget.serialNumber,
    );
    svc.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
    });
    svc.connectionStream.listen((c) {
      if (!mounted) return;
      setState(() {
        _connected = c;
        if (c) _feedEpoch++;
      });
    });
    svc.consoleStream.listen((line) {
      if (!mounted) return;
      final now = DateTime.now();
      final ts =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      setState(() {
        _consoleLines.add('$ts  $line');
        if (_consoleLines.length > 15) _consoleLines.removeAt(0);
      });
    });
    svc.connect();
    _service = svc;
  }

  void _handleEStopArmed() {
    if (_eStopDialogOpen || !mounted) return;
    setState(() => _eStopDialogOpen = true);
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: EStopConfirmDialog(
          onConfirm: () {
            Navigator.of(ctx).pop();
            _sendEStop();
          },
          onCancel: () => Navigator.of(ctx).pop(),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _eStopDialogOpen = false);
    });
  }

  void _sendEStop() {
    if (!_connected || _service == null) {
      showEStopToast(context, error: 'Not connected');
      return;
    }
    _service!.stopPrint();
    showEStopToast(context, error: null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service?.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildFeed(),
            InfoOverlay(
              state: _state,
              connected: _connected,
              onSettings: widget.onSettings,
              settingsFocusNode: widget.settingsFocusNode,
              compact: true,
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onToggleOverlay,
      onDoubleTap: () => _transform.value = Matrix4.identity(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            transformationController: _transform,
            minScale: 1.0,
            maxScale: 6.0,
            clipBehavior: Clip.none,
            child: SizedBox.expand(
              child: RepaintBoundary(child: _buildFeed()),
            ),
          ),
          if (widget.showOverlay)
            InfoOverlay(
              state: _state,
              connected: _connected,
              onSettings: widget.onSettings,
              settingsFocusNode: widget.settingsFocusNode,
              consoleLines: widget.showConsole ? _consoleLines : null,
              onEStopArmed: widget.eStopEnabled ? _handleEStopArmed : null,
              eStopHoldMs: widget.eStopHoldMs,
              onBackToSplit: widget.onBackToSplit,
            ),
        ],
      ),
    );
  }

  Widget _buildFeed() {
    if (widget.host.isEmpty || widget.serialNumber.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Printer not fully configured.\nCheck host and serial number in settings.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      );
    }
    return Mjpeg(
      key: ValueKey('feed_$_feedEpoch'),
      stream: _webcamUrl,
      isLive: true,
      fit: BoxFit.contain,
      timeout: const Duration(seconds: 10),
      error: (context, error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Camera feed unavailable\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
