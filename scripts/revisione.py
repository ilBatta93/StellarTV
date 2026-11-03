"""Review before push: rules checks on the diff, targeted verification, app ↔ site consistency.

Usage (from either repository, or with --repo):
  python scripts/revisione.py              changes not yet pushed + uncommitted
  python scripts/revisione.py --esegui     also runs the targeted checks
  python scripts/revisione.py --pre-push   git pre-push hook: blocking rules only
  python scripts/revisione.py --installa-hook   installs the pre-push hook in both repositories
"""
import argparse
import re
import sys
from pathlib import Path

import gemelle
from ecosistema import (APP, SITE, git, lexicon_findings, message_findings, out, parse_diff, release_status,
                        repo_kind, run, secret_findings, utf8_stdout)

ZERO = '0' * 40
CODE = re.compile(r'\.(dart|ts|tsx|java|kt)$')
DECLARATION = re.compile(
    r'^\s*(?:export\s+(?:default\s+)?(?:async\s+)?(?:function|const|class|type|interface|enum)\s+(\w+)'
    r'|(?:abstract\s+)?(?:class|enum|mixin|extension)\s+(\w+)'
    r'|(?:static\s+)?(?:Future<[^>]*>|Stream<[^>]*>|void|bool|int|double|String|Widget|[A-Z]\w*(?:<[^>]*>)?)\??\s+(\w+)\s*[(<])')
SITE_BUILD = re.compile(r'^(src/routes/|src/(server|start|router)\.tsx?$|vite\.config|package\.json|bun\.lock|tsconfig)'
                        r'|\.server\.ts$|\.functions\.ts$')
PLAYER_CHECKS = ['test/tv_playback_shortcuts_check.dart', 'test/playback_work_policy_check.dart',
                 'test/live_preview_policy_check.dart']
WIDGET_TESTS = ['test/tv_navigation_test.dart', 'test/tv_navigation_rules_test.dart', 'test/tv_home_rows_stress_test.dart']
MAX_TESTS = 25


def collect(repo, base=None, head='HEAD', include_worktree=True):
    """Diff, commit messages and changed paths from base (default: upstream) to head, plus the working tree."""
    if base is None:
        base = git(repo, 'merge-base', '@{u}', head) or git(repo, 'rev-parse', f'{head}~1')
    diff = git(repo, 'diff', '-U0', '--no-color', '--no-ext-diff', f'{base}..{head}') if base else ''
    if include_worktree:
        diff += '\n' + git(repo, 'diff', '-U0', '--no-color', '--no-ext-diff', 'HEAD')
        for untracked in git(repo, 'ls-files', '--others', '--exclude-standard').splitlines():
            path = Path(repo) / untracked
            if path.is_file() and path.stat().st_size < 500_000:
                lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
                diff += f'\ndiff --git a/{untracked} b/{untracked}\n--- /dev/null\n+++ b/{untracked}\n@@ -0,0 +1 @@\n'
                diff += '\n'.join('+' + line for line in lines)
    messages = git(repo, 'log', '--format=%s%n%b%x00', f'{base}..{head}').split('\x00') if base else []
    status = git(repo, 'diff', '--name-status', f'{base}..{head}') if base else ''
    return parse_diff(diff), [m.strip() for m in messages if m.strip()], status


def rule_findings(files, messages):
    blocking, warnings = [], []
    for path, change in files.items():
        b, w = secret_findings(path, change['added'])
        blocking += b
        warnings += w
        b, w = lexicon_findings(path, change['added'])
        blocking += b
        warnings += w
    blocking += message_findings(messages)
    return blocking, warnings


def removed_symbols(files):
    """Declarations that disappear from a file without coming back anywhere in the diff (master §6)."""
    added_all = set()
    for change in files.values():
        for _, text in change['added']:
            match = DECLARATION.match(text)
            if match:
                added_all.add(next(g for g in match.groups() if g))
    gone = []
    for path, change in files.items():
        if not CODE.search(path):
            continue
        for text in change['removed']:
            match = DECLARATION.match(text)
            if match:
                name = next(g for g in match.groups() if g)
                if name not in added_all and not name.startswith('_') and f'{path}: {name}' not in gone:
                    gone.append(f'{path}: {name}')
    return gone


def app_plan(paths, test_files):
    """Targeted commands for the app; test_files maps a test path to its content (for import lookup)."""
    dart = [p for p in paths if p.endswith('.dart') and p.startswith(('lib/', 'test/'))]
    steps, notes = [], []
    if dart:
        steps.append(('analisi', 'flutter analyze --no-fatal-infos lib test'))
        steps.append(('formato', 'dart format --output=none --set-exit-if-changed ' + ' '.join(sorted(dart))))
    tests, checks = set(), set()
    for path in dart:
        name = Path(path).stem
        if path.endswith('_test.dart'):
            tests.add(path)
        elif path.endswith('_check.dart'):
            checks.add(path)
        else:
            for test_path, content in test_files.items():
                if f'/{name}.dart' in content or test_path == f'test/{name}_test.dart':
                    (checks if test_path.endswith('_check.dart') else tests).add(test_path)
            if f'test/{name}_check.dart' in test_files:
                checks.add(f'test/{name}_check.dart')
        if path.startswith('lib/player/'):
            checks.update(c for c in PLAYER_CHECKS if c in test_files)
        if path.startswith('lib/widgets/'):
            tests.update(t for t in WIDGET_TESTS if t in test_files)
        if path.startswith('lib/screens/tv_') and 'test/tv_render_policy_check.dart' in test_files:
            checks.add('test/tv_render_policy_check.dart')
    if tests:
        ordered = sorted(tests)
        if len(ordered) > MAX_TESTS:
            notes.append(f'{len(ordered)} file di test collegati: eseguo i primi {MAX_TESTS}, il resto lo copre la CI')
            ordered = ordered[:MAX_TESTS]
        steps.append(('test', 'flutter test ' + ' '.join(ordered)))
    for check in sorted(checks):
        steps.append((f'check {Path(check).stem}', f'dart run {check}'))
    if any(p.startswith('scripts/') and p.endswith('.py') for p in paths):
        steps.append(('script', 'python -m unittest discover -s scripts -p "*_test.py"'))
    if any(p.startswith('packages/video_player_android/lib/') or p.startswith('packages/video_player_android/test/')
           for p in paths):
        steps.append(('fork video', 'cd packages/video_player_android && flutter test'))
    if any(p.startswith('packages/') and p.endswith('.java') for p in paths) or \
            any(p.startswith('android/') and not p.endswith('.md') for p in paths):
        notes.append('Java/Kotlin/Gradle toccati: si compilano solo con «fai build android», dichiarali non compilati')
    if any(p.startswith('ios/') and not p.endswith('.md') for p in paths):
        notes.append('iOS toccato: si compila solo nel workflow iOS')
    if any(p.startswith('.github/workflows/') for p in paths):
        notes.append('workflow toccato: provalo con una run di verify.yml')
    return steps, notes


def site_plan(paths, site_files):
    """Targeted commands for the site; site_files maps a test path to its content."""
    code = [p for p in paths if re.search(r'\.(ts|tsx)$', p) and p.startswith('src/')]
    steps, tests = [], set()
    for path in code:
        if re.search(r'\.test\.tsx?$', path):
            tests.add(path)
            continue
        stem = re.sub(r'\.tsx?$', '', path)
        name = Path(stem).name
        for test_path, content in site_files.items():
            if test_path in (f'{stem}.test.ts', f'{stem}.test.tsx') or re.search(rf'["\'/]{re.escape(name)}["\']', content):
                tests.add(test_path)
        if path.startswith('src/routes/'):
            tests.add('src/test/app-routing.test.tsx')
    if tests:
        steps.append(('test', 'bun run test ' + ' '.join(sorted(tests)[:MAX_TESTS])))
    if code or any(p.endswith(('.js', '.json')) for p in paths):
        steps.append(('lint', 'bun run lint'))
    if any(SITE_BUILD.search(p) and not p.endswith('.md') for p in paths):
        steps.append(('build', 'bun run build'))
    return steps, []


def test_sources(repo, kind):
    if kind == 'app':
        files = list((repo / 'test').rglob('*_test.dart')) + list((repo / 'test').glob('*_check.dart'))
    else:
        files = [p for p in (repo / 'src').rglob('*.test.ts*')]
    return {p.relative_to(repo).as_posix(): p.read_text(encoding='utf-8', errors='replace') for p in files}


def reminders(kind, paths, status):
    """Documents and twins that usually follow the change."""
    notes = []
    if kind == 'app':
        status_info = release_status() if any(p.startswith(('lib/', 'packages/')) and not p.endswith('.md')
                                              for p in paths) else None
        if status_info is not None and status_info[1] and not status_info[0]:
            notes.append('docs/release-current.md non ha righe nuove dopo l\'ultima build: la prossima si fermerà')
        if any(p.startswith(('lib/screens/', 'lib/widgets/')) for p in paths):
            guide = git(SITE, 'log', '--since=1.day', '--format=%h', '--', 'src/lib/guideContent.ts') or \
                git(SITE, 'diff', '--name-only', 'HEAD', '--', 'src/lib/guideContent.ts')
            if not guide:
                notes.append('schermate o widget toccati: se il comportamento visibile cambia, aggiorna la guida del sito')
    else:
        added_routes = [line.split()[-1] for line in status.splitlines()
                        if line[:1] in 'ADR' and 'src/routes/' in line and not line.endswith('CLAUDE.md')]
        if added_routes and 'src/routeTree.gen.ts' not in paths:
            notes.append('rotte aggiunte o spostate senza src/routeTree.gen.ts nel commit')
        if 'src/lib/guideContent.ts' in paths:
            notes.append('guida cambiata: hai aggiornato GUIDE_APP_VERSION?')
    if any(re.match(r'docs/[^/]+\.sql$', p) for p in paths):
        types = git(SITE, 'log', '--since=1.day', '--format=%h', '--', 'src/integrations/external/types.ts') or \
            git(SITE, 'diff', '--name-only', 'HEAD', '--', 'src/integrations/external/types.ts')
        if not types:
            notes.append('SQL cambiato: aggiorna src/integrations/external/types.ts del sito se cambia lo schema')
        notes.append('SQL cambiato: dopo l\'esecuzione, python scripts/db_salute.py per vedere l\'effetto')
    return notes


def execute(repo, steps):
    failed = 0
    for label, command in steps:
        code, text = run(command, cwd=repo, timeout=900)
        if code == 0:
            out(f'  ✓ {label}')
        else:
            failed += 1
            out(f'  ✗ {label} (uscita {code}): {command}')
            for line in text.strip().splitlines()[-25:]:
                out(f'      {line}')
    return failed


def review(repo, execute_steps):
    kind = repo_kind(repo)
    files, messages, status = collect(repo)
    paths = sorted(files)
    out(f'Revisione {kind} ({repo.name}): {len(paths)} file, {len(messages)} commit non ancora spinti')
    if not paths:
        out('  nessuna modifica da rivedere')
        return 0
    blocking, warnings = rule_findings(files, messages)
    gone = removed_symbols(files)
    sources = test_sources(repo, kind)
    steps, notes = app_plan(paths, sources) if kind == 'app' else site_plan(paths, sources)
    notes += reminders(kind, paths, status)

    out('Regole')
    for line in blocking:
        out(f'  ✗ {line}')
    for line in warnings[:15]:
        out(f'  ! {line}')
    if len(warnings) > 15:
        out(f'  ! … altri {len(warnings) - 15} avvisi')
    if not blocking and not warnings:
        out('  ✓ lessico neutro e segreti')
    if gone:
        out('Simboli rimossi o rinominati (master §6: confermali)')
        for line in gone[:15]:
            out(f'  ? {line}')
    for note in notes:
        out(f'  · {note}')

    # Only pairs touched by the changes under review; the other side counts its last day of work.
    gemelle_problems = gemelle.report(
        *((paths, gemelle.changed_since(SITE, 1)) if kind == 'app' else (gemelle.changed_since(APP, 1), paths)),
        only_side=kind)

    out('Verifiche mirate' + ('' if execute_steps else ' (aggiungi --esegui per lanciarle)'))
    if not steps:
        out('  nessun test collegato ai file toccati')
    failed = execute(repo, steps) if execute_steps else 0
    if not execute_steps:
        for label, command in steps:
            out(f'  - {label}: {command}')
    return len(blocking) + gemelle_problems + failed


def pre_push(repo, stdin_lines):
    """Blocking rules only, on the commits being pushed. Fast, no tests."""
    blocking = []
    for line in stdin_lines:
        parts = line.split()
        if len(parts) != 4 or parts[1] == ZERO:
            continue
        local_sha, remote_sha = parts[1], parts[3]
        base = remote_sha if remote_sha != ZERO else (git(repo, 'merge-base', 'origin/main', local_sha) or None)
        files, messages, _ = collect(repo, base=base, head=local_sha, include_worktree=False)
        found, _ = rule_findings(files, messages)
        blocking += found
    if blocking:
        out('Push fermato da scripts/revisione.py (master §4 e §5):')
        for line in blocking:
            out(f'  ✗ {line}')
        out('Correggi e rifai il commit. Se è un falso positivo, dillo all\'utente: decide lui.')
    return 1 if blocking else 0


HOOK = '''#!/bin/sh
# Installed by StellarTV/scripts/revisione.py --installa-hook: lexicon and secret rules before every push.
exec python "{script}" --pre-push --repo "$(git rev-parse --show-toplevel)"
'''


def install_hooks():
    script = Path(__file__).resolve().as_posix()
    for repo in (APP, SITE):
        hooks = Path(git(repo, 'rev-parse', '--absolute-git-dir') or repo / '.git') / 'hooks'
        target = hooks / 'pre-push'
        if target.exists() and 'revisione.py' not in target.read_text(encoding='utf-8', errors='replace'):
            out(f'{target}: esiste già un hook diverso, non lo sovrascrivo')
            continue
        target.write_text(HOOK.format(script=script), encoding='utf-8', newline='\n')
        target.chmod(0o755)
        out(f'hook installato: {target}')


def main():
    utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--repo', help='repository da rivedere (default: quello della cartella corrente)')
    parser.add_argument('--esegui', action='store_true', help='esegue le verifiche mirate')
    parser.add_argument('--pre-push', action='store_true', help='modalità hook git: solo regole bloccanti')
    parser.add_argument('--installa-hook', action='store_true', help='installa il pre-push nei due repository')
    args = parser.parse_args()
    if args.installa_hook:
        install_hooks()
        return
    repo = Path(args.repo or git(Path.cwd(), 'rev-parse', '--show-toplevel') or APP).resolve()
    if repo_kind(repo) is None:
        out(f'{repo} non è né l\'app né il sito')
        sys.exit(2)
    if args.pre_push:
        sys.exit(pre_push(repo, sys.stdin.read().splitlines()))
    sys.exit(1 if review(repo, args.esegui) else 0)


if __name__ == '__main__':
    main()
