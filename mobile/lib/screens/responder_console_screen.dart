import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../services/location_service.dart';

class ResponderConsoleScreen extends StatefulWidget {
  const ResponderConsoleScreen({super.key, required this.session});
  final AppSession session;

  @override
  State<ResponderConsoleScreen> createState() => _ResponderConsoleScreenState();
}

class _ResponderConsoleScreenState extends State<ResponderConsoleScreen> {
  final _location = LocationService();
  ResponderProfile? _profile;
  List<ResponderIncident> _incidents = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.session.api.responderMe(),
        widget.session.api.responderIncidents(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as ResponderProfile;
        _incidents = results[1] as List<ResponderIncident>;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    }
  }

  Future<void> _setAvailability(bool available) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final p = await _location.current();
      final profile = await widget.session.api.updateResponderStatus(
        latitude: p.latitude,
        longitude: p.longitude,
        isAvailable: available,
      );
      if (mounted) setState(() => _profile = profile);
      await _load();
    } on Object catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(ResponderIncident incident, String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (action) {
        case 'accept':
          await widget.session.api.responderAccept(incident.alertId);
          break;
        case 'arrive':
          await widget.session.api.responderArrive(incident.alertId);
          break;
        case 'complete':
          await widget.session.api.responderComplete(incident.alertId);
          break;
        case 'decline':
          await widget.session.api.responderDecline(incident.alertId);
          break;
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
  }

  Future<void> _openMap(ResponderIncident incident) async {
    final uri = Uri.parse('geo:${incident.latitude},${incident.longitude}?q=${incident.latitude},${incident.longitude}(ViraNari%20SOS)');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Verified responder console')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          children: [
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
            else if (_error != null)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: ViraColors.dangerSoft, borderRadius: BorderRadius.circular(20)),
                child: Text(_error!, style: const TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w700)),
              )
            else if (profile != null) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: ViraColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: ViraColors.lilacStrong)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_rounded, color: ViraColors.success),
                        const SizedBox(width: 9),
                        Expanded(child: Text(profile.organizationName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text('${profile.responderName} · ${profile.category.replaceAll('_', ' ')}', style: const TextStyle(color: ViraColors.mutedPlum)),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: profile.isAvailable,
                      onChanged: _busy ? null : _setAvailability,
                      title: const Text('Available for emergency assignments', style: TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: const Text('Updating availability also refreshes this responder’s current device location.'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Assigned incidents', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: ViraColors.plum)),
              const SizedBox(height: 8),
              if (_incidents.isEmpty)
                const Text('No incidents are currently assigned to this verified responder.', style: TextStyle(color: ViraColors.mutedPlum))
              else
                ..._incidents.map((incident) => _IncidentCard(
                      incident: incident,
                      busy: _busy,
                      onAction: (action) => _action(incident, action),
                      onMap: () => _openMap(incident),
                      onCall: incident.senderPhoneE164 == null ? null : () => _call(incident.senderPhoneE164),
                    )),
            ],
          ],
        ),
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident, required this.busy, required this.onAction, required this.onMap, this.onCall});
  final ResponderIncident incident;
  final bool busy;
  final ValueChanged<String> onAction;
  final VoidCallback onMap;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final state = incident.assignment.state;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: ViraColors.dangerSoft, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.crisis_alert_rounded, color: ViraColors.pinkDark),
              const SizedBox(width: 8),
              Expanded(child: Text('${incident.senderName} needs help', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
              Text(state.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: ViraColors.pinkDark)),
            ],
          ),
          const SizedBox(height: 7),
          Text('GPS: ${incident.latitude.toStringAsFixed(5)}, ${incident.longitude.toStringAsFixed(5)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (incident.note != null) ...[const SizedBox(height: 4), Text(incident.note!)],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(onPressed: onMap, icon: const Icon(Icons.map_outlined), label: const Text('Open map')),
              if (onCall != null) OutlinedButton.icon(onPressed: onCall, icon: const Icon(Icons.call_rounded), label: const Text('Call sender')),
            ],
          ),
          const SizedBox(height: 10),
          if (state == 'offered')
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: busy ? null : () => onAction('accept'), icon: const Icon(Icons.check_rounded), label: const Text('Accept'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: busy ? null : () => onAction('decline'), child: const Text('Decline'))),
            ])
          else if (state == 'accepted')
            FilledButton.icon(onPressed: busy ? null : () => onAction('arrive'), icon: const Icon(Icons.location_on_rounded), label: const Text('Mark arrived'))
          else if (state == 'arrived')
            FilledButton.icon(onPressed: busy ? null : () => onAction('complete'), icon: const Icon(Icons.health_and_safety_rounded), label: const Text('Complete response'))
          else
            Text(state == 'completed' ? 'Response completed.' : 'This assignment is no longer active.', style: const TextStyle(color: ViraColors.mutedPlum, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
