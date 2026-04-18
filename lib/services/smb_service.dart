import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smb_connect/smb_connect.dart';
import 'package:smb_connect/src/connect/impl/base_configuration.dart';
import 'package:smb_connect/src/smb/ntlm_password_authenticator.dart';
import 'package:smb_connect/src/smb/authentication_type.dart';
import 'package:anivault/services/logger_service.dart';

class SMBService extends ChangeNotifier {
  static final SMBService _instance = SMBService._internal();
  factory SMBService() => _instance;
  SMBService._internal();

  SmbConnect? _connection;
  String _host = '';
  String _share = '';
  
  String _savedUser = '';
  String _savedPass = '';
  String _savedDomain = '';

  bool get isConnected => _connection != null;
  String get currentHost => _host;
  String get savedHost => _host;
  String get savedUser => _savedUser;
  String get savedPass => _savedPass;
  String get savedDomain => _savedDomain;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString('smb_host') ?? '';
    _savedUser = prefs.getString('smb_user') ?? '';
    _savedPass = prefs.getString('smb_pass') ?? '';
  }
  
  Future<bool> connect(String host, String domain, String username, String password) async {
    try {
      LoggerService().log('[SMB] Connecting to $host (Injecting 1MB Buffers)...');

      final creds = NtlmPasswordAuthenticator(
        type: AuthenticationType.USER, domain: domain, username: username, password: password
      );

      final config = BaseConfiguration(
        credentials: creds,
        username: username,
        password: password,
        domain: domain,
        bufferCacheSize: 0xFFFF,  // 64K cache pools
        maximumBufferSize: 1048576, // 1MB Maximum throughput
        receiveBufferSize: 1048576,
        sendBufferSize: 1048576,
      );

      _connection = await SmbConnect.connect(
        config,
        host,
        onDisconnect: (ctx) {
          LoggerService().log('[SMB] Connection dropped unexpectedly.');
          _connection = null;
          notifyListeners();
        }
      );

      _host = host;
      _savedUser = username;
      _savedPass = password;
      _savedDomain = domain;

      // Persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('smb_host', host);
      await prefs.setString('smb_user', username);
      await prefs.setString('smb_pass', password);

      LoggerService().log('[SMB] Connected successfully (High Throughput Tunnel Active).');
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
