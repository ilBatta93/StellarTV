"""Consistency between app and site: shared constants, public API routes, twin files changed on one side only.

Usage: python scripts/gemelle.py [--giorni N]   (default: file cambiati nell'ultimo giorno)
"""
import argparse
import re
import sys

from ecosistema import APP, SITE, git, out, parse_diff, utf8_stdout

# Same value on both sides, or the two stop understanding each other.
CONSTANTS = [
    ('versione della busta del vault',
     ('lib/services/personal_vault.dart', r'envelopeVersion\s*=\s*(\d+)'),
     ('src/lib/personalVault.ts', r'VAULT_ENVELOPE_VERSION\s*=\s*(\d+)')),
    ('AAD del vault',
     ('lib/services/personal_vault.dart', r"'(StellarTV:vault:)"),
     ('src/lib/personalVault.ts', r'`(StellarTV:vault:)')),
    ('corsia dei nomi dei profili',
     ('lib/services/personal_vault.dart', r"profilesLane\s*=\s*'([^']+)'"),
     ('src/lib/personalVault.ts', r'PROFILES_LANE\s*=\s*"([^"]+)"')),
    ('info HKDF del passaggio chiave',
     ('lib/services/key_handoff.dart', r"'(STV-HANDOFF-\d+)\|"),
     ('src/lib/keyHandoff.ts', r'`(STV-HANDOFF-\d+)\|')),
    ('chiave della soglia di completamento',
     ('lib/models/watch_completion_policy.dart', r"key\s*=\s*'([^']+)'"),
     ('src/lib/cloudPrivacy.ts', r'"(ui_watched_percent)"')),
]

# Files that change together. strict: shared format, the other side must follow.
# contract: an app service and the route it calls, check only if the request or response changed.
PAIRS = [
    ('vault', 'strict', ['lib/services/personal_vault.dart', 'test/fixtures/'],
     ['src/lib/personalVault.ts', 'src/lib/personalVault.appV2.fixture.json']),
    ('passaggio chiave', 'strict', ['lib/services/key_handoff.dart'], ['src/lib/keyHandoff.ts']),
    ('profilo bambino', 'strict', ['lib/services/kids_policy.dart'], ['src/lib/kidsPolicy.ts']),
    ('voti', 'contract', ['lib/models/rating_policy.dart'], ['src/lib/tmdbVotes.ts']),
    ('sincronizzazione', 'contract', ['lib/services/sync_service.dart'], ['src/lib/appSync.ts', 'src/lib/cloudPrivacy.ts']),
    ('pairing TV', 'contract', ['lib/services/tv_pairing_service.dart'], ['src/routes/api/public/pair.ts', 'src/lib/pairing']),
    ('sottotitoli', 'contract', ['lib/services/subtitles_service.dart'],
     ['src/routes/api/public/subtitles.ts', 'src/routes/api/public/opensubtitles.ts', 'src/lib/subtitle']),
    ('segmenti', 'contract', ['lib/services/segment_library.dart'], ['src/routes/api/public/segments.ts', 'src/lib/segmentCache.ts']),
    ('profilo bambino (API)', 'contract', ['lib/services/kids_content_service.dart'],
     ['src/routes/api/public/kids-check.ts', 'src/routes/api/public/kids-lookup.ts', 'src/lib/kidsCacheWrite.ts']),
    ('TMDB e locandine', 'contract', ['lib/services/tmdb_service.dart'],
     ['src/routes/api/public/tmdb.ts', 'src/routes/api/public/artwork.ts', 'src/routes/api/public/platform-catalog.ts',
      'src/lib/tmdbMetadataCache.ts']),
    ('IMDb', 'contract', ['lib/services/imdb_rating_service.dart', 'lib/services/imdb_resolver.dart'],
     ['src/routes/api/public/imdb.ts', 'src/routes/api/public/imdb-ratings.ts', 'src/lib/imdbRatings.ts']),
    ('voti (API)', 'contract', ['lib/services/catalog_rating_service.dart'], ['src/routes/api/public/ratings.ts']),
]

API_CALL = re.compile(r"(?:apiBase\}|/api/public)/([a-z0-9-]+)")


def read(repo, rel):
    try:
        return (repo / rel).read_text(encoding='utf-8')
    except OSError:
        return None


def check_constants(read_app, read_site):
    """Mismatches as text lines; read_* map a relative path to its content or None."""
    problems = []
    for label, (app_file, app_re), (site_file, site_re) in CONSTANTS:
        app_text, site_text = read_app(app_file), read_site(site_file)
        app_m = re.search(app_re, app_text or '')
        site_m = re.search(site_re, site_text or '')
        if not app_m or not site_m:
            missing = app_file if not app_m else site_file
            problems.append(f'{label}: valore non trovato in {missing} (regola in scripts/gemelle.py da aggiornare?)')
        elif app_m.group(1) != site_m.group(1):
            problems.append(f'{label}: app {app_m.group(1)} ≠ sito {site_m.group(1)}')
    return problems


def check_api(dart_sources, route_names):
    """(called by the app but missing on the site, routes no app code calls)."""
    called = set()
    for text in dart_sources:
        called.update(API_CALL.findall(text))
    return sorted(called - route_names), sorted(route_names - called)


def one_sided(app_changed, site_changed):
    """Pairs touched on one side only: [(name, kind, side touched, files to look at on the other side)]."""
    def touched(paths, prefixes):
        return any(p == pre or p.startswith(pre) for p in paths for pre in prefixes)
    result = []
    for name, kind, app_prefixes, site_prefixes in PAIRS:
        app_hit, site_hit = touched(app_changed, app_prefixes), touched(site_changed, site_prefixes)
        if app_hit and not site_hit:
            result.append((name, kind, 'app', site_prefixes))
        elif site_hit and not app_hit:
            result.append((name, kind, 'sito', app_prefixes))
    return result


def changed_since(repo, days):
    """Files changed in commits of the last N days plus uncommitted changes, ignoring whitespace-only edits."""
    log = parse_diff(git(repo, 'log', f'--since={days}.days', '-p', '-w', '-U0', '--no-color', '--format='))
    paths = {path for path, change in log.items() if change['added'] or change['removed']}
    paths.update(git(repo, 'diff', '--name-only', 'HEAD').splitlines())
    paths.update(git(repo, 'ls-files', '--others', '--exclude-standard').splitlines())
    return {p for p in paths if p}


def route_names():
    folder = SITE / 'src/routes/api/public'
    return {p.stem for p in folder.glob('*.ts') if not p.stem.endswith('.test')}


def dart_sources():
    return [p.read_text(encoding='utf-8', errors='replace') for p in (APP / 'lib').rglob('*.dart')]


def report(app_changed=None, site_changed=None, days=1, only_side=None):
    """Prints the check; returns the number of hard problems. only_side keeps pairs touched on that side."""
    if not SITE.exists():
        out(f'Sito non trovato in {SITE}: controllo saltato.')
        return 0
    hard = check_constants(lambda rel: read(APP, rel), lambda rel: read(SITE, rel))
    missing, unused = check_api(dart_sources(), route_names())
    hard += [f'l\'app chiama /api/public/{name}, che nel sito non esiste' for name in missing]
    if app_changed is None:
        app_changed, site_changed = changed_since(APP, days), changed_since(SITE, days)
    sides = [s for s in one_sided(app_changed, site_changed) if only_side in (None, s[2])]

    out('Coerenza app ↔ sito')
    out(f'  costanti condivise: {len(CONSTANTS)} controllate, {len(hard)} problemi')
    for line in hard:
        out(f'  ✗ {line}')
    if unused:
        out(f'  · rotte del sito che nessun servizio dell\'app chiama: {", ".join(unused)}')
    for name, kind, side, others in sides:
        other = 'sito' if side == 'app' else 'app'
        if kind == 'strict':
            out(f'  ! {name}: toccato solo lato {side}. Formato condiviso: allinea {other} ({", ".join(others)})')
        else:
            out(f'  · {name}: toccato solo lato {side}. Se cambia richiesta o risposta, allinea {other}')
    if not hard and not sides:
        out('  ✓ nessuna differenza')
    return len(hard)


def main():
    utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--giorni', type=int, default=1, help='finestra dei file cambiati (default 1)')
    args = parser.parse_args()
    sys.exit(1 if report(days=args.giorni) else 0)


if __name__ == '__main__':
    main()
