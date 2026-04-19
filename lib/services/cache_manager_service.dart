import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smb_connect/smb_connect.dart';

import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/smb_service.dart';

class CacheTask {
  final String smbPath;
  final String localPath;
  final String fileName;
  final int totalBytes;
  final DateTime startedAt;

  int downloadedBytes = 0;
  bool isCompleted = false;

  CacheTask({
    required this.smbPath,
    required this.localPath,
    required this.fileName,
    required this.totalBytes,
    required this.startedAt,
  });

  double get progress {
    if (totalBytes <= 0) return 0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  double get speedBytesPerSecond {
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds / 1000;
    if (elapsed <= 0) return 0;
    return downloadedBytes / elapsed;
  }
}

class CachedDownload {
  final String smbPath;
  final String localPath;
  final String fileName;
  final int size;
  final DateTime cachedAt;

  const CachedDownload({
    required this.smbPath,
    required this.localPath,
    required this.fileName,
    required this.size,
    required this.cachedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'smbPath': smbPath,
      'localPath': localPath,
      'fileName': fileName,
      'size': size,
      'cachedAt': cachedAt.toIso8601String(),
    };
  }

  factory CachedDownload.fromJson(Map<String, dynamic> json) {
    return CachedDownload(
      smbPath: json['smbPath'] as String? ?? '',
      localPath: json['localPath'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      cachedAt:
          DateTime.tryParse(json['cachedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class CacheManagerService extends ChangeNotifier {
  static final CacheManagerService _instance = CacheManagerService._internal();
  factory CacheManagerService() => _instance;
  CacheManagerService._internal();

  static const _downloadsKey = 'cached_downloads';
  static const _progressNotifyInterval = Duration(milliseconds: 250);
  static const _progressNotifyBytes = 1024 * 1024;

  double _cacheLimitGB = 10.0;
  final Map<String, CacheTask> _activeTasks = {};
  final List<CachedDownload> _cachedDownloads = [];

  double get cacheLimitGB => _cacheLimitGB;
  Map<String, CacheTask> get activeTasks => Map.unmodifiable(_activeTasks);
  List<CachedDownload> get cachedDownloads =>
      List.unmodifiable(_cachedDownloads);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _cacheLimitGB = prefs.getDouble('cache_limit_gb') ?? 10.0;

    _cachedDownloads.clear();
    final rawDownloads = prefs.getStringList(_downloadsKey) ?? [];
    for (final raw in rawDownloads) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final record = CachedDownload.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (record.smbPath.isNotEmpty && record.localPath.isNotEmpty) {
            _cachedDownloads.add(record);
          }
        }
      } catch (_) {
        // Ignore old or partial metadata entries.
      }
    }

    await _reconcileDownloads();
  }

  Future<void> setCacheLimit(double gb) async {
    _cacheLimitGB = gb;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cache_limit_gb', gb);
    notifyListeners();
    await _enforceLRU();
  }

  bool isCached(String smbPath, {int? expectedBytes}) {
    final record = _downloadForPath(smbPath);
    if (record == null) return false;
    final file = File(record.localPath);
    if (!file.existsSync()) return false;
    if (expectedBytes != null && expectedBytes > 0) {
      try {
        return file.lengthSync() == expectedBytes;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  Future<void> cacheFile(SmbFile smbFile) async {
    if (_activeTasks.containsKey(smbFile.path)) return;

    final existingPath = await getCachedPath(
      smbFile.path,
      expectedBytes: smbFile.size,
    );
    if (existingPath != null) {
      LoggerService().log('[Download] Already downloaded: ${smbFile.name}');
      return;
    }

    final smbConn = SMBService().connection;
    if (smbConn == null) {
      LoggerService().log('[Download] SMB is not connected.');
      return;
    }

    IOSink? writer;
    File? partFile;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(docDir.path, 'SMBVault'));
      if (!await vaultDir.exists()) await vaultDir.create(recursive: true);

      await _enforceLRU(incomingBytes: smbFile.size);

      final localFile = File(
        p.join(vaultDir.path, _safeCacheName(smbFile.path)),
      );
      partFile = File('${localFile.path}.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }

      final task = CacheTask(
        smbPath: smbFile.path,
        localPath: localFile.path,
        fileName: smbFile.name,
        totalBytes: smbFile.size,
        startedAt: DateTime.now(),
      );
      _activeTasks[smbFile.path] = task;
      notifyListeners();

      LoggerService().log('[Download] Starting: ${smbFile.name}');

      final reader = await smbConn.openRead(smbFile, 0, smbFile.size);
      writer = partFile.openWrite(mode: FileMode.writeOnly);

      var lastNotifyAt = DateTime.now();
      var lastNotifyBytes = 0;

      await for (final chunk in reader) {
        final remainingBytes = task.totalBytes - task.downloadedBytes;
        if (remainingBytes <= 0) break;

        final bytesToWrite = chunk.length > remainingBytes
            ? remainingBytes
            : chunk.length;
        if (bytesToWrite <= 0) break;

        writer.add(
          bytesToWrite == chunk.length
              ? chunk
              : Uint8List.sublistView(chunk, 0, bytesToWrite),
        );
        task.downloadedBytes += bytesToWrite;

        final now = DateTime.now();
        final shouldNotify =
            now.difference(lastNotifyAt) >= _progressNotifyInterval ||
            task.downloadedBytes - lastNotifyBytes >= _progressNotifyBytes ||
            task.downloadedBytes >= task.totalBytes;

        if (shouldNotify) {
          lastNotifyAt = now;
          lastNotifyBytes = task.downloadedBytes;
          notifyListeners();
        }
      }

      await writer.close();
      writer = null;

      if (task.totalBytes > 0 && task.downloadedBytes != task.totalBytes) {
        throw FileSystemException(
          'Download ended at ${task.downloadedBytes} bytes, expected ${task.totalBytes} bytes',
          partFile.path,
        );
      }

      if (await localFile.exists()) {
        await localFile.delete();
      }
      await partFile.rename(localFile.path);

      task.downloadedBytes = task.totalBytes;
      task.isCompleted = true;
      _upsertDownload(
        CachedDownload(
          smbPath: smbFile.path,
          localPath: localFile.path,
          fileName: smbFile.name,
          size: smbFile.size,
          cachedAt: DateTime.now(),
        ),
      );
      await _saveDownloads();

      LoggerService().log('[Download] Complete: ${smbFile.name}');
      notifyListeners();

      Future.delayed(const Duration(seconds: 2), () {
        if (_activeTasks[smbFile.path] == task) {
          _activeTasks.remove(smbFile.path);
          notifyListeners();
        }
      });
    } catch (e) {
      LoggerService().log('[Download] Failed: ${smbFile.name} ($e)');
      _activeTasks.remove(smbFile.path);
      try {
        await writer?.close();
      } catch (_) {}
      try {
        if (partFile != null && await partFile.exists()) {
          await partFile.delete();
        }
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<void> deleteDownload(CachedDownload download) async {
    try {
      final file = File(download.localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      LoggerService().log(
        '[Download] Failed to delete ${download.fileName}: $e',
      );
    }

    _cachedDownloads.removeWhere((item) => item.smbPath == download.smbPath);
    await _saveDownloads();
    notifyListeners();
  }

  Future<String?> getCachedPath(String smbPath, {int? expectedBytes}) async {
    final record = _downloadForPath(smbPath);
    if (record != null) {
      final file = File(record.localPath);
      if (await file.exists()) {
        if (expectedBytes != null &&
            expectedBytes > 0 &&
            await file.length() != expectedBytes) {
          await _removeBadDownload(record, file);
          return null;
        }
        await _touch(file);
        return file.path;
      }

      _cachedDownloads.removeWhere((item) => item.smbPath == smbPath);
      await _saveDownloads();
      notifyListeners();
      return null;
    }

    final docDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(docDir.path, 'SMBVault'));
    final localFile = File(p.join(vaultDir.path, _safeCacheName(smbPath)));

    if (await localFile.exists()) {
      if (expectedBytes != null &&
          expectedBytes > 0 &&
          await localFile.length() != expectedBytes) {
        try {
          await localFile.delete();
        } catch (_) {}
        return null;
      }
      await _touch(localFile);
      _upsertDownload(
        CachedDownload(
          smbPath: smbPath,
          localPath: localFile.path,
          fileName: p.basename(smbPath),
          size: await localFile.length(),
          cachedAt: await localFile.lastModified(),
        ),
      );
      await _saveDownloads();
      notifyListeners();
      return localFile.path;
    }

    return null;
  }

  Future<void> _enforceLRU({int incomingBytes = 0}) async {
    final docDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(docDir.path, 'SMBVault'));
    if (!await vaultDir.exists()) return;

    final limitBytes = (_cacheLimitGB * 1024 * 1024 * 1024).toInt();
    final cachedFiles = <File>[];
    var currentSizeBytes = 0;

    await for (final entity in vaultDir.list(recursive: false)) {
      if (entity is File && !entity.path.endsWith('.part')) {
        cachedFiles.add(entity);
        currentSizeBytes += await entity.length();
      }
    }

    if (currentSizeBytes + incomingBytes <= limitBytes) return;

    LoggerService().log(
      '[Download] Cache limit reached. Removing old files...',
    );
    cachedFiles.sort(
      (a, b) => a.lastAccessedSync().compareTo(b.lastAccessedSync()),
    );

    final targetSize = limitBytes - incomingBytes;
    var changed = false;

    for (final file in cachedFiles) {
      if (currentSizeBytes <= targetSize) break;

      final size = await file.length();
      try {
        await file.delete();
        currentSizeBytes -= size;
        _cachedDownloads.removeWhere((item) => item.localPath == file.path);
        changed = true;
        LoggerService().log(
          '[Download] Removed old file: ${p.basename(file.path)}',
        );
      } catch (e) {
        LoggerService().log(
          '[Download] Could not remove ${p.basename(file.path)}: $e',
        );
      }
    }

    if (changed) {
      await _saveDownloads();
      notifyListeners();
    }
  }

  Future<void> _reconcileDownloads() async {
    final before = _cachedDownloads.length;
    _cachedDownloads.removeWhere((item) => !File(item.localPath).existsSync());
    if (_cachedDownloads.length != before) {
      await _saveDownloads();
    }
  }

  Future<void> _saveDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _downloadsKey,
      _cachedDownloads.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  void _upsertDownload(CachedDownload download) {
    _cachedDownloads.removeWhere((item) => item.smbPath == download.smbPath);
    _cachedDownloads.insert(0, download);
  }

  CachedDownload? _downloadForPath(String smbPath) {
    for (final item in _cachedDownloads) {
      if (item.smbPath == smbPath) return item;
    }
    return null;
  }

  Future<void> _removeBadDownload(CachedDownload record, File file) async {
    try {
      await file.delete();
    } catch (_) {}
    _cachedDownloads.removeWhere((item) => item.smbPath == record.smbPath);
    await _saveDownloads();
    LoggerService().log(
      '[Download] Removed incomplete file: ${record.fileName}',
    );
    notifyListeners();
  }

  String _safeCacheName(String smbPath) {
    return smbPath.replaceAll('/', '_').replaceAll('\\', '_');
  }

  Future<void> _touch(File file) async {
    try {
      await file.setLastAccessed(DateTime.now());
    } catch (_) {}
  }
}
