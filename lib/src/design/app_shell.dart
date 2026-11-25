import 'dart:ui' show ImageFilter;

// Flutter 3.50 deprecates the library in favour of package:material_ui;
// see docs/PLAN.md for the migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:uikit_tab_bar/uikit_tab_bar.dart';

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
    this.iosSymbol,
  });

  final AppTab tab;
  final String label;
  final IconData icon;

  /// The SF Symbol the system tab bar shows on iOS; [icon] when null.
  final String? iosSymbol;
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
///
/// On iOS 26 and later the tabs are the system's own `UITabBarController`
/// (via `uikit_tab_bar`), because only a system tab bar is moved by iOS into
/// iPhone Duo's vertical strip beside the status bar; where that does not
/// apply the shell draws its own bar (docs/JOURNAL.md, 2026-11-25).
///
/// Elsewhere on iOS and on Android a window at least [sideNavigationMinWidth] wide — an
/// open iPhone Duo, an iPhone in landscape, an Android tablet or foldable —
/// gets the tabs as a column on the leading side and the content as a centred
/// column at most [wideContentMaxWidth] wide, instead of a phone layout
/// stretched across the screen. The decision follows the window's width only:
/// on iOS, Flutter reports no fold, and the device's orientation says nothing
/// about the window's shape (docs/JOURNAL.md, 2026-11-25).
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

  /// The narrowest window that gets the side navigation: Material's
  /// compact/medium boundary. A closed iPhone Duo (466 pt) and an app beside
  /// another in Split View (469 pt) stay below it; an open one (669 pt and
  /// wider) is above.
  static const double sideNavigationMinWidth = 600;

  /// The widest the content column grows next to the side navigation.
  static const double wideContentMaxWidth = 640;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (style.isIos && UIKitTabBar.isNativeSupported) {
          return _buildSystemTabBar(
            body,
            wide: constraints.maxWidth >= sideNavigationMinWidth,
          );
        }
        if (!style.isDesktop &&
            constraints.maxWidth >= sideNavigationMinWidth) {
          return _buildWide(style, body);
        }
        return _buildNarrow(style, body);
      },
    );
  }

  /// The system tab bar decides its own place: along the bottom, or on iPhone
  /// Duo a column under the status bar. Its insets reach the content as
  /// `MediaQuery` padding, which the [SafeArea] keeps clear. It never
  /// minimizes on scroll: a pan on a sheet over the content would count too.
  Widget _buildSystemTabBar(Widget body, {required bool wide}) {
    return UIKitTabScaffold(
      tabBar: UIKitTabBar(
        tabs: <UIKitTab>[
          for (final item in tabs)
            UIKitTab(
              id: item.tab.name,
              label: item.label,
              icon: switch (item.iosSymbol) {
                final String symbol => UIKitTabIcon.symbol(symbol),
                null => UIKitTabIcon.icon(item.icon),
              },
            ),
        ],
        selectedId: currentTab.name,
        onSelected: (id) => onTabSelected(AppTab.values.byName(id)),
        minimizeBehavior: UIKitTabBarMinimizeBehavior.never,
        style: const UIKitTabBarStyle(tintColor: NocturneColors.accent),
      ),
      body: Scaffold(
        backgroundColor: NocturneColors.bg,
        body: SafeArea(
          top: false,
          child: wide
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: wideContentMaxWidth,
                    ),
                    child: body,
                  ),
                )
              : body,
        ),
      ),
    );
  }

  /// Tabs on the leading side, content centred. Every inset is honoured edge by
  /// edge: iPhone Duo puts the status bar and camera on a side, not the top.
  Widget _buildWide(PlatformStyle style, Widget body) {
    return Scaffold(
      backgroundColor: NocturneColors.bg,
      body: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ShellSideBar(
              tabs: tabs,
              currentTab: currentTab,
              onTabSelected: onTabSelected,
              style: style,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: wideContentMaxWidth,
                  ),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrow(PlatformStyle style, Widget body) {
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

/// The tabs as a column on the leading side of a wide window, with the same
/// buttons as the bottom bar: the iOS set over the background, the Android set
/// on the surface with the active pill.
class _ShellSideBar extends StatelessWidget {
  const _ShellSideBar({
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
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: style.isIos ? NocturneColors.bg : NocturneColors.surface,
        border: const BorderDirectional(
          end: BorderSide(color: NocturneColors.divider, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: NocturneSpacing.x4),
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (final item in tabs)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: NocturneSpacing.x2,
                ),
                child: _ShellTabButton(
                  item: item,
                  selected: item.tab == currentTab,
                  onTap: () => onTabSelected(item.tab),
                  style: style,
                ),
              ),
          ],
        ),
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
              // Shrinks to fit instead of cutting the word short at large
              // Dynamic Type; the system tab bar does the same on iOS 26+.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: NocturneType.family,
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: NocturneType.medium,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
