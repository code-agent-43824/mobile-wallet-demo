import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'nocturne.dart';
import 'platform_style.dart';

/// The four destinations of the redesigned app.
///
/// The redesign replaces the prototype's single scrolling screen with standard
/// crypto-wallet tab navigation, so balance, history, connections and settings
/// each get their own surface instead of stacking into one column.
enum AppTab { wallet, activity, connections, settings }

/// A tab's presentation data, resolved by the caller so this file stays free of
/// localization lookups.
@immutable
class AppTabItem {
  const AppTabItem({
    required this.tab,
    required this.label,
    required this.icon,
  });

  final AppTab tab;
  final String label;
  final IconData icon;
}

/// The redesigned app shell: a platform-appropriate header, the tab body, and
/// the bottom navigation.
///
/// The two platform pattern sets are kept fully separate, per the design
/// package and the owner's decision:
/// * **iOS** — a 44pt navigation bar and a translucent, blurred tab bar with a
///   hairline top divider; the selected item is tinted with the accent itself.
/// * **Android** — a 56dp top app bar and an opaque navigation bar whose
///   selected item sits on a filled accent pill.
///
/// Windows reuses the Android pattern set but constrains the content width so
/// the mobile layout stays legible in a wide window.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.tabs,
    required this.currentTab,
    required this.onTabSelected,
    required this.child,
    this.actions = const <Widget>[],
    this.banner,
  });

  /// Header title for the current tab.
  final String title;

  final List<AppTabItem> tabs;
  final AppTab currentTab;
  final ValueChanged<AppTab> onTabSelected;

  /// Body of the selected tab.
  final Widget child;

  /// Trailing header actions (e.g. the network switch).
  final List<Widget> actions;

  /// Optional full-width banner pinned under the header — the offline-cache
  /// notice and error messages use this slot.
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final style = PlatformStyle.of(context);
    final body = Column(
      children: [
        _ShellHeader(title: title, actions: actions, style: style),
        if (banner case final Widget shellBanner) shellBanner,
        Expanded(child: child),
      ],
    );

    return Scaffold(
      backgroundColor: NocturneColors.bg,
      body: SafeArea(
        top: false,
        bottom: false,
        child: style.maxContentWidth.isFinite
            ? Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: style.maxContentWidth),
                  child: body,
                ),
              )
            : body,
      ),
      bottomNavigationBar: _ShellTabBar(
        tabs: tabs,
        currentTab: currentTab,
        onTabSelected: onTabSelected,
        style: style,
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.title,
    required this.actions,
    required this.style,
  });

  final String title;
  final List<Widget> actions;
  final PlatformStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // iOS uses a large left-aligned title below a compact bar; Android uses the
    // Material top app bar's inline title.
    final titleStyle = style.isIos
        ? theme.textTheme.headlineMedium
        : theme.textTheme.titleLarge;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        NocturneSpacing.gutter,
        style.isIos ? NocturneSpacing.x6 : NocturneSpacing.x4,
        NocturneSpacing.gutter,
        style.isIos ? NocturneSpacing.x3 : NocturneSpacing.x4,
      ),
      child: SizedBox(
        height: style.headerHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                style: titleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _ShellTabBar extends StatelessWidget {
  const _ShellTabBar({
    required this.tabs,
    required this.currentTab,
    required this.onTabSelected,
    required this.style,
  });

  final List<AppTabItem> tabs;
  final AppTab currentTab;
  final ValueChanged<AppTab> onTabSelected;
  final PlatformStyle style;

  @override
  Widget build(BuildContext context) {
    final viewportBottom = MediaQuery.viewPaddingOf(context).bottom;
    final bottomInset = viewportBottom > 0
        ? viewportBottom
        : style.fallbackBottomInset;

    final bar = Container(
      decoration: BoxDecoration(
        // iOS: a translucent bar over the content with a hairline rule.
        // Android: an opaque surface, per Material's navigation bar.
        color: style.isIos
            ? NocturneColors.bg.withValues(alpha: 0.82)
            : NocturneColors.surface,
        border: const Border(
          top: BorderSide(color: NocturneColors.divider, width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        top: style.isIos ? NocturneSpacing.x2 : NocturneSpacing.x3,
        bottom: bottomInset + NocturneSpacing.x2,
      ),
      child: Row(
        children: [
          for (final item in tabs)
            Expanded(
              child: _ShellTabButton(
                item: item,
                selected: item.tab == currentTab,
                onTap: () => onTabSelected(item.tab),
                style: style,
              ),
            ),
        ],
      ),
    );

    if (!style.isIos) {
      return bar;
    }
    // The iOS tab bar is translucent, so blur whatever scrolls under it.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: bar,
      ),
    );
  }
}

class _ShellTabButton extends StatelessWidget {
  const _ShellTabButton({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.style,
  });

  final AppTabItem item;
  final bool selected;
  final VoidCallback onTap;
  final PlatformStyle style;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? style.activeTabColor
        : NocturneColors.textSubtle;
    final pill = selected ? style.activeTabPill : null;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: NocturneRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NocturneSpacing.x1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Android draws the selected icon on a filled pill; iOS does not.
              Container(
                padding: pill == null
                    ? const EdgeInsets.symmetric(vertical: 2)
                    : const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
                decoration: pill == null
                    ? null
                    : BoxDecoration(
                        color: pill,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(999),
                        ),
                      ),
                child: Icon(item.icon, size: 22, color: foreground),
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: NocturneType.family,
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: NocturneType.medium,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
