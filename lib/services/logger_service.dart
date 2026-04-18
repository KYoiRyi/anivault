import 'package:flutter/foundation.dart';

class LoggerService extends ChangeNotifier {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  final List<String> _logs = [];

  List<String> get logs => List.unmodifiable(_logs);

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    _logs.insert(0, '[$timestamp] $message'); // Add to top
    if (_logs.length > 500) {
      _logs.removeLast(); // Keep recent 500
    }
    notifyListeners();
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }
}
