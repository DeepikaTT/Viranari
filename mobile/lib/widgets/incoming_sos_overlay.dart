import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/theme.dart';

class IncomingSosOverlay extends StatefulWidget {
  const IncomingSosOverlay({
    super.key,
    required this.alert,
    required this.onAccept,
  });

  final InboxAlert alert;
  final Future<void> Function() onAccept;

  @override
  State<IncomingSosOverlay> createState() => _IncomingSosOverlayState();
}

class _IncomingSosOverlayState extends State<IncomingSosOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _hapticTimer;
  bool _accepting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
      lowerBound: 0,
      upperBound: 1,
    )..repeat(reverse: true);
    unawaited(HapticFeedback.heavyImpact());
    _hapticTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(HapticFeedback.heavyImpact()),
    );
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await widget.onAccept();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _accepting = false;
        _error = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.08 + (_pulse.value * 0.16);
        return Material(
          color: Color.lerp(ViraColors.surface, ViraColors.dangerSoft, glow),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Spacer(),
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ViraColors.pinkDark.withValues(alpha: .12 + _pulse.value * .12),
                      border: Border.all(
                        color: ViraColors.pinkDark,
                        width: 4 + (_pulse.value * 3),
                      ),
                    ),
                    child: const Icon(
                      Icons.crisis_alert_rounded,
                      size: 56,
                      color: ViraColors.pinkDark,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.alert.silentMode ? 'SILENT SOS RECEIVED' : 'SOS RECEIVED',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      color: ViraColors.pinkDark,
                      letterSpacing: .6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${widget.alert.senderName} needs your attention',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: ViraColors.plum,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.alert.silentMode
                        ? 'The sender may be unable to speak, type or visibly use the phone.'
                        : 'Accept the request to start responder location sharing and Live Track.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ViraColors.mutedPlum,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, color: ViraColors.plum),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${widget.alert.latitude.toStringAsFixed(5)}, ${widget.alert.longitude.toStringAsFixed(5)}',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                        if (widget.alert.batteryPercent != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.battery_5_bar_rounded, color: ViraColors.plum),
                              const SizedBox(width: 8),
                              Text('Victim battery ${widget.alert.batteryPercent}%'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: ViraColors.pinkDark, fontWeight: FontWeight.w800),
                    ),
                  ],
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton.icon(
                      onPressed: _accepting ? null : _accept,
                      style: FilledButton.styleFrom(backgroundColor: ViraColors.pinkDark),
                      icon: _accepting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.volunteer_activism_rounded),
                      label: Text(
                        _accepting ? 'ACCEPTING…' : 'ACCEPT & OPEN LIVE TRACK',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This alert keeps pulsing until it is acknowledged.',
                    style: TextStyle(color: ViraColors.mutedPlum, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
