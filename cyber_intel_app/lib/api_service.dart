import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ApiMessage {
  final String role;
  final String content;
  final String type; // 'user', 'rag', 'news', 'alert'

  ApiMessage({required this.role, required this.content, this.type = 'rag'});

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'type': type,
  };

  factory ApiMessage.fromJson(Map<String, dynamic> json) => ApiMessage(
    role: json['role'],
    content: json['content'],
    type: json['type'],
  );
}

class ApiService with ChangeNotifier {
  String _baseUrl = AppConfig.apiBaseUrl;

  final List<ApiMessage> _messages = [];
  bool _isLoading = false;
  int _queryCount = 0;

  // NOTE: the old `_threatLevel` was removed. It rose by +15 on any message
  // containing "attack" or "hack" and +2 on everything else, so it climbed
  // with conversation length and reflected no real measurement. Presenting a
  // fabricated risk score in a security product is worse than showing none;
  // the real posture number will come from actual scan findings.

  ApiService() {
    _loadHistory();
  }

  List<ApiMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  int get queryCount => _queryCount;

  void setBaseUrl(String url) {
    _baseUrl = url;
    notifyListeners();
  }

  Future<void> sendMessage(String query) async {
    if (query.trim().isEmpty) return;

    // Add user message to UI
    _messages.add(ApiMessage(role: 'user', content: query, type: 'user'));
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'query': query,
          'user_id': 'mobile_user_1',
          'use_rag': true, // Always default to smart RAG with server fallback
        }),
      ).timeout(AppConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String botResponse = data['response'];
        // Simple logic to detect message type from response content (similar to app.py)
        String type = _detectMessageType(query, botResponse);
        
        _messages.add(ApiMessage(
          role: 'assistant', 
          content: botResponse, 
          type: type
        ));
        
        _queryCount++;
      } else {
        String errorMsg = "Error: ${response.statusCode}";
        if (response.statusCode == 429) errorMsg = "Rate limit exceeded. Try again later.";
        _messages.add(ApiMessage(role: 'assistant', content: errorMsg, type: 'alert'));
      }
    } catch (e) {
      _messages.add(ApiMessage(
        role: 'assistant', 
        content: "Connection failed. Please ensure the backend server is running at $_baseUrl.", 
        type: 'alert'
      ));
    } finally {
      _isLoading = false;
      _saveHistory();
      notifyListeners();
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = jsonEncode(_messages.map((m) => m.toJson()).toList());
    await prefs.setString('chat_history', encodedData);
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyString = prefs.getString('chat_history');
    if (historyString != null) {
      final List<dynamic> decodedData = jsonDecode(historyString);
      _messages.clear();
      _messages.addAll(decodedData.map((m) => ApiMessage.fromJson(m)).toList());
      notifyListeners();
    }
  }

  void clearChat(BuildContext context) {
    _messages.clear();
    _queryCount = 0;
    _saveHistory();
    notifyListeners();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conversation history cleared')),
    );
  }

  String _detectMessageType(String query, String response) {
    final q = query.toLowerCase();
    final r = response.toLowerCase();
    
    if (q.contains('news') || q.contains('latest') || q.contains('incident')) return 'news';
    if (r.contains('attack type:') || r.contains('critical') || r.contains('vulnerability')) return 'alert';
    return 'rag';
  }

}
