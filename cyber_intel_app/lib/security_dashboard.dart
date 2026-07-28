import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'config.dart';
import 'services/security_channel.dart';
import 'widgets/message_body.dart';
import 'theme/app_theme.dart';
import 'widgets/glass.dart';


// ─────────────────────────────────────────────────────────────────────────────
//  SecurityDashboardScreen
//  Three scans: URL/message analysis (with real-time watching), Wi-Fi security
//  read from the system, and device posture.
//
//  The installed-app audit tab was removed: it shipped every package name on
//  the device to the LLM, which contradicts the findings-only privacy boundary,
//  and duplicated what Deep Scan will do properly.
// ─────────────────────────────────────────────────────────────────────────────

class SecurityDashboardScreen extends StatefulWidget {
  /// When embedded in HomeShell the surrounding Scaffold and AppBar are
  /// supplied by the shell, so this renders only the tabs and their content.
  final bool embedded;
  const SecurityDashboardScreen({super.key, this.embedded = false});

  @override
  State<SecurityDashboardScreen> createState() =>
      _SecurityDashboardScreenState();
}

class _SecurityDashboardScreenState extends State<SecurityDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _baseUrl = AppConfig.apiBaseUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = TabBar(
      controller: _tabController,
      indicatorColor: AppColors.gold,
      indicatorWeight: 2,
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: AppColors.gold,
      unselectedLabelColor: AppColors.textMuted,
      dividerColor: AppColors.border,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle:
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      tabs: const [
        Tab(height: 46, icon: Icon(Icons.link, size: 17), iconMargin: EdgeInsets.only(bottom: 2), text: 'Links'),
        Tab(height: 46, icon: Icon(Icons.wifi, size: 17), iconMargin: EdgeInsets.only(bottom: 2), text: 'Wi-Fi'),
        Tab(height: 46, icon: Icon(Icons.phone_android, size: 17), iconMargin: EdgeInsets.only(bottom: 2), text: 'Device'),
      ],
    );

    final content = TabBarView(
      controller: _tabController,
      children: [
        _PhishingTab(baseUrl: _baseUrl),
        _WifiTab(baseUrl: _baseUrl),
        _DeviceTab(baseUrl: _baseUrl),
      ],
    );

    if (widget.embedded) {
      return Column(
        children: [
          // Clear the translucent app bar overlaying the body.
          SizedBox(height: MediaQuery.of(context).padding.top + 62),
          tabs,
          Expanded(child: content),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Security Scan'), bottom: tabs),
      body: content,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────



// ─────────────────────────────────────────────────────────────────────────────
//  Tab 1 — URL / Message Analyzer  (+ real-time scanning)
// ─────────────────────────────────────────────────────────────────────────────

class _PhishingTab extends StatefulWidget {
  final String baseUrl;
  const _PhishingTab({required this.baseUrl});

  @override
  State<_PhishingTab> createState() => _PhishingTabState();
}

class _PhishingTabState extends State<_PhishingTab> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _result;

  // Real-time scanning state, backed by the accessibility service.
  bool _serviceBound = false;
  bool _scanning = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _refreshScannerState();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _refreshScannerState() async {
    setState(() => _checking = true);
    try {
      final bound = await SecurityChannel.isAccessibilityServiceEnabled();
      final on = await SecurityChannel.isScannerEnabled();
      if (mounted) setState(() { _serviceBound = bound; _scanning = on; });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _toggleScanning(bool value) async {
    if (!_serviceBound) {
      await SecurityChannel.openAccessibilitySettings();
      return;
    }
    await SecurityChannel.setScannerEnabled(value);
    setState(() => _scanning = value);
  }

  Future<void> _analyze() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() { _loading = true; _result = null; });
    try {
      final resp = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/security/phishing'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': _ctrl.text.trim()}),
          )
          .timeout(AppConfig.requestTimeout);
      if (resp.statusCode == 200) {
        setState(() => _result = jsonDecode(resp.body));
      } else {
        setState(() => _result = {'error': 'Server error ${resp.statusCode}'});
      }
    } catch (e) {
      setState(() => _result = {'error': 'Network error: $e'});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg,
          AppSpacing.bottomClearance(context)),
      children: [
        _RealtimeScanCard(
          bound: _serviceBound,
          scanning: _scanning,
          checking: _checking,
          onToggle: _toggleScanning,
          onRefresh: _refreshScannerState,
        ),
        const SizedBox(height: AppSpacing.lg),

        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MANUAL CHECK', style: AppTheme.label()),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Paste a link, SMS or email to analyse it now.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _ctrl,
                maxLines: 4,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'e.g. Urgent! Verify your account at http://bit.ly/x',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _analyze,
                  icon: _loading
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF1A1200)))
                      : const Icon(Icons.search, size: 18),
                  label: Text(_loading ? 'Analysing…' : 'Analyse'),
                ),
              ),
            ],
          ),
        ),

        if (_result != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _PhishResult(result: _result!),
        ],
      ],
    );
  }
}

/// Real-time scanning control.
///
/// The accessibility service that reads browser URL bars already existed but
/// had no UI, so it could never be switched on. Two independent states matter
/// and are shown separately: whether Android has BOUND the service at all, and
/// whether our own scanning toggle is on.
class _RealtimeScanCard extends StatelessWidget {
  final bool bound, scanning, checking;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRefresh;

  const _RealtimeScanCard({
    required this.bound,
    required this.scanning,
    required this.checking,
    required this.onToggle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final active = bound && scanning;
    final accent = active ? AppColors.green : AppColors.textMuted;

    return GlassCard(
      accent: accent,
      selected: active,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(active ? Icons.radar : Icons.radar_outlined,
                    size: 18, color: accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Real-time URL scanning',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      checking
                          ? 'Checking…'
                          : !bound
                              ? 'Accessibility service not enabled'
                              : scanning
                                  ? 'Watching browser URLs'
                                  : 'Paused',
                      style: TextStyle(fontSize: 12, color: accent),
                    ),
                  ],
                ),
              ),
              if (checking)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textMuted),
                )
              else
                Switch(
                  value: active,
                  activeThumbColor: AppColors.green,
                  onChanged: onToggle,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            bound
                ? 'URLs opened in Chrome, Firefox, Edge, Brave, Opera, Samsung '
                  'Internet and DuckDuckGo are checked as you browse. Only the '
                  'URL is analysed; page content is never read or stored.'
                : 'Android must bind the QuantX scanner before it can watch '
                  'browser URLs. Enable it under Accessibility, then return here.',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textMuted, height: 1.5),
          ),
          if (!bound && !checking) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onToggle(true),
                    icon: const Icon(Icons.settings_accessibility, size: 17),
                    label: const Text('Open Accessibility'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, color: AppColors.textMuted),
                  tooltip: 'Re-check',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Explainability panel: risk score, then each contributing signal.
///
/// Mirrors the PhishSense browser-extension panel — a bare verdict is not
/// actionable, and for a technical audience the signal breakdown is the
/// interesting part.
class _PhishResult extends StatelessWidget {
  final Map<String, dynamic> result;
  const _PhishResult({required this.result});

  @override
  Widget build(BuildContext context) {
    if (result['error'] != null) {
      return GlassCard(
        accent: AppColors.critical,
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                color: AppColors.critical, size: 18),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text('${result['error']}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ),
          ],
        ),
      );
    }

    final score = (result['risk_score'] as num?)?.toInt() ?? 0;
    final prediction = '${result['prediction'] ?? 'unknown'}';
    final reasons = (result['reasons'] as List?)?.cast<String>() ?? const [];
    final words = (result['highlighted_words'] as List?)?.cast<String>() ?? const [];
    final urlFlag = '${result['url_flag'] ?? '-'}';
    final ai = '${result['ai_explanation'] ?? ''}';

    final band = score >= 70
        ? AppColors.critical
        : score >= 40
            ? AppColors.medium
            : AppColors.safe;
    final bandLabel =
        score >= 70 ? 'HIGH RISK' : score >= 40 ? 'MEDIUM RISK' : 'LOW RISK';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          accent: band,
          selected: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration:
                        BoxDecoration(color: band, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('$score%',
                      style: TextStyle(
                          color: band,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: AppSpacing.sm),
                  Text(bandLabel, style: AppTheme.label(color: band)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(prediction.toUpperCase(),
                        style: AppTheme.mono(size: 10)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: score / 100,
                  minHeight: 5,
                  backgroundColor: AppColors.bg,
                  valueColor: AlwaysStoppedAnimation(band),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Signals: ${reasons.length}   ·   URL check: $urlFlag',
                  style: AppTheme.mono(size: 11)),
            ],
          ),
        ),

        if (reasons.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('THREAT SIGNALS', style: AppTheme.label()),
          const SizedBox(height: AppSpacing.sm),
          ...reasons.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: GlassCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4, right: 10),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                            color: band, shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Text(r,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.4)),
                      ),
                    ],
                  ),
                ),
              )),
        ],

        if (words.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('FLAGGED TERMS', style: AppTheme.label()),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: words
                .map((w) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: band.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: band.withOpacity(0.35)),
                      ),
                      child: Text(w, style: AppTheme.mono(size: 11, color: band)),
                    ))
                .toList(),
          ),
        ],

        if (ai.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('ANALYSIS', style: AppTheme.label()),
          const SizedBox(height: AppSpacing.sm),
          GlassCard(child: MessageBody(text: ai)),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tab 2 — Wi-Fi Security  (measured, not user-declared)
// ─────────────────────────────────────────────────────────────────────────────

class _WifiTab extends StatefulWidget {
  final String baseUrl;
  const _WifiTab({required this.baseUrl});

  @override
  State<_WifiTab> createState() => _WifiTabState();
}

class _WifiTabState extends State<_WifiTab> {
  Map<String, dynamic>? _net;
  String? _analysis;
  bool _reading = true;
  bool _asking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() { _reading = true; _error = null; });
    try {
      // Scan results need location permission on Android 12 and below.
      if (await Permission.locationWhenInUse.isDenied) {
        await Permission.locationWhenInUse.request();
      }
      final net = await SecurityChannel.getWifiSecurity();
      if (mounted) setState(() => _net = net);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// Deterministic verdict from the measured security type.
  ///
  /// Computed locally and offline. The LLM adds explanation on request, but the
  /// risk classification itself must not depend on a network call — an audit
  /// that fails open when the server is unreachable is worse than useless.
  (String, Color, String) _verdict() {
    final s = '${_net?['security'] ?? 'UNKNOWN'}'.toUpperCase();
    if (s.contains('OPEN') && !s.contains('ENHANCED')) {
      return ('CRITICAL', AppColors.critical,
          'This network has no encryption. Anyone in range can read your '
          'traffic. Do not sign in to anything.');
    }
    if (s.contains('WEP')) {
      return ('CRITICAL', AppColors.critical,
          'WEP is broken and can be cracked in minutes. Treat this network as '
          'fully untrusted.');
    }
    if (s.contains('WPA (LEGACY)')) {
      return ('HIGH', AppColors.high,
          'Original WPA with TKIP is deprecated and has practical attacks.');
    }
    if (s.contains('WPA3') || s.contains('SAE')) {
      return ('SECURE', AppColors.safe,
          'WPA3 with SAE. Resistant to offline dictionary attacks and gives '
          'forward secrecy.');
    }
    if (s.contains('OWE') || s.contains('ENHANCED OPEN')) {
      return ('MODERATE', AppColors.medium,
          'Enhanced Open encrypts traffic but does not authenticate the access '
          'point, so an evil-twin AP is still possible.');
    }
    if (s.contains('ENTERPRISE') || s.contains('EAP')) {
      return ('SECURE', AppColors.safe,
          'Enterprise authentication (802.1X). The access point is verified '
          'against a RADIUS server.');
    }
    if (s.contains('WPA')) {
      return ('MODERATE', AppColors.medium,
          'WPA2-PSK. Acceptable, but everyone with the password can derive '
          'your session keys — WPA3 fixes that.');
    }
    return ('UNKNOWN', AppColors.textMuted,
        'Security type could not be read. Location permission may be required.');
  }

  Future<void> _explain() async {
    setState(() { _asking = true; _analysis = null; });
    try {
      final resp = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/security/wifi'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              // Only the security TYPE leaves the device — never the SSID,
              // which identifies a home or workplace.
              'ssid': 'redacted',
              'security_type': '${_net?['security']}',
              'is_public': false,
            }),
          )
          .timeout(AppConfig.requestTimeout);
      if (resp.statusCode == 200) {
        setState(() => _analysis = jsonDecode(resp.body)['analysis']);
      } else {
        setState(() => _analysis = 'Server error ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _analysis = 'Network error: $e');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _net?['connected'] == true;
    final (label, color, detail) = _verdict();

    return RefreshIndicator(
      onRefresh: _read,
      backgroundColor: AppColors.surface,
      color: AppColors.gold,
      child: ListView(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg,
            AppSpacing.lg, AppSpacing.bottomClearance(context)),
        children: [
          if (_reading)
            const GlassCard(
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.gold)),
                SizedBox(width: AppSpacing.md),
                Text('Reading network…',
                    style: TextStyle(color: AppColors.textSecondary)),
              ]),
            )
          else if (!connected)
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.wifi_off, color: AppColors.textMuted, size: 18),
                    SizedBox(width: AppSpacing.md),
                    Text('Not connected to Wi-Fi',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error ?? 'Connect to a network, then pull down to refresh.',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12.5),
                  ),
                ],
              ),
            )
          else ...[
            GlassCard(
              accent: color,
              selected: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.wifi, color: color, size: 20),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text('${_net!['ssid']}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: color.withOpacity(0.45)),
                        ),
                        child: Text(label,
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6)),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(detail,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('MEASURED', style: AppTheme.label()),
            const SizedBox(height: AppSpacing.sm),
            GlassSection(children: [
              GlassRow(
                  icon: Icons.lock_outline,
                  iconColor: color,
                  title: 'Security',
                  subtitle: 'Read from the system, not entered by you',
                  trailing: Text('${_net!['security']}',
                      style: AppTheme.mono(size: 11, color: color))),
              GlassRow(
                  icon: Icons.speed,
                  title: 'Link speed',
                  trailing: Text('${_net!['linkSpeedMbps'] ?? '-'} Mbps',
                      style: AppTheme.mono(size: 11))),
              GlassRow(
                  icon: Icons.signal_cellular_alt,
                  title: 'Signal',
                  trailing: Text('${_net!['rssi'] ?? '-'} dBm',
                      style: AppTheme.mono(size: 11))),
              GlassRow(
                  icon: Icons.router_outlined,
                  title: 'Band',
                  trailing: Text('${_net!['band'] ?? '-'}',
                      style: AppTheme.mono(size: 11))),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Text('source: ${_net!['source']}   ·   API ${_net!['sdkInt']}',
                style: AppTheme.mono(size: 10, color: AppColors.textMuted)),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _asking ? null : _explain,
                icon: _asking
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF1A1200)))
                    : const Icon(Icons.auto_awesome, size: 17),
                label: Text(_asking ? 'Analysing…' : 'Explain this network'),
              ),
            ),
            if (_analysis != null) ...[
              const SizedBox(height: AppSpacing.lg),
              GlassCard(child: MessageBody(text: _analysis!)),
            ],
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tab 3 — Device Posture
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceTab extends StatefulWidget {
  final String baseUrl;
  const _DeviceTab({required this.baseUrl});

  @override
  State<_DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends State<_DeviceTab> {
  bool _loading = false;
  String? _result;
  String _osVersion = '—';
  String _model = '—';
  int _sdk = 0;
  bool _physical = true;

  bool _usbDebug = false;
  bool _unknownSources = false;
  bool _devMode = false;
  bool _screenLock = true;
  bool _playProtect = true;

  @override
  void initState() {
    super.initState();
    _readDevice();
  }

  Future<void> _readDevice() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      setState(() {
        _osVersion = 'Android ${info.version.release}';
        _sdk = info.version.sdkInt;
        _model = '${info.manufacturer} ${info.model}';
        _physical = info.isPhysicalDevice;
      });
    } catch (_) {/* leave defaults */}
  }

  Future<void> _audit() async {
    setState(() { _loading = true; _result = null; });
    try {
      final resp = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/security/device'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'os_version': '$_osVersion (API $_sdk)',
              'usb_debugging': _usbDebug,
              'unknown_sources': _unknownSources,
              'developer_mode': _devMode,
              'screen_lock': _screenLock,
              'google_play_protect': _playProtect,
            }),
          )
          .timeout(AppConfig.requestTimeout);
      if (resp.statusCode == 200) {
        setState(() => _result = jsonDecode(resp.body)['analysis']);
      } else {
        setState(() => _result = 'Server error ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _result = 'Network error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _toggle(String title, String sub, bool value, ValueChanged<bool> on,
      {bool riskyWhenOn = true}) {
    final risky = riskyWhenOn ? value : !value;
    return GlassRow(
      icon: risky ? Icons.warning_amber_rounded : Icons.check_circle_outline,
      iconColor: risky ? AppColors.high : AppColors.safe,
      title: title,
      subtitle: sub,
      trailing: Switch(
          value: value, activeThumbColor: AppColors.gold, onChanged: on),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg,
          AppSpacing.bottomClearance(context)),
      children: [
        Text('DETECTED', style: AppTheme.label()),
        const SizedBox(height: AppSpacing.sm),
        GlassSection(children: [
          GlassRow(
              icon: Icons.phone_android,
              title: 'Device',
              trailing: Text(_model, style: AppTheme.mono(size: 11))),
          GlassRow(
              icon: Icons.android,
              title: 'OS',
              trailing:
                  Text('$_osVersion · API $_sdk', style: AppTheme.mono(size: 11))),
          GlassRow(
              icon: _physical ? Icons.verified_outlined : Icons.desktop_windows,
              iconColor: _physical ? AppColors.safe : AppColors.high,
              title: 'Hardware',
              trailing: Text(_physical ? 'Physical' : 'Emulator',
                  style: AppTheme.mono(
                      size: 11,
                      color: _physical ? AppColors.safe : AppColors.high))),
        ]),

        const SizedBox(height: AppSpacing.lg),
        Text('SETTINGS YOU CONFIRM', style: AppTheme.label()),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Android does not expose these to third-party apps without elevated '
          'access, so they are declared rather than measured. Deep Scan mode '
          'will read them directly.',
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.45),
        ),
        const SizedBox(height: AppSpacing.sm),
        GlassSection(children: [
          _toggle('USB debugging', 'ADB access over cable', _usbDebug,
              (v) => setState(() => _usbDebug = v)),
          _toggle('Unknown sources', 'Sideloading allowed', _unknownSources,
              (v) => setState(() => _unknownSources = v)),
          _toggle('Developer options', 'Debug surface enabled', _devMode,
              (v) => setState(() => _devMode = v)),
          _toggle('Screen lock', 'PIN, pattern or biometric', _screenLock,
              (v) => setState(() => _screenLock = v), riskyWhenOn: false),
          _toggle('Play Protect', 'Google malware scanning', _playProtect,
              (v) => setState(() => _playProtect = v), riskyWhenOn: false),
        ]),

        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _loading ? null : _audit,
            icon: _loading
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF1A1200)))
                : const Icon(Icons.shield_outlined, size: 17),
            label: Text(_loading ? 'Auditing…' : 'Run device audit'),
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: AppSpacing.lg),
          GlassCard(child: MessageBody(text: _result!)),
        ],
      ],
    );
  }
}
