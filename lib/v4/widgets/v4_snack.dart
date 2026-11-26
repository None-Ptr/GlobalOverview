// Hallmark · component: snackbar · genre: editorial · theme: project (V4 tokens) · states: plain, success, warning, error, action, long copy
import 'package:flutter/material.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';

enum V4SnackTone { plain, success, warning, error }

/// One bar for every transient message: surface card, hairline rule, tone icon.
void showV4Snack(
  BuildContext context,
  String message, {
  V4SnackTone tone = V4SnackTone.plain,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.of(context);
  final v4 = context.v4;
  final type = context.v4Type;
  final IconData icon;
  final Color tint;
  switch (tone) {
    case V4SnackTone.success:
      icon = Icons.check_circle_outline;
      tint = v4.success;
    case V4SnackTone.warning:
      icon = Icons.error_outline;
      tint = v4.warning;
    case V4SnackTone.error:
      icon = Icons.error_outline;
      tint = v4.error;
    case V4SnackTone.plain:
      icon = Icons.info_outline;
      tint = v4.inkMuted;
  }
  final hasAction = actionLabel != null && onAction != null;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(
        V4Space.lg,
        0,
        V4Space.lg,
        V4Space.lg,
      ),
      duration: duration,
      content: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: EdgeInsets.fromLTRB(
          V4Space.lg,
          V4Space.md,
          hasAction ? V4Space.xs : V4Space.lg,
          V4Space.md,
        ),
        decoration: BoxDecoration(
          color: v4.surface,
          borderRadius: BorderRadius.circular(V4Radius.card),
          border: Border.all(color: v4.rule),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: tint),
            const SizedBox(width: V4Space.md),
            Expanded(
              child: Text(
                message,
                style: type.label.copyWith(color: v4.ink, height: 1.4),
              ),
            ),
            if (hasAction)
              _SnackAction(
                label: actionLabel,
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  onAction();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _SnackAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SnackAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V4Radius.control),
      child: Container(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: V4Space.md),
        child: Text(
          label,
          style: context.v4Type.label.copyWith(
            color: v4.brand,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
