import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/theme.dart';
import 'contacts_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'inbox_screen.dart';
import 'live_map_hub_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.session});
  final AppSession session;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(session: widget.session),
      LiveMapHubScreen(session: widget.session),
      ContactsScreen(session: widget.session),
      InboxScreen(session: widget.session),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_rounded, color: ViraColors.plum),
            SizedBox(width: 7),
            Text('ViraNari', style: TextStyle(fontWeight: FontWeight.w900, color: ViraColors.plum)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'history') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryScreen(session: widget.session)));
              } else if (value == 'logout') {
                widget.session.logout();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(widget.session.user?.email ?? '')),
              const PopupMenuItem(value: 'history', child: Row(children: [Icon(Icons.history), SizedBox(width: 8), Text('SOS history')])),
              const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout), SizedBox(width: 8), Text('Sign out')])),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        indicatorColor: ViraColors.lilacStrong,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Circle'),
          NavigationDestination(icon: Icon(Icons.notifications_none), selectedIcon: Icon(Icons.notifications), label: 'Response'),
        ],
      ),
    );
  }
}
