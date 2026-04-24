import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:anivault/services/logger_service.dart';

// Type definitions for C-FFI functions
typedef ArtCnnInitC = ffi.Int32 Function(ffi.Pointer<Utf8> modelPath);
typedef ArtCnnInitDart = int Function(ffi.Pointer<Utf8> modelPath);

typedef ArtCnnProcessFrameC = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> buffer,
  ffi.Int32 bufferSize,
  ffi.Int32 width,
  ffi.Int32 height,
);
typedef ArtCnnProcessFrameDart = int Function(
  ffi.Pointer<ffi.Uint8> buffer,
  int bufferSize,
  int width,
  int height,
);

class FFIEngine {
  static final FFIEngine _instance = FFIEngine._internal();
  factory FFIEngine() => _instance;

  late final ffi.DynamicLibrary _lib;
  late final ArtCnnInitDart _initModel;
  late final ArtCnnProcessFrameDart _processFrame;
  bool _isLoaded = false;

  FFIEngine._internal() {
    _loadLibrary();
  }

  void _loadLibrary() {
    try {
      if (Platform.isWindows) {
        _lib = ffi.DynamicLibrary.open('anivault_core.dll');
      } else if (Platform.isIOS || Platform.isMacOS) {
        _lib = ffi.DynamicLibrary.process(); // iOS statically links Rust archives
      } else if (Platform.isAndroid || Platform.isLinux) {
        _lib = ffi.DynamicLibrary.open('libanivault_core.so');
      } else {
        throw UnsupportedError('Unsupported Platform');
      }

      _initModel = _lib
          .lookup<ffi.NativeFunction<ArtCnnInitC>>('artcnn_init')
          .asFunction();
      _processFrame = _lib
          .lookup<ffi.NativeFunction<ArtCnnProcessFrameC>>('artcnn_process_frame')
          .asFunction();

      _isLoaded = true;
      LoggerService().log('[FFI] anivault_core successfully linked!');
    } catch (e) {
      LoggerService().log('[FFI Error] Failed to load anivault_core: $e');
    }
  }

  /// Bootstraps the ONNX CoreML/DirectML Execution Providers in Rust
  bool initializeArtCNN(String modelAbsPath) {
    if (!_isLoaded) return false;
    final modelPathPtr = modelAbsPath.toNativeUtf8();
    final status = _initModel(modelPathPtr);
    malloc.free(modelPathPtr);
    
    if (status == 0) {
      LoggerService().log('[FFI] ArtCNN Engine Initialized natively.');
      return true;
    } else {
      LoggerService().log('[FFI Error] ArtCNN init failed with code: $status');
      return false;
    }
  }

  /// Processes raw RGB frame. 
  /// WARNING: Intended for debugging/fallback if Native video filter hook is bypassed.
  bool processFrameSync(ffi.Pointer<ffi.Uint8> buffer, int size, int width, int height) {
    if (!_isLoaded) return false;
    // Blocks thread during DirectML / CoreML inference
    final status = _processFrame(buffer, size, width, height);
    return status == 0;
  }
}
