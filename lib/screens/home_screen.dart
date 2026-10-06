import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/content_type.dart';
import '../providers/profile_provider.dart';
import '../services/profile_service.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/tv_catalog_navigation.dart';
import '../widgets/catalog_status_indicator.dart';
import '../widgets/catalog_section_status.dart';
import 'catalog_page.dart';
import 'discover_page.dart';
import 'favorites_page.dart';
import 'live_page.dart';
import 'profile_picker_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  // Tabs are built only once visited, so opening Home does not build every
  // catalog at the same time.
  final Set<int> _visited = {0};

  static const _pages = [
    DiscoverPage(),
    CatalogSectionFrame(type: ContentType.live, child: LivePage()),
    CatalogSectionFrame(
      type: ContentType.movie,
      child: CatalogPage(type: ContentType.movie),
    ),
    CatalogSectionFrame(
      type: ContentType.series,
      child: CatalogPage(type: ContentType.series),
    ),
    FavoritesPage(),
  ];

  void _push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    if (DeviceTypeService.isTv) return _buildTv(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 20,
        title: const BrandLogo(size: 28),
        actions: [
          IconButton(
            tooltip: 'Cerca',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => _push(const SearchScreen()),
          ),
          IconButton(
            tooltip: 'Preferiti',
            icon: Icon(Icons.favorite_rounded, color: AppColors.primary),
            onPressed: () => _push(const FavoritesPage()),
          ),
          const _ProfileButton(),
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _push(const SettingsScreen()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (var i = 0; i < _pages.length; i++)
            _visited.contains(i) ? _pages[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() {
            _currentIndex = i;
            _visited.add(i);
          }),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: CatalogNavigationIcon(
                icon: Icons.live_tv_outlined,
                type: ContentType.live,
              ),
              selectedIcon: CatalogNavigationIcon(
                icon: Icons.live_tv_rounded,
                type: ContentType.live,
              ),
              label: 'Diretta',
            ),
            NavigationDestination(
              icon: CatalogNavigationIcon(
                icon: Icons.movie_outlined,
                type: ContentType.movie,
              ),
              selectedIcon: CatalogNavigationIcon(
                icon: Icons.movie_rounded,
                type: ContentType.movie,
              ),
              label: 'Film',
            ),
            NavigationDestination(
              icon: CatalogNavigationIcon(
                icon: Icons.video_library_outlined,
                type: ContentType.series,
              ),
              selectedIcon: CatalogNavigationIcon(
                icon: Icons.video_library_rounded,
                type: ContentType.series,
              ),
              label: 'Serie TV',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_border_rounded),
              selectedIcon: Icon(Icons.favorite_rounded),
              label: 'Preferiti',
            ),
          ],
        ),
      ),
    );
  }

  final FocusScopeNode _tvNavScope = FocusScopeNode(debugLabel: 'tvNav');
  final FocusScopeNode _tvContentScope = FocusScopeNode(
    debugLabel: 'tvContent',
  );
  // One node per tab pill, so the white focus oval always follows the tab that
  // is actually selected (e.g. after Back returns to Home).
  final List<FocusNode> _tabNodes = List.generate(
    _pages.length,
    (i) => FocusNode(debugLabel: 'tvTab$i'),
  );

  @override
  void dispose() {
    _tvNavScope.dispose();
    _tvContentScope.dispose();
    for (final n in _tabNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _selectTab(int i) => setState(() {
    _currentIndex = i;
    _visited.add(i);
  });

  void _focusNav() => _tabNodes[_currentIndex].requestFocus();

  /// Moves focus from the top menu to the first item of the visible tab.
  void _focusContent() {
    if (_currentIndex >= 1 && _currentIndex <= 3) {
      final searches = _tvContentScope.traversalDescendants.where(
        (n) => n.debugLabel == 'catalogSearch' && n.canRequestFocus,
      );
      if (searches.isNotEmpty) {
        searches.first.requestFocus();
        return;
      }
    }
    _tvContentScope.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final primary = FocusManager.instance.primaryFocus;
      final inside =
          primary != null &&
          primary != _tvContentScope &&
          primary.ancestors.contains(_tvContentScope);
      if (!inside) _tvContentScope.nextFocus();
    });
  }

  static bool _isKeyPress(KeyEvent e) =>
      e is KeyDownEvent || e is KeyRepeatEvent;

  // Arrow Down on the top menu always enters the content of the current tab.
  KeyEventResult _onNavKey(FocusNode node, KeyEvent event) {
    if (!_isKeyPress(event)) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _focusContent();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Arrow Up inside the content moves up normally; at the top row it returns
  // to the menu instead of getting stuck.
  KeyEventResult _onContentKey(FocusNode node, KeyEvent event) {
    if (!_isKeyPress(event)) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (_currentIndex >= 1 && _currentIndex <= 3) {
      return KeyEventResult.ignored;
    }
    if (primary != null &&
        primary != _tvContentScope &&
        primary.focusInDirection(TraversalDirection.up)) {
      return KeyEventResult.handled;
    }
    _focusNav();
    return KeyEventResult.handled;
  }

  // Back on TV: content -> top menu -> Home tab -> app to background (it keeps
  // running, like other TV apps, instead of closing).
  void _onTvBack() {
    if (!_tvNavScope.hasFocus) {
      _focusNav();
      return;
    }
    if (_currentIndex != 0) {
      _selectTab(0);
      _tabNodes[0].requestFocus();
      return;
    }
    DeviceTypeService.moveToBackground();
  }

  Widget _buildTv(BuildContext context) {
    final content = IndexedStack(
      index: _currentIndex,
      children: [
        for (var i = 0; i < _pages.length; i++)
          // Hidden tabs must never receive D-Pad focus.
          ExcludeFocus(
            excluding: i != _currentIndex,
            child: _visited.contains(i) ? _pages[i] : const SizedBox.shrink(),
          ),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onTvBack();
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Home draws its hero under the menu; other tabs start below it.
            Positioned.fill(
              top: _currentIndex == 0 ? 0 : _TvTopBar.height,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onContentKey,
                child: TvCatalogMenu(
                  onMenu: _focusNav,
                  child: FocusScope(node: _tvContentScope, child: content),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onNavKey,
                child: FocusScope(
                  node: _tvNavScope,
                  autofocus: true,
                  child: _TvTopBar(
                    selectedIndex: _currentIndex,
                    tabNodes: _tabNodes,
                    onSelected: _selectTab,
                    onSearch: () => _push(const SearchScreen()),
                    onProfile: () => _push(const ProfilePickerScreen()),
                    onSettings: () => _push(const SettingsScreen()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvTopBar extends StatelessWidget {
  static const double height = 60;

  final int selectedIndex;
  final List<FocusNode> tabNodes;
  final ValueChanged<int> onSelected;
  final VoidCallback onSearch;
  final VoidCallback onProfile;
  final VoidCallback onSettings;

  const _TvTopBar({
    required this.selectedIndex,
    required this.tabNodes,
    required this.onSelected,
    required this.onSearch,
    required this.onProfile,
    required this.onSettings,
  });

  static const _tabs = ['Home', 'Diretta', 'Film', 'Serie TV'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // On narrow TV windows the full-size pills overflow and clip the
        // settings icon at the right edge; switch to a compact layout.
        final compact = constraints.maxWidth < 1150;
        return _buildBar(context, compact);
      },
    );
  }

  Widget _buildBar(BuildContext context, bool compact) {
    final name = context.watch<ProfileProvider>().selected?.name.trim() ?? '';
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 40),
      // Solid enough to stay readable over bright artwork.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withValues(alpha: 0.97),
            AppColors.background.withValues(alpha: 0.85),
            AppColors.background.withValues(alpha: 0),
          ],
          stops: const [0, 0.7, 1],
        ),
      ),
      child: Row(
        children: [
          BrandLogo(size: compact ? 20 : 26),
          SizedBox(width: compact ? 16 : 32),
          _TvNavPill(
            label: 'Cerca',
            icon: Icons.search_rounded,
            compact: compact,
            onPressed: onSearch,
          ),
          for (var i = 0; i < _tabs.length; i++)
            _TvNavPill(
              label: _tabs[i],
              contentType: switch (i) {
                1 => ContentType.live,
                2 => ContentType.movie,
                3 => ContentType.series,
                _ => null,
              },
              focusNode: tabNodes[i],
              selected: selectedIndex == i,
              autofocus: i == selectedIndex,
              compact: compact,
              onPressed: () => onSelected(i),
            ),
          const Spacer(),
          _TvNavPill(
            icon: Icons.favorite_rounded,
            focusNode: tabNodes[4],
            selected: selectedIndex == 4,
            compact: compact,
            onPressed: () => onSelected(4),
          ),
          _TvNavPill(
            label: name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            compact: compact,
            onPressed: onProfile,
          ),
          _TvNavPill(
            icon: Icons.settings_rounded,
            compact: compact,
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

class _TvNavPill extends StatefulWidget {
  final String? label;
  final ContentType? contentType;
  final IconData? icon;
  final bool selected;
  final bool autofocus;
  final bool compact;
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  const _TvNavPill({
    this.label,
    this.contentType,
    this.icon,
    this.selected = false,
    this.autofocus = false,
    this.compact = false,
    this.focusNode,
    required this.onPressed,
  });

  @override
  State<_TvNavPill> createState() => _TvNavPillState();
}

class _TvNavPillState extends State<_TvNavPill> {
  bool _focused = false;
  bool _pressed = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final k = event.logicalKey;
    final ok =
        k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA;
    if (!ok) return KeyEventResult.ignored;
    // Only a full press on this pill: a key up left over from a closed
    // panel or page must not switch tab.
    if (event is KeyDownEvent) _pressed = true;
    if (event is KeyUpEvent) {
      if (_pressed) widget.onPressed();
      _pressed = false;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final fg = _focused
        ? AppColors.background
        : widget.selected
        ? AppColors.primary
        : AppColors.textPrimary;
    const shadow = [Shadow(color: Color(0xCC000000), blurRadius: 6)];
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: (v) => setState(() {
        _focused = v;
        if (!v) _pressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: widget.compact ? 2 : 4),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact
                ? (widget.label == null ? 8 : 12)
                : (widget.label == null ? 12 : 20),
            vertical: widget.compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: _focused ? AppColors.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
            border: widget.selected && !_focused
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null)
                Icon(
                  widget.icon,
                  color: fg,
                  size: widget.compact ? 20 : 24,
                  shadows: _focused ? null : shadow,
                ),
              if (widget.icon != null && widget.label != null)
                SizedBox(width: widget.compact ? 6 : 8),
              if (widget.label != null)
                Text(
                  widget.label!.toUpperCase(),
                  style: TextStyle(
                    color: fg,
                    fontSize: widget.compact ? 16 : 19,
                    shadows: _focused ? null : shadow,
                    fontWeight: widget.selected || _focused
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              if (widget.contentType case final type?) ...[
                const SizedBox(width: 6),
                CatalogStatusIndicator(type: type, foreground: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar of the currently selected profile in the top bar; tapping it opens
/// the profile picker. Hidden when no profile is selected.
class _ProfileButton extends StatelessWidget {
  const _ProfileButton();

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ProfileProvider>();
    final profile = profiles.selected;
    if (profile == null) return const SizedBox.shrink();
    final color = Color(
      ProfileAvatars.colors[profile.avatarColor] ??
          ProfileAvatars.colors['arancio']!,
    );
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: IconButton(
        tooltip: 'Cambia profilo',
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ProfilePickerScreen())),
        icon: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Center(
            child: Text(
              profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
