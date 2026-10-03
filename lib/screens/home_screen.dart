import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/content_type.dart';
import '../providers/profile_provider.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import 'catalog_page.dart';
import 'discover_page.dart';
import 'favorites_page.dart';
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

  static const _pages = [
    DiscoverPage(),
    CatalogPage(type: ContentType.live),
    CatalogPage(type: ContentType.movie),
    CatalogPage(type: ContentType.series),
    FavoritesPage(),
  ];

  void _push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const BrandLogo(size: 30),
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
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.live_tv_outlined),
                selectedIcon: Icon(Icons.live_tv_rounded),
                label: 'Diretta'),
            NavigationDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie_rounded),
                label: 'Film'),
            NavigationDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library_rounded),
                label: 'Serie TV'),
            NavigationDestination(
                icon: Icon(Icons.favorite_border_rounded),
                selectedIcon: Icon(Icons.favorite_rounded),
                label: 'Preferiti'),
          ],
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
    final color = Color(ProfileAvatars.colors[profile.avatarColor] ??
        ProfileAvatars.colors['arancio']!);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: IconButton(
        tooltip: 'Cambia profilo',
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfilePickerScreen())),
        icon: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(9),
            border:
                Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
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
