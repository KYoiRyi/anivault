import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smb_connect/smb_connect.dart';
import 'package:path/path.dart' as p;
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/smb_service.dart';

class CacheTask {
  final String smbPath;
  final String localPath;
  double progress = 0.0;
  bool isCompleted = false;

  CacheTask({required this.smbPath, required this.localPath});
}

class CacheManagerService extends ChangeNotifier {
  static final CacheManagerService _instance = CacheManagerService._internal();
  factory CacheManagerService() => _instance;
  CacheManagerService._internal();

  double _cacheLimitGB = 10.0;
  final Map<String, CacheTask> _activeTasks = {};
  
  double get cacheLimitGB => _cacheLimitGB;
  Map<String, CacheTask> get activeTasks => _activeTasks;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _cacheLimitGB = prefs.getDouble('cache_limit_gb') ?? 10.0;
  }

  Future<void> setCacheLimit(double gb) async {
    _cacheLimitGB = gb;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cache_limit_gb', gb);
    notifyListeners();
    await _enforceLRU();
  }

  Future<void> cacheFile(SmbFile smbFile) async {
    if (_activeTasks.containsKey(smbFile.path)) return; // Already downloading

    final smbConn = SMBService().connection;
    if (smbConn == null) {
      LoggerService().log('[Cache] Error: SMB not connected.');
      return;
    }

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(docDir.path, 'SMBVault'));
      if (!await vaultDir.exists()) await vaultDir.create(recursive: true);

      // Enforce space before starting
      await _enforceLRU(incomingBytes: smbFile.size);

      // Replace / with _ for flat cache storage name mapping
      final safeName = smbFile.path.replaceAll('/', '_').replaceAll('\\', '_');
      final localFile = File(p.join(vaultDir.path, safeName));

      _activeTasks[smbFile.path] = CacheTask(smbPath: smbFile.path, localPath: localFile.path);
      notifyListeners();

      LoggerService().log('[Cache] Starting download: ${smbFile.name} -> ${localFile.path}');
      
      final reader = await smbConn.openRead(smbFile);
      final writer = localFile.openWrite();

      final totalBytes = smbFile.size;
      int downloadedBytes = 0;

      await for (final chunk in reader) {
        writer.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          _activeTasks[smbFile.path]!.progress = downloadedBytes / totalBytes;
          notifyListeners();
        }
      }

      await writer.flush();
      await writer.close();
      
      _activeTasks[smbFile.path]!.progress = 1.0;
      _activeTasks[smbFile.path]!.isCompleted = true;
      LoggerService().log('[Cache] Download complete: ${smbFile.name}');
      
      notifyListeners();
      
      // Let it stay in active tasks for a moment to show 100% completion
      Future.delayed(const Duration(seconds: 2), () {
        _activeTasks.remove(smbFile.path);
        notifyListeners();
      });

    } catch (e) {
      LoggerService().log('[Cache ERROR] Download failed for ${smbFile.name}: $e');
      _activeTasks.remove(smbFile.path);
      notifyListeners();
    }
  }

  // LRU strategy enforcing
  Future<void> _enforceLRU({int incomingBytes = 0}) async {
    final docDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(docDir.path, 'SMBVault'));
    if (!await vaultDir.exists()) return;

    final limitBytes = (_cacheLimitGB * 1024 * 1024 * 1024).toInt();
    
    // Calculate current size
    final List<File> cachedFiles = [];
    int currentSizeBytes = 0;
    
    await for (final entity in vaultDir.list(recursive: false)) {
      if (entity is File) {
        cachedFiles.add(entity);
        currentSizeBytes += await entity.length();
      }
    }

    if (currentSizeBytes + incomingBytes <= limitBytes) return;

    LoggerService().log('[Cache LRU] Limit exceeded. Evicting oldest files...');
    
    // Sort by last accessed time (oldest first)
    cachedFiles.sort((a, b) => a.lastAccessedSync().compareTo(b.lastAccessedSync()));

    int targetSize = limitBytes - incomingBytes;
    
    for (final file in cachedFiles) {
      if (currentSizeBytes <= targetSize) break;
      
      final size = await file.length();
      try {
        await file.delete();
        currentSizeBytes -= size;
        LoggerService().log('[Cache LRU] Evicted: ${p.basename(file.path)}');
      } catch (e) {
        LoggerService().log('[Cache LRU] Failed to evict ${p.basename(file.path)}: $e');
      }
    }
  }

  // Returns local file path if cached, otherwise null
  Future<String?> getCachedPath(String smbPath) async {
    final docDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(docDir.path, 'SMBVault'));
    final safeName = smbPath.replaceAll('/', '_').replaceAll('\\', '_');
    final localFile = File(p.join(vaultDir.path, safeName));
    
    if (await localFile.exists()) {
      // Touch file to update last accessed time for LRU
      final now = DateTime.now();
      try {
         await localFile.setLastAccessed(now);
      } catch(_) {}
      return localFile.path;
    }
    return null;
  }
}
