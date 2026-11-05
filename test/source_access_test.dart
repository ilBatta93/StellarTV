import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/models/content_type.dart';
import 'package:stellar_tv/models/source_access.dart';
import 'package:stellar_tv/services/key_handoff.dart';
import 'package:stellar_tv/services/link_source.dart';
import 'package:stellar_tv/services/portal_source.dart';
import 'package:stellar_tv/services/settings_service.dart';
import 'package:stellar_tv/services/stream_address.dart';
import 'package:stellar_tv/widgets/source_access_form.dart';

void main() {
  group('SourceAccess', () {
    test('old saved data without kind reads as an account', () {
      final a = SourceAccess.fromCredentials({
        'server': 'http://a.test',
        'username': 'u',
        'password': 'p',
      })!;
      expect(a.kind, SourceKind.account);
      expect(a.toCredentials().containsKey('kind'), isFalse);
    });

    test('a list address with user and password becomes an account', () {
      final a = SourceAccess.fromLink(
        'http://host.test:8080/get.php?username=me&password=pw&type=x&output=ts',
      );
      expect(a.kind, SourceKind.account);
      expect(a.server, 'http://host.test:8080');
      expect(a.username, 'me');
      expect(a.password, 'pw');
    });

    test('any other address stays a single-address list', () {
      final a = SourceAccess.fromLink(' https://cdn.test/list.txt ');
      expect(a.kind, SourceKind.link);
      expect(a.server, 'https://cdn.test/list.txt');
      expect(a.problem, isNull);
    });

    test('MAC addresses are normalized or refused', () {
      expect(
        SourceAccess.normalizeMac('00-1a-79-ab-cd-ef'),
        '00:1A:79:AB:CD:EF',
      );
      expect(SourceAccess.normalizeMac('001A79ABCDEF'), '00:1A:79:AB:CD:EF');
      expect(SourceAccess.normalizeMac('00:1A:79:AB:CD'), isNull);
      expect(SourceAccess.normalizeMac('zz:1A:79:AB:CD:EF'), isNull);
    });

    test('portal access needs a valid MAC', () {
      const bad = SourceAccess(
        kind: SourceKind.portal,
        server: 'http://p.test/c/',
        username: '12',
      );
      expect(bad.problem, contains('MAC'));
    });

    test('a patch changes only the fields it carries', () {
      const stored = SourceAccess(
        kind: SourceKind.account,
        server: 'http://old.test',
        username: 'u',
        password: 'p',
      );
      final next = stored.patched(const SourcePatch(server: 'http://new.test'));
      expect(next.server, 'http://new.test');
      expect(next.username, 'u');
      expect(next.password, 'p');
      final empty = stored.patched(
        const SourcePatch(server: '', username: '', password: 'q'),
      );
      expect(empty.server, 'http://old.test');
      expect(empty.username, 'u');
      expect(empty.password, 'q');
    });

    test('a patch of another kind does not carry old fields over', () {
      const stored = SourceAccess(
        kind: SourceKind.account,
        server: 'http://old.test',
        username: 'u',
        password: 'p',
      );
      final next = stored.patched(
        const SourcePatch(kind: SourceKind.link, server: 'http://l.test/x'),
      );
      expect(next.kind, SourceKind.link);
      expect(next.username, '');
      expect(next.password, '');
    });
  });

  group('SourceHandoff', () {
    test('reads the old complete account message', () {
      final p = SourceHandoff.parse(
        jsonEncode({
          'kind': 'xtream',
          'host': 'http://a.test',
          'username': 'u',
          'password': 'p',
        }),
      )!;
      expect(p.kind, SourceKind.account);
      expect(p.server, 'http://a.test');
    });

    test('reads a partial edit with the address only', () {
      final p = SourceHandoff.parse(
        jsonEncode({
          'kind': 'source',
          'type': 'account',
          'host': 'http://new.test',
        }),
      )!;
      expect(p.server, 'http://new.test');
      expect(p.username, isNull);
      expect(p.password, isNull);
    });

    test('reads a portal with MAC and refuses bad values', () {
      final p = SourceHandoff.parse(
        jsonEncode({
          'kind': 'source',
          'type': 'portal',
          'host': 'http://p.test/c/',
          'mac': '00-1a-79-00-00-01',
        }),
      )!;
      expect(p.kind, SourceKind.portal);
      expect(p.username, '00:1A:79:00:00:01');
      expect(
        SourceHandoff.parse(
          jsonEncode({'kind': 'source', 'type': 'portal', 'mac': 'x'}),
        ),
        isNull,
      );
      expect(
        SourceHandoff.parse(
          jsonEncode({'kind': 'source', 'type': 'link', 'host': 'ftp://x'}),
        ),
        isNull,
      );
      expect(
        SourceHandoff.parse(jsonEncode({'kind': 'source', 'type': 'link'})),
        isNull,
      );
    });

    test('QR bundle carries any kind of access', () {
      final b = BundleHandoff.parse(
        jsonEncode({
          'kind': 'bundle',
          'source': {'type': 'link', 'host': 'http://l.test/all'},
        }),
      )!;
      expect(b.access!.kind, SourceKind.link);
      expect(b.access!.server, 'http://l.test/all');
      final old = BundleHandoff.parse(
        jsonEncode({
          'kind': 'bundle',
          'xtream': {'host': 'http://a.test', 'username': 'u', 'password': 'p'},
        }),
      )!;
      expect(old.access!.kind, SourceKind.account);
      expect(old.access!.username, 'u');
    });
  });

  group('SourceAccessController', () {
    test('applies a phone patch over the typed fields', () {
      final c = SourceAccessController(
        const SourceAccess(
          kind: SourceKind.account,
          server: 'http://old.test',
          username: 'u',
          password: 'p',
        ),
      );
      c.apply(
        const SourcePatch(kind: SourceKind.account, server: 'http://new.test'),
      );
      expect(c.access.server, 'http://new.test');
      expect(c.access.username, 'u');
      expect(c.access.password, 'p');
      c.apply(
        const SourcePatch(
          kind: SourceKind.portal,
          server: 'http://p.test/c/',
          username: '00:1A:79:00:00:02',
        ),
      );
      expect(c.kind, SourceKind.portal);
      expect(c.access.mac, '00:1A:79:00:00:02');
      c.dispose();
    });
  });

  group('LinkSource.parse', () {
    LinkCatalog parse(String text) =>
        LinkSource.parse(Uint8List.fromList(utf8.encode(text)));

    const sample =
        '#EXTM3U url-tvg="http://g.test/guide.xml"\n'
        '#EXTINF:-1 tvg-id="one.it" tvg-logo="http://l.test/1.png" '
        'group-title="Notizie, Italia",Canale Uno\n'
        'http://s.test/live/1.ts\n'
        '#EXTINF:-1 group-title="Film",Un titolo (2019)\n'
        'http://s.test/movie/u/p/10.mkv\n'
        '#EXTINF:-1 group-title="Serie",Una serie S01 E02\n'
        'http://s.test/series/u/p/20.mp4\n'
        '#EXTINF:-1,Senza gruppo\n'
        '#EXTVLCOPT:http-user-agent=x\n'
        'http://s.test/clip.mp4\n'
        'http://s.test/orphan.ts\n';

    test('splits entries into sections with guide address', () {
      final c = parse(sample);
      expect(c.guideUrl, 'http://g.test/guide.xml');
      expect(c.channels, hasLength(4));
      final live = c.section(ContentType.live).single;
      expect(live.name, 'Canale Uno');
      expect(live.group, 'Notizie, Italia');
      expect(live.tvgId, 'one.it');
      expect(live.logo, 'http://l.test/1.png');
      expect(c.section(ContentType.movie).map((m) => m.name), [
        'Un titolo (2019)',
        'Senza gruppo',
      ]);
      final ep = c.section(ContentType.series).single;
      expect(ep.season, 1);
      expect(ep.episode, 2);
      expect(ep.seriesName, isNotEmpty);
      expect(ep.seriesKey, isNotNull);
    });

    test('ids are stable across reads', () {
      expect(
        parse(sample).channels.map((c) => c.id).toList(),
        parse(sample).channels.map((c) => c.id).toList(),
      );
    });
  });

  group('PortalSource', () {
    test('finds the portal root from the address boxes use', () {
      expect(
        PortalSource.rootOf('http://p.test:8080/c/'),
        'http://p.test:8080',
      );
      expect(
        PortalSource.rootOf('p.test/stalker_portal/c'),
        'http://p.test/stalker_portal',
      );
      expect(PortalSource.rootOf('http://p.test/portal.php'), 'http://p.test');
    });

    test('extracts the playable link of a portal command', () {
      expect(
        PortalSource.linkFromCmd('ffmpeg http://s.test/play/1?t=a'),
        'http://s.test/play/1?t=a',
      );
      expect(PortalSource.linkFromCmd('ffrt http://localhost/ch/1'), isNull);
    });

    test('portal addresses round-trip and need resolving', () async {
      final url = PortalSource.address(
        'vod',
        'eyJ0eXBlIjoic2VyaWVzIn0=',
        episode: 3,
      );
      expect(StreamAddress.needsResolve(url), isTrue);
      final uri = Uri.parse(url);
      expect(uri.host, 'vod');
      expect(uri.queryParameters['cmd'], 'eyJ0eXBlIjoic2VyaWVzIn0=');
      expect(uri.queryParameters['series'], '3');
      expect(StreamAddress.needsResolve('http://s.test/1.ts'), isFalse);
      StreamAddress.override = (u) async => 'http://resolved.test/x';
      addTearDown(() => StreamAddress.override = null);
      expect(await StreamAddress.resolve(url), 'http://resolved.test/x');
      expect(
        await StreamAddress.resolve('http://s.test/1.ts'),
        'http://s.test/1.ts',
      );
    });
  });

  test('the access kind is stored next to the credentials', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setXtreamCredentials(
      server: 'http://p.test/c/',
      username: '00:1A:79:00:00:01',
      password: '',
      kind: 'portal',
    );
    final saved = await settings.getXtreamCredentials();
    expect(SourceAccess.kindOf(saved), SourceKind.portal);
    await settings.setXtreamCredentials(
      server: 'http://a.test',
      username: 'u',
      password: 'p',
    );
    expect(
      SourceAccess.kindOf(await settings.getXtreamCredentials()),
      SourceKind.account,
    );
    await settings.clearCredentials();
    expect(await settings.getXtreamCredentials(), isNull);
  });
}
