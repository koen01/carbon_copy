import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/discovery_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hostController = TextEditingController();
  final _accessCodeController = TextEditingController();
  final _snController = TextEditingController();
  final _host2Controller = TextEditingController();
  final _accessCode2Controller = TextEditingController();
  final _sn2Controller = TextEditingController();

  // One FocusNode per interactive element, in top-to-bottom order.
  final _hostFocus = FocusNode();
  final _accessCodeFocus = FocusNode();
  final _snFocus = FocusNode();
  final _keepScreenOnFocus = FocusNode();
  final _showDebugLogFocus = FocusNode();
  final _secondPrinterFocus = FocusNode();
  final _host2Focus = FocusNode();
  final _accessCode2Focus = FocusNode();
  final _sn2Focus = FocusNode();
  final _eStopFocus = FocusNode();
  final _holdDurationFocus = FocusNode();
  final _saveFocus = FocusNode();

  bool _loaded = false;
  bool _saving = false;
  bool _keepScreenOn = true;
  bool _showDebugLog = false;
  bool _secondPrinterEnabled = false;
  bool _eStopEnabled = true;
  int _eStopHoldMs = 1500;

  // Which text field is currently open for keyboard editing (null = none).
  FocusNode? _editingNode;

  // Ordered list of currently visible/reachable nodes (state-dependent).
  List<FocusNode> get _navOrder => [
        _hostFocus,
        _accessCodeFocus,
        _snFocus,
        _keepScreenOnFocus,
        _showDebugLogFocus,
        _secondPrinterFocus,
        if (_secondPrinterEnabled) ...[
          _host2Focus,
          _accessCode2Focus,
          _sn2Focus,
        ],
        _eStopFocus,
        if (_eStopEnabled) _holdDurationFocus,
        _saveFocus,
      ];

  @override
  void initState() {
    super.initState();
    _setupNav();
    _load();
  }

  // Wire up arrow-key navigation and D-pad select on every focusable node.
  void _setupNav() {
    void navigate(FocusNode node, LogicalKeyboardKey key) {
      final order = _navOrder;
      final idx = order.indexOf(node);
      if (idx == -1) return;
      final next = key == LogicalKeyboardKey.arrowDown
          ? (idx < order.length - 1 ? order[idx + 1] : null)
          : (idx > 0 ? order[idx - 1] : null);
      if (next != null) {
        next.requestFocus();
        _scrollTo(next);
      }
    }

    void nav(
      FocusNode node, {
      VoidCallback? onSelect,
      bool isTextField = false,
    }) {
      node.onKeyEvent = (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        // ── Edit mode: this text field has the keyboard open ──────────
        if (isTextField && _editingNode == node) {
          if (key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.arrowUp) {
            // Close keyboard, exit edit mode, then move focus.
            setState(() => _editingNode = null);
            SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
            navigate(node, key);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            setState(() => _editingNode = null);
            SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
            return KeyEventResult.handled;
          }
          // All other keys (typing, cursor movement) go to the TextField.
          return KeyEventResult.ignored;
        }

        // ── Navigation mode ───────────────────────────────────────────
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp) {
          navigate(node, key);
          // Consume even at boundaries to stop focus leaking to the AppBar.
          return KeyEventResult.handled;
        }

        // Select on a text field: open keyboard (enter edit mode).
        if (isTextField &&
            (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter)) {
          _enterEditMode(node);
          return KeyEventResult.handled;
        }

        // Select on a toggle or button.
        if (onSelect != null && key == LogicalKeyboardKey.select) {
          onSelect();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      };
    }

    nav(_hostFocus, isTextField: true);
    nav(_accessCodeFocus, isTextField: true);
    nav(_snFocus, isTextField: true);
    nav(_keepScreenOnFocus,
        onSelect: () => setState(() => _keepScreenOn = !_keepScreenOn));
    nav(_showDebugLogFocus,
        onSelect: () => setState(() => _showDebugLog = !_showDebugLog));
    nav(_secondPrinterFocus,
        onSelect: () =>
            setState(() => _secondPrinterEnabled = !_secondPrinterEnabled));
    nav(_host2Focus, isTextField: true);
    nav(_accessCode2Focus, isTextField: true);
    nav(_sn2Focus, isTextField: true);
    nav(_eStopFocus,
        onSelect: () => setState(() => _eStopEnabled = !_eStopEnabled));
    nav(_holdDurationFocus);
    nav(_saveFocus, onSelect: _save);
  }

  // Put a text field into edit mode so it stops being readOnly and the
  // soft keyboard opens. Used by both touch (onTap) and D-pad select.
  void _enterEditMode(FocusNode node) {
    if (_editingNode == node) return;
    setState(() => _editingNode = node);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  void _scrollTo(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _hostController.text = prefs.getString('printer_host') ?? '';
    _accessCodeController.text = prefs.getString('printer_access_code') ?? '';
    _snController.text = prefs.getString('printer_sn') ?? '';
    _host2Controller.text = prefs.getString('printer_host_2') ?? '';
    _accessCode2Controller.text =
        prefs.getString('printer_access_code_2') ?? '';
    _sn2Controller.text = prefs.getString('printer_sn_2') ?? '';
    setState(() {
      _keepScreenOn = prefs.getBool('keep_screen_on') ?? true;
      _showDebugLog = prefs.getBool('show_debug_log') ?? false;
      _secondPrinterEnabled = prefs.getBool('second_printer_enabled') ?? false;
      _eStopEnabled = prefs.getBool('estop_enabled') ?? true;
      _eStopHoldMs = prefs.getInt('estop_hold_ms') ?? 1500;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final host = _hostController.text.trim();
    final host2 = _host2Controller.text.trim();

    // Auto-detect the serial number over UDP unless the user gave one.
    var sn = _snController.text.trim();
    if (sn.isEmpty && host.isNotEmpty) {
      sn = await DiscoveryService.discoverSerial(host) ?? '';
    }
    var sn2 = _sn2Controller.text.trim();
    if (_secondPrinterEnabled && sn2.isEmpty && host2.isNotEmpty) {
      sn2 = await DiscoveryService.discoverSerial(host2) ?? '';
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_host', host);
    await prefs.setString(
        'printer_access_code', _accessCodeController.text.trim());
    await prefs.setString('printer_sn', sn);
    await prefs.setBool('keep_screen_on', _keepScreenOn);
    await prefs.setBool('show_debug_log', _showDebugLog);
    await prefs.setBool('second_printer_enabled', _secondPrinterEnabled);
    await prefs.setString('printer_host_2', host2);
    await prefs.setString(
        'printer_access_code_2', _accessCode2Controller.text.trim());
    await prefs.setString('printer_sn_2', sn2);
    await prefs.setBool('estop_enabled', _eStopEnabled);
    await prefs.setInt('estop_hold_ms', _eStopHoldMs);
    await WakelockPlus.toggle(enable: _keepScreenOn);

    if (!mounted) return;

    if (host.isNotEmpty && sn.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          "Couldn't auto-detect the printer's serial number. "
          "Enter it manually below if the feed doesn't connect.",
        ),
      ));
      setState(() => _saving = false);
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _accessCodeController.dispose();
    _snController.dispose();
    _host2Controller.dispose();
    _accessCode2Controller.dispose();
    _sn2Controller.dispose();
    _hostFocus.dispose();
    _accessCodeFocus.dispose();
    _snFocus.dispose();
    _keepScreenOnFocus.dispose();
    _showDebugLogFocus.dispose();
    _secondPrinterFocus.dispose();
    _host2Focus.dispose();
    _accessCode2Focus.dispose();
    _sn2Focus.dispose();
    _eStopFocus.dispose();
    _holdDurationFocus.dispose();
    _saveFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          backgroundColor: Colors.black,
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Printer 1 ────────────────────────────────────────
                    const Text('Printer host',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text(
                      'IP address of your Centauri Carbon 2 on the LAN.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _hostController,
                      focusNode: _hostFocus,
                      autofocus: true,
                      readOnly: _editingNode != _hostFocus,
                      onTap: () => _enterEditMode(_hostFocus),
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      onEditingComplete: () {
                        setState(() => _editingNode = null);
                        _accessCodeFocus.requestFocus();
                      },
                      decoration: const InputDecoration(
                        hintText: '192.168.1.60',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Access code',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text(
                      'LAN access code shown on the printer\'s touchscreen '
                      '(Settings → LAN Only Mode).',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _accessCodeController,
                      focusNode: _accessCodeFocus,
                      readOnly: _editingNode != _accessCodeFocus,
                      onTap: () => _enterEditMode(_accessCodeFocus),
                      autocorrect: false,
                      onEditingComplete: () {
                        setState(() => _editingNode = null);
                        _snFocus.requestFocus();
                      },
                      decoration: const InputDecoration(
                        hintText: '123456',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Serial number (optional)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text(
                      'Auto-detected on save. Fill in only if that fails.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _snController,
                      focusNode: _snFocus,
                      readOnly: _editingNode != _snFocus,
                      onTap: () => _enterEditMode(_snFocus),
                      autocorrect: false,
                      onEditingComplete: () {
                        setState(() => _editingNode = null);
                        _keepScreenOnFocus.requestFocus();
                      },
                      decoration: const InputDecoration(
                        hintText: 'e.g. F01U3UD3798YT8K',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Toggles ──────────────────────────────────────────
                    SwitchListTile(
                      focusNode: _keepScreenOnFocus,
                      value: _keepScreenOn,
                      onChanged: (v) => setState(() => _keepScreenOn = v),
                      title: const Text('Keep screen on',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                        'Prevent the screen from turning off while the app is open.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      focusNode: _showDebugLogFocus,
                      value: _showDebugLog,
                      onChanged: (v) => setState(() => _showDebugLog = v),
                      title: const Text('Show debug log overlay',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                        'Show the last 15 raw messages from the printer in the bottom-right corner.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      focusNode: _secondPrinterFocus,
                      value: _secondPrinterEnabled,
                      onChanged: (v) =>
                          setState(() => _secondPrinterEnabled = v),
                      title: const Text('Enable second printer',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                        'Show two printers side by side.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),

                    // ── Second printer fields (conditional) ──────────────
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: _secondPrinterEnabled
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Divider(color: Colors.white24),
                          const SizedBox(height: 8),
                          const Text('Second printer host',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _host2Controller,
                            focusNode: _host2Focus,
                            readOnly: _editingNode != _host2Focus,
                            onTap: () => _enterEditMode(_host2Focus),
                            autocorrect: false,
                            keyboardType: TextInputType.url,
                            onEditingComplete: () {
                              setState(() => _editingNode = null);
                              _accessCode2Focus.requestFocus();
                            },
                            decoration: const InputDecoration(
                              hintText: '192.168.1.61',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text('Second printer access code',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _accessCode2Controller,
                            focusNode: _accessCode2Focus,
                            readOnly: _editingNode != _accessCode2Focus,
                            onTap: () => _enterEditMode(_accessCode2Focus),
                            autocorrect: false,
                            onEditingComplete: () {
                              setState(() => _editingNode = null);
                              _sn2Focus.requestFocus();
                            },
                            decoration: const InputDecoration(
                              hintText: '123456',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text('Second printer serial number (optional)',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _sn2Controller,
                            focusNode: _sn2Focus,
                            readOnly: _editingNode != _sn2Focus,
                            onTap: () => _enterEditMode(_sn2Focus),
                            autocorrect: false,
                            onEditingComplete: () {
                              setState(() => _editingNode = null);
                              _eStopFocus.requestFocus();
                            },
                            decoration: const InputDecoration(
                              hintText: 'Auto-detected on save',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),

                    // ── Safety ───────────────────────────────────────────
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 8),
                    const Text(
                      'Safety',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white38,
                          letterSpacing: 0.8),
                    ),
                    SwitchListTile(
                      focusNode: _eStopFocus,
                      value: _eStopEnabled,
                      onChanged: (v) => setState(() => _eStopEnabled = v),
                      title: const Text('Emergency Stop',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                        'Show button on camera view. Stops the current print.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: _eStopEnabled
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Hold Duration',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              Text(
                                '${(_eStopHoldMs / 1000).toStringAsFixed(1)}s',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14),
                              ),
                            ],
                          ),
                          Slider(
                            focusNode: _holdDurationFocus,
                            value: _eStopHoldMs.toDouble(),
                            min: 800,
                            max: 3000,
                            divisions: 22,
                            onChanged: (v) =>
                                setState(() => _eStopHoldMs = v.round()),
                          ),
                          const Text(
                            'Press & hold the E-stop button this long to trigger confirmation. A dialog will still ask before sending the command.',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),

                    // ── Save ─────────────────────────────────────────────
                    const SizedBox(height: 24),
                    ElevatedButton(
                      focusNode: _saveFocus,
                      onPressed: _saving ? null : _save,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : const Text('Save & connect',
                                style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
