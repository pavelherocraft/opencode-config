#!/usr/bin/env python3
"""
check.py - POSIX mirror of check.ps1

Fast LLM-free integrity check of the live<->repo agent orchestration config:
5 sync pairs (SHA256 drift report), JSON validity (live + repo), agent counts
(derived: live == repo == opencode.json entries), routing counts (derived from
plugin ROUTING_TABLES vs opencode.json task-allowlists vs ARCHITECTURE.md
whitelist headers/rows), frontmatter model key format + existence in
opencode.json provider models.

No hardcoded expectations: counters are DERIVED from the fact and cross-checked
against each other.

Usage:
    python check.py [--json]

Output:
    STATUS:/PAIR:/JSON:/COUNT:/FORMAT:/EXISTS:/DRIFT:/WARN:/SUMMARY:/ERROR: lines

Exit codes:
    0 all pass (WARNs allowed)
    2 usage/environment error
    3 one or more FAIL findings

Strictly read-only.
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


def read_raw(p):
    """Byte-safe read: decode UTF-8 (strip BOM if present)."""
    data = Path(p).read_bytes()
    bom = data.startswith(b'\xef\xbb\xbf')
    return data.decode('utf-8-sig' if bom else 'utf-8')


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest().upper()


def get_fm_model(text):
    m = re.match(r'(?s)\A---\r?\n(.*?)\r?\n---', text)
    if not m:
        return None
    mm = re.search(r'(?m)^model:[ \t]*(.*)$', m.group(1))
    if not mm:
        return None
    return mm.group(1).strip()


def count_task_allow(cfg, primary):
    try:
        task = cfg['agent'][primary]['permission']['task']
    except (KeyError, TypeError):
        return None
    return sum(1 for k, v in task.items() if k != '*' and v == 'allow')


def count_routing_plugin(ts_text, primary):
    outer = re.search(r'const ROUTING_TABLES = \{(.*?)\r?\n\}', ts_text, re.S)
    if not outer:
        return None
    inner = re.search(re.escape(primary) + r'\s*:\s*\[(.*?)\]', outer.group(1), re.S)
    if not inner:
        return None
    return len(re.findall(r'"[^"]+"', inner.group(1)))


def get_whitelist_count(arch_text, primary):
    m = re.search(r'^### ' + re.escape(primary) + r' Whitelist \((\d+) agents\)',
                  arch_text, re.M)
    if not m:
        return None
    header = int(m.group(1))
    after = arch_text[m.end():]
    fp = re.search(r'(?m)^\|', after)
    if not fp:
        return {'header': header, 'rows': -1}
    rest = after[fp.start():]
    blank = re.search(r'\r?\n[ \t]*\r?\n', rest)
    tbl = rest[:blank.start()] if blank else rest
    rows = len(re.findall(r'(?m)^\|\s*\d+\s*\|', tbl))
    return {'header': header, 'rows': rows}


class Report:
    def __init__(self, as_json):
        self.checks = []
        self.pass_n = 0
        self.fail_n = 0
        self.warn_n = 0
        self.as_json = as_json

    def add(self, cid, target, status, detail=''):
        self.checks.append({'id': cid, 'target': target, 'status': status, 'detail': detail})
        if status == 'PASS':
            self.pass_n += 1
        elif status == 'FAIL':
            self.fail_n += 1
        else:
            self.warn_n += 1
        if not self.as_json:
            display = status
            if cid == 'PAIR' and status == 'PASS':
                display = 'OK'
            payload = target
            if detail:
                payload = f'{target} {detail}' if target else detail
            print(f'{cid}:{payload} -> {display}')


def repo_root(script_dir):
    """<repo>/.opencode/skills/<skill>/scripts -> <repo>."""
    root = script_dir.resolve().parents[3]
    if (root / '.opencode' / 'skills').is_dir():
        return root
    try:
        out = subprocess.check_output(
            ['git', '-C', str(script_dir), 'rev-parse', '--show-toplevel'],
            stderr=subprocess.DEVNULL, text=True
        ).strip()
        if out:
            return Path(out)
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return root


def pair_defs(live_dir, root):
    return [
        {'name': 'agents', 'kind': 'multi', 'pattern': '*.md',
         'live': live_dir / 'agents', 'repo': root / 'agents'},
        {'name': 'opencode.json', 'kind': 'file',
         'live': live_dir / 'opencode.json', 'repo': root / 'opencode.json'},
        {'name': 'plugin', 'kind': 'file',
         'live': live_dir / 'plugins' / 'workflow-enforcement.ts',
         'repo': root / 'plugins' / 'workflow-enforcement.ts'},
        {'name': 'skills/git-commit', 'kind': 'multi', 'pattern': '*',
         'live': live_dir / 'skills' / 'git-commit',
         'repo': root / 'skills' / 'git-commit'},
        {'name': 'AGENTS.md', 'kind': 'file',
         'live': live_dir / 'AGENTS.md', 'repo': root / 'AGENTS.global.md'},
    ]


def multi_files(d, pattern):
    if not d.is_dir():
        return []
    if pattern == '*.md':
        return sorted(f.name for f in d.glob(pattern) if f.is_file())
    return sorted(p.relative_to(d).as_posix() for p in d.rglob(pattern) if p.is_file())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()

    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)
    live_dir = Path.home() / '.config' / 'opencode'
    live_agents_dir = live_dir / 'agents'
    repo_agents_dir = root / 'agents'

    if not live_agents_dir.is_dir():
        print(f'ERROR: live agents dir not found: {live_agents_dir}')
        sys.exit(2)
    if not repo_agents_dir.is_dir():
        print(f'ERROR: repo agents dir not found: {repo_agents_dir}')
        sys.exit(2)
    if not (live_dir / 'opencode.json').is_file():
        print(f"ERROR: live opencode.json not found: {live_dir / 'opencode.json'}")
        sys.exit(2)

    rep = Report(args.json)
    if not args.json:
        print('STATUS:CHECK_START')

    # 1. JSON validity (live + repo) — C5
    cfg = None
    json_live_ok = True
    try:
        cfg = json.loads(read_raw(live_dir / 'opencode.json'))
    except (ValueError, OSError):
        json_live_ok = False
    rep.add('JSON', 'opencode.json live', 'PASS' if json_live_ok else 'FAIL',
            'parse ok' if json_live_ok else 'invalid JSON')
    json_repo_ok = True
    try:
        json.loads(read_raw(root / 'opencode.json'))
    except (ValueError, OSError):
        json_repo_ok = False
    rep.add('JSON', 'opencode.json repo', 'PASS' if json_repo_ok else 'FAIL',
            'parse ok' if json_repo_ok else 'invalid JSON')

    # 2. Sync-pair drift (5 pairs) — C3
    for pair in pair_defs(live_dir, root):
        if pair['kind'] == 'multi':
            live_names = multi_files(pair['live'], pair['pattern'])
            repo_names = multi_files(pair['repo'], pair['pattern'])
            union = list(dict.fromkeys(live_names + repo_names))
            for n in union:
                l = pair['live'] / n
                r = pair['repo'] / n
                label = f"{pair['name']}/{n}"
                if l.is_file() and r.is_file():
                    h1, h2 = sha256_file(l), sha256_file(r)
                    if h1 == h2:
                        rep.add('PAIR', label, 'PASS')
                    else:
                        rep.add('DRIFT', label, 'FAIL',
                                f'live={h1[:8]} repo={h2[:8]} (use: config-sync --save)')
                else:
                    rep.add('DRIFT', label, 'FAIL', 'side missing (use: config-sync --save)')
        else:
            lp, rp = pair['live'], pair['repo']
            if lp.is_file() and rp.is_file():
                h1, h2 = sha256_file(lp), sha256_file(rp)
                if h1 == h2:
                    rep.add('PAIR', pair['name'], 'PASS')
                else:
                    rep.add('DRIFT', pair['name'], 'FAIL',
                            f'live={h1[:8]} repo={h2[:8]} (use: config-sync --save)')
            else:
                rep.add('DRIFT', pair['name'], 'FAIL', 'side missing (use: config-sync --save)')

    # 3. Agent counts (derived) — C2
    live_files = sorted(live_agents_dir.glob('*.md'))
    repo_files = sorted(repo_agents_dir.glob('*.md'))
    live_names = [f.stem for f in live_files]
    repo_names = [f.stem for f in repo_files]
    cfg_agent_count = len(cfg.get('agent', {})) if json_live_ok else None
    counts = [len(live_files), len(repo_files)] + ([cfg_agent_count] if cfg_agent_count is not None else [])
    count_ok = len(set(counts)) == 1
    detail = f'agents_live={len(live_files)} agents_repo={len(repo_files)} opencode_json={cfg_agent_count} (derived, no hardcoded expectation)'
    if not count_ok:
        only_live = [n for n in live_names if n not in repo_names]
        only_repo = [n for n in repo_names if n not in live_names]
        if only_live or only_repo:
            detail += f" live_only=[{','.join(only_live)}] repo_only=[{','.join(only_repo)}]"
    rep.add('COUNT', '', 'PASS' if count_ok else 'FAIL', detail)

    # 4. Routing counts (derived, cross-checked: plugin vs json vs ARCHITECTURE) — C1/C2
    ts_text = None
    ts_path = live_dir / 'plugins' / 'workflow-enforcement.ts'
    if ts_path.is_file():
        ts_text = read_raw(ts_path)
    arch_text = None
    arch_path = root / 'ARCHITECTURE.md'
    if arch_path.is_file():
        arch_text = read_raw(arch_path)
    else:
        rep.add('WARN', 'ARCHITECTURE.md', 'WARN', 'not found — whitelist cross-check skipped')

    for primary in ('orchestrator', 'plankestrator'):
        json_n = count_task_allow(cfg, primary) if json_live_ok else None
        plug_n = count_routing_plugin(ts_text, primary) if ts_text is not None else None
        arch_h = arch_r = None
        if arch_text is not None:
            wl = get_whitelist_count(arch_text, primary)
            if wl is not None:
                arch_h, arch_r = wl['header'], wl['rows']
        values = [v for v in (json_n, plug_n, arch_h, arch_r) if v is not None]
        ok = len(values) >= 2 and len(set(values)) == 1
        rep.add('COUNT', '', 'PASS' if ok else 'FAIL',
                f'routing_{primary} json={json_n} plugin={plug_n} '
                f'arch_header={arch_h} arch_rows={arch_r} (derived cross-check)')
        if plug_n is None:
            rep.add('WARN', 'routing', 'WARN',
                    f'{primary} plugin anchor not parsed (skipped plugin source)')
        if arch_h is None and arch_text is not None:
            rep.add('WARN', 'routing', 'WARN',
                    f'{primary} ARCHITECTURE whitelist anchor not parsed')

    # 5. Model key format + existence — C4
    for f in live_files:
        name = f.stem
        m = get_fm_model(read_raw(f))
        if not m:
            rep.add('FORMAT', name, 'FAIL', 'frontmatter without model line')
            continue
        fmt_ok = re.match(r'^[A-Za-z0-9._-]+/.+$', m) is not None
        rep.add('FORMAT', name, 'PASS' if fmt_ok else 'FAIL', f'model={m}')
        if json_live_ok:
            exists = False
            if fmt_ok:
                slash = m.find('/')
                prov = m[:slash]
                key = m[slash + 1:]
                models = (cfg.get('provider', {}).get(prov) or {}).get('models')
                if isinstance(models, dict):
                    exists = key in models
            rep.add('EXISTS', name, 'PASS' if exists else 'FAIL', m)
    if not json_live_ok:
        rep.add('EXISTS', '', 'WARN', 'checks skipped (opencode.json parse failed)')

    # 6. Summary
    if args.json:
        doc = {
            'checks': rep.checks,
            'summary': {
                'total': len(rep.checks),
                'pass': rep.pass_n,
                'fail': rep.fail_n,
                'warn': rep.warn_n,
            },
        }
        print(json.dumps(doc, indent=2, ensure_ascii=False))
    else:
        print(f'SUMMARY:checks={len(rep.checks)} pass={rep.pass_n} '
              f'fail={rep.fail_n} warn={rep.warn_n}')
        if rep.fail_n > 0:
            print(f'STATUS:FAILURES fail={rep.fail_n}')
        else:
            print('STATUS:ALL_PASS')

    sys.exit(3 if rep.fail_n > 0 else 0)


if __name__ == '__main__':
    main()
