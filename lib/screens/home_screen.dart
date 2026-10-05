import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/content_type.dart';
import '../providers/profile_provider.dart';
import '../services/profile_service.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
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
    LivePage(),
    CatalogPage(type: ContentType.movie),
    CatalogPage(type: ContentType.series),
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
              icon: Icon(Icons.live_tv_outlined),
              selectedIcon: Icon(Icons.live_tv_rounded),
              label: 'Diretta',
            ),
            NavigationDestination(
              icon: Icon(Icons.movie_outlined),
              selectedIcon: Icon(Icons.movie_rounded),
              label: 'Film',
            ),
            NavigationDestination(
              icon: Icon(Icons.video_library_outlined),
              selectedIcon: Icon(Icons.video_library_rounded),
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

  @override
  void dispose() {
    _tvNavScope.dispose();
    super.dispose();
  }

  void _selectTab(int i) => setState(() {
    _currentIndex = i;
    _visited.add(i);
  });

  // Back on TV: content -> top menu -> Home tab -> app to background (it keeps
  // running, like other TV apps, instead of closing).
  void _onTvBack() {
    if (!_tvNavScope.hasFocus) {
      _tvNavScope.requestFocus();
      return;
    }
    if (_currentIndex != 0) {
      _selectTab(0);
      return;
    }
    DeviceTypeService.moveToBackground();
  }

  Widget _buildTv(BuildContext context) {
    final content = IndexedStack(
      index: _currentIndex,
      children: [
        for (var i = 0; i < _pages.length; i++)
          _visited.contains(i) ? _pages[i] : const SizedBox.shrink(),
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
            Positioned.fill(top: _currentIndex == 0 ? 0 : 92, child: content),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: FocusScope(
                node: _tvNavScope,
                child: _TvTopBar(
                  selectedIndex: _currentIndex,
                  onSelected: _selectTab,
                  onSearch: () => _push(const SearchScreen()),
                  onProfile: () => _push(const ProfilePickerScreen()),
                  onSettings: () => _push(const SettingsScreen()),
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
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSearch;
  final VoidCallback onProfile;
  final VoidCallback onSettings;

  const _TvTopBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.onSearch,
    required this.onProfile,
    required this.onSettings,
  });

  static const _tabs = ['Home', 'Diretta', 'Film', 'Serie TV', 'Preferiti'];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE60B0D10), Color(0x000B0D10)],
        ),
      ),
      child: Row(
        children: [
          const BrandLogo(size: 26),
          const SizedBox(width: 32),
          _TvNavPill(
            label: 'Cerca',
            icon: Icons.search_rounded,
            onPressed: onSearch,
          ),
          for (var i = 0; i < _tabs.length; i++)
            _TvNavPill(
              label: _tabs[i],
              selected: selectedIndex == i,
              autofocus: i == 0,
              onPressed: () => onSelected(i),
            ),
          const Spacer(),
          _TvNavPill(icon: Icons.person_rounded, onPressed: onProfile),
          _TvNavPill(icon: Icons.settings_rounded, onPressed: onSettings),
        ],
      ),
    );
  }
}

class _TvNavPill extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final bool selected;
  final bool autofocus;
  final VoidCallback onPressed;

  const _TvNavPill({
    this.label,
    this.icon,
    this.selected = false,
    this.autofocus = false,
    required this.onPressed,
  });

  @override
  State<_TvNavPill> createState() => _TvNavPillState();
}

class _TvNavPillState extends State<_TvNavPill> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final k = event.logicalKey;
    final ok =
        k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA;
    if (!ok) return KeyEventResult.ignored;
    if (event is KeyUpEvent) widget.onPressed();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final fg = _focused
        ? AppColors.background
        : widget.selected
        ? AppColors.primary
        : AppColors.textPrimary;
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: (v) => setState(() => _focused = v),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: EdgeInsets.symmetric(
            horizontal: widget.label == null ? 12 : 20,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: _focused ? AppColors.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) Icon(widget.icon, color: fg, size: 24),
              if (widget.icon != null && widget.label != null)
                const SizedBox(width: 8),
              if (widget.label != null)
                Text(
                  widget.label!,
                  style: TextStyle(
                    color: fg,
                    fontSize: 19,
                    fontWeight: widget.selected || _focused
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
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
          child: Icon(
            ProfileAvatars.iconOf(profile.avatarKey),
            color: color,
            size: 18,
          ),
        ),
      ),
    );
  }
}
