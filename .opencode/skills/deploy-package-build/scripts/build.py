#!/usr/bin/env python3
"""
build.py - POSIX mirror of build.ps1

Deterministic rebuild of deploy-package/ from live sources: byte-copy live
agents + opencode.json + workflow-enforcement.ts + 4 root docs, SHA256-verify
every copy, regenerate HASHES.txt, gate on counters (agents/models/routing
across 3 sources) and a literal-secrets scan. --plan (default) reports without
writing; --apply performs the build; --archive rebuilds deploy-package.7z.

Usage:
    python build.py [--plan | --apply] [--archive] [--strict] [--json]
                    [--expected-agents 37] [--expected-models 10]
                    [--expected-orch 25] [--expected-plan 10]

Output:
    STATUS:/GATE:/COUNT:/SAME:/CHANGED:/NEW:/COPIED:/VERIFY:/WARN:/ERROR:/
    PLAN:/EDITED:/ARCHIVED:/SUMMARY: lines or a JSON document

Exit codes:
    0 plan clean report / apply success
    2 usage/environment error
    3 gate block, copy/verify failure, HASHES write failure, --strict with STALE

NEVER deletes files, never runs git, never touches live files.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


def read_raw(p):
    data = Path(p).read_bytes()
    bom = data.startswith(b'\xef\xbb\xbf')
    return data.decode('utf-8-sig' if bom else 'utf-8'), bom


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


def repo_root(script_dir):
    """<repo>/.opencode/skills/<skill>/scripts -> <repo>."""
    root = script_dir.resolve().parents[3]
    if (root / 'deploy-package').exists():
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


# --- Routing counter parsers (verbatim copies of the integrity-check helpers) ---

def count_task_allow(cfg, primary):
    try:
        node = cfg['agent'][primary]['permission']['task']
    except (KeyError, TypeError):
        return None
    if not node:
        return None
    return sum(1 for k, v in node.items() if k != '*' and v == 'allow')


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


# --- Build helpers -----------------------------------------------------------

def build_file_map(live_dir, root, pkg):
    entries = []
    for f in sorted((live_dir / 'agents').glob('*.md'), key=lambda p: p.name):
        entries.append({'src': str(f), 'dst': str(pkg / 'agents' / f.name),
                        'rel': 'agents/' + f.name})
    entries.append({'src': str(live_dir / 'opencode.json'),
                    'dst': str(pkg / 'opencode.json'), 'rel': 'opencode.json'})
    entries.append({'src': str(live_dir / 'plugins' / 'workflow-enforcement.ts'),
                    'dst': str(pkg / 'plugins' / 'workflow-enforcement.ts'),
                    'rel': 'plugins/workflow-enforcement.ts'})
    for d in ('ARCHITECTURE.md', 'AGENTS.md', 'MCP_SETUP.md', 'PLUGIN.md'):
        entries.append({'src': str(root / d), 'dst': str(pkg / 'project-files' / d),
                        'rel': 'project-files/' + d})
    return entries


def test_secrets(json_text):
    """Conservative literal-secret scan - values are NEVER printed."""
    hits = []
    pats = [
        ('sk-token', r'"sk-[A-Za-z0-9_\-]{16,}"'),
        ('literal-key-field',
         r'(?i)"(?:api[_-]?key|apikey|access[_-]?token|secret)"\s*:\s*"(?!\$)(?!YOUR_)(?!\{\{)[^"]{12,}"'),
    ]
    for name, rx in pats:
        n = len(re.findall(rx, json_text))
        if n > 0:
            hits.append({'pattern': name, 'count': n})
    return hits


def get_hashes_scope(pkg):
    entries = []
    for f in sorted(pkg.rglob('*')):
        if not f.is_file():
            continue
        rel = f.relative_to(pkg).as_posix()
        if rel.startswith('plugins/node_modules/'):
            continue
        if rel in ('deploy-package.7z', 'HASHES.txt') or rel.endswith('.tmp7z'):
            continue
        entries.append({'rel': rel, 'sha': sha256_file(f)})
    return sorted(entries, key=lambda e: e['rel'])


def write_hashes_file(pkg):
    scope = get_hashes_scope(pkg)
    text = '\n'.join('%s  %s' % (e['sha'], e['rel']) for e in scope) + '\n'
    data = text.encode('utf-8')   # no BOM, LF
    target = pkg / 'HASHES.txt'
    if target.is_file() and target.read_bytes() == data:
        return {'changed': False, 'lines': len(scope)}
    target.write_bytes(data)
    return {'changed': True, 'lines': len(scope)}


def find_seven_zip():
    for cand in (shutil.which('7z'), shutil.which('7za')):
        if cand:
            return cand
    p = Path('/usr/bin/7z')
    if p.is_file():
        return str(p)
    return None


def get_stale_files(pkg, live_agent_names):
    stale = []
    dep_agents = pkg / 'agents'
    if dep_agents.is_dir():
        for f in dep_agents.glob('*.md'):
            if f.stem not in live_agent_names:
                stale.append('agents/' + f.name)
    pf = pkg / 'project-files'
    allowed = {'ARCHITECTURE.md', 'AGENTS.md', 'MCP_SETUP.md', 'PLUGIN.md'}
    if pf.is_dir():
        for f in pf.glob('*.md'):
            if f.name not in allowed:
                stale.append('project-files/' + f.name)
    return stale


def ns(v):
    """None -> empty string (PowerShell $null interpolation parity)."""
    return '' if v is None else str(v)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--plan', action='store_true')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--archive', action='store_true')
    parser.add_argument('--strict', action='store_true')
    parser.add_argument('--expected-agents', type=int, default=37)
    parser.add_argument('--expected-models', type=int, default=10)
    parser.add_argument('--expected-orch', type=int, default=25)
    parser.add_argument('--expected-plan', type=int, default=10)
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()

    if args.plan and args.apply:
        print('ERROR:FLAGS -Plan and -Apply are mutually exclusive')
        sys.exit(2)
    if args.archive and not args.apply:
        print('ERROR:FLAGS -Archive requires -Apply')
        sys.exit(2)
    mode = 'apply' if args.apply else 'plan'   # --plan is the default

    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)
    live_dir = Path.home() / '.config' / 'opencode'
    pkg = root / 'deploy-package'
    live_agents_dir = live_dir / 'agents'
    live_cfg = live_dir / 'opencode.json'
    live_ts = live_dir / 'plugins' / 'workflow-enforcement.ts'

    # Pre-checks (exit 2, zero copies)
    pre = [
        (live_dir, 'live config dir'),
        (live_agents_dir, 'live agents dir'),
        (live_cfg, 'live opencode.json'),
        (live_ts, 'live workflow-enforcement.ts'),
        (pkg, 'deploy-package dir'),
        (pkg / 'agents', 'deploy-package agents dir'),
        (pkg / 'project-files', 'deploy-package project-files dir'),
        (root / 'ARCHITECTURE.md', 'root ARCHITECTURE.md'),
        (root / 'AGENTS.md', 'root AGENTS.md'),
        (root / 'MCP_SETUP.md', 'root MCP_SETUP.md'),
        (root / 'PLUGIN.md', 'root PLUGIN.md'),
    ]
    pre_fail = [f'ERROR:ENV {what} not found: {p}' for p, what in pre if not p.exists()]
    if pre_fail:
        for e in pre_fail:
            print(e)
        sys.exit(2)
    live_agent_files = list(live_agents_dir.glob('*.md'))
    if not live_agent_files:
        print(f'ERROR:ENV live agents dir empty: {live_agents_dir}')
        sys.exit(2)
    seven_zip = None
    if args.archive:
        seven_zip = find_seven_zip()
        if not seven_zip:
            print('ERROR:ENV sevenzip not found (7z/7za in PATH, /usr/bin/7z)')
            sys.exit(2)
    file_map = build_file_map(live_dir, root, pkg)
    for e in file_map:
        if not Path(e['src']).is_file():
            print(f"ERROR:ENV mapped source missing: {e['src']}")
            sys.exit(2)

    if not args.json:
        print('STATUS:BUILD_START mode={0} agents_expected={1}'.format(
            mode, args.expected_agents))

    # Gates (before any write)
    gates = []
    gates_failed = 0

    cfg_text, _ = read_raw(live_cfg)
    try:
        cfg = json.loads(cfg_text)
        json_ok = True
    except ValueError:
        cfg = None
        json_ok = False
    if json_ok:
        gates.append({'id': 'JSON', 'status': 'PASS', 'detail': 'file=opencode.json parse ok'})
    else:
        gates.append({'id': 'JSON', 'status': 'BLOCK', 'detail': 'file=opencode.json invalid JSON'})
        gates_failed += 1

    secret_hits = test_secrets(cfg_text)
    if not secret_hits:
        gates.append({'id': 'SECRETS', 'status': 'PASS', 'detail': 'file=opencode.json hits=0'})
    else:
        pat_csv = ','.join(h['pattern'] for h in secret_hits)
        hits_n = sum(h['count'] for h in secret_hits)
        gates.append({'id': 'SECRETS', 'status': 'BLOCK',
                      'detail': 'file=opencode.json hits={0} patterns={1}'.format(hits_n, pat_csv)})
        gates_failed += 1

    n_agents = len(live_agent_files)
    ok = n_agents == args.expected_agents
    gates.append({'id': 'agents_live', 'status': 'PASS' if ok else 'BLOCK',
                  'detail': '{0} expected={1}'.format(n_agents, args.expected_agents)})
    if not ok:
        gates_failed += 1

    models_used = set()
    for f in live_agent_files:
        m = get_fm_model(read_raw(f)[0])
        if m:
            models_used.add(m)
    ok = len(models_used) == args.expected_models
    gates.append({'id': 'models_used', 'status': 'PASS' if ok else 'BLOCK',
                  'detail': '{0} expected={1}'.format(len(models_used), args.expected_models)})
    if not ok:
        gates_failed += 1

    arch_text, _ = read_raw(root / 'ARCHITECTURE.md')
    ts_text, _ = read_raw(live_ts)
    routing_warns = []
    for prim, exp in (('orchestrator', args.expected_orch),
                      ('plankestrator', args.expected_plan)):
        json_n = count_task_allow(cfg, prim) if json_ok else None
        wl = get_whitelist_count(arch_text, prim)
        arch_h = wl['header'] if wl is not None else None
        arch_r = wl['rows'] if wl is not None else None
        plug_n = count_routing_plugin(ts_text, prim)
        ok = (json_n is not None and json_n == exp
              and arch_h is not None and arch_h == exp
              and arch_r is not None and arch_r == exp)
        if plug_n is not None and plug_n != exp:
            ok = False
        if plug_n is None:
            routing_warns.append(
                'WARN:routing {0} plugin anchor not parsed (skipped plugin source)'.format(prim))
        plug_s = str(plug_n) if plug_n is not None else '-'
        detail = 'json={0} arch_header={1} arch_rows={2} plugin={3} expected={4}'.format(
            ns(json_n), ns(arch_h), ns(arch_r), plug_s, exp)
        gates.append({'id': 'routing_' + prim, 'status': 'PASS' if ok else 'BLOCK',
                      'detail': detail})
        if not ok:
            gates_failed += 1

    if not args.json:
        for g in gates:
            if g['id'] in ('JSON', 'SECRETS'):
                print('GATE:{0} {1} -> {2}'.format(g['id'], g['detail'], g['status']))
            elif g['id'].startswith('routing_'):
                print('COUNT:{0} {1} -> {2}'.format(g['id'], g['detail'], g['status']))
            else:
                print('COUNT:{0}={1} -> {2}'.format(g['id'], g['detail'], g['status']))
        for w in routing_warns:
            print(w)

    if gates_failed > 0:
        if args.json:
            print(json.dumps({'mode': mode, 'gates': gates, 'files': [], 'stale': [],
                              'hashes': None, 'archive': None,
                              'summary': {'mode': mode, 'gates_failed': gates_failed,
                                          'blocked': True}}, indent=2, ensure_ascii=False))
        else:
            print('SUMMARY:gates_failed={0}'.format(gates_failed))
            print('STATUS:BLOCKED gates={0}'.format(gates_failed))
        sys.exit(3)

    # Diff scan
    diff = []
    n_same = n_changed = n_new = 0
    for e in file_map:
        src_sha = sha256_file(e['src'])
        if not Path(e['dst']).is_file():
            n_new += 1
            diff.append({'rel': e['rel'], 'status': 'NEW', 'src': e['src'], 'dst': e['dst'],
                         'live8': src_sha[:8], 'dep8': '', 'bytes': 0})
            if not args.json:
                print('NEW:{0}'.format(e['rel']))
        else:
            dst_sha = sha256_file(e['dst'])
            if src_sha == dst_sha:
                n_same += 1
                diff.append({'rel': e['rel'], 'status': 'SAME', 'src': e['src'], 'dst': e['dst'],
                             'live8': src_sha[:8], 'dep8': dst_sha[:8], 'bytes': 0})
                if not args.json:
                    print('SAME:{0} sha={1}'.format(e['rel'], src_sha[:8]))
            else:
                n_changed += 1
                diff.append({'rel': e['rel'], 'status': 'CHANGED', 'src': e['src'], 'dst': e['dst'],
                             'live8': src_sha[:8], 'dep8': dst_sha[:8], 'bytes': 0})
                if not args.json:
                    print('CHANGED:{0} live={1} deploy={2}'.format(e['rel'], src_sha[:8], dst_sha[:8]))

    # STALE scan (strict block happens BEFORE any write)
    live_names = [f.stem for f in live_agent_files]
    stale = get_stale_files(pkg, live_names)
    for s in stale:
        if not args.json:
            print('WARN:STALE:{0}'.format(s))
    if args.strict and stale:
        if args.json:
            print(json.dumps({'mode': mode, 'gates': gates,
                              'files': [{'rel': d['rel'], 'status': d['status'],
                                         'live_sha8': d['live8'], 'deploy_sha8': d['dep8']} for d in diff],
                              'stale': stale, 'hashes': None, 'archive': None,
                              'summary': {'mode': mode, 'gates_failed': 0,
                                          'stale': len(stale), 'blocked': True}},
                             indent=2, ensure_ascii=False))
        else:
            print('STATUS:BLOCKED stale={0}'.format(len(stale)))
        sys.exit(3)

    # Plan mode
    if mode == 'plan':
        hash_lines = len(get_hashes_scope(pkg))
        if args.json:
            print(json.dumps({'mode': 'plan', 'gates': gates,
                              'files': [{'rel': d['rel'], 'status': d['status'],
                                         'live_sha8': d['live8'], 'deploy_sha8': d['dep8']} for d in diff],
                              'stale': stale, 'hashes': {'lines': hash_lines, 'changed': None},
                              'archive': None,
                              'summary': {'mode': 'plan', 'scanned': len(diff), 'same': n_same,
                                          'changed': n_changed, 'new': n_new, 'stale': len(stale)}},
                             indent=2, ensure_ascii=False))
        else:
            print('PLAN:HASHES.txt files={0}'.format(hash_lines))
            print('SUMMARY:mode=plan scanned={0} same={1} changed={2} new={3} stale={4}'.format(
                len(diff), n_same, n_changed, n_new, len(stale)))
            print('STATUS:PLAN_OK')
        sys.exit(0)

    # Apply mode
    n_copied = n_failed = total_bytes = 0
    for e in diff:
        if e['status'] not in ('CHANGED', 'NEW'):
            continue
        dst = Path(e['dst'])
        os.makedirs(dst.parent, exist_ok=True)
        try:
            shutil.copyfile(e['src'], e['dst'])
        except OSError as ex:
            n_failed += 1
            if not args.json:
                print('ERROR:{0} copy failed: {1}'.format(e['rel'], ex))
            continue
        src_sha = sha256_file(e['src'])
        dst_sha = sha256_file(e['dst'])
        if src_sha != dst_sha:
            n_failed += 1
            if not args.json:
                print('ERROR:{0} hash mismatch after copy'.format(e['rel']))
            continue
        n_bytes = dst.stat().st_size
        n_copied += 1
        total_bytes += n_bytes
        if not args.json:
            print('COPIED:{0} sha={1} bytes={2}'.format(e['rel'], src_sha[:8], n_bytes))
            print('VERIFY:{0} identical'.format(e['rel']))
    if n_failed > 0:
        if args.json:
            print(json.dumps({'mode': 'apply', 'gates': gates,
                              'files': [{'rel': d['rel'], 'status': d['status'],
                                         'live_sha8': d['live8'], 'deploy_sha8': d['dep8']} for d in diff],
                              'stale': stale, 'hashes': None, 'archive': None,
                              'summary': {'mode': 'apply', 'scanned': len(diff), 'same': n_same,
                                          'changed': n_changed, 'new': n_new, 'copied': n_copied,
                                          'failed': n_failed, 'stale': len(stale), 'bytes': total_bytes}},
                             indent=2, ensure_ascii=False))
        else:
            print('STATUS:FAILED copied={0} failed={1} (copied files are KEPT - never deleted)'.format(
                n_copied, n_failed))
        sys.exit(3)

    # HASHES.txt
    try:
        hash_info = write_hashes_file(pkg)
    except OSError as ex:
        if not args.json:
            print('ERROR:HASHES write failed: {0}'.format(ex))
        sys.exit(3)
    if not args.json:
        if hash_info['changed']:
            print('EDITED:HASHES.txt lines={0}'.format(hash_info['lines']))
        else:
            print('SAME:HASHES.txt')

    # --archive (only after success)
    arch_info = None
    if args.archive:
        tmp = pkg / 'deploy-package.7z.tmp7z'
        proc = subprocess.run(
            [seven_zip, 'a', '-t7z', '-mx=5', '-w' + str(root),
             'deploy-package/deploy-package.7z.tmp7z', os.path.join('deploy-package', '*'),
             '-xr!*.tmp7z', '-xr!deploy-package.7z'],
            cwd=str(root), capture_output=True, text=True)
        if proc.returncode >= 2:
            if not args.json:
                print('ERROR:ARCHIVE 7z exit={0} (tmp KEPT - never deleted)'.format(proc.returncode))
            sys.exit(3)
        final = pkg / 'deploy-package.7z'
        os.replace(tmp, final)
        arch_sha = sha256_file(final)
        arch_bytes = final.stat().st_size
        arch_info = {'file': 'deploy-package.7z', 'sha8': arch_sha[:8], 'bytes': arch_bytes}
        if not args.json:
            print('ARCHIVED:deploy-package.7z sha={0} bytes={1}'.format(arch_sha[:8], arch_bytes))

    if not args.json:
        print('WARN:MANUAL commit deploy-package changes via the git-commit agent')
        print('WARN:MANUAL live-config changes take effect in a NEW opencode session')
        print('WARN:MANUAL target install via deploy-package\\scripts\\install.ps1')
        print('WARN:MANUAL recommended post-check: integrity-check + deploy-package\\scripts\\verify.ps1')

    if args.json:
        print(json.dumps({'mode': 'apply', 'gates': gates,
                          'files': [{'rel': d['rel'], 'status': d['status'],
                                     'live_sha8': d['live8'], 'deploy_sha8': d['dep8']} for d in diff],
                          'stale': stale,
                          'hashes': {'lines': hash_info['lines'], 'changed': hash_info['changed']},
                          'archive': arch_info,
                          'summary': {'mode': 'apply', 'scanned': len(diff), 'same': n_same,
                                      'changed': n_changed, 'new': n_new, 'copied': n_copied,
                                      'stale': len(stale), 'bytes': total_bytes}},
                         indent=2, ensure_ascii=False))
    else:
        print('SUMMARY:mode=apply scanned={0} same={1} changed={2} new={3} copied={4} '
              'stale={5} bytes={6}'.format(len(diff), n_same, n_changed, n_new, n_copied,
                                           len(stale), total_bytes))
        print('STATUS:SUCCESS')
    sys.exit(0)


if __name__ == '__main__':
    main()
