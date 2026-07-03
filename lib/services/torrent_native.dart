import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _NativeStringC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _NativeStringDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _StatusC = ffi.Pointer<Utf8> Function();
typedef _StatusDart = ffi.Pointer<Utf8> Function();
typedef _RemoveC =
    ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>, ffi.Int32 dropData);
typedef _RemoveDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>, int);
typedef _FreeC = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeDart = void Function(ffi.Pointer<Utf8>);

class TorrentNative {
  static final TorrentNative _instance = TorrentNative._internal();
  factory TorrentNative() => _instance;

  late final ffi.DynamicLibrary _library;
  late final _NativeStringDart _init;
  late final _NativeStringDart _addMagnet;
  late final _NativeStringDart _pause;
  late final _NativeStringDart _resume;
  late final _RemoveDart _remove;
  late final _StatusDart _status;
  late final _FreeDart _free;

  TorrentNative._internal() {
    _library = _openLibrary();
    _init = _lookupString('anivault_torrent_init');
    _addMagnet = _lookupString('anivault_torrent_add_magnet');
    _pause = _lookupString('anivault_torrent_pause');
    _resume = _lookupString('anivault_torrent_resume');
    _remove = _library
        .lookup<ffi.NativeFunction<_RemoveC>>('anivault_torrent_remove')
        .asFunction();
    _status = _library
        .lookup<ffi.NativeFunction<_StatusC>>('anivault_torrent_status')
        .asFunction();
    _free = _library
        .lookup<ffi.NativeFunction<_FreeC>>('anivault_torrent_free')
        .asFunction();
  }

  Map<String, dynamic> init(String downloadDir) =>
      _callString(_init, downloadDir);
  Map<String, dynamic> addMagnet(String magnet) =>
      _callString(_addMagnet, magnet);
  Map<String, dynamic> pause(String id) => _callString(_pause, id);
  Map<String, dynamic> resume(String id) => _callString(_resume, id);

  Map<String, dynamic> status() {
    final outputPtr = _status();
    return _decodeAndFree(outputPtr);
  }

  Map<String, dynamic> remove(String id, {bool dropData = false}) {
    final inputPtr = id.toNativeUtf8();
    final outputPtr = _remove(inputPtr, dropData ? 1 : 0);
    malloc.free(inputPtr);
    return _decodeAndFree(outputPtr);
  }

  _NativeStringDart _lookupString(String name) {
    return _library
        .lookup<ffi.NativeFunction<_NativeStringC>>(name)
        .asFunction();
  }

  Map<String, dynamic> _callString(_NativeStringDart fn, String value) {
    final inputPtr = value.toNativeUtf8();
    final outputPtr = fn(inputPtr);
    malloc.free(inputPtr);
    return _decodeAndFree(outputPtr);
  }

  Map<String, dynamic> _decodeAndFree(ffi.Pointer<Utf8> outputPtr) {
    if (outputPtr == ffi.nullptr) return const {'ok': false, 'error': 'null'};
    try {
      final decoded = jsonDecode(outputPtr.toDartString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } finally {
      _free(outputPtr);
    }
  }

  ffi.DynamicLibrary _openLibrary() {
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$exeDir\\anivault_torrent.dll',
        '${Directory.current.path}\\build\\windows\\x64\\runner\\Release\\anivault_torrent.dll',
        '${Directory.current.path}\\build\\windows\\x64\\runner\\Debug\\anivault_torrent.dll',
        '${Directory.current.path}\\AniVault-windows-release\\anivault_torrent.dll',
      ];
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return ffi.DynamicLibrary.open(candidate);
        }
      }
      return ffi.DynamicLibrary.open('anivault_torrent.dll');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return ffi.DynamicLibrary.process();
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return ffi.DynamicLibrary.open('libanivault_torrent.so');
    }
    throw UnsupportedError('Unsupported platform for torrent native library');
  }
}
