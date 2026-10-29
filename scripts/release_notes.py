"""Generate neutral, change-scoped release notes; never publish raw commits."""
import re
import subprocess
from pathlib import Path

BLOCKED = re.compile(r'\b(iptv|xtream|provider|playlist|film|serie|password|token)\b', re.I)

def bullet_lines(text):
    return [line[2:].strip() for line in text.splitlines() if line.startswith('- ') and line[2:].strip()]

def bullets(text):
    lines = bullet_lines(text)
    if not lines or any(BLOCKED.search(line) for line in lines):
        raise ValueError('Release notes must contain neutral feature bullets')
    return lines

def fresh_lines(current_text, previous_text):
    """Bullets present now and absent from the file at the last built commit."""
    current = bullets(current_text)
    if not previous_text.strip():
        return current
    previous = set(bullet_lines(previous_text))
    return [line for line in current if line not in previous]

def previous_build_sha(runs, current_run_id=None):
    """Commit of the newest successful build that is not the one publishing now."""
    current = str(current_run_id) if current_run_id else ''
    for run in runs:
        if current and str(run.get('databaseId')) == current:
            continue
        sha = str(run.get('headSha') or '').strip()
        if sha:
            return sha
    return None

def select_notes(current_text, previous_text, changed_paths):
    """Notes are only the bullets added since the last built commit."""
    lines = fresh_lines(current_text, previous_text)
    if not lines and any(path.startswith('lib/') for path in changed_paths):
        raise ValueError('Update docs/release-current.md for this build before publishing')
    return lines

def render(version, lines):
    body = '\n'.join('- ' + line[:140] for line in lines)
    return (f'## StellarTV v{version}\n\n<!-- stellar-summary -->\n{body}\n'
            '<!-- /stellar-summary -->\n')

def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()

SERIES_FROM_RUN = 110  # run 110 publishes 3.8.0

def series_version(version, run_number):
    """3.8.N from build 108 on; older runs keep the version they received."""
    if run_number is not None and run_number >= SERIES_FROM_RUN:
        return f'3.8.{run_number - SERIES_FROM_RUN}'
    return version

def _workflow_runs(workflow, branch):
    import json
    command = ['gh', 'run', 'list', '--workflow', workflow, '--status', 'success',
               '--limit', '20', '--json', 'databaseId,headSha']
    if branch:
        command.extend(['--branch', branch])
    try:
        raw = subprocess.check_output(command, text=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as error:
        raise ValueError('Impossibile leggere il commit dell\'ultima build') from error
    return json.loads(raw)

def successful_runs():
    """Successful runs of this workflow, newest first. None outside CI."""
    import os
    workflow = os.environ.get('GITHUB_WORKFLOW', '')
    if not os.environ.get('GITHUB_RUN_ID') or not workflow:
        return None
    branch = os.environ.get('GITHUB_REF_NAME', '')
    return _workflow_runs(workflow, branch) or _workflow_runs(workflow, '')

def notes_at(commit):
    if not commit:
        return ''
    try:
        return git('show', commit + ':docs/release-current.md')
    except subprocess.CalledProcessError as error:
        raise ValueError('Il commit dell\'ultima build non è in questo ramo') from error

def main():
    import os
    import sys
    run = os.environ.get('GITHUB_RUN_NUMBER')
    version = series_version(sys.argv[1], int(run) if run and run.isdigit() else None)
    env_file = os.environ.get('GITHUB_ENV')
    if env_file and version != sys.argv[1]:
        # Later GITHUB_ENV lines win: the APK, tag and release use 3.8.N.
        with open(env_file, 'a') as f:
            f.write(f'VERSION={version}\n')
    runs = successful_runs()
    baseline = previous_build_sha(runs or [], os.environ.get('GITHUB_RUN_ID'))
    if not baseline:
        # Fallback: latest production tag (v3.8.X), regardless of branch.
        tags = git('tag', '--list', 'v3.*', '--sort=-v:refname').splitlines()
        previous = next((t for t in tags if t != 'v' + version), None)
        if previous:
            baseline = git('rev-parse', previous + '^{commit}')
    if os.environ.get('GITHUB_RUN_ID') and not baseline:
        raise ValueError('Manca il commit dell\'ultima build')
    current_text = Path('docs/release-current.md').read_text()
    previous_text = notes_at(baseline)
    changed = git('diff', '--name-only', baseline, 'HEAD').splitlines() if baseline else []
    Path('RELEASE_NOTES.md').write_text(
        render(version, select_notes(current_text, previous_text, changed)),
    )

if __name__ == '__main__':
    main()