import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:smb_connect/smb_connect.dart';
import 'package:anivault/services/logger_service.dart';

class SMBService extends ChangeNotifier {
  static final SMBService _instance = SMBService._internal();
  factory SMBService() => _instance;
  SMBService._internal();

  SmbConnect? _connection;
  String _host = '';
  String _share = '';
  
  bool get isConnected => _connection != null;
  String get currentHost => _host;
  
  Future<bool> connect(String host, String domain, String username, String password) async {
    try {
      LoggerService().log('[SMB] Connecting to $host...');
      _connection = await SmbConnect.connectAuth(
        host: host,
        domain: domain,
        username: username,
        password: password,
        onDisconnect: (ctx) {
          LoggerService().log('[SMB] Connection dropped unexpectedly.');
          _connection = null;
          notifyListeners();
        }
      );
      _host = host;
      LoggerService().log('[SMB] Connected successfully.');
      notifyListeners();
      return true;
    } catch (e) {
      LoggerService().log('[SMB ERROR] Connection failed: $e');
      _connection = null;
      notifyListeners();
      return false;
    }
  }

  Future<List<SmbFile>> listShares() async {
    if (_connection == null) return [];
    try {
      return await _connection!.listShares();
    } catch (e) {
      LoggerService().log('[SMB ERROR] Failed to list shares: $e');
      return [];
    }
  }

  Future<List<SmbFile>> listFiles(String smbPath) async {
    if (_connection == null) return [];
    try {
      SmbFile folder = await _connection!.file(smbPath);
      return await _connection!.listFiles(folder);
    } catch (e) {
      LoggerService().log('[SMB ERROR] Failed scanning path $smbPath: $e');
      return [];
    }
  }
  
  SmbConnect? get connection => _connection;

  Future<void> disconnect() async {
    if (_connection != null) {
      await _connection!.close();
      _connection = null;
      LoggerService().log('[SMB] Disconnected.');
      notifyListeners();
    }
  }
}
