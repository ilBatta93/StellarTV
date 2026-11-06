import base64
import json
import unittest

import avvio
import db_salute
import gemelle
import revisione
from ecosistema import lexicon_findings, message_findings, parse_diff, pending_release_lines, secret_findings


def fake_jwt(role):
    def part(data):
        return base64.urlsafe_b64encode(json.dumps(data).encode()).decode().rstrip('=')
    return f'{part({"alg": "HS256"})}.{part({"role": role, "iss": "supabase"})}.' + 'x' * 20


DIFF = '''diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -3,2 +3,2 @@
-  void oldName() {}
-class Kept {}
+  void newName() {}
+class Kept {}
diff --git a/lib/gone.dart b/lib/gone.dart
--- a/lib/gone.dart
+++ /dev/null
@@ -1 +0,0 @@
-class Gone {}
diff --git a/docs/new.md b/docs/new.md
--- /dev/null
+++ b/docs/new.md
@@ -0,0 +1,2 @@
+# Titolo
+--- non è un'intestazione di diff
'''


class DiffTest(unittest.TestCase):
    def test_added_removed_and_deleted_files(self):
        files = parse_diff(DIFF)
        self.assertEqual(files['lib/a.dart']['added'][0], (3, '  void newName() {}'))
        self.assertEqual(files['lib/gone.dart']['removed'], ['class Gone {}'])
        self.assertEqual([t for _, t in files['docs/new.md']['added']], ['# Titolo', "--- non è un'intestazione di diff"])

    def test_removed_symbols_ignore_moved_ones(self):
        gone = revisione.removed_symbols(parse_diff(DIFF))
        self.assertIn('lib/a.dart: oldName', gone)
        self.assertIn('lib/gone.dart: Gone', gone)
        self.assertNotIn('lib/a.dart: Kept', gone)


class RulesTest(unittest.TestCase):
    def test_strong_secrets_block(self):
        lines = [(1, 'key = "' + 'sb_' + 'secret_' + 'a' * 20 + '"'), (2, 'k = "' + fake_jwt('service_role') + '"'),
                 (3, '-----BEGIN ' + 'PRIVATE KEY-----')]
        blocking, _ = secret_findings('lib/x.dart', lines)
        self.assertEqual(len(blocking), 3)

    def test_public_anon_key_passes(self):
        blocking, warnings = secret_findings('src/x.ts', [(1, 'const k = "' + fake_jwt('anon') + '"')])
        self.assertEqual((blocking, warnings), ([], []))

    def test_secret_files_and_private_env_names(self):
        self.assertTrue(secret_findings('android/key.properties', [])[0])
        self.assertTrue(secret_findings('android/app/upload.jks', [])[0])
        self.assertTrue(secret_findings('.env', [(4, 'SUPABASE_SERVICE_ROLE_KEY=abc')])[0])
        self.assertFalse(secret_findings('.env', [(4, 'VITE_SUPABASE_URL=https://x.supabase.co')])[0])

    def test_lexicon_blocks_public_text_only(self):
        blocking, _ = lexicon_findings('docs/release-current.md', [(2, '- Nuove liste m3u')])
        self.assertEqual(len(blocking), 1)
        blocking, _ = lexicon_findings('src/lib/guideContent.ts', [(9, 'text: "Collega il tuo provider"')])
        self.assertEqual(len(blocking), 1)

    def test_release_notes_use_the_build_list(self):
        # The release build stopped on this line: the review must stop it first.
        line = '- Pulsante «Apri con» anche per le serie'
        blocking, _ = lexicon_findings('docs/release-current.md', [(5, line)])
        self.assertEqual(blocking, ['docs/release-current.md:5 «serie»'])
        # Other public text keeps the master list only.
        self.assertEqual(lexicon_findings('docs/player.md', [(1, line)]), ([], []))

    def test_lexicon_allows_hls_and_legacy_identifiers(self):
        lines = [(1, "final url = '$base/index.m3u8';"), (2, 'final s = XtreamService();'),
                 (3, "import 'package:provider/provider.dart';")]
        self.assertEqual(lexicon_findings('lib/x.dart', lines), ([], []))

    def test_lexicon_warns_on_ui_text_and_comments(self):
        _, warnings = lexicon_findings('lib/x.dart', [(1, "Text('Accesso Xtream Codes')"), (2, '// parse the m3u header')])
        self.assertEqual(len(warnings), 2)

    def test_rule_files_are_exempt(self):
        self.assertEqual(lexicon_findings('lib/CLAUDE.md', [(1, 'vietati: IPTV, provider')]), ([], []))

    def test_commit_messages(self):
        self.assertEqual(len(message_findings(['Lettore: nuovo parser IPTV', 'Diretta più fluida'])), 1)


class PlanTest(unittest.TestCase):
    TESTS = {'test/sync_service_test.dart': "import 'package:stellar_tv/services/sync_service.dart';",
             'test/other_test.dart': '', 'test/kids_policy_check.dart': "import '../lib/services/kids_policy.dart';",
             'test/tv_playback_shortcuts_check.dart': '', 'test/playback_work_policy_check.dart': '',
             'test/live_preview_policy_check.dart': ''}

    def test_app_plan_is_targeted(self):
        steps, _ = revisione.app_plan(['lib/services/sync_service.dart', 'lib/services/kids_policy.dart'], self.TESTS)
        commands = dict(steps)
        self.assertEqual(commands['test'], 'flutter test test/sync_service_test.dart')
        self.assertIn('check kids_policy_check', commands)
        self.assertIn('lib/services/sync_service.dart', commands['formato'])

    def test_player_runs_its_checks(self):
        steps, _ = revisione.app_plan(['lib/player/exo_engine.dart'], self.TESTS)
        self.assertEqual(sum(label.startswith('check') for label, _ in steps), 3)

    def test_native_changes_are_declared(self):
        _, notes = revisione.app_plan(['android/app/src/main/kotlin/tv/stellar/app/MainActivity.kt'], {})
        self.assertTrue(any('fai build android' in n for n in notes))

    def test_site_plan(self):
        files = {'src/lib/kidsPolicy.test.ts': "import { x } from './kidsPolicy';", 'src/test/app-routing.test.tsx': ''}
        commands = dict(revisione.site_plan(['src/lib/kidsPolicy.ts'], files)[0])
        self.assertEqual(commands['test'], 'bun run test src/lib/kidsPolicy.test.ts')
        self.assertNotIn('build', commands)
        self.assertEqual(revisione.site_plan(['src/routes/api/public/CLAUDE.md'], files)[0], [])
        commands = dict(revisione.site_plan(['src/routes/api/public/pair.ts'], files)[0])
        self.assertIn('src/test/app-routing.test.tsx', commands['test'])
        self.assertIn('build', commands)


class TwinsTest(unittest.TestCase):
    def test_constants_compare_both_sides(self):
        app = {'lib/services/personal_vault.dart': "static const envelopeVersion = 3;"}
        site = {'src/lib/personalVault.ts': 'export const VAULT_ENVELOPE_VERSION = 2;'}
        problems = gemelle.check_constants(app.get, site.get)
        self.assertIn('versione della busta del vault: app 3 ≠ sito 2', problems)

    def test_api_routes(self):
        dart = ["Uri.parse('${SupabaseConfig.apiBase}/ratings')", "'https://x.app/api/public/tmdb'",
                "Uri.parse('${SupabaseConfig.apiBase}/nuova')"]
        missing, unused = gemelle.check_api(dart, {'ratings', 'tmdb', 'pair'})
        self.assertEqual((missing, unused), (['nuova'], ['pair']))

    def test_one_sided_changes(self):
        sides = gemelle.one_sided({'lib/services/personal_vault.dart'}, {'src/lib/tmdbVotes.ts'})
        self.assertEqual([(n, k, s) for n, k, s, _ in sides], [('vault', 'strict', 'app'), ('voti', 'contract', 'sito')])
        self.assertEqual(gemelle.one_sided({'lib/services/key_handoff.dart'}, {'src/lib/keyHandoff.ts'}), [])

    def test_fixtures_belong_to_their_own_pair(self):
        # A backup fixture is not a vault change, and the backup twins move together.
        backup = gemelle.one_sided({'test/fixtures/backup_transfer.json'}, set())
        self.assertEqual([(n, s) for n, _, s, _ in backup], [('backup sul telefono', 'app')])
        self.assertEqual(gemelle.one_sided(
            {'lib/services/backup_transfer.dart', 'test/fixtures/backup_transfer.json'},
            {'src/lib/backupTransfer.ts', 'src/lib/backupTransfer.fixture.json'}), [])
        vault = gemelle.one_sided({'test/fixtures/web_vault_v2.json'}, set())
        self.assertEqual([n for n, _, _, _ in vault], ['vault'])


class StartTest(unittest.TestCase):
    def test_handoff_fields_and_next_steps(self):
        text = '---\ntype: handoff\nautore: grok\nstatus: in-corso\nrepo: app\n---\n## Obiettivo\nx\n' \
               '## Prossimo passo\n1. Primo\n2. Secondo\n3. Terzo\n4. Quarto\n'
        fields, steps = avvio.parse_handoff(text)
        self.assertEqual((fields['autore'], fields['status']), ('grok', 'in-corso'))
        self.assertEqual(steps, ['1. Primo', '2. Secondo', '3. Terzo'])

    def test_vercel_first_row(self):
        text = '  Age     Project      Deployment                     Status      Environment     Duration\n' \
               '  30m     team/site    https://site-abc.vercel.app    ● Ready     Production      13s\n'
        self.assertEqual(avvio.parse_vercel('https://site-abc.vercel.app\n' + text), ('30m', 'Ready', 'Production'))

    def test_latest_run_per_workflow(self):
        runs = [{'workflowName': 'StellarTV Android Release', 'conclusion': 'success'},
                {'workflowName': 'StellarTV Verifica (senza rilascio)', 'conclusion': 'failure'},
                {'workflowName': 'StellarTV Verifica (senza rilascio)', 'conclusion': 'success'}]
        self.assertEqual(avvio.summarize_runs(runs)['verifica']['conclusion'], 'failure')

    def test_release_lines_after_build(self):
        self.assertEqual(pending_release_lines('- A\n- B\n', '- A\n'), ['B'])
        self.assertEqual(pending_release_lines('- A\n', '- A\n'), [])

    def test_hook_scope(self):
        self.assertFalse(avvio.hook_allows(json.dumps({'cwd': '/altrove', 'source': 'startup'})))
        self.assertFalse(avvio.hook_allows(json.dumps({'cwd': str(avvio.ROOT), 'source': 'compact'})))
        self.assertTrue(avvio.hook_allows(json.dumps({'cwd': str(avvio.APP), 'source': 'startup'})))


class DatabaseTest(unittest.TestCase):
    def test_internal_queries_are_skipped(self):
        rows = [{'query': 'SELECT e.name FROM pg_available_extensions e', 'total_exec_time': '00:00:18', 'ncalls': '45'},
                {'query': 'select set_config($1)', 'total_exec_time': '00:00:07', 'ncalls': '166,307'},
                {'query': 'SELECT "sessions"."id" FROM "auth"."sessions"', 'total_exec_time': '00:00:03', 'ncalls': '9'},
                {'query': 'SELECT "public"."kids_ratings"."key" FROM "public"."kids_ratings" '
                          'WHERE pg_catalog.count(_postgrest_t) > 0',
                 'total_exec_time': '00:00:02.5', 'prop_exec_time': '5%', 'ncalls': '1,000'}]
        lines = db_salute.query_lines(rows, 5)
        self.assertEqual(len(lines), 1)
        self.assertIn('2.5 ms/chiamata', lines[0])
        self.assertIn('SELECT kids_ratings.key FROM kids_ratings', lines[0])

    def test_findings_flag_what_matters(self):
        data = {'db-stats': [{'index_hit_rate': '0.95', 'table_hit_rate': '1.00', 'database_size': '1 GB'}],
                'table-stats': [{'name': 'public.big', 'estimated_row_count': '50,000', 'seq_scans': '900'},
                                {'name': 'public.small', 'estimated_row_count': '50', 'seq_scans': '9000'}],
                'index-stats': [{'name': 'public.idx_x', 'unused': True, 'size': '2 MB'},
                                {'name': 'public.t_pkey', 'unused': True}],
                'bloat': [{'name': 'public.t', 'bloat': '3.1', 'waste': '20 MB'}, {'name': 'public.u', 'bloat': '5', 'waste': '8 kB'}],
                'vacuum-stats': [{'name': 'public.t', 'expect_autovacuum': 'yes', 'dead_rowcount': ' 10 '}]}
        text = '\n'.join(line for _, lines in db_salute.findings(data) for line in lines)
        self.assertIn('sotto 0.99', text)
        self.assertIn('public.big', text)
        self.assertNotIn('public.small', text)
        self.assertIn('idx_x', text)
        self.assertNotIn('t_pkey', text)
        self.assertIn('bloat 3.1', text)
        self.assertNotIn('public.u', text)
        self.assertIn('10 righe morte', text)

    def test_time_parsing(self):
        self.assertAlmostEqual(db_salute.seconds('1 day 00:01:02.5'), 86462.5)


if __name__ == '__main__':
    unittest.main()
