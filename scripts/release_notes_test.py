import unittest
from release_notes import fresh_lines, previous_build_sha, render, select_notes, series_version

class NotesTest(unittest.TestCase):
    def test_series_38_starts_at_build_108(self):
        self.assertEqual(series_version('3.7.20', 110), '3.8.0')
        self.assertEqual(series_version('3.7.21', 111), '3.8.1')
        self.assertEqual(series_version('3.7.16', 106), '3.7.16')
    def test_notes_list_every_new_change_once(self):
        output = render('3.8.10', ['Ordine per voto aggiornato', 'Risoluzione separata dal voto'])
        self.assertNotIn('## Modifiche', output)
        summary = output.split('<!-- stellar-summary -->')[1].split('<!-- /stellar-summary -->')[0]
        self.assertEqual(summary.count('- '), 2)
        self.assertEqual(output.count('Ordine per voto aggiornato'), 1)
    def test_unsafe_source_words_fail(self):
        with self.assertRaises(ValueError):
            fresh_lines('- Aggiornamento provider', '')
    def test_notes_keep_only_lines_absent_from_the_previous_release(self):
        fresh = fresh_lines('- Nuova voce\n- Voce già pubblicata\n', '- Voce già pubblicata\n')
        self.assertEqual(fresh, ['Nuova voce'])
    def test_notes_after_the_last_built_commit_drop_older_lines(self):
        current = '- Voce nuova\n- Voce del commit già compilato\n- Altra voce vecchia\n'
        built = '- Voce del commit già compilato\n- Altra voce vecchia\n'
        self.assertEqual(select_notes(current, built, ['lib/main.dart']), ['Voce nuova'])
    def test_library_change_without_a_new_line_fails(self):
        with self.assertRaises(ValueError):
            select_notes('- Voce già pubblicata\n', '- Voce già pubblicata\n', ['lib/main.dart'])
    def test_unchanged_notes_are_empty_when_the_library_did_not_change(self):
        self.assertEqual(
            select_notes('- Voce già pubblicata\n', '- Voce già pubblicata\n', ['scripts/release_notes.py']),
            [],
        )
    def test_rule_files_inside_lib_do_not_require_a_new_line(self):
        self.assertEqual(
            select_notes('- Voce già pubblicata\n', '- Voce già pubblicata\n', ['lib/CLAUDE.md']),
            [],
        )
    def test_previous_build_is_the_newest_successful_commit(self):
        runs = [
            {'databaseId': 9, 'headSha': 'current'},
            {'databaseId': 8, 'headSha': 'last-built'},
            {'databaseId': 7, 'headSha': 'older'},
        ]
        self.assertEqual(previous_build_sha(runs, 9), 'last-built')
        self.assertEqual(previous_build_sha([{'databaseId': 1, 'headSha': ''}], None), None)

if __name__ == '__main__': unittest.main()
