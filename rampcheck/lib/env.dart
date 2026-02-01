import 'dart:io';

class Env {
  static String get apiBase {
    if (Platform.isAndroid) {
      //Android emulator
      return 'http://10.0.2.2:5000';
    }
    //Windows desktop
    return 'http://localhost:5000';
  }

  static const apiKey = 'api_warehouse_student_key_1234567890abcdef';
}