import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unitec_os_app/config/api_config.dart';
import 'package:unitec_os_app/config/app_version.dart';
import 'package:unitec_os_app/config/device_identity.dart';
import 'package:unitec_os_app/screens/detalhe_os_screen.dart';
import 'package:unitec_os_app/screens/login_screen.dart';
import 'package:unitec_os_app/screens/minhas_os_screen.dart';
import 'package:unitec_os_app/screens/nova_os_screen.dart';
import 'package:unitec_os_app/services/sync_service.dart';
import 'package:unitec_os_app/session/app_session.dart';
import 'package:unitec_os_app/theme/app_theme.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Oculta a barra preta de navegação do Android em todas as telas.
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // Mantém a tela ligada enquanto o app estiver aberto (igual Força de Vendas).
  await WakelockPlus.enable();

  await DeviceIdentity.ensureReady();
  await ApiConfig.loadSavedUrl();
  await AppSession.load();
  await AppVersion.load();
  await SyncService.instance.start();
  runApp(const UnitecOsApp());
}

class UnitecOsApp extends StatefulWidget {
  const UnitecOsApp({super.key});

  @override
  State<UnitecOsApp> createState() => _UnitecOsAppState();
}

class _UnitecOsAppState extends State<UnitecOsApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
    }
  }

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
