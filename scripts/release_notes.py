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

def _neutral(text):
    try:
        bullets(text)
        return True
    except ValueError:
        return False

def render(version, texts):
    lines = list(dict.fromkeys(line for text in texts for line in bullets(text)))
    summary = '\n'.join('- ' + line[:140] for line in lines[:3])
    return (f'## StellarTV v{version}\n\n<!-- stellar-summary -->\n{summary}\n'
            '<!-- /stellar-summary -->\n\n## Modifiche\n\n' +
            '\n'.join('- ' + line for line in lines) + '\n')

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
    texts = [git('show', c + ':docs/release-current.md') for c in commits]
    if texts:
        # A later commit may replace non-neutral wording: keep only valid
        # versions, but the current file must always be valid itself.
        bullets(texts[-1])
        texts = [t for t in texts if _neutral(t)]
    if not texts:
        texts = [Path('docs/release-current.md').read_text()]
    Path('RELEASE_NOTES.md').write_text(render(version, texts))

if __name__ == '__main__':
    main()
