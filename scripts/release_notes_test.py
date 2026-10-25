import unittest
from release_notes import fresh_lines, render, series_version

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

if __name__ == '__main__': unittest.main()
