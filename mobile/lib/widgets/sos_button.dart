import 'package:flutter/material.dart';

import '../core/theme.dart';

class SosButton extends StatelessWidget {
  const SosButton({super.key, required this.onPressed, required this.busy, this.label});
  final VoidCallback? onPressed;
  final bool busy;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Send emergency SOS',
      hint: enabled ? 'Press and hold to activate emergency response' : 'Emergency response is already active',
      child: InkWell(
        customBorder: const CircleBorder(),
        onLongPress: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 196,
          height: 196,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: enabled ? const [Color(0xFFEC658C), ViraColors.pinkDark] : const [Color(0xFFB8B8B8), Color(0xFF8C8C8C)],
            ),
            boxShadow: enabled
                ? [BoxShadow(color: ViraColors.pink.withValues(alpha: 0.28), blurRadius: 32, spreadRadius: 8)]
                : const [],
          ),
          child: Center(
            child: busy
                ? const CircularProgressIndicator(color: Colors.white)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sos_rounded, color: Colors.white, size: 62),
                      const SizedBox(height: 4),
                      Text(enabled ? (label ?? 'HOLD FOR HELP') : 'SOS ACTIVE', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
