import 'package:flutter/material.dart';

class ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool destructive;
  final VoidCallback? onTap;

  const ProfileMenuTile({super.key, 
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  }) : destructive = false;

  static const Color primaryGreen = Color(0xFF2E6B3E);

  @override
  Widget build(BuildContext context) {
    final Color color = destructive ? Colors.redAccent : Colors.black87;
    final Color iconBg = destructive
        ? Colors.redAccent.withValues(alpha: 0.08)
        : primaryGreen.withValues(alpha: 0.08);
    final Color iconColor = destructive ? Colors.redAccent : primaryGreen;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF0F0F0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
