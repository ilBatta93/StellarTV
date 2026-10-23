import unittest
from release_notes import render

class NotesTest(unittest.TestCase):
    def test_summary_is_three_changes_and_complete_notes_kept(self):
        output = render('3.6.22', ['- Prima modifica\n- Seconda modifica\n- Terza modifica\n- Quarta modifica'])
        summary = output.split('<!-- stellar-summary -->')[1].split('<!-- /stellar-summary -->')[0]
        self.assertEqual(summary.count('- '), 3)
        self.assertIn('Quarta modifica', output)
    def test_unsafe_source_words_fail(self):
        with self.assertRaises(ValueError):
            render('3.6.22', ['- Aggiornamento provider'])
    def test_notes_deduplicate_changes_between_builds(self):
        output = render('3.6.22', ['- Navigazione migliorata', '- Navigazione migliorata\n- Lettura migliorata'])
        self.assertEqual(output.split('## Modifiche')[1].count('Navigazione migliorata'), 1)

if __name__ == '__main__': unittest.main()
