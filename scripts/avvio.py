"""Session start summary for both repositories, in about 25 lines.

Aligns each repository (fetch, then pull --ff-only only when clean and behind), and reports:
recent commits, latest handoff and work done after it, CI and release, site deploy, release notes, new TODOs.

Usage: python scripts/avvio.py           (also run by the SessionStart hook with --hook)
"""
import argparse
import json
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

from ecosistema import APP, HANDOFF, ROOT, SITE, git, out, parse_diff, release_status, run, utf8_stdout

TODO = re.compile(r'\b(TODO|FIXME)\b')


def align(repo):
    """Fetch and fast-forward when safe. Returns a one-line state."""
    if not repo.exists():
        return f'{repo.name}: cartella assente'
    fetched = run(['git', '-C', str(repo), 'fetch', '--quiet'], timeout=25)[0] == 0
    counts = git(repo, 'rev-list', '--left-right', '--count', 'HEAD...@{u}').split()
    ahead, behind = (int(counts[0]), int(counts[1])) if len(counts) == 2 else (0, 0)
    dirty = [line[3:] for line in git(repo, 'status', '--porcelain').splitlines()]
    pulled = ''
    if behind and not ahead and not dirty:
        if run(['git', '-C', str(repo), 'pull', '--ff-only', '--quiet'], timeout=40)[0] == 0:
            pulled, behind = f'aggiornato con {behind} commit dal remoto', 0
    parts = [] if fetched else ['fetch non riuscito']
    if pulled:
        parts.append(pulled)
    if ahead:
        parts.append(f'{ahead} commit da spingere')
    if behind:
        parts.append(f'{behind} commit indietro, pull non fatto perché ci sono modifiche locali')
    if dirty:
        shown = ', '.join(dirty[:4]) + (f' … (+{len(dirty) - 4})' if len(dirty) > 4 else '')
        parts.append(f'{len(dirty)} file modificati: {shown}')
    return f'{repo.name}: ' + ('; '.join(parts) if parts else 'allineato al remoto, pulito')


def parse_handoff(text):
    """Front matter fields plus the first lines of «Prossimo passo»."""
    fields = dict(re.findall(r'^(\w+):\s*(.+)$', text.split('\n---', 2)[0] if text.startswith('---') else '', re.M))
    section = re.search(r'^## Prossimo passo\s*\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    steps = [line.strip() for line in (section.group(1) if section else '').splitlines() if line.strip()]
    return fields, steps[:3]


def latest_handoff():
    files = sorted(HANDOFF.glob('*.md'), key=lambda p: p.stat().st_mtime, reverse=True) if HANDOFF.exists() else []
    return files[0] if files else None


def commits_after(repo, moment):
    log = git(repo, 'log', f'--since={moment.isoformat()}', '--format=%h %s')
    return [line for line in log.splitlines() if line]


def summarize_runs(runs):
    """Latest verify run, latest Android build and latest iOS build from `gh run list` JSON."""
    picked = {}
    for item in runs:
        name = item.get('workflowName', '')
        key = 'verifica' if 'Verifica' in name else 'android' if 'Android' in name else 'ios' if 'iOS' in name else None
        if key and key not in picked:
            picked[key] = item
    return picked


def run_line(label, item):
    if not item:
        return f'{label}: nessuna run'
    state = item.get('conclusion') or item.get('status')
    mark = '✓' if state == 'success' else '…' if item.get('status') != 'completed' else '✗'
    return f'{label} {mark} {state} ({item.get("createdAt", "")[5:16].replace("T", " ")})'


def verify_failures(run_id):
    """Annotation «Esiti» and error annotations of a failed verify run."""
    code, text = run(['gh', 'run', 'view', str(run_id), '-R', 'ilBatta93/StellarTV', '--json', 'jobs'], timeout=25)
    try:
        job = json.loads(text)['jobs'][0]['databaseId'] if code == 0 else None
    except (ValueError, KeyError, IndexError):
        job = None
    if not job:
        return []
    code, text = run(['gh', 'api', f'repos/ilBatta93/StellarTV/check-runs/{job}/annotations'], timeout=25)
    try:
        notes = json.loads(text) if code == 0 else []
    except ValueError:
        return []
    return [f'{n.get("title")}: {n.get("message", "").splitlines()[0][:140]}' for n in notes
            if n.get('annotation_level') == 'failure' or n.get('title') == 'Esiti']


def ci_state():
    code, text = run(['gh', 'run', 'list', '-R', 'ilBatta93/StellarTV', '-L', '15', '--json',
                      'databaseId,workflowName,conclusion,status,createdAt,headSha'], timeout=25)
    try:
        runs = json.loads(text) if code == 0 else []
    except ValueError:
        runs = []
    picked = summarize_runs(runs)
    lines = ['  ' + ' · '.join(run_line(label, picked.get(key)) for key, label in
                               (('verifica', 'Verifica'), ('android', 'Android'), ('ios', 'iOS')))] if runs else \
        ['  CI non leggibile (gh non autenticato o rete assente)']
    verify = picked.get('verifica')
    if verify and verify.get('conclusion') not in (None, 'success'):
        lines += [f'    {line}' for line in verify_failures(verify['databaseId'])]
    code, text = run(['gh', 'release', 'list', '-R', 'ilBatta93/StellarTV-releases', '-L', '1', '--json',
                      'tagName,publishedAt'], timeout=25)
    try:
        release = json.loads(text)[0] if code == 0 else None
    except (ValueError, IndexError):
        release = None
    if release:
        lines.append(f'  Ultima release {release["tagName"]} del {release["publishedAt"][:10]}')
    build_sha = next((r['headSha'] for r in runs if 'Android' in r.get('workflowName', '')
                      and r.get('conclusion') == 'success'), None)
    return lines, build_sha


def parse_vercel(text):
    """First deployment row of `vercel ls`: (age, status, environment) or None.

    Without a terminal the CLI prints bare URLs on stdout and the table on stderr: only table rows have «●».
    """
    for line in text.splitlines():
        if 'https://' in line and '●' in line:
            cells = [c for c in re.split(r'\s{2,}', line.strip()) if c]
            status = next((c.replace('●', '').strip() for c in cells if '●' in c), '?')
            env = next((c for c in cells if c in ('Production', 'Preview')), '')
            return cells[0], status, env
    return None


def site_deploy():
    if not SITE.exists():
        return '  Sito: cartella assente'
    code, text = run(['vercel', 'ls'], cwd=SITE, timeout=25)
    row = parse_vercel(text) if code == 0 else None
    if not row:
        return '  Sito: stato del deploy non leggibile'
    age, status, env = row
    mark = '✓' if status == 'Ready' else '✗' if status in ('Error', 'Canceled') else '…'
    return f'  Sito: ultimo deploy{" " + env if env else ""} {mark} {status}, {age} fa'


def release_line(build_sha):
    try:
        status = release_status(build_sha)
    except OSError:
        status = None
    if status is None:
        return None
    pending, changed = status
    if pending:
        return f'  Note di rilascio: {len(pending)} righe pronte per la prossima build'
    if changed:
        return (f'  Note di rilascio: {len(changed)} file dell\'app cambiati dopo l\'ultima build e nessuna riga nuova '
                'in docs/release-current.md (la build si fermerebbe)')
    return '  Note di rilascio: nulla da pubblicare, docs/release-current.md contiene solo righe già uscite'


def new_todos(repo, days=7):
    files = parse_diff(git(repo, 'log', f'--since={days}.days', '-p', '-U0', '--no-color', '--format='))
    found = []
    for path, change in files.items():
        if path.endswith('.md'):
            continue
        found += [f'{repo.name}/{path}:{n}' for n, text in change['added'] if TODO.search(text)]
    return found


def summary():
    with ThreadPoolExecutor(max_workers=4) as pool:
        ci_future = pool.submit(ci_state)
        deploy_future = pool.submit(site_deploy)
        aligned = list(pool.map(align, (APP, SITE)))
        ci_lines, build_sha = ci_future.result()
        deploy = deploy_future.result()

    out(f'Riepilogo di avvio StellarTV — {datetime.now().strftime("%d/%m %H:%M")}')
    out('Repository')
    for line in aligned:
        out(f'  {line}')

    handoff = latest_handoff()
    if handoff:
        fields, steps = parse_handoff(handoff.read_text(encoding='utf-8', errors='replace'))
        moment = datetime.fromtimestamp(handoff.stat().st_mtime, tz=timezone.utc)
        out(f'Ultimo handoff: {handoff.name} ({fields.get("autore", "?")}, {fields.get("status", "?")}, '
            f'repo {fields.get("repo", "?")})')
        if fields.get('status', '').strip() == 'in-corso':
            for step in steps:
                out(f'  {step[:160]}')
        after = {repo.name: commits_after(repo, moment) for repo in (APP, SITE) if repo.exists()}
        total = sum(len(v) for v in after.values())
        if total:
            out(f'  ! {total} commit dopo questo handoff e nessun handoff che li descriva:')
            for name, commits in after.items():
                if commits:
                    out(f'    {name}: ' + ' | '.join(c.split(' ', 1)[1][:55] for c in commits[:4])
                        + (f' … (+{len(commits) - 4})' if len(commits) > 4 else ''))
    else:
        out('Ultimo handoff: nessuno in StellarTV/docs/handoff/')
        for repo in (APP, SITE):
            recent = git(repo, 'log', '-3', '--format=%h %s').splitlines()
            out(f'  {repo.name}: ' + ' | '.join(recent))

    out('CI e rilascio')
    for line in ci_lines:
        out(line)
    note = release_line(build_sha)
    if note:
        out(note)
    out(deploy)

    todos = [t for repo in (APP, SITE) if repo.exists() for t in new_todos(repo)]
    if todos:
        out(f'TODO/FIXME aggiunti negli ultimi 7 giorni: {len(todos)}')
        for todo in todos[:5]:
            out(f'  {todo}')


def hook_allows(stdin_text):
    """SessionStart hook: only inside C:\\Progetti, never after a compaction."""
    try:
        data = json.loads(stdin_text or '{}')
    except ValueError:
        data = {}
    if data.get('source') == 'compact':
        return False
    cwd = os.path.normcase(os.path.abspath(data.get('cwd') or os.getcwd()))
    return cwd.startswith(os.path.normcase(str(ROOT)))


def main():
    utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--hook', action='store_true', help='modalità hook SessionStart (legge il JSON da stdin)')
    args = parser.parse_args()
    if args.hook and not hook_allows(sys.stdin.read()):
        return
    summary()


if __name__ == '__main__':
    main()
