import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'api_service.dart';
import 'widgets/neural_background.dart';
import 'widgets/threat_monitor.dart';
import 'scanner_service.dart';
import 'security_dashboard.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ApiService()),
      ],
      child: const QuantXApp(),
    ),
  );
}

class QuantXApp extends StatelessWidget {
  const QuantXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuantX AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F14),
        primaryColor: const Color(0xFFFFC857),
        hintColor: const Color(0xFF4CAF50),
        
        // Define Cyberpunk Typography
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
          displayLarge: GoogleFonts.orbitron(
            color: const Color(0xFFFFC857),
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
          titleMedium: GoogleFonts.rajdhani(
            color: const Color(0xFF4CAF50),
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _scannerEnabled = false;

  @override
  void initState() {
    super.initState();
    ScannerService.isScannerEnabled().then((v) => setState(() => _scannerEnabled = v));
  }

  Future<void> _toggleScanner(bool val) async {
    if (val) {
      // Show permission guide before enabling
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0F1923),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Enable Web Scanner', style: TextStyle(color: Color(0xFFFFC857), fontWeight: FontWeight.bold)),
          content: const Text(
            'QuantX needs Accessibility Permission to scan websites you visit.\n\n'
            '1. Tap OK to open Android Accessibility Settings.\n'
            '2. Tap "QuantX Web Scanner".\n'
            '3. Toggle it ON.\n\n'
            'Only URLs are analyzed. No browsing history is stored.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC857), foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await ScannerService.openAccessibilitySettings();
      }
    }
    await ScannerService.setScannerEnabled(val);
    setState(() => _scannerEnabled = val);
  }

  void _sendMessage(BuildContext context) {
    if (_controller.text.trim().isEmpty) return;
    
    final api = Provider.of<ApiService>(context, listen: false);
    api.sendMessage(_controller.text.trim());
    _controller.clear();
    
    // Unfocus the keyboard
    FocusScope.of(context).unfocus();
  }

  Widget _statusCard(BuildContext context, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1923),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 8),
            Text(value,
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold,
                shadows: [Shadow(color: color.withOpacity(0.6), blurRadius: 8)])),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(BuildContext context, {required IconData icon, required Color iconColor, required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1923),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🛡 QUANTX AI', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 18)),
        backgroundColor: const Color(0xFF0B0F14).withOpacity(0.9),
        elevation: 0,
        centerTitle: true,
        // The hamburger icon will automatically appear when we add a Drawer!
      ),
      drawer: Drawer(
        width: MediaQuery.of(context).size.width * 0.85,
        backgroundColor: const Color(0xFF0B0F14),
        child: Consumer<ApiService>(
          builder: (context, apiService, _) {
            return Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F1923),
                    border: Border(bottom: BorderSide(color: Color(0xFF4CAF50), width: 2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFF4CAF50), width: 1.5),
                              borderRadius: BorderRadius.circular(8),
                              color: const Color(0xFF4CAF50).withOpacity(0.1),
                            ),
                            child: const Icon(Icons.shield, color: Color(0xFF4CAF50), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('QUANTX AI',
                                style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 16)),
                              const Text('Cybersecurity Intelligence',
                                style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4CAF50),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Color(0xFF4CAF50), blurRadius: 6, spreadRadius: 1)],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('SYSTEM ONLINE',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 12, letterSpacing: 2)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Scrollable Content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          _statusCard(context, 'Queries', apiService.queryCount.toString(), Icons.query_stats, const Color(0xFFFFC857)),
                          const SizedBox(width: 12),
                          _statusCard(context, 'RAG', 'ACTIVE', Icons.psychology, const Color(0xFF4CAF50)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1923),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: ThreatMonitor(threatLevel: apiService.threatLevel),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1923),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_done, color: Color(0xFF2196F3), size: 20),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('BACKEND', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                                SizedBox(height: 2),
                                Text('HuggingFace · 16GB · Online', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── SCANNER TOGGLE ──────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1923),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _scannerEnabled
                                ? const Color(0xFF4CAF50).withOpacity(0.6)
                                : Colors.white12,
                          ),
                          boxShadow: _scannerEnabled
                              ? [BoxShadow(color: const Color(0xFF4CAF50).withOpacity(0.12), blurRadius: 12, spreadRadius: 1)]
                              : [],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (_scannerEnabled ? const Color(0xFF4CAF50) : Colors.white24).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                _scannerEnabled ? Icons.radar : Icons.radar_outlined,
                                color: _scannerEnabled ? const Color(0xFF4CAF50) : Colors.white38,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'WEB SCANNER',
                                    style: TextStyle(
                                      color: _scannerEnabled ? const Color(0xFF4CAF50) : Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  Text(
                                    _scannerEnabled ? 'Scanning all browsers...' : 'Background URL scanning',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _scannerEnabled,
                              onChanged: _toggleScanner,
                              activeColor: const Color(0xFF4CAF50),
                              inactiveThumbColor: Colors.white38,
                              inactiveTrackColor: Colors.white12,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),
                      // ── Security Dashboard nav tile ──────────
                      _menuTile(
                        context,
                        icon: Icons.shield_outlined,
                        iconColor: const Color(0xFFFFC857),
                        title: 'Security Dashboard',
                        subtitle: 'Phishing · Wi-Fi · Device · Apps',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const SecurityDashboardScreen(),
                          ));
                        },
                      ),
                      const SizedBox(height: 8),

                      _menuTile(
                        context,
                        icon: Icons.history_edu,
                        iconColor: const Color(0xFFFFC857),
                        title: 'Mission Log History',
                        subtitle: 'Locally saved conversations',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Chat history auto-saved locally.')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _menuTile(
                        context,
                        icon: Icons.auto_awesome,
                        iconColor: const Color(0xFF4CAF50),
                        title: 'Smart Intelligence',
                        subtitle: 'Auto-switching RAG & LLM',
                        onTap: () {},
                      ),
                      const SizedBox(height: 8),
                      _menuTile(
                        context,
                        icon: Icons.delete_sweep_rounded,
                        iconColor: const Color(0xFFFF5252),
                        title: 'Clear Tactical Interface',
                        subtitle: 'Wipe all chat history',
                        onTap: () {
                          apiService.clearChat(context);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white12)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('v1.2.0 — OPTIMIZED ROUTING',
                        style: TextStyle(color: Colors.white38, fontSize: 10)),
                      Icon(Icons.verified_user_outlined, color: Color(0xFF4CAF50), size: 14),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: NeuralBackground(
        child: Consumer<ApiService>(
          builder: (context, apiService, _) {
            return SafeArea(
              child: Column(
              children: [
                Expanded(
                  child: apiService.messages.isEmpty
                      ? Center(
                          child: Text(
                            'Tactical Interface Ready\nAwaiting Command...',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: const Color(0xFF4CAF50).withOpacity(0.8),
                              shadows: [
                                Shadow(color: const Color(0xFF4CAF50).withOpacity(0.6), blurRadius: 10),
                              ]
                            ),
                          ),
                        )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        reverse: false, // In a real app we might want to reverse or auto-scroll
                        itemCount: apiService.messages.length,
                        itemBuilder: (context, index) {
                          final msg = apiService.messages[index];
                          final isUser = msg.role == 'user';
                          
                          Color borderColor = isUser ? const Color(0xFF4CAF50) : const Color(0xFFFFC857);
                          if (msg.type == 'alert') borderColor = Colors.redAccent;
                          
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return Transform.translate(
                                  offset: Offset(isUser ? 20 * (1 - value) : -20 * (1 - value), 0),
                                  child: Opacity(
                                    opacity: value,
                                    child: child,
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF161F28).withOpacity(0.85),
                                  border: Border.all(color: borderColor.withOpacity(0.4), width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: borderColor.withOpacity(0.15),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    )
                                  ],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  msg.content,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              
              if (apiService.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: SpinKitThreeBounce(
                    color: Color(0xFFFFC857),
                    size: 20.0,
                  ),
                ),
                
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFF161F28),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter command parameters...',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          filled: true,
                          fillColor: const Color(0xFF0B0F14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey.shade800),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        onSubmitted: (_) => _sendMessage(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.black),
                        onPressed: () => _sendMessage(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
              ),
            );
          },
        ),
      ),
    );
  }
}
