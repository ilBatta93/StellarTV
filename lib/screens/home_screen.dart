import 'package:flutter/material.dart';
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

  Widget _buildTv(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _TvNavigationRail(
            selectedIndex: _currentIndex,
            onSelected: (i) => setState(() {
              _currentIndex = i;
              _visited.add(i);
            }),
            onSearch: () => _push(const SearchScreen()),
            onProfile: () => _push(const ProfilePickerScreen()),
            onSettings: () => _push(const SettingsScreen()),
          ),
          Expanded(
            child: SafeArea(
              left: false,
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    _visited.contains(i) ? _pages[i] : const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvNavigationRail extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSearch;
  final VoidCallback onProfile;
  final VoidCallback onSettings;

  const _TvNavigationRail({
    required this.selectedIndex,
    required this.onSelected,
    required this.onSearch,
    required this.onProfile,
    required this.onSettings,
  });

  @override
  State<_TvNavigationRail> createState() => _TvNavigationRailState();
}

class _TvNavigationRailState extends State<_TvNavigationRail> {
  bool _expanded = false;

  static const _destinations = [
    (Icons.home_rounded, 'Home'),
    (Icons.live_tv_rounded, 'Diretta'),
    (Icons.movie_rounded, 'Film'),
    (Icons.video_library_rounded, 'Serie TV'),
    (Icons.favorite_rounded, 'Preferiti'),
  ];

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _expanded = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: _expanded ? 220 : 88,
        color: AppColors.surface,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: BrandLogo(size: _expanded ? 30 : 26),
              ),
              for (var i = 0; i < _destinations.length; i++)
                _TvRailItem(
                  icon: _destinations[i].$1,
                  label: _destinations[i].$2,
                  selected: widget.selectedIndex == i,
                  expanded: _expanded,
                  autofocus: i == 0,
                  onPressed: () => widget.onSelected(i),
                ),
              const Spacer(),
              _TvRailItem(
                icon: Icons.search_rounded,
                label: 'Cerca',
                expanded: _expanded,
                onPressed: widget.onSearch,
              ),
              _TvRailItem(
                icon: Icons.person_rounded,
                label: 'Profilo',
                expanded: _expanded,
                onPressed: widget.onProfile,
              ),
              _TvRailItem(
                icon: Icons.settings_rounded,
                label: 'Impostazioni',
                expanded: _expanded,
                onPressed: widget.onSettings,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvRailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final bool autofocus;
  final VoidCallback onPressed;

  const _TvRailItem({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.onPressed,
    this.selected = false,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: ListTile(
        autofocus: autofocus,
        selected: selected,
        leading: Icon(
          icon,
          color: selected ? AppColors.primary : AppColors.textSecondary,
        ),
        title: expanded
            ? Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 17,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              )
            : null,
        onTap: onPressed,
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
