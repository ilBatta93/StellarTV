"""Generate neutral, change-scoped release notes; never publish raw commits."""
import re
import subprocess
from pathlib import Path

BLOCKED = re.compile(r'\b(iptv|xtream|provider|playlist|film|serie|password|token)\b', re.I)

def bullets(text):
    lines = [line[2:].strip() for line in text.splitlines() if line.startswith('- ')]
    if not lines or any(BLOCKED.search(line) for line in lines):
        raise ValueError('Release notes must contain neutral feature bullets')
    return lines

def fresh_lines(current_text, previous_text):
    """Bullets present now and absent from the previous release."""
    current = bullets(current_text)
    if not previous_text.strip():
        return current
    try:
        previous = set(bullets(previous_text))
    except ValueError:
        previous = set()
    fresh = [line for line in current if line not in previous]
    if not fresh:
        raise ValueError('Release notes must describe what changed since the previous build')
    return fresh

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
    tags = git('tag', '--list', 'v3.*', '--sort=-v:refname').splitlines()
    previous = next((t for t in tags if t != 'v' + version), None)
    scope = previous + '..HEAD' if previous else 'HEAD'
    commits = git('log', '--reverse', '--format=%H', scope, '--', 'docs/release-current.md').splitlines()
    changed = git('diff', '--name-only', previous, 'HEAD') if previous else ''
    if not commits and any(p.startswith('lib/') for p in changed.splitlines()):
        raise ValueError('Update docs/release-current.md for this build before publishing')
    current_text = Path('docs/release-current.md').read_text()
    bullets(current_text)
    previous_text = ''
    if previous:
        try:
            previous_text = git('show', previous + ':docs/release-current.md')
        except subprocess.CalledProcessError:
            previous_text = ''
    Path('RELEASE_NOTES.md').write_text(render(version, fresh_lines(current_text, previous_text)))

if __name__ == '__main__':
    main()
