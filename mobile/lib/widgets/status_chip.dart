import 'package:flutter/material.dart';

import '../core/theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.icon, this.good = false});
  final String label;
  final IconData icon;
  final bool good;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: good ? ViraColors.successSoft : ViraColors.lilac,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: good ? ViraColors.success : ViraColors.plum),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: good ? ViraColors.success : ViraColors.plum)),
        ],
      ),
    );
  }
}
