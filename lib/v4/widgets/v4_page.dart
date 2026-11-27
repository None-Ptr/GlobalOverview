// Hallmark · component: pushed page shell · genre: editorial · theme: project (V4 tokens) · viewport: wide
// critique: P5 H5 E5 S4 R4 V4 · weakest S — the title row is unchanged; only the body learns to stop growing
import 'package:flutter/material.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';

/// Centres a column of content and stops it growing with the window. Gutters
/// grow, the measure does not.
class V4Column extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const V4Column({
    super.key,
    this.maxWidth = V4Layout.page,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Pushed page: back arrow, page title, trailing actions, optional bottom bar.
class V4Page extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final Widget body;
  final Widget? bottomBar;

  const V4Page({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.bottomBar,
  });

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Scaffold(
      backgroundColor: v4.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V4Space.sm,
                V4Space.sm,
                V4Space.md,
                V4Space.xs,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.pageTitle,
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
            Expanded(child: V4Column(child: body)),
          ],
        ),
      ),
      bottomNavigationBar: bottomBar == null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  V4Space.lg,
                  V4Space.md,
                  V4Space.lg,
                  V4Space.md,
                ),
                decoration: BoxDecoration(
                  color: v4.surface,
                  border: Border(top: BorderSide(color: v4.rule)),
                ),
                // V4Column's Center expands under loose constraints; the
                // bottom-nav slot is loose and would eat the whole body. Align
                // with heightFactor 1 keeps the bar at its intrinsic height.
                child: Align(
                  alignment: Alignment.center,
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: V4Layout.page),
                    child: SizedBox(width: double.infinity, child: bottomBar!),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Section label above a bordered card that holds tiles separated by rules.
class V4Section extends StatelessWidget {
  final String? title;
  final String? hint;
  final List<Widget> children;

  const V4Section({
    super.key,
    this.title,
    this.hint,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, color: v4.rule));
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(
              left: V4Space.xs,
              bottom: V4Space.sm,
            ),
            child: Text(title!, style: type.sectionTitle),
          ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(
              left: V4Space.xs,
              bottom: V4Space.sm,
            ),
            child: Text(hint!, style: type.caption),
          ),
        Container(
          decoration: BoxDecoration(
            color: v4.surface,
            borderRadius: BorderRadius.circular(V4Radius.card),
            border: Border.all(color: v4.rule),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ],
    );
  }
}

/// One row inside a [V4Section]: title, optional detail, optional trailing.
class V4Tile extends StatelessWidget {
  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  const V4Tile({
    super.key,
    required this.title,
    this.detail,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final titleStyle = type.itemTitle.copyWith(
      color: danger ? v4.error : v4.ink,
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: V4Space.lg,
        vertical: V4Space.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle),
                if (detail != null) ...[
                  const SizedBox(height: V4Space.xs),
                  Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: V4Space.md),
            trailing!,
          ] else if (onTap != null)
            Icon(Icons.chevron_right, size: 20, color: v4.inkMuted),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

/// Selectable chip that sizes to its label, safe to put in a [Wrap].
class V4Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const V4Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V4Radius.control),
      child: Container(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: V4Space.md),
        decoration: BoxDecoration(
          color: selected ? v4.surfaceSubtle : v4.surface,
          borderRadius: BorderRadius.circular(V4Radius.control),
          border: Border.all(color: selected ? v4.brand : v4.rule),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.v4Type.label.copyWith(
                color: selected ? v4.ink : v4.inkSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty or failed state: a short title, one line of guidance, optional action.
class V4Notice extends StatelessWidget {
  final String title;
  final String message;
  final Widget? action;

  const V4Notice({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final type = context.v4Type;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: V4Space.xl,
        vertical: V4Space.huge,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title, textAlign: TextAlign.center, style: type.sectionTitle),
          const SizedBox(height: V4Space.sm),
          Text(message, textAlign: TextAlign.center, style: type.caption),
          if (action != null) ...[
            const SizedBox(height: V4Space.xl),
            action!,
          ],
        ],
      ),
    );
  }
}
