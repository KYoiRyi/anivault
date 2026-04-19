// ignore_for_file: implementation_imports

import 'dart:async';
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
  bool _isConnecting = false;
  String _host = '';

  String _savedUser = '';
  String _savedPass = '';
  String _savedDomain = '';

  bool get isConnected => _connection != null;
  bool get isConnecting => _isConnecting;
  bool get hasSavedConnection => _host.trim().isNotEmpty;
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
    _savedDomain = prefs.getString('smb_domain') ?? '';
  }

  Future<bool> connect(
    String host,
    String domain,
    String username,
    String password,
  ) async {
    await saveSettings(
      host: host,
      domain: domain,
      username: username,
      password: password,
    );
    if (_isConnecting) return false;
    _isConnecting = true;
    notifyListeners();

    try {
      LoggerService().log('[SMB] Connecting to $host...');

      final creds = NtlmPasswordAuthenticator(
        type: AuthenticationType.USER,
        domain: domain,
        username: username,
        password: password,
      );

      final config = BaseConfiguration(
        credentials: creds,
        username: username,
        password: password,
        domain: domain,
        bufferCacheSize: 32,
        maximumBufferSize: 1048576,
        transactionBufferSize: 1048576,
        receiveBufferSize: 1048576,
        sendBufferSize: 1048576,
      );

      final previousConnection = _connection;
      _connection = null;
      await previousConnection?.close();

      _connection = await SmbConnect.connect(
        config,
        host,
        onDisconnect: (ctx) {
          LoggerService().log('[SMB] Connection dropped unexpectedly.');
          _connection = null;
          notifyListeners();
        },
      );

      LoggerService().log('[SMB] Connected successfully.');
      notifyListeners();
      return true;
    } catch (e) {
      LoggerService().log('[SMB ERROR] Connection failed: $e');
      _connection = null;
      notifyListeners();
      return false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<bool> connectSaved() async {
    if (!hasSavedConnection || isConnected || _isConnecting) {
      return isConnected;
    }

    return connect(_host, _savedDomain, _savedUser, _savedPass);
  }

  Future<void> saveSettings({
    required String host,
    required String domain,
    required String username,
    required String password,
  }) async {
    _host = host;
    _savedDomain = domain;
    _savedUser = username;
    _savedPass = password;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('smb_host', host);
    await prefs.setString('smb_domain', domain);
    await prefs.setString('smb_user', username);
    await prefs.setString('smb_pass', password);
    notifyListeners();
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

  Future<SmbFile?> fileInfo(String smbPath) async {
    if (_connection == null) return null;
    try {
      return await _connection!.file(smbPath);
    } catch (e) {
      LoggerService().log('[SMB ERROR] Failed to read file info $smbPath: $e');
      return null;
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
