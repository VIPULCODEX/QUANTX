import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';   // MethodChannel
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'api_service.dart';


// ─────────────────────────────────────────────────────────────────────────────
//  SecurityDashboardScreen
//  Four scan cards: Phishing Analyzer, Wi-Fi Scanner, Device Audit, App Audit
// ─────────────────────────────────────────────────────────────────────────────

class SecurityDashboardScreen extends StatefulWidget {
  const SecurityDashboardScreen({super.key});

  @override
  State<SecurityDashboardScreen> createState() =>
      _SecurityDashboardScreenState();
}

class _SecurityDashboardScreenState extends State<SecurityDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _baseUrl = "https://vipulcdex-quantx.hf.space";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1923),
        title: const Text(
          '🔒 SECURITY SCANNER',
          style: TextStyle(
            color: Color(0xFFFFC857),
            fontWeight: FontWeight.bold,
            fontSize: 16,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFC857),
          labelColor: const Color(0xFFFFC857),
          unselectedLabelColor: Colors.white38,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.link, size: 16), text: 'Phishing'),
            Tab(icon: Icon(Icons.wifi, size: 16), text: 'Wi-Fi'),
            Tab(icon: Icon(Icons.phone_android, size: 16), text: 'Device'),
            Tab(icon: Icon(Icons.apps, size: 16), text: 'Apps'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PhishingTab(baseUrl: _baseUrl),
          _WifiTab(baseUrl: _baseUrl),
          _DeviceTab(baseUrl: _baseUrl),
          _AppAuditTab(baseUrl: _baseUrl),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────

Widget _scanCard({required Widget child}) => Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1923),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF4CAF50).withOpacity(0.05),
              blurRadius: 20)
        ],
      ),
      child: child,
    );

Widget _resultBox(String text, {Color? borderColor}) => Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF161F28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: (borderColor ?? const Color(0xFF4CAF50)).withOpacity(0.4)),
      ),
      child: SelectableText(
        text,
        style:
            const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
      ),
    );

Widget _riskBadge(int score) {
  Color c = score >= 70
      ? Colors.redAccent
      : score >= 40
          ? const Color(0xFFFFC857)
          : const Color(0xFF4CAF50);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c)),
    child: Text('Risk: $score%',
        style: TextStyle(
            color: c, fontWeight: FontWeight.bold, fontSize: 13)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tab 1 — Phishing Analyzer
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

  Future<void> _analyze() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final resp = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/security/phishing'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': _ctrl.text.trim()}),
          )
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        setState(() => _result = jsonDecode(resp.body));
      } else {
        setState(() => _result = {'error': 'Server error ${resp.statusCode}'});
      }
    } catch (e) {
      setState(() => _result = {'error': 'Network error: $e'});
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: _scanCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste a message, URL, or SMS text:',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText:
                    'e.g. "Urgent! Click http://bit.ly/win100 to claim prize"',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF161F28),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFF4CAF50))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white12)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _analyze,
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.search, size: 16),
                label:
                    Text(_loading ? 'Scanning...' : 'ANALYZE WITH PHISHSENSE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC857),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_result != null) ...[
              if (_result!.containsKey('error'))
                _resultBox(_result!['error'], borderColor: Colors.redAccent)
              else ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    _riskBadge(_result!['risk_score'] ?? 0),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: (_result!['prediction'] == 'safe'
                                ? Colors.green
                                : Colors.redAccent)
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _result!['prediction'] == 'safe'
                                ? Colors.green
                                : Colors.redAccent),
                      ),
                      child: Text(
                        (_result!['prediction'] as String)
                            .toUpperCase()
                            .replaceAll('_', ' '),
                        style: TextStyle(
                          color: _result!['prediction'] == 'safe'
                              ? Colors.green
                              : Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((_result!['reasons'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  const Text('Reasons:',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 11)),
                  ...(_result!['reasons'] as List).map((r) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFFFC857), size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                              child: Text(r.toString(),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12))),
                        ]),
                      )),
                ],
                if ((_result!['ai_explanation'] as String?)?.isNotEmpty ==
                    true)
                  _resultBox('🤖 AI Explanation:\n${_result!['ai_explanation']}'),
              ]
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tab 2 — Wi-Fi Scanner
// ─────────────────────────────────────────────────────────────────────────────

class _WifiTab extends StatefulWidget {
  final String baseUrl;
  const _WifiTab({required this.baseUrl});

  @override
  State<_WifiTab> createState() => _WifiTabState();
}

class _WifiTabState extends State<_WifiTab> {
  bool _loading = false;
  String? _result;
  String _ssid = 'Unknown';
  String _security = 'Unknown';

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final info = NetworkInfo();
      final ssid = await info.getWifiName() ?? 'Unknown';
      final bssid = await info.getWifiBSSID() ?? '';
      // Android doesn't expose security type directly via API — we ask user
      _ssid = ssid.replaceAll('"', '');

      final resp = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/security/wifi'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'ssid': _ssid,
              'security_type': _security,
              'is_public': false,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _result = data['analysis']);
      } else {
        setState(() => _result = 'Server error ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: _scanCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Current Wi-Fi Network Security Assessment',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 16),
            // Security type selector
            const Text('Network Security Type:',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['WPA3', 'WPA2', 'WEP', 'Open'].map((type) {
                final selected = _security == type;
                return ChoiceChip(
                  label: Text(type),
                  selected: selected,
                  selectedColor: const Color(0xFF4CAF50),
                  backgroundColor: const Color(0xFF161F28),
                  labelStyle: TextStyle(
                      color: selected ? Colors.black : Colors.white54,
                      fontSize: 12),
                  onSelected: (_) => setState(() => _security = type),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _scan,
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.wifi_find, size: 16),
                label: Text(_loading ? 'Scanning...' : 'SCAN NETWORK'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_result != null) _resultBox(_result!),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tab 3 — Device Audit
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

  Future<void> _audit() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final deviceInfo = DeviceInfoPlugin();
      final android = await deviceInfo.androidInfo;

      final resp = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/security/device'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'os_version': 'Android ${android.version.release} (SDK ${android.version.sdkInt})',
              'usb_debugging': false,       // Cannot read this without root
              'unknown_sources': false,     // Cannot read this without root
              'developer_mode': false,      // Cannot read this without root
              'screen_lock': true,          // Assume enabled (user confirms)
              'google_play_protect': true,  // Assume enabled (user confirms)
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _result = data['analysis']);
      } else {
        setState(() => _result = 'Server error ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: _scanCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Device Security Audit',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            const Text(
              'QuantX will read your Android version and send it to the AI for a security assessment. No personal data is collected.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _audit,
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.security, size: 16),
                label: Text(_loading ? 'Auditing...' : 'RUN DEVICE AUDIT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_result != null) _resultBox(_result!),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tab 4 — App Permission Auditor
// ─────────────────────────────────────────────────────────────────────────────

class _AppAuditTab extends StatefulWidget {
  final String baseUrl;
  const _AppAuditTab({required this.baseUrl});

  @override
  State<_AppAuditTab> createState() => _AppAuditTabState();
}

class _AppAuditTabState extends State<_AppAuditTab> {
  bool _loading = false;
  String? _result;
  int _appCount = 0;

  // Same channel MainActivity registers. App enumeration is done natively via
  // PackageManager rather than through the `installed_apps` plugin, which was
  // removed for causing SDK mismatches and which returned no permission data.
  static const _channel = MethodChannel('com.quantx.cyber_intel_app/scanner');

  Future<void> _audit() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'getInstalledApps',
        {'includeSystem': false},
      );
      final apps = (raw ?? []).cast<Map<dynamic, dynamic>>();
      _appCount = apps.length;

      final appList = apps.take(40).map((app) => {
        'name': app['name'] ?? 'Unknown',
        'package': app['package'] ?? '',
        'permissions': (app['permissions'] as List<dynamic>? ?? []).cast<String>(),
        'installer': app['installer'],
      }).toList();

      final resp = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/security/apps'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'apps': appList}),
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _result = data['analysis']);
      } else {
        setState(() => _result = 'Server error ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _result = 'Error: $e\n\nNote: App listing requires QUERY_ALL_PACKAGES permission.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: _scanCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Installed App Permission Auditor',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            const Text(
              'QuantX reads your installed app names and sends them to the AI to flag any suspicious apps. Your app data is not stored.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _audit,
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.manage_search, size: 16),
                label: Text(_loading
                    ? 'Scanning $_appCount apps...'
                    : 'SCAN INSTALLED APPS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5252).withOpacity(0.85),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_result != null) _resultBox(_result!),
          ],
        ),
      ),
    );
  }
}
