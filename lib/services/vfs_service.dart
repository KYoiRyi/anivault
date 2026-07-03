import 'dart:io';

class VFSService {
  static final VFSService _instance = VFSService._internal();
  factory VFSService() => _instance;
  VFSService._internal();

  final Set<String> _virtualFiles = {};

  void registerVirtualFile(String path) {
    _virtualFiles.add(path);
  }

  void unregisterVirtualFile(String path) {
    _virtualFiles.remove(path);
  }

  List<String> getVirtualFiles() {
    return _virtualFiles.toList();
  }

  bool existsSync(String path) {
    if (_virtualFiles.contains(path)) return true;
    return File(path).existsSync();
  }
}
