import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';

class SafeReachSheet extends StatefulWidget {
  const SafeReachSheet({
    super.key,
    required this.session,
    required this.alertId,
    this.canRematch = false,
  });

  final AppSession session;
  final String alertId;
  final bool canRematch;

  @override
  State<SafeReachSheet> createState() => _SafeReachSheetState();
}

class _SafeReachSheetState extends State<SafeReachSheet> {
  AlertRecord? _alert;
  ProofVerification? _verification;
  ProofChain? _proof;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.session.api.getAlert(widget.alertId),
        widget.session.api.verifyProof(widget.alertId),
        widget.session.api.proofChain(widget.alertId),
      ]);
      if (!mounted) return;
      setState(() {
        _alert = results[0] as AlertRecord;
        _verification = results[1] as ProofVerification;
        _proof = results[2] as ProofChain;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final opened = await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the phone app.')));
    }
  }

  Future<void> _rematch() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.session.api.rematchSafeReach(widget.alertId);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _eventLabel(String raw) => raw
      .replaceAll('SAFE_REACH_', '')
      .replaceAll('_', ' ')
      .toLowerCase()
      .split(' ')
      .where((e) => e.isNotEmpty)
      .map((e) => '${e[0].toUpperCase()}${e.substring(1)}')
      .join(' ');

  Color _stateColor(String state) {
    switch (state) {
      case 'accepted':
      case 'arrived':
      case 'completed':
        return ViraColors.success;
      case 'offered':
        return ViraColors.gold;
      default:
        return ViraColors.mutedPlum;
    }
  }

  @override
  Widget build(BuildContext context) {
    final alert = _alert;
    final assignment = alert?.safeReach;
    final verification = _verification;
    final proof = _proof;
    final recentEvents = proof == null ? const <ProofEvent>[] : proof.events.reversed.take(12).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .86,
      minChildSize: .55,
      maxChildSize: .97,
      builder: (context, controller) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('SafeReach', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: ViraColors.plum)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: ViraColors.successSoft, borderRadius: BorderRadius.circular(99)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user_rounded, size: 15, color: ViraColors.success),
                      SizedBox(width: 5),
                      Text('VERIFIED HELP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: ViraColors.success)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              'Nearest verified responder routing with a cryptographically verifiable incident record.',
              style: TextStyle(color: ViraColors.mutedPlum, height: 1.35),
            ),
            const SizedBox(height: 18),
            if (_loading && alert == null)
              const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()))
            else if (_error != null)
              _MessageCard(icon: Icons.cloud_off_outlined, title: 'SafeReach unavailable', body: _error!)
            else if (assignment == null)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: ViraColors.lilac, borderRadius: BorderRadius.circular(22)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.search_rounded, color: ViraColors.plum),
                        SizedBox(width: 9),
                        Expanded(child: Text('No verified responder matched yet', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                      ],
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Trusted Circle and live location remain active. SafeReach only routes to responders that are verified, available, recently online and within their service radius.',
                      style: TextStyle(color: ViraColors.mutedPlum, height: 1.4),
                    ),
                    if (widget.canRematch && alert?.isActive == true) ...[
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _rematch,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Search again'),
                      ),
                    ],
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: assignment.state == 'arrived' ? ViraColors.successSoft : ViraColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: assignment.state == 'arrived' ? ViraColors.success : ViraColors.lilacStrong),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_rounded, color: ViraColors.success),
                        const SizedBox(width: 9),
                        Expanded(child: Text(assignment.organizationName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(color: _stateColor(assignment.state), borderRadius: BorderRadius.circular(99)),
                          child: Text(assignment.statusLabel, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('${assignment.responderName} · ${assignment.category.replaceAll('_', ' ')}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text('Matched about ${assignment.distanceM < 1000 ? '${assignment.distanceM.toStringAsFixed(0)} m' : '${(assignment.distanceM / 1000).toStringAsFixed(1)} km'} away', style: const TextStyle(color: ViraColors.mutedPlum)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (assignment.phoneE164 != null)
                          FilledButton.tonalIcon(
                            onPressed: () => _call(assignment.phoneE164),
                            icon: const Icon(Icons.call_rounded),
                            label: const Text('Call responder'),
                          ),
                        if (widget.canRematch && alert?.isActive == true && assignment.state == 'offered')
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _rematch,
                            icon: const Icon(Icons.swap_horiz_rounded),
                            label: const Text('Try another'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: verification?.valid == true ? ViraColors.successSoft : ViraColors.dangerSoft,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: verification?.valid == true ? ViraColors.success : ViraColors.pinkDark.withValues(alpha: .35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(verification?.valid == true ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded, color: verification?.valid == true ? ViraColors.success : ViraColors.pinkDark),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          verification?.valid == true ? 'ProofChain integrity verified' : 'ProofChain verification needs attention',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    verification == null
                        ? 'Checking signed incident events…'
                        : '${verification.eventCount} signed event${verification.eventCount == 1 ? '' : 's'} · SHA-256 chain ${verification.hashChainValid ? 'valid' : 'invalid'} · Ed25519 signatures ${verification.signaturesValid ? 'valid' : 'invalid'}',
                    style: const TextStyle(color: ViraColors.mutedPlum, height: 1.35),
                  ),
                  if (verification != null) ...[
                    const SizedBox(height: 5),
                    SelectableText('Key ID: ${verification.keyId}', style: const TextStyle(fontSize: 11, color: ViraColors.mutedPlum)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text('Incident actions', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: ViraColors.plum)),
            const SizedBox(height: 8),
            if (recentEvents.isEmpty)
              const Text('No signed actions yet.', style: TextStyle(color: ViraColors.mutedPlum))
            else
              ...recentEvents.map(
                (event) => _ProofEventTile(
                  title: _eventLabel(event.eventType),
                  time: DateFormat('h:mm:ss a').format(event.createdAt.toLocal()),
                  hash: event.eventHash,
                  actor: event.actorType.replaceAll('_', ' '),
                ),
              ),
            if (proof != null && proof.events.length > recentEvents.length)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${proof.events.length - recentEvents.length} earlier signed events retained on the server.', style: const TextStyle(color: ViraColors.mutedPlum, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProofEventTile extends StatelessWidget {
  const _ProofEventTile({required this.title, required this.time, required this.hash, required this.actor});
  final String title;
  final String time;
  final String hash;
  final String actor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: ViraColors.lilac),
              child: const Icon(Icons.link_rounded, size: 16, color: ViraColors.plum),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('$time · $actor', style: const TextStyle(fontSize: 11, color: ViraColors.mutedPlum)),
                  SelectableText('${hash.substring(0, 16)}…', style: const TextStyle(fontSize: 10, color: ViraColors.mutedPlum)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: ViraColors.lilac, borderRadius: BorderRadius.circular(22)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: ViraColors.plum),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(body, style: const TextStyle(color: ViraColors.mutedPlum, height: 1.35))])),
          ],
        ),
      );
}
