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

def main():
    import sys
    version = sys.argv[1]
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
