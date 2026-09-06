import 'package:flutter/material.dart';
import 'package:unitec_os_app/config/api_config.dart';
import 'package:unitec_os_app/screens/detalhe_os_screen.dart';
import 'package:unitec_os_app/screens/login_screen.dart';
import 'package:unitec_os_app/screens/minhas_os_screen.dart';
import 'package:unitec_os_app/screens/nova_os_screen.dart';
import 'package:unitec_os_app/services/sync_service.dart';
import 'package:unitec_os_app/session/app_session.dart';
import 'package:unitec_os_app/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceIdentity.ensureReady();
  await ApiConfig.loadSavedUrl();
  await AppSession.load();
  await SyncService.instance.start();
  runApp(const UnitecOsApp());
}

class UnitecOsApp extends StatelessWidget {
  const UnitecOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final initial = AppSession.isLoggedIn && AppSession.manterConectado
        ? MinhasOsScreen.route
        : LoginScreen.route;

    return MaterialApp(
      title: 'Unitec OS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: initial,
      routes: {
        LoginScreen.route: (_) => const LoginScreen(),
        MinhasOsScreen.route: (_) => const MinhasOsScreen(),
        NovaOsScreen.route: (_) => const NovaOsScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == DetalheOsScreen.route) {
          final raw = settings.arguments;
          final key = raw is String
              ? raw
              : (raw is int ? 's:$raw' : 's:${int.tryParse('$raw') ?? 0}');
          return MaterialPageRoute(
            builder: (_) => DetalheOsScreen(osKey: key),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}
