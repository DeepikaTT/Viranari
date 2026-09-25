import 'package:flutter/material.dart';

import '../core/theme.dart';

class SosButton extends StatelessWidget {
  const SosButton({super.key, required this.onPressed, required this.busy});
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Send emergency SOS',
      child: InkWell(
        customBorder: const CircleBorder(),
        onLongPress: onPressed,
        child: Container(
          width: 196,
          height: 196,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF5D8E), ViraColors.pinkDark],
            ),
            boxShadow: [
              BoxShadow(color: ViraColors.pink.withValues(alpha: 0.28), blurRadius: 32, spreadRadius: 8),
            ],
          ),
          child: Center(
            child: busy
                ? const CircularProgressIndicator(color: Colors.white)
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sos_rounded, color: Colors.white, size: 62),
                      SizedBox(height: 4),
                      Text('HOLD FOR HELP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
