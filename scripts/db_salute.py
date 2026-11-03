"""Supabase health in about 30 lines: slow and frequent queries, scans, unused indexes, bloat, vacuum.

Read-only: only `supabase inspect db` (master §8), run from the site repository, which is linked.
Statistics count from the last reset shown in the first line.

Usage: python scripts/db_salute.py [--salva CARTELLA]   (--salva keeps the raw JSON for a deeper look)
"""
import argparse
import json
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from ecosistema import SITE, out, run, utf8_stdout

COMMANDS = ['db-stats', 'outliers', 'calls', 'table-stats', 'index-stats', 'bloat', 'vacuum-stats']
# Only the app's and site's own tables and RPCs live in «public»: the rest is the Supabase dashboard,
# auth and PostgREST bookkeeping. Catalog reads can mention «public» as a filter, so they stay out;
# pg_catalog is not a marker, PostgREST calls pg_catalog functions in every app query.
APP_QUERY = re.compile(r'\bpublic\.\w+')
INTERNAL = re.compile(r'pg_available|information_schema|pg_namespace|pg_proc|pg_class|pg_temp', re.I)


def seconds(value):
    """'00:00:18.026835' or '1 day 02:00:00' → seconds."""
    match = re.search(r'(?:(\d+) days? )?(\d+):(\d+):([\d.]+)', value or '')
    if not match:
        return 0.0
    days, hours, minutes, secs = match.groups()
    return int(days or 0) * 86400 + int(hours) * 3600 + int(minutes) * 60 + float(secs)


def number(value):
    try:
        return float(str(value).replace(',', '').strip() or 0)
    except ValueError:
        return 0.0


def size_bytes(value):
    match = re.match(r'([\d.]+)\s*(bytes|kB|MB|GB)', value or '')
    if not match:
        return 0
    return float(match.group(1)) * {'bytes': 1, 'kB': 1024, 'MB': 1024 ** 2, 'GB': 1024 ** 3}[match.group(2)]


def short_query(query, width=130):
    text = re.sub(r'\s+', ' ', query or '').replace('"public".', '').replace('"', '')
    text = re.sub(r'WITH pgrst_source AS \( ', '', text)
    return text[:width] + ('…' if len(text) > width else '')


def app_queries(rows):
    # Schemas come quoted ("public"."kids_ratings"): match on the unquoted text.
    texts = [(r, (r.get('query') or '').replace('"', '')) for r in rows]
    return [r for r, text in texts if APP_QUERY.search(text) and not INTERNAL.search(text)]


def query_lines(rows, limit):
    lines = []
    for r in app_queries(rows)[:limit]:
        total, calls = seconds(r.get('total_exec_time')), number(r.get('ncalls'))
        mean = total / calls * 1000 if calls else 0
        lines.append(f'  {total:7.1f} s {r.get("prop_exec_time", ""):>6} {int(calls):>9,} chiamate '
                     f'{mean:8.1f} ms/chiamata  {short_query(r.get("query"))}')
    return lines


def findings(data):
    """Text lines grouped by section, from the parsed JSON rows of each command."""
    sections = []
    stats = (data.get('db-stats') or [{}])[0]
    hit = [f'{k.split("_")[0]} {stats.get(k)}' for k in ('index_hit_rate', 'table_hit_rate')]
    low_hit = any(number(stats.get(k)) < 0.99 for k in ('index_hit_rate', 'table_hit_rate') if stats.get(k))
    sections.append(('Database', [f'  {stats.get("database_size", "?")} (tabelle {stats.get("total_table_size", "?")}, '
                                  f'indici {stats.get("total_index_size", "?")}), cache hit {", ".join(hit)}'
                                  f'{"  ! sotto 0.99" if low_hit else ""}, statistiche da '
                                  f'{str(stats.get("time_since_stats_reset", "?")).split(".")[0]}']))
    # Each CLI list stops at ten rows, mostly dashboard queries: merge both before ranking by time.
    merged = {r.get('query'): r for r in data.get('calls', []) + data.get('outliers', [])}
    by_time = sorted(merged.values(), key=lambda r: seconds(r.get('total_exec_time')), reverse=True)
    sections.append(('Query più costose (tempo totale)', query_lines(by_time, 5)
                     or ['  nessuna query dell\'app fra le più costose']))
    sections.append(('Query più frequenti', query_lines(data.get('calls', []), 4) or ['  nessuna']))

    scans = [r for r in data.get('table-stats', [])
             if number(r.get('estimated_row_count')) > 10_000 and number(r.get('seq_scans')) > 100]
    sections.append(('Scansioni sequenziali su tabelle grandi', [
        f'  ! {r["name"]}: {int(number(r["seq_scans"])):,} scansioni su {int(number(r["estimated_row_count"])):,} righe'
        for r in scans] or ['  ✓ nessuna']))

    unused = [r for r in data.get('index-stats', []) if str(r.get('unused')).lower() == 'true'
              and not r.get('name', '').endswith('_pkey')]
    sections.append(('Indici mai usati (costano spazio e scritture)', [
        f'  · {r["name"]} ({r.get("size", "?")})' for r in unused[:8]] or ['  ✓ nessuno']))

    bloated = [r for r in data.get('bloat', []) if number(r.get('bloat')) >= 2 and size_bytes(r.get('waste')) > 1024 ** 2]
    sections.append(('Spazio sprecato (bloat ≥ 2, oltre 1 MB)', [
        f'  · {r["name"]}: bloat {r["bloat"]}, {r["waste"]}' for r in bloated[:6]] or ['  ✓ nessuno']))

    vacuum = [r for r in data.get('vacuum-stats', []) if str(r.get('expect_autovacuum', '')).strip() == 'yes']
    sections.append(('Vacuum in attesa', [
        f'  · {r["name"]}: {r.get("dead_rowcount", "").strip()} righe morte' for r in vacuum[:6]] or ['  ✓ nessuno']))
    return sections


def inspect(command):
    code, text = run(['supabase', 'inspect', 'db', command, '--linked', '--output-format', 'json'],
                     cwd=SITE, timeout=120)
    start = text.find('{')
    try:
        # The CLI may append an update notice after the JSON: decode the first object only.
        parsed = json.JSONDecoder().raw_decode(text[start:])[0] if code == 0 and start >= 0 else None
    except ValueError:
        parsed = None
    if parsed is None:
        return command, None, text.strip().splitlines()[-1:] or ['nessun output']
    return command, parsed.get('rows', parsed) if isinstance(parsed, dict) else parsed, None


def main():
    utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--salva', help='cartella dove salvare il JSON grezzo di ogni comando')
    args = parser.parse_args()
    if not SITE.exists():
        out(f'Sito non trovato in {SITE}: serve il progetto collegato a Supabase.')
        sys.exit(2)
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(inspect, COMMANDS))
    data, errors = {}, []
    for command, rows, error in results:
        if rows is None:
            errors.append(f'{command}: {error[0][:160]}')
        else:
            data[command] = rows
    if args.salva:
        folder = Path(args.salva)
        folder.mkdir(parents=True, exist_ok=True)
        for command, rows in data.items():
            (folder / f'{command}.json').write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding='utf-8')
    out('Salute del database Supabase (sola lettura)')
    for title, lines in findings(data):
        out(title)
        for line in lines:
            out(line)
    for error in errors:
        out(f'  ✗ {error}')
    sys.exit(1 if errors else 0)


if __name__ == '__main__':
    main()
