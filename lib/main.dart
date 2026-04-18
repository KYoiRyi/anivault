import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:anivault/ui/home_screen.dart';
import 'package:anivault/services/shader_service.dart';
import 'package:anivault/services/cache_manager_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  
  // Extract shaders from assets to local filesystem for native hook support
  await ShaderService().initializeShaders();
  await CacheManagerService().initialize();
  
  runApp(const AniVaultApp());
}

class AniVaultApp extends StatelessWidget {
  const AniVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.grey,
        scaffoldBackgroundColor: Colors.black, // Pure black
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
