# Warehouse Maintenance API (Flask + SQLite)

A small teaching API for warehouse maintenance logs with a hardcoded API key that students embed in their client apps.

## Quick start

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python init_db.py
python app.py
```

The API runs at `http://localhost:5000` and uses `warehouse.db` in the project root.

## API key

Use the same hardcoded key in your client apps:

```
api_warehouse_student_key_1234567890abcdef
```

Send it as either:

- `X-API-Key: api_warehouse_student_key_1234567890abcdef`
- `Authorization: Bearer api_warehouse_student_key_1234567890abcdef`

All `/logs` endpoints require the API key. `/users` endpoints are open for teaching purposes.

## Example requests

Create a user:

```bash
curl -X POST http://localhost:5000/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"username":"alex","password":"secret","role":"manager"}'
```

Log in:

```bash
curl -X POST http://localhost:5000/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d '{"username":"alex","password":"secret"}'
```

Create a maintenance log (API key required):

```bash
curl -X POST http://localhost:5000/api/v1/logs \
  -H "Content-Type: application/json" \
  -H "X-API-Key: api_warehouse_student_key_1234567890abcdef" \
  -d '{"title":"Replace filter","description":"HVAC filter replacement","priority":"high","status":"open","user_id":1}'
```

## Flutter usage guide (simple)

Install the HTTP package in your Flutter app:

```bash
flutter pub add http
```

### Suggested API helper

Use a base URL that matches your device:

- Android emulator: `http://10.0.2.2:5000`
- iOS simulator: `http://localhost:5000`
- Physical device: `http://<your-computer-ip>:5000`

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class WarehouseApi {
  WarehouseApi({required this.baseUrl});

  final String baseUrl;

  static const apiKey = 'api_warehouse_student_key_1234567890abcdef';

  Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json',
      };

  Map<String, String> _authHeaders() => {
        ..._jsonHeaders(),
        'X-API-Key': apiKey,
      };

  Future<Map<String, dynamic>> createUser({
    required String username,
    required String password,
    required String role,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'username': username,
        'password': password,
        'role': role,
      }),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/login'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createLog({
    required String title,
    required String description,
    required String priority,
    required String status,
    required int userId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/logs'),
      headers: _authHeaders(),
      body: jsonEncode({
        'title': title,
        'description': description,
        'priority': priority,
        'status': status,
        'user_id': userId,
      }),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
```

### Example usage in Flutter

```dart
final api = WarehouseApi(baseUrl: 'http://10.0.2.2:5000/api/v1/');

final user = await api.createUser(
  username: 'alex',
  password: 'secret',
  role: 'manager',
);

final login = await api.login(
  username: 'alex',
  password: 'secret',
);

final log = await api.createLog(
  title: 'Replace filter',
  description: 'HVAC filter replacement',
  priority: 'high',
  status: 'open',
  userId: user['id'] as int,
);
```
