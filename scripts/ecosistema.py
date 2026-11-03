"""Shared helpers for the session tools: paths, git diff parsing, lexicon and secret rules."""
import base64
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

# The release build refuses these words in the notes: the review reads the same list.
from release_notes import BLOCKED as RELEASE_BLOCKED

APP =Path(__file__).resolve().parents[1]
ROOT = APP.parent
SITE = ROOT / 'stellartv-ae76efd2'
HANDOFF = APP / 'docs' / 'handoff'

# Master §4. m3u8 is the HLS format and stays allowed; the playlist form does not.
FORBIDDEN = re.compile(r'\b(iptv|xtream(?:\s+codes)?|m3u|abbonament[oi]|provider|copyright)\b', re.I)
# In code, legacy identifiers keep their names: only these words are worth flagging.
FORBIDDEN_CODE = re.compile(r'\b(iptv|xtream(?:\s+codes)?|m3u|abbonament[oi])\b', re.I)
# Files that name the forbidden words on purpose, to forbid them.
LEXICON_EXEMPT = re.compile(r'(^|/)(CLAUDE|AGENTS)\.md$|(^|/)scripts/[^/]+\.py$')
# Text that reaches users or public history: a forbidden word here blocks the push.
PUBLIC_TEXT = re.compile(r'\.md$|(^|/)guideContent\.ts$')
RELEASE_NOTES = 'docs/release-current.md'

STRONG_SECRETS = [
    ('chiave privata', re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----')),
    ('chiave segreta Supabase', re.compile(r'\bsb_secret_[A-Za-z0-9_-]{10,}')),
    ('token GitHub', re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})')),
    ('chiave AWS', re.compile(r'\bAKIA[0-9A-Z]{16}\b')),
    ('chiave API', re.compile(r'\bsk-(?:ant-|proj-)?[A-Za-z0-9_-]{24,}')),
]
WEAK_SECRET = re.compile(
    r'(?i)\b\w*(service_role|secret|password|passwd|api_?key|private_?key)\w*\s*[:=]\s*["\'][^"\'\s]{12,}["\']')
JWT = re.compile(r'eyJ[A-Za-z0-9_-]{10,}\.(eyJ[A-Za-z0-9_-]{10,})\.[A-Za-z0-9_-]{10,}')
SECRET_FILES = re.compile(
    r'(^|/)(key\.properties|[^/]*\.(jks|keystore|p12|mobileprovision)|\.env\.[^/]+|service-account[^/]*\.json)$')
# The site .env is versioned with public values only (master §5).
PUBLIC_ENV = re.compile(r'(^|/)\.env$')
PRIVATE_ENV_NAME = re.compile(r'^\s*\w*(SERVICE_ROLE|SECRET|PRIVATE)\w*\s*=', re.I)


def out(text=''):
    print(text, flush=True)


def utf8_stdout():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding='utf-8')
        except (AttributeError, ValueError):
            pass


def run(cmd, cwd=None, timeout=60):
    """Run a command; returns (exit code, combined output). Never raises."""
    if isinstance(cmd, str):
        args, shell = cmd, True
    else:
        exe = shutil.which(cmd[0])
        if not exe:
            return 127, f'{cmd[0]} non trovato'
        args, shell = [exe, *cmd[1:]], False
    try:
        done = subprocess.run(args, cwd=cwd, shell=shell, capture_output=True, timeout=timeout,
                              encoding='utf-8', errors='replace')
    except subprocess.TimeoutExpired:
        return 124, f'tempo scaduto dopo {timeout} s'
    except OSError as error:
        return 126, str(error)
    return done.returncode, (done.stdout or '') + (done.stderr or '')


def git(repo, *args, timeout=60):
    code, text = run(['git', '-C', str(repo), *args], timeout=timeout)
    return text.strip() if code == 0 else ''


def repo_kind(path):
    path = Path(path).resolve()
    if (path / 'pubspec.yaml').exists():
        return 'app'
    if (path / 'package.json').exists():
        return 'sito'
    return None


def parse_diff(text):
    """Unified diff with -U0 → {path: {'added': [(line, text)], 'removed': [text]}}."""
    files, current, source, line_no = {}, None, None, 0
    for raw in text.splitlines():
        if raw.startswith('diff --git '):
            current = source = None
        elif raw.startswith('--- ') and current is None:
            name = raw[4:].strip()
            source = None if name == '/dev/null' else name[2:] if name.startswith('a/') else name
        elif raw.startswith('+++ ') and current is None:
            name = raw[4:].strip()
            # A deleted file has +++ /dev/null: its removed lines belong to the old path.
            current = source if name == '/dev/null' else name[2:] if name.startswith('b/') else name
            if current:
                files.setdefault(current, {'added': [], 'removed': []})
        elif raw.startswith('@@'):
            match = re.search(r'\+(\d+)', raw)
            line_no = int(match.group(1)) if match else 0
        elif current and raw.startswith('+'):
            files[current]['added'].append((line_no, raw[1:]))
            line_no += 1
        elif current and raw.startswith('-'):
            files[current]['removed'].append(raw[1:])
    return files


def jwt_role(token_payload):
    try:
        padded = token_payload + '=' * (-len(token_payload) % 4)
        return json.loads(base64.urlsafe_b64decode(padded)).get('role')
    except (ValueError, json.JSONDecodeError, AttributeError):
        return None


def secret_findings(path, added):
    """(blocking, warnings) lists of 'path:line motivo' for one file's added lines."""
    blocking, warnings = [], []
    if SECRET_FILES.search(path):
        blocking.append(f'{path}: file con chiavi o segreti, non va versionato')
    for line_no, text in added:
        where = f'{path}:{line_no}'
        for label, pattern in STRONG_SECRETS:
            if pattern.search(text):
                blocking.append(f'{where} {label}')
        for match in JWT.finditer(text):
            if jwt_role(match.group(1)) == 'service_role':
                blocking.append(f'{where} JWT service_role')
        if PUBLIC_ENV.search(path) and PRIVATE_ENV_NAME.search(text):
            blocking.append(f'{where} variabile segreta nel .env pubblico')
        elif WEAK_SECRET.search(text) and not re.search(r'(?i)(test|fixture|example|fake|dummy)', path):
            warnings.append(f'{where} possibile segreto in chiaro')
    return blocking, warnings


def _code_parts(text):
    """String literals that contain a space (UI text, not identifiers) and comments."""
    parts = [m.group(2) for m in re.finditer(r'(["\'`])((?:(?!\1).)*\s(?:(?!\1).)*)\1', text)]
    comment = re.search(r'(//|#)\s(.*)$', text)
    if comment:
        parts.append(comment.group(2))
    return parts


def lexicon_findings(path, added):
    """(blocking, warnings): public text blocks, UI strings and comments in code warn."""
    blocking, warnings = [], []
    if LEXICON_EXEMPT.search(path):
        return blocking, warnings
    public = bool(PUBLIC_TEXT.search(path))
    for line_no, text in added:
        if public:
            match = FORBIDDEN.search(text)
            if not match and path == RELEASE_NOTES and text.startswith('- '):
                match = RELEASE_BLOCKED.search(text)
            if match:
                blocking.append(f'{path}:{line_no} «{match.group(0)}»')
            continue
        for part in _code_parts(text):
            match = FORBIDDEN_CODE.search(part)
            if match:
                warnings.append(f'{path}:{line_no} «{match.group(0)}» in testo o commento')
                break
    return blocking, warnings


def message_findings(messages):
    return [f'commit «{m[:60]}»: «{FORBIDDEN.search(m).group(0)}»' for m in messages if FORBIDDEN.search(m)]


def last_successful_build_sha():
    code, text = run(['gh', 'run', 'list', '-R', 'ilBatta93/StellarTV', '-w', 'build.yml', '--status', 'success',
                      '-L', '1', '--json', 'headSha'], timeout=30)
    try:
        return json.loads(text)[0]['headSha'] if code == 0 else None
    except (ValueError, IndexError, KeyError):
        return None


def pending_release_lines(current_text, published_text):
    """Bullets written after the last successful build: what the next build will publish."""
    def bullets(text):
        return [line[2:].strip() for line in text.splitlines() if line.startswith('- ') and line[2:].strip()]
    published = set(bullets(published_text))
    return [line for line in bullets(current_text) if line not in published]


def release_status(build_sha=None):
    """(lines to publish next, user-facing files changed since the last build) or None if unknown."""
    sha = build_sha or last_successful_build_sha()
    if not sha:
        return None
    current = (APP / 'docs' / 'release-current.md').read_text(encoding='utf-8')
    published = git(APP, 'show', f'{sha}:docs/release-current.md')
    changed = git(APP, 'diff', '--name-only', sha, 'HEAD', '--', 'lib', 'packages').splitlines()
    changed = [p for p in changed if not p.endswith('.md')]
    return pending_release_lines(current, published), changed
