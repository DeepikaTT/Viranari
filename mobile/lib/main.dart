import 'package:flutter/material.dart';

import 'core/session.dart';
import 'core/theme.dart';
import 'screens/auth_screen.dart';
import 'screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = AppSession();
  await session.initialize();
  runApp(ViraNariApp(session: session));
}

class ViraNariApp extends StatelessWidget {
  const ViraNariApp({super.key, required this.session});
  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ViraNari',
      debugShowCheckedModeBanner: false,
      theme: buildViraTheme(),
      home: AnimatedBuilder(
        animation: session,
        builder: (context, _) {
          if (!session.initialized) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return session.isSignedIn ? MainShell(session: session) : AuthScreen(session: session);
        },
      ),
    );
  }
}
