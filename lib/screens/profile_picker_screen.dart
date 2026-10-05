import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_profile.dart';
import '../providers/profile_provider.dart';
import '../services/profile_service.dart';
import '../widgets/pin_dialog.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import '../services/device_type_service.dart';
import '../widgets/tv_focusable.dart';
import 'home_screen.dart';

/// Netflix-style profile picker shown after login. Lets the user pick an
/// existing profile, create a new one with a custom icon and color, or edit
/// and delete existing ones.
class ProfilePickerScreen extends StatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ProfileProvider>();
      // Profiles already loaded: show them at once, refresh only if empty.
      if (!provider.hasLoaded || provider.items.isEmpty) provider.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ProfileProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: profiles.isLoading && profiles.items.isEmpty
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    const Center(child: BrandLogo(size: 46)),
                    const SizedBox(height: 12),
                    Text(
                      'Chi sta guardando?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 32),
                    if (profiles.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          profiles.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 20,
                        runSpacing: 24,
                        children: [
                          for (final p in profiles.items)
                            _ProfileAvatar(
                              profile: p,
                              selected: p.id == profiles.selectedId,
                              onTap: () => _select(p),
                              onLongPress: () => _showActions(p),
                            ),
                          _AddProfileTile(onTap: _createProfile),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }

  /// True when leaving the kids profile is allowed (PIN entered or none).
  Future<bool> _unlockFromKids() async {
    final current = context.read<ProfileProvider>().selected;
    if (current == null || !current.isKids) return true;
    return verifyKidsPin(context);
  }

  Future<void> _select(UserProfile p) async {
    final provider = context.read<ProfileProvider>();
    if (!p.isKids && !await _unlockFromKids()) return;
    if (!mounted) return;
    unawaited(provider.select(p));
    if (!mounted) return;
    // Opened from Home: just go back instead of rebuilding the whole Home.
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  Future<void> _createProfile() async {
    if (!await _unlockFromKids() || !mounted) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ProfileEditorSheet(),
    );
    if (created == true && mounted) {
      context.read<ProfileProvider>().load();
    }
  }

  Future<void> _showActions(UserProfile p) async {
    if (!await _unlockFromKids() || !mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Modifica profilo'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: const Text(
                'Elimina profilo',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final provider = context.read<ProfileProvider>();
    if (action == 'edit') {
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _ProfileEditorSheet(existing: p),
      );
      provider.load();
    } else if (action == 'delete') {
      await provider.delete(p);
    }
  }
}

class _ProfileAvatar extends StatelessWidget {
  final UserProfile profile;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ProfileAvatar({
    required this.profile,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(
      ProfileAvatars.colors[profile.avatarColor] ??
          ProfileAvatars.colors['arancio']!,
    );
    final icon = ProfileAvatars.iconOf(profile.avatarKey);
    final tile = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 92,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? AppColors.primary : Colors.transparent,
                  width: 3,
                ),
              ),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 40),
              ),
            ),
            const SizedBox(height: 8),
            if (profile.isKids)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'BAMBINI',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
    return TvFocusable(
      onPressed: onTap,
      onLongPress: onLongPress,
      autofocus: DeviceTypeService.isTv && selected,
      borderRadius: BorderRadius.circular(16),
      child: tile,
    );
  }
}

class _AddProfileTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddProfileTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tile = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 92,
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: AppColors.textSecondary,
                size: 36,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nuovo',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
    return TvFocusable(
      onPressed: onTap,
      borderRadius: BorderRadius.circular(16),
      child: tile,
    );
  }
}

/// Create-or-edit sheet: name field plus avatar icon and color pickers.
class _ProfileEditorSheet extends StatefulWidget {
  final UserProfile? existing;

  const _ProfileEditorSheet({this.existing});

  @override
  State<_ProfileEditorSheet> createState() => _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends State<_ProfileEditorSheet> {
  late final TextEditingController _nameController;
  late String _avatarKey;
  late String _avatarColor;
  late bool _isKids;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _avatarKey = widget.existing?.avatarKey ?? 'rocket';
    _avatarColor = widget.existing?.avatarColor ?? 'arancio';
    _isKids = widget.existing?.isKids ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? 'Nuovo profilo' : 'Modifica profilo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            maxLength: 20,
            autofocus: widget.existing == null,
            decoration: const InputDecoration(
              labelText: 'Nome',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Icona',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in ProfileAvatars.entries.entries)
                _IconOption(
                  icon: ProfileAvatars.iconOf(entry.key),
                  color: Color(
                    ProfileAvatars.colors[_avatarColor] ??
                        ProfileAvatars.colors['arancio']!,
                  ),
                  selected: entry.key == _avatarKey,
                  onTap: () => setState(() => _avatarKey = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Colore',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in ProfileAvatars.colors.entries)
                _ColorOption(
                  color: Color(entry.value),
                  selected: entry.key == _avatarColor,
                  onTap: () => setState(() => _avatarColor = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _isKids,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _isKids = v),
            title: const Text('Profilo bambini'),
            subtitle: const Text(
              'Mostra solo canali, film e serie per bambini (cartoni, animazione, famiglia).',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('Salva'),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_isKids && !await ensureKidsPin(context)) return;
    if (!mounted) return;
    setState(() => _saving = true);
    final provider = context.read<ProfileProvider>();
    try {
      if (widget.existing == null) {
        await provider.create(
          name: name,
          avatarKey: _avatarKey,
          avatarColor: _avatarColor,
          isKids: _isKids,
        );
      } else {
        await provider.update(
          widget.existing!,
          name: name,
          avatarKey: _avatarKey,
          avatarColor: _avatarColor,
          isKids: _isKids,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Salvataggio non riuscito. Controlla la connessione.',
            ),
          ),
        );
      }
    }
  }
}

class _IconOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _IconOption({
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

class _ColorOption extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorOption({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 3,
          ),
        ),
      ),
    );
  }
}
