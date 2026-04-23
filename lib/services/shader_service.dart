import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:anivault/services/logger_service.dart';

class ShaderService {
  static final ShaderService _instance = ShaderService._internal();
  factory ShaderService() => _instance;
  ShaderService._internal();

  final Map<String, String> _shaderPaths = {};
  String _artCnnPath = '';

  Future<void> initializeShaders() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final shaderDir = Directory(p.join(appDir.path, 'shaders'));

      if (!await shaderDir.exists()) {
        await shaderDir.create(recursive: true);
      }

      final models = [
        'Anime4K_Restore_CNN_S.glsl',
        'Anime4K_Restore_CNN_M.glsl',
        'Anime4K_Restore_CNN_L.glsl',
        'Anime4K_Restore_CNN_VL.glsl',
        'ArtCNN_C4F32.onnx',
      ];

      for (var model in models) {
        final destFile = File(p.join(shaderDir.path, model));
        if (!await destFile.exists()) {
          LoggerService().log('Shader: preparing $model...');
          final byteData = await rootBundle.load('assets/shaders/$model');
          await destFile.writeAsBytes(
            byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ),
          );
        } else {
          LoggerService().log('Shader: ready at ${destFile.path}');
        }

        switch (model) {
          case 'Anime4K_Restore_CNN_S.glsl':
            _shaderPaths['Speed'] = destFile.path;
            break;
          case 'Anime4K_Restore_CNN_M.glsl':
            _shaderPaths['Balanced'] = destFile.path;
            break;
          case 'Anime4K_Restore_CNN_L.glsl':
            _shaderPaths['Quality'] = destFile.path;
            break;
          case 'Anime4K_Restore_CNN_VL.glsl':
            _shaderPaths['Extreme'] = destFile.path;
            break;
          case 'ArtCNN_C4F32.onnx':
            _artCnnPath = destFile.path;
            break;
        }
      }
      LoggerService().log('Shader & ML Models: initialized successfully.');
    } catch (e) {
      LoggerService().log('ERROR: Failed to unpack shaders: $e');
    }
  }

  String? getShaderPath(String key) => _shaderPaths[key];
  String get artCnnPath => _artCnnPath;
}
