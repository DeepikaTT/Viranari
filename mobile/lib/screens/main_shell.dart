import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../core/storage.dart';
import '../core/theme.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../widgets/incoming_sos_overlay.dart';
import 'contacts_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'inbox_screen.dart';
import 'live_tracking_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.session});
  final AppSession session;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  final SafetySettingsStore _safetySettings = SafetySettingsStore();
  final LocationService _location = LocationService();
  final NotificationService _notifications = NotificationService();
  int _index = 0;
  Timer? _presenceTimer;
  Timer? _incomingTimer;
  bool _presenceUpdateRunning = false;
  bool _incomingPollRunning = false;
  bool _incomingDialogOpen = false;
  String? _incomingNotificationAlertId;
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_publishPresenceIfEnabled()),
    );
    _incomingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_checkIncomingSos()),
    );
    unawaited(_notifications.requestPermission());
    unawaited(_publishPresenceIfEnabled());
    unawaited(_checkIncomingSos());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) {
      unawaited(_publishPresenceIfEnabled());
      unawaited(_checkIncomingSos());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _incomingTimer?.cancel();
    super.dispose();
  }

  Future<void> _publishPresenceIfEnabled() async {
    if (_presenceUpdateRunning || !widget.session.isSignedIn) return;
    _presenceUpdateRunning = true;
    try {
      if (!await _safetySettings.safetyPresenceEnabled()) return;
      final deviceId = await _safetySettings.installationId();
      final position = await _location.current();
      await widget.session.api.updatePresence(
        deviceId: deviceId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // Presence is intentionally best-effort and must never block SOS/location.
    } finally {
      _presenceUpdateRunning = false;
    }
  }

  Future<void> _checkIncomingSos() async {
    if (_incomingPollRunning || _incomingDialogOpen || !widget.session.isSignedIn) return;
    _incomingPollRunning = true;
    try {
      final items = await widget.session.api.inbox();
      InboxAlert? candidate;
      for (final item in items) {
        if (item.isActive && item.acknowledgedAt == null) {
          candidate = item;
          break;
        }
      }
      if (candidate == null) {
        final previous = _incomingNotificationAlertId;
        if (previous != null) {
          await _notifications.cancelIncomingSos(previous);
          _incomingNotificationAlertId = null;
        }
        return;
      }
      if (_incomingNotificationAlertId != candidate.alertId) {
        await _notifications.showIncomingSos(candidate);
        _incomingNotificationAlertId = candidate.alertId;
      }
      if (!mounted || _incomingDialogOpen || !_isForeground) return;
      await _showIncomingSos(candidate);
    } catch (_) {
      // Incoming SOS polling is best effort; Inbox remains available manually.
    } finally {
      _incomingPollRunning = false;
    }
  }

  Future<void> _showIncomingSos(InboxAlert alert) async {
    if (_incomingDialogOpen || !mounted) return;
    _incomingDialogOpen = true;
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => IncomingSosOverlay(
          alert: alert,
          onAccept: () async {
            await widget.session.api.acknowledge(alert.alertId);
            await _notifications.cancelIncomingSos(alert.alertId);
            _incomingNotificationAlertId = null;
            if (!mounted) return;
            Navigator.of(context, rootNavigator: true).pop();
            setState(() => _index = 2);
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LiveTrackingScreen(session: widget.session, initial: alert),
              ),
            );
          },
        ),
      );
    } finally {
      _incomingDialogOpen = false;
    }
  }

  Future<void> _triggerSilentSos() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 110));
    await HapticFeedback.lightImpact();
    widget.session.requestSilentSos();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(session: widget.session),
      ContactsScreen(session: widget.session),
      InboxScreen(session: widget.session),
      HistoryScreen(session: widget.session),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Hold for Silent Safety Session',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: _triggerSilentSos,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.shield_rounded, color: ViraColors.plum),
                ),
              ),
            ),
            const SizedBox(width: 7),
            const Text(
              'ViraNari',
              style: TextStyle(fontWeight: FontWeight.w900, color: ViraColors.plum),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') widget.session.logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(widget.session.user?.email ?? '')),
              const PopupMenuItem(
                enabled: false,
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined),
                    SizedBox(width: 8),
                    Expanded(child: Text('Hold the shield logo for Silent SOS')),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [Icon(Icons.logout), SizedBox(width: 8), Text('Sign out')]),
              ),
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
          NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Circle'),
          NavigationDestination(icon: Icon(Icons.notifications_none), selectedIcon: Icon(Icons.notifications), label: 'Inbox'),
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history_rounded), label: 'History'),
        ],
      ),
    );
  }
}
