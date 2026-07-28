import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'api_service.dart';
import 'services/scan_service.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';
import 'widgets/liquid_glass.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Awaited so the first frame already has refraction. If it fails the app
  // still starts — LiquidGlass falls back to a plain blur.
  await LiquidGlassProgram.load();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ApiService()),
        ChangeNotifierProvider(create: (_) => ScanService()),
      ],
      child: const QuantXApp(),
    ),
  );
}

class QuantXApp extends StatelessWidget {
  const QuantXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuantX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const HomeShell(),
    );
  }
}
