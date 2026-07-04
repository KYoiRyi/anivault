import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LoggerService extends ChangeNotifier {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  final List<String> _logs = [];
  IOSink? _sink;
  File? _logFile;

  List<String> get logs => List.unmodifiable(_logs);
  String? get logFilePath => _logFile?.path;
  List<String> get errorLogs =>
      _logs.where((line) => _isErrorLine(line)).toList(growable: false);

  Future<void> initialize() async {
    if (_sink != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory(p.join(dir.path, 'logs'));
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      _logFile = File(p.join(logDir.path, 'anivault-$stamp.log'));
      _sink = _logFile!.openWrite(mode: FileMode.append);
      log('[Log] Session log: ${_logFile!.path}');
    } catch (e) {
      debugPrint('Logger file init failed: $e');
    }
  }

  void log(String message) {
    final timestamp = DateTime.now()
        .toIso8601String()
        .split('T')
        .last
        .substring(0, 8);
    _logs.insert(0, '[$timestamp] $message'); // Add to top
    _sink?.writeln('[$timestamp] $message');
    if (_logs.length > 500) {
      _logs.removeLast(); // Keep recent 500
    }
    notifyListeners();
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }

  bool _isErrorLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('error') || lower.contains('failed');
  }
}
