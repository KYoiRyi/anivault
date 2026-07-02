import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _ParseJsonC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> input);
typedef _ParseJsonDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> input);
typedef _FreeC = ffi.Void Function(ffi.Pointer<Utf8> value);
typedef _FreeDart = void Function(ffi.Pointer<Utf8> value);

class AnitomyNative {
  static final AnitomyNative _instance = AnitomyNative._internal();
  factory AnitomyNative() => _instance;

  late final ffi.DynamicLibrary _library;
  late final _ParseJsonDart _parseJson;
  late final _FreeDart _free;

  AnitomyNative._internal() {
    _library = _openLibrary();
    _parseJson = _library
        .lookup<ffi.NativeFunction<_ParseJsonC>>('anivault_anitomy_parse_json')
        .asFunction();
    _free = _library
        .lookup<ffi.NativeFunction<_FreeC>>('anivault_anitomy_free')
        .asFunction();
  }

  Map<String, dynamic> parse(String input) {
    final inputPtr = input.toNativeUtf8();
    final outputPtr = _parseJson(inputPtr);
    malloc.free(inputPtr);
    if (outputPtr == ffi.nullptr) return const {};
    try {
      final output = outputPtr.toDartString();
      final decoded = jsonDecode(output);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } finally {
      _free(outputPtr);
    }
  }

  ffi.DynamicLibrary _openLibrary() {
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$exeDir\\anivault_anitomy.dll',
        '${Directory.current.path}\\build\\windows\\x64\\runner\\Release\\anivault_anitomy.dll',
        '${Directory.current.path}\\build\\windows\\x64\\runner\\Debug\\anivault_anitomy.dll',
        '${Directory.current.path}\\AniVault-windows-release\\anivault_anitomy.dll',
      ];
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return ffi.DynamicLibrary.open(candidate);
        }
      }
      return ffi.DynamicLibrary.open('anivault_anitomy.dll');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return ffi.DynamicLibrary.process();
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return ffi.DynamicLibrary.open('libanivault_anitomy.so');
    }
    throw UnsupportedError('Unsupported platform for Anitomy');
  }
}
