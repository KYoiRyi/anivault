import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class VFSService {
  static final VFSService _instance = VFSService._internal();
  factory VFSService() => _instance;
  VFSService._internal();

  final Set<String> _virtualFiles = {};
  String? _docDirPath;

  Future<void> initialize() async {
    final docDir = await getApplicationDocumentsDirectory();
    _docDirPath = docDir.path;
  }

  String resolvePath(String path) {
    if (_docDirPath == null) return path;
    
    // Normalize path separators to forward slashes for cross-platform matching
    final normalizedPath = path.replaceAll('\\', '/');
    final btIndex = normalizedPath.indexOf('BTLibrary');
    if (btIndex != -1) {
      final relativePart = normalizedPath.substring(btIndex);
      // Join using the current OS path style
      return p.join(_docDirPath!, relativePart.replaceAll('/', p.separator));
    }
    return path;
  }

  void registerVirtualFile(String path) {
    _virtualFiles.add(resolvePath(path));
  }

  void unregisterVirtualFile(String path) {
    _virtualFiles.remove(resolvePath(path));
  }

  List<String> getVirtualFiles() {
    return _virtualFiles.toList();
  }

  bool existsSync(String path) {
    final resolved = resolvePath(path);
    if (_virtualFiles.contains(resolved)) return true;
    return File(resolved).existsSync();
  }
}
