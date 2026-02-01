import 'dart:convert';
import 'package:http/http.dart' as http;
import 'env.dart';

class ApiClient {
  final String _base = Env.apiBase;

  Map<String, String> _headers({bool withKey = false}) {
    return {
      'Content-Type': 'application/json',
      if (withKey) 'X-API-Key': Env.apiKey,
    };
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$_base/api/v1/users/login'),
      headers: _headers(),
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('Login failed: ${res.body}');
    }
    return jsonDecode(res.body);
  }

  Future<List<Map<String, dynamic>>> listLogs() async {
    final res = await http.get(
      Uri.parse('$_base/api/v1/logs'),
      headers: _headers(withKey: true),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to load logs: ${res.body}');
    }

    return List<Map<String, dynamic>>.from(jsonDecode(res.body));
  }

  Future<Map<String, dynamic>> createLog({
    required String title,
    required String description,
    required String priority,
    required String status,
    int? userId,
  }) async {
    final payload = {
      'title': title,
      'description': description,
      'priority': priority,
      'status': status,
      'user_id': userId,
    };

    final res = await http.post(
      Uri.parse('$_base/api/v1/logs'),
      headers: _headers(withKey: true),
      body: jsonEncode(payload),
    );

    if (res.statusCode != 201) {
      throw Exception('Failed to create log: ${res.body}');
    }

    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> updateLog({
    required int remoteId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await http.put(
      Uri.parse('$_base/api/v1/logs/$remoteId'),
      headers: _headers(withKey: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('Update log failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body);
  }

}