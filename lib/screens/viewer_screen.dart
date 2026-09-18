import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../widgets/printer_pane.dart';
import '../widgets/walkthrough_overlay.dart';
import 'settings_screen.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  // Printer 1
  String? _host;
  String _accessCode = '';
  String _sn = '';

  // Printer 2
  bool _secondPrinterEnabled = false;
  String? _host2;
  String _accessCode2 = '';
  String _sn2 = '';

  // UI state
  bool _showOverlay = true;
  bool _showDebugLog = false;
  bool _eStopEnabled = true;
  int _eStopHoldMs = 1500;
  bool _showWalkthrough = false;

  // Split/focus state: null = split (when 2 printers), else 0/1
  int? _focusedPane;
  int _highlightedPane = 0;
  // Only draw the pane highlight once a D-pad/keyboard is actually in use,
  // so touch users never see a stray focus border.
  bool _dpadActive = false;

  final FocusNode _settingsFocusNode = FocusNode();
  final FocusNode _settingsFocusNode2 = FocusNode();

  bool get _splitMode =>
      _secondPrinterEnabled &&
      (_host2?.isNotEmpty ?? false) &&
      _focusedPane == null;

  bool get _configured => (_host?.isNotEmpty ?? false) && _sn.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final keepScreenOn = prefs.getBool('keep_screen_on') ?? true;
    await WakelockPlus.toggle(enable: keepScreenOn);
    setState(() {
      _host = prefs.getString('printer_host');
      _accessCode = prefs.getString('printer_access_code') ?? '';
      _sn = prefs.getString('printer_sn') ?? '';
      _showDebugLog = prefs.getBool('show_debug_log') ?? false;
      _secondPrinterEnabled = prefs.getBool('second_printer_enabled') ?? false;
      _host2 = prefs.getString('printer_host_2');
      _accessCode2 = prefs.getString('printer_access_code_2') ?? '';
      _sn2 = prefs.getString('printer_sn_2') ?? '';
      _eStopEnabled = prefs.getBool('estop_enabled') ?? true;
      _eStopHoldMs = prefs.getInt('estop_hold_ms') ?? 1500;
      final onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
      _showWalkthrough = !onboardingSeen;
    });
  }

  Future<void> _dismissWalkthrough() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (!mounted) return;
    setState(() => _showWalkthrough = false);
    if (!_configured) _openSettings();
  }

  Future<void> _openSettings() async {
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (saved == true) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _host = prefs.getString('printer_host');
        _accessCode = prefs.getString('printer_access_code') ?? '';
        _sn = prefs.getString('printer_sn') ?? '';
        _showDebugLog = prefs.getBool('show_debug_log') ?? false;
        _secondPrinterEnabled =
            prefs.getBool('second_printer_enabled') ?? false;
        _host2 = prefs.getString('printer_host_2');
        _accessCode2 = prefs.getString('printer_access_code_2') ?? '';
        _sn2 = prefs.getString('printer_sn_2') ?? '';
        _eStopEnabled = prefs.getBool('estop_enabled') ?? true;
        _eStopHoldMs = prefs.getInt('estop_hold_ms') ?? 1500;
        // Reset focus to split when settings change
        _focusedPane = null;
        _showOverlay = true;
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Return to split view from a focused pane (Escape / Back)
    if (_focusedPane != null &&
        (key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack)) {
      setState(() {
        _focusedPane = null;
        _showOverlay = true;
      });
      return KeyEventResult.handled;
    }

    if (_splitMode) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        setState(() {
          _dpadActive = true;
          _highlightedPane = 0;
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        setState(() {
          _dpadActive = true;
          _highlightedPane = 1;
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.gameButtonA) {
        setState(() {
          _focusedPane = _highlightedPane;
          _showOverlay = true;
        });
        return KeyEventResult.handled;
      }
    } else {
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.gameButtonA) {
        if (!_configured) {
          _openSettings();
        } else {
          if (!_showOverlay) setState(() => _showOverlay = true);
          (_focusedPane == 1 ? _settingsFocusNode2 : _settingsFocusNode)
              .requestFocus();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _settingsFocusNode.dispose();
    _settingsFocusNode2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _focusedPane == null && !_showOverlay,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_focusedPane != null) {
          setState(() {
            _focusedPane = null;
            _showOverlay = true;
          });
        } else {
          setState(() => _showOverlay = false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Focus(
              autofocus: !_showWalkthrough,
              onKeyEvent: _handleKeyEvent,
              child: !_configured
                  ? Stack(
                      children: [
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Tap the gear icon to configure your printer.',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 16),
                            ),
                          ),
                        ),
                        SafeArea(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: IconButton(
                                icon: const Icon(Icons.settings,
                                    color: Colors.white70, size: 28),
                                tooltip: 'Settings',
                                focusNode: _settingsFocusNode,
                                onPressed: _openSettings,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : _splitMode
                      ? _buildSplitView()
                      : _buildSingleView(),
            ),
            if (_showWalkthrough)
              Positioned.fill(
                child: WalkthroughOverlay(onDone: _dismissWalkthrough),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleView() {
    final isSecond = _focusedPane == 1;
    final activeHost = isSecond ? (_host2 ?? _host ?? '') : (_host ?? '');
    final activeAccessCode = isSecond ? _accessCode2 : _accessCode;
    final activeSn = isSecond ? _sn2 : _sn;
    final focusNode = isSecond ? _settingsFocusNode2 : _settingsFocusNode;

    return PrinterPane(
      key: ValueKey('pane_${_focusedPane ?? 0}'),
      host: activeHost,
      accessCode: activeAccessCode,
      serialNumber: activeSn,
      compact: false,
      showOverlay: _showOverlay,
      showConsole: _showDebugLog,
      eStopEnabled: _eStopEnabled,
      eStopHoldMs: _eStopHoldMs,
      onSettings: _openSettings,
      settingsFocusNode: focusNode,
      onToggleOverlay: () => setState(() => _showOverlay = !_showOverlay),
      onBackToSplit: _focusedPane != null
          ? () => setState(() {
                _focusedPane = null;
                _showOverlay = true;
              })
          : null,
    );
  }

  Widget _buildSplitView() {
    return Row(
      children: [
        Expanded(
          child: _buildPaneWrapper(
              0, _host ?? '', _accessCode, _sn, _settingsFocusNode),
        ),
        Container(width: 1, color: Colors.white12),
        Expanded(
          child: _buildPaneWrapper(
              1, _host2 ?? '', _accessCode2, _sn2, _settingsFocusNode2),
        ),
      ],
    );
  }

  Widget _buildPaneWrapper(int index, String host, String accessCode, String sn,
      FocusNode focusNode) {
    final highlighted = _dpadActive && _highlightedPane == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      foregroundDecoration: BoxDecoration(
        border: Border.all(
          color: highlighted ? Colors.white70 : Colors.transparent,
          width: 3,
        ),
      ),
      child: PrinterPane(
        key: ValueKey('split_$index'),
        host: host,
        accessCode: accessCode,
        serialNumber: sn,
        compact: true,
        showOverlay: true,
        showConsole: false,
        onSettings: _openSettings,
        settingsFocusNode: focusNode,
        onTap: () => setState(() {
          _focusedPane = index;
          _showOverlay = true;
        }),
      ),
    );
  }
}
