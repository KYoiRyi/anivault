import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/torrent_native.dart';

class TorrentFileState {
  final String path;
  final String displayPath;
  final int length;
  final int downloadedBytes;

  const TorrentFileState({
    required this.path,
    required this.displayPath,
    required this.length,
    required this.downloadedBytes,
  });

  factory TorrentFileState.fromJson(Map<String, dynamic> json) {
    return TorrentFileState(
      path: json['path'] as String? ?? '',
      displayPath: json['displayPath'] as String? ?? '',
      length: (json['length'] as num?)?.toInt() ?? 0,
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class TorrentTaskState {
  final String id;
  final String magnet;
  final String name;
  final int downloadedBytes;
  final int totalBytes;
  final double progress;
  final bool complete;
  final bool paused;
  final bool gotInfo;
  final String? error;
  final String? diagnostics;
  final List<TorrentFileState> files;

  const TorrentTaskState({
    required this.id,
    required this.magnet,
    required this.name,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.progress,
    required this.complete,
    required this.paused,
    required this.gotInfo,
    required this.files,
    this.error,
    this.diagnostics,
  });

  factory TorrentTaskState.fromJson(Map<String, dynamic> json) {
    return TorrentTaskState(
      id: json['id'] as String? ?? '',
      magnet: json['magnet'] as String? ?? '',
      name: json['name'] as String? ?? 'Magnet',
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      complete: json['complete'] == true,
      paused: json['paused'] == true,
      gotInfo: json['gotInfo'] == true,
      error: json['error'] as String?,
      diagnostics: json['diagnostics'] as String?,
      files:
          (json['files'] as List?)
              ?.whereType<Map>()
              .map(
                (item) =>
                    TorrentFileState.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList() ??
          const [],
    );
  }

  String? get bestLibraryPath {
    final videoFiles =
        completedVideoPaths
            .map((path) => files.firstWhere((file) => file.path == path))
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    return videoFiles.isNotEmpty ? videoFiles.first.path : null;
  }

  List<String> get completedVideoPaths {
    return files
        .where(
          (file) =>
              _isVideoPath(file.path) &&
              file.length > 0 &&
              file.downloadedBytes >= file.length &&
              File(PathResolver.resolve(file.path)).existsSync(),
        )
        .map((file) => file.path)
        .toList();
  }

  bool get hasCompletedLibraryMedia =>
      complete || completedVideoPaths.isNotEmpty;
}

class TorrentService extends ChangeNotifier {
  static final TorrentService _instance = TorrentService._internal();
  factory TorrentService() => _instance;
  TorrentService._internal();

  static const _taskKey = 'bt_tasks';
  static const _completedKey = 'bt_completed_library_paths';
  static const _pollInterval = Duration(seconds: 1);

  final Map<String, String> _magnetsById = {};
  final Map<String, TorrentTaskState> _tasks = {};
  final Set<String> _completedLibraryPaths = {};
  final Map<String, String> _lastLoggedDiagnostics = {};
  Directory? _downloadRoot;
  Timer? _pollTimer;
  bool _initialized = false;
  bool _nativeReady = false;
  String? _lastError;
  Future<void> Function()? _onLibraryChanged;

  bool get nativeReady => _nativeReady;
  String? get lastError => _lastError;
  String? get downloadDirectory => _downloadRoot?.path;
  List<TorrentTaskState> get tasks => List.unmodifiable(_tasks.values);

  void setLibraryChangedHandler(Future<void> Function()? handler) {
    _onLibraryChanged = handler;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _loadPersistedTasks();
    try {
      final dir = await _downloadDirectory();
      _downloadRoot = dir;
      _check(TorrentNative().init(dir.path));
      LoggerService().log('[BT] Download directory: ${dir.path}');
      _nativeReady = true;
      for (final magnet in _magnetsById.values) {
        _restoreMagnet(magnet);
      }
      _startPolling();
    } catch (e) {
      _lastError = e.toString();
      LoggerService().log('[BT] Native torrent init failed: $e');
    }
    notifyListeners();
  }

  Future<void> addMagnet(String magnet) async {
    await initialize();
    final trimmed = magnet.trim();
    if (trimmed.isEmpty) return;
    final data = _check(TorrentNative().addMagnet(trimmed));
    final task = TorrentTaskState.fromJson(Map<String, dynamic>.from(data));
    _magnetsById[task.id] = trimmed;
    _tasks[task.id] = task;
    await _savePersistedTasks();
    _startPolling();
    notifyListeners();
  }

  Future<void> pause(String id) async {
    final data = _check(TorrentNative().pause(id));
    _tasks[id] = TorrentTaskState.fromJson(Map<String, dynamic>.from(data));
    notifyListeners();
  }

  Future<void> resume(String id) async {
    final data = _check(TorrentNative().resume(id));
    _tasks[id] = TorrentTaskState.fromJson(Map<String, dynamic>.from(data));
    _startPolling();
    notifyListeners();
  }

  Future<void> remove(String id, {bool dropData = false}) async {
    _check(TorrentNative().remove(id, dropData: dropData));
    _magnetsById.remove(id);
    _tasks.remove(id);
    await _savePersistedTasks();
    notifyListeners();
  }

  Future<void> poll({Future<void> Function()? onLibraryChanged}) async {
    if (!_nativeReady) return;
    try {
      final data = _check(TorrentNative().status());
      final list = data is List ? data : const [];
      var libraryChanged = false;
      _tasks
        ..clear()
        ..addEntries(
          list.whereType<Map>().map((item) {
            final task = TorrentTaskState.fromJson(
              Map<String, dynamic>.from(item),
            );
            _magnetsById[task.id] = task.magnet;
            return MapEntry(task.id, task);
          }),
        );
      for (final task in _tasks.values) {
        _logTaskDiagnostics(task);
        if (task.hasCompletedLibraryMedia) {
          libraryChanged =
              await _markCompletedForLibrary(task) || libraryChanged;
        }
      }
      libraryChanged =
          await _scanDownloadRootIntoLibrary(_activeIncompletePaths()) ||
          libraryChanged;
      await _savePersistedTasks();
      if (libraryChanged) {
        await _refreshLibraryFromPrefs();
        await onLibraryChanged?.call();
      }
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      LoggerService().log('[BT] Poll failed: $e');
      notifyListeners();
    }
  }

  void _logTaskDiagnostics(TorrentTaskState task) {
    final message = task.error ?? task.diagnostics;
    if (message == null || message.trim().isEmpty) return;
    if (_lastLoggedDiagnostics[task.id] == message) return;
    _lastLoggedDiagnostics[task.id] = message;
    LoggerService().log('[BT] ${task.name}: $message');
  }

  dynamic _check(Map<String, dynamic> response) {
    if (response['ok'] == true) {
      _lastError = null;
      return response['data'];
    }
    throw StateError(
      response['error'] as String? ?? 'Torrent native call failed',
    );
  }

  void _restoreMagnet(String magnet) {
    try {
      final data = _check(TorrentNative().addMagnet(magnet));
      final task = TorrentTaskState.fromJson(Map<String, dynamic>.from(data));
      _tasks[task.id] = task;
      _magnetsById[task.id] = magnet;
    } catch (e) {
      LoggerService().log('[BT] Restore failed: $e');
    }
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(
      _pollInterval,
      (_) => unawaited(poll(onLibraryChanged: _onLibraryChanged)),
    );
  }

  Future<Directory> _downloadDirectory() async {
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final dir = Directory(p.join(exeDir, 'download'));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      return docDir;
    }
  }

  Future<bool> _markCompletedForLibrary(TorrentTaskState task) async {
    final paths = task.completedVideoPaths
        .where(
          (path) =>
              !_completedLibraryPaths.contains(PathResolver.canonicalKey(path)),
        )
        .toList();
    if (paths.isEmpty) return false;

    var changed = false;
    for (final path in paths) {
      final resolvedPath = PathResolver.resolve(path);
      if (!File(resolvedPath).existsSync()) continue;
      _completedLibraryPaths.add(PathResolver.canonicalKey(resolvedPath));
      await _addPathToMediaLibrary(resolvedPath);
      LoggerService().log('[BT] Added to library: ${p.basename(resolvedPath)}');
      changed = true;
    }
    if (changed) await _saveCompletedLibraryPaths();
    return changed;
  }

  Set<String> _activeIncompletePaths() {
    return {
      for (final task in _tasks.values)
        if (!task.complete)
          for (final file in task.files)
            if (_isFinalVideoPath(file.path))
              PathResolver.canonicalKey(file.path),
    };
  }

  Future<bool> _scanDownloadRootIntoLibrary(
    Set<String> activeIncompletePaths,
  ) async {
    final root = _downloadRoot;
    if (root == null || !await root.exists()) return false;
    final discovered = <String>[];
    await for (final file in _walkVideoFiles(root)) {
      discovered.add(file.path);
    }
    if (Platform.isWindows) {
      final legacy = Directory(
        p.join(File(Platform.resolvedExecutable).parent.path, 'downloads'),
      );
      if (await legacy.exists()) {
        await for (final file in _walkVideoFiles(legacy)) {
          discovered.add(file.path);
        }
      }
    }
    var changed = false;
    for (final path in discovered.toSet()) {
      final resolvedPath = PathResolver.resolve(path);
      final key = PathResolver.canonicalKey(resolvedPath);
      if (activeIncompletePaths.contains(key)) continue;
      if (_completedLibraryPaths.contains(key)) continue;
      _completedLibraryPaths.add(key);
      await _addPathToMediaLibrary(resolvedPath);
      LoggerService().log(
        '[BT] Scanned into library: ${p.basename(resolvedPath)}',
      );
      changed = true;
    }
    if (changed) await _saveCompletedLibraryPaths();
    return changed;
  }

  Stream<File> _walkVideoFiles(Directory root) async* {
    Stream<FileSystemEntity> children;
    try {
      children = root.list(followLinks: false);
    } on FileSystemException catch (e) {
      LoggerService().log(
        '[BT] Skip inaccessible directory: ${root.path} ($e)',
      );
      return;
    }

    try {
      await for (final entity in children) {
        if (entity is Directory) {
          yield* _walkVideoFiles(entity);
        } else if (entity is File &&
            _isFinalVideoPath(entity.path) &&
            await entity.length() > 0) {
          yield entity;
        }
      }
    } on FileSystemException catch (e) {
      LoggerService().log(
        '[BT] Skip inaccessible directory: ${root.path} ($e)',
      );
    }
  }

  Future<void> _addPathToMediaLibrary(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedPath = PathResolver.resolve(path);
    final existing = prefs.getStringList('media_library') ?? const [];
    final paths = _uniqueResolvedPaths([resolvedPath, ...existing]);
    if (paths.length != existing.length ||
        paths.isNotEmpty && paths.first == resolvedPath) {
      await prefs.setStringList('media_library', paths);
    }
  }

  Future<void> _refreshLibraryFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final paths =
        prefs
            .getStringList('media_library')
            ?.map(PathResolver.resolve)
            .toSet()
            .where((path) => File(path).existsSync())
            .toList() ??
        const [];
    if (paths.isEmpty) return;
    final languageCode = Platform.localeName.split('_').first;
    await AnimeLibraryService().refreshLibrary(
      paths,
      languageCode: languageCode.isEmpty ? 'en' : languageCode,
    );
  }

  Future<void> _loadPersistedTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final rawTasks = prefs.getStringList(_taskKey) ?? const [];
    for (final raw in rawTasks) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final id = decoded['id'] as String? ?? '';
          final magnet = decoded['magnet'] as String? ?? '';
          if (id.isNotEmpty && magnet.isNotEmpty) _magnetsById[id] = magnet;
        }
      } catch (_) {}
    }
    final completed = prefs.getStringList(_completedKey) ?? const [];
    _completedLibraryPaths
      ..clear()
      ..addAll(completed.map(PathResolver.canonicalKey));
  }

  Future<void> _savePersistedTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _taskKey,
      _magnetsById.entries
          .map((entry) => jsonEncode({'id': entry.key, 'magnet': entry.value}))
          .toList(),
    );
  }

  Future<void> _saveCompletedLibraryPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_completedKey, _completedLibraryPaths.toList());
  }

  List<String> _uniqueResolvedPaths(Iterable<String> paths) {
    final seen = <String>{};
    final result = <String>[];
    for (final path in paths) {
      final resolved = PathResolver.resolve(path);
      final key = PathResolver.canonicalKey(resolved);
      if (seen.add(key)) result.add(resolved);
    }
    return result;
  }
}

bool _isVideoPath(String path) {
  return _isFinalVideoPath(path);
}

bool _isFinalVideoPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm');
}

class PathResolver {
  static String? _docDirPath;
  static String? _exeDirPath;

  @visibleForTesting
  static void configureForTesting({String? docDirPath, String? exeDirPath}) {
    _docDirPath = docDirPath;
    _exeDirPath = exeDirPath;
  }

  static Future<void> initialize() async {
    final docDir = await getApplicationDocumentsDirectory();
    _docDirPath = docDir.path;
    _exeDirPath = File(Platform.resolvedExecutable).parent.path;
  }

  static String resolve(String path) {
    final normalized = path.replaceAll('\\', '/');

    // 1. Check if it's a Windows download path. Keep the old plural folder
    // for users who already downloaded files before the folder was renamed.
    for (final folder in const ['download', 'downloads']) {
      final marker = '/$folder/';
      final folderIndex = normalized.indexOf(marker);
      if (folderIndex != -1 && _exeDirPath != null) {
        final relativePart = normalized.substring(folderIndex + marker.length);
        return p.join(
          _exeDirPath!,
          folder,
          relativePart.replaceAll('/', p.separator),
        );
      }
    }

    // 2. Check if it's a mobile Documents path. LiveContainer may preserve
    // another app sandbox path under Documents; keep one nested sandbox prefix,
    // but collapse duplicates created by resolving already-resolved paths.
    final docIndex = normalized.indexOf('/Documents/');
    if (docIndex != -1 && _docDirPath != null) {
      final relativePart = _collapseMobileDocumentRelativePath(
        normalized.substring(docIndex + 11),
      );
      final resolved = p.join(
        _docDirPath!,
        relativePart.replaceAll('/', p.separator),
      );
      if (File(resolved).existsSync() || Directory(resolved).existsSync()) {
        return resolved;
      }
      final lastDocIndex = normalized.lastIndexOf('/Documents/');
      if (lastDocIndex != docIndex) {
        final lastRelativePart = normalized.substring(lastDocIndex + 11);
        final lastResolved = p.join(
          _docDirPath!,
          lastRelativePart.replaceAll('/', p.separator),
        );
        if (File(lastResolved).existsSync() ||
            Directory(lastResolved).existsSync()) {
          return lastResolved;
        }
      }
      return resolved;
    }

    return path;
  }

  static String canonicalKey(String path) {
    final resolved = resolve(path).replaceAll('\\', '/');
    final normalized = p.posix.normalize(resolved);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static String _collapseMobileDocumentRelativePath(String relativePath) {
    const marker = 'Data/Application/';
    final markerIndex = relativePath.indexOf(marker);
    if (markerIndex == -1) return relativePath;

    final nestedDocIndex = relativePath.indexOf('/Documents/', markerIndex);
    if (nestedDocIndex == -1) return relativePath;

    final prefix = relativePath.substring(0, nestedDocIndex + 11);
    var rest = relativePath.substring(nestedDocIndex + 11);
    while (rest.startsWith(marker)) {
      final nextDocIndex = rest.indexOf('/Documents/');
      if (nextDocIndex == -1) break;
      rest = rest.substring(nextDocIndex + 11);
    }
    return '$prefix$rest';
  }
}
