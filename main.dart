import 'package:cliff_messenger/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'client/db/client_db.dart';
import 'core/constants/theme.dart';
import 'core/utils/logger.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/server_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.init(level: Level.ALL);
  await ClientDb.initialize();
  runApp(const CliffMessengerApp());
}

class CliffMessengerApp extends StatelessWidget {
  const CliffMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ServerProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: MaterialApp(
        title: 'Cliff Messenger',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
