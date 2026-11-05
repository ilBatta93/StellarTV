import 'package:flutter/material.dart';

import '../models/source_access.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import 'auth_scaffold.dart';
import 'tv_text_field.dart';

/// Form state of the access data: the chosen kind and the fields of every
/// kind, so switching kind back and forth keeps what was typed.
class SourceAccessController extends ChangeNotifier {
  SourceAccessController([SourceAccess? initial]) {
    if (initial != null) load(initial);
  }

  SourceKind _kind = SourceKind.account;
  SourceKind get kind => _kind;
  set kind(SourceKind value) {
    if (value == _kind) return;
    _kind = value;
    notifyListeners();
  }

  final server = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final link = TextEditingController();
  final portal = TextEditingController();
  final mac = TextEditingController();

  /// What the form describes now. A single address that carries a user
  /// name and password is read as an account login.
  SourceAccess get access => switch (_kind) {
    SourceKind.account => SourceAccess(
      kind: SourceKind.account,
      server: server.text.trim(),
      username: username.text.trim(),
      password: password.text.trim(),
    ),
    SourceKind.link => SourceAccess.fromLink(link.text),
    SourceKind.portal => SourceAccess(
      kind: SourceKind.portal,
      server: portal.text.trim(),
      username: SourceAccess.normalizeMac(mac.text) ?? mac.text.trim(),
    ),
  };

  void load(SourceAccess a) {
    _kind = a.kind;
    switch (a.kind) {
      case SourceKind.account:
        server.text = a.server;
        username.text = a.username;
        password.text = a.password;
      case SourceKind.link:
        link.text = a.server;
      case SourceKind.portal:
        portal.text = a.server;
        mac.text = a.mac;
    }
    notifyListeners();
  }

  /// Fills in only what the phone sent; the other fields stay as they are.
  void apply(SourcePatch patch) {
    final kind = patch.kind ?? _kind;
    final current = _kind == kind ? access : _fieldsOf(kind);
    load(
      current.patched(
        SourcePatch(
          kind: kind,
          server: patch.server,
          username: patch.username,
          password: patch.password,
        ),
      ),
    );
  }

  SourceAccess _fieldsOf(SourceKind kind) => switch (kind) {
    SourceKind.account => SourceAccess(
      kind: kind,
      server: server.text.trim(),
      username: username.text.trim(),
      password: password.text.trim(),
    ),
    SourceKind.link => SourceAccess(kind: kind, server: link.text.trim()),
    SourceKind.portal => SourceAccess(
      kind: kind,
      server: portal.text.trim(),
      username: mac.text.trim(),
    ),
  };

  @override
  void dispose() {
    for (final c in [server, username, password, link, portal, mac]) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Kind choice plus the fields of the chosen kind.
class SourceAccessFields extends StatefulWidget {
  const SourceAccessFields({
    super.key,
    required this.controller,
    this.nextFocus,
    this.onSubmitted,
    this.labelsAbove = false,
  });

  final SourceAccessController controller;

  /// Field after the last access field (recovery key), if shown.
  final FocusNode? nextFocus;
  final VoidCallback? onSubmitted;

  /// Login style: labels above the fields; otherwise floating labels.
  final bool labelsAbove;

  @override
  State<SourceAccessFields> createState() => _SourceAccessFieldsState();
}

class _SourceAccessFieldsState extends State<SourceAccessFields> {
  final _second = FocusNode();
  final _third = FocusNode();
  bool _obscure = true;

  @override
  void dispose() {
    _second.dispose();
    _third.dispose();
    super.dispose();
  }

  static String label(SourceKind kind) => switch (kind) {
    SourceKind.account => 'Nome utente e password',
    SourceKind.link => 'Indirizzo unico',
    SourceKind.portal => 'Portale MAC',
  };

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in SourceKind.values)
                AuthAction(
                  onPressed: () => c.kind = kind,
                  child: ChoiceChip(
                    label: Text(label(kind)),
                    selected: c.kind == kind,
                    onSelected: (_) => c.kind = kind,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ..._fields(c),
        ],
      ),
    );
  }

  List<Widget> _fields(SourceAccessController c) {
    final last = widget.nextFocus;
    final lastAction = last != null
        ? TextInputAction.next
        : TextInputAction.done;
    void submit(String _) => widget.onSubmitted?.call();
    return switch (c.kind) {
      SourceKind.account => [
        ..._field(
          'Server URL',
          TvTextField(
            key: const ValueKey('access-server'),
            autofocus: DeviceTypeService.isTv,
            controller: c.server,
            nextFocus: _second,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.url,
            decoration: _decoration(
              'Server URL',
              'http://tuo-server.com:8080',
              Icons.dns_outlined,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ..._field(
          'Nome utente',
          TvTextField(
            key: const ValueKey('access-user'),
            controller: c.username,
            focusNode: _second,
            nextFocus: _third,
            textInputAction: TextInputAction.next,
            decoration: _decoration(
              'Nome utente',
              'Inserisci il nome utente',
              Icons.person_outline_rounded,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ..._field(
          'Password',
          TvTextField(
            key: const ValueKey('access-password'),
            controller: c.password,
            focusNode: _third,
            nextFocus: last,
            obscureText: _obscure,
            textInputAction: lastAction,
            onSubmitted: last == null ? submit : null,
            decoration: _decoration(
              'Password',
              'Inserisci la password',
              Icons.lock_outline_rounded,
            ).copyWith(suffixIcon: _eye()),
          ),
        ),
      ],
      SourceKind.link => [
        ..._field(
          'Indirizzo',
          TvTextField(
            key: const ValueKey('access-link'),
            autofocus: DeviceTypeService.isTv,
            controller: c.link,
            nextFocus: last,
            keyboardType: TextInputType.url,
            textInputAction: lastAction,
            onSubmitted: last == null ? submit : null,
            decoration: _decoration(
              'Indirizzo',
              'http://tuo-server.com/elenco',
              Icons.link_rounded,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Un solo indirizzo che contiene tutti i contenuti. Se include '
          'nome utente e password, l’app li usa per caricare anche le '
          'schede delle serie e la guida.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
      SourceKind.portal => [
        ..._field(
          'Indirizzo del portale',
          TvTextField(
            key: const ValueKey('access-portal'),
            autofocus: DeviceTypeService.isTv,
            controller: c.portal,
            nextFocus: _second,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: _decoration(
              'Indirizzo del portale',
              'http://portale.com:8080/c/',
              Icons.router_outlined,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ..._field(
          'Indirizzo MAC',
          TvTextField(
            key: const ValueKey('access-mac'),
            controller: c.mac,
            focusNode: _second,
            nextFocus: last,
            textInputAction: lastAction,
            onSubmitted: last == null ? submit : null,
            decoration: _decoration(
              'Indirizzo MAC',
              '00:1A:79:00:00:00',
              Icons.memory_rounded,
            ),
          ),
        ),
      ],
    };
  }

  Widget _eye() => AuthAction(
    onPressed: () => setState(() => _obscure = !_obscure),
    child: IconButton(
      tooltip: _obscure ? 'Mostra password' : 'Nascondi password',
      icon: Icon(
        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
        color: AppColors.textSecondary,
      ),
      onPressed: () => setState(() => _obscure = !_obscure),
    ),
  );

  InputDecoration _decoration(String label, String hint, IconData icon) =>
      widget.labelsAbove
      ? InputDecoration(hintText: hint, prefixIcon: Icon(icon, size: 20))
      : InputDecoration(labelText: label, prefixIcon: Icon(icon));

  List<Widget> _field(String label, Widget field) => widget.labelsAbove
      ? [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          field,
        ]
      : [field];
}
