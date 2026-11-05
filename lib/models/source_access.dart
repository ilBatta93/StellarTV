/// How the device reaches the user's media source.
///
/// * [account]: server address, user name and password (catalog API).
/// * [link]: one address that returns the whole list as text.
/// * [portal]: set-top-box portal address plus the device MAC address.
enum SourceKind { account, link, portal }

/// Access data of the media source. Stored on the device only, in the same
/// three credential slots as before: for [SourceKind.portal] the user name
/// slot holds the MAC address, for [SourceKind.link] only the server slot is
/// used. Old saved data has no kind and reads as [SourceKind.account].
class SourceAccess {
  const SourceAccess({
    required this.kind,
    required this.server,
    this.username = '',
    this.password = '',
  });

  final SourceKind kind;
  final String server;
  final String username;
  final String password;

  String get mac => username;

  static SourceKind kindOf(Map<String, String>? credentials) =>
      switch (credentials?['kind']) {
        'link' => SourceKind.link,
        'portal' => SourceKind.portal,
        _ => SourceKind.account,
      };

  static SourceAccess? fromCredentials(Map<String, String>? c) {
    final server = c?['server'];
    if (c == null || server == null) return null;
    return SourceAccess(
      kind: kindOf(c),
      server: server,
      username: c['username'] ?? '',
      password: c['password'] ?? '',
    );
  }

  Map<String, String> toCredentials() => {
    'server': server,
    'username': username,
    'password': password,
    if (kind != SourceKind.account) 'kind': kind.name,
  };

  /// First problem to fix, in the order the form shows the fields; null
  /// when the access data is complete.
  String? get problem {
    final uri = Uri.tryParse(server.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return 'Inserisci un indirizzo http o https valido.';
    }
    return switch (kind) {
      SourceKind.account =>
        username.trim().isEmpty || password.isEmpty
            ? 'Inserisci nome utente e password.'
            : null,
      SourceKind.link => null,
      SourceKind.portal =>
        normalizeMac(username) == null
            ? 'Inserisci un indirizzo MAC valido (00:1A:79:xx:xx:xx).'
            : null,
    };
  }

  /// A list address that carries a user name and password in its query
  /// (`get.php?username=…&password=…`) is the same server's catalog API:
  /// reading it as an account gives series details, guide and archive.
  static SourceAccess fromLink(String raw) {
    final text = raw.trim();
    final uri = Uri.tryParse(text);
    final user = uri?.queryParameters['username'] ?? '';
    final pass = uri?.queryParameters['password'] ?? '';
    if (uri != null &&
        uri.host.isNotEmpty &&
        user.isNotEmpty &&
        pass.isNotEmpty &&
        uri.path.toLowerCase().endsWith('/get.php')) {
      final port = uri.hasPort ? ':${uri.port}' : '';
      final prefix = uri.path.substring(0, uri.path.length - '/get.php'.length);
      return SourceAccess(
        kind: SourceKind.account,
        server: '${uri.scheme}://${uri.host}$port$prefix',
        username: user,
        password: pass,
      );
    }
    return SourceAccess(kind: SourceKind.link, server: text);
  }

  /// `00:1A:79:AB:CD:EF` from any common spelling (dashes, no separators,
  /// lower case); null when it is not six hexadecimal bytes.
  static String? normalizeMac(String raw) {
    final hex = raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (hex.length != 12 || raw.trim().length > 17) return null;
    return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
  }

  /// Applies only the fields that were filled in: an empty value keeps the
  /// stored one, so the phone can change the address alone.
  SourceAccess patched(SourcePatch patch) {
    final nextKind = patch.kind ?? kind;
    final sameKind = nextKind == kind;
    String pick(String? value, String current) =>
        value != null && value.isNotEmpty ? value : (sameKind ? current : '');
    return SourceAccess(
      kind: nextKind,
      server: pick(patch.server, server),
      username: pick(patch.username, username),
      password: pick(patch.password, password),
    );
  }
}

/// Partial access data received from the phone. Null or empty fields mean
/// "leave as it is".
class SourcePatch {
  const SourcePatch({this.kind, this.server, this.username, this.password});
  final SourceKind? kind;
  final String? server;
  final String? username;
  final String? password;

  bool get isEmpty =>
      (server ?? '').isEmpty &&
      (username ?? '').isEmpty &&
      (password ?? '').isEmpty;
}
