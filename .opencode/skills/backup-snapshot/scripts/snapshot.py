#!/usr/bin/env python3
"""
snapshot.py - POSIX mirror of snapshot.ps1

Pre-change snapshot of the live config: live agent .md files (--agents,
default) or agents + live opencode.json + live plugin + live and root
documentation (--full) into backup/<ts>[_<label>]/ with HASHES.txt (SHA256,
sorted) and MANIFEST.json, byte-verifying every copy. --compare <dir>
re-hashes the current state against a snapshot (SAME/CHANGED/MISSING_NOW/
NEW/CORRUPT report; --strict turns differences into exit 3). NEVER deletes
or modifies sources.

Usage:
    python snapshot.py [--agents | --full] [--label L] [--dest DIR]
                       [--compare DIR [--strict]] [--expected-agents N] [--json]

Output:
    COPIED:/SAME:/CHANGED:/MISSING_NOW:/NEW:/CORRUPT:/SUMMARY:/STATUS:/
    WARN:/ERROR:/BLOCK: lines

Exit codes:
    0 snapshot created / compare report
    2 usage/environment error
    3 copy/verify/manifest failure, invalid compare inputs, strict differences
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HASHES_RE = re.compile(r'^([0-9A-F]{64})  (.+)$')


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


def get_scope(mode, live_dir, root):
    scope = []
    for f in sorted((live_dir / 'agents').glob('*.md')):
        scope.append({'src': str(f), 'rel': 'live/agents/' + f.name})
    if mode == 'full':
        scope.append({'src': str(live_dir / 'opencode.json'), 'rel': 'live/opencode.json'})
        scope.append({'src': str(live_dir / 'plugins' / 'workflow-enforcement.ts'),
                      'rel': 'live/plugins/workflow-enforcement.ts'})
        for f in ('AGENTS', 'ARCHITECTURE', 'MCP_SETUP', 'PLUGIN', 'REVIEW_CONTEXT'):
            scope.append({'src': str(live_dir / (f + '.md')), 'rel': 'live/docs/' + f + '.md'})
        for f in ('ARCHITECTURE', 'AGENTS', 'PLUGIN', 'MCP_SETUP', 'REVIEW_CONTEXT', 'CHANGELOG'):
            scope.append({'src': str(root / (f + '.md')), 'rel': 'repo/docs/' + f + '.md'})
    return scope


def rel_to_repo(p, root):
    p = Path(p).resolve()
    try:
        return p.relative_to(root.resolve()).as_posix()
    except ValueError:
        return p.as_posix()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--agents', action='store_true')
    parser.add_argument('--full', action='store_true')
    parser.add_argument('--label', default='')
    parser.add_argument('--dest', default='')
    parser.add_argument('--compare', default='')
    parser.add_argument('--strict', action='store_true')
    parser.add_argument('--expected-agents', type=int, default=38)
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()

    if args.compare:
        if args.agents or args.full or args.label or args.dest:
            print('ERROR:--compare is mutually exclusive with --agents/--full/--label/--dest')
            sys.exit(2)
    else:
        if args.strict:
            print('ERROR:--strict requires --compare')
            sys.exit(2)
        if args.agents and args.full:
            print('ERROR:--agents and --full are mutually exclusive')
            sys.exit(2)
        if not args.agents and not args.full:
            args.agents = True

    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)
    if not root.is_dir():
        print(f'ERROR:repo root not found: {root}')
        sys.exit(2)
    live_dir = Path.home() / '.config' / 'opencode'
    if not live_dir.is_dir():
        print(f'ERROR:live config dir not found: {live_dir}')
        sys.exit(2)

    # ------------------------------------------------------------------ compare
    if args.compare:
        cmp_dir = Path(args.compare)
        if not cmp_dir.is_absolute():
            cmp_dir = root / args.compare
        if not cmp_dir.is_dir():
            print(f'ERROR:compare dir not found: {cmp_dir}')
            sys.exit(2)
        manifest_path = cmp_dir / 'MANIFEST.json'
        hashes_path = cmp_dir / 'HASHES.txt'
        if not manifest_path.is_file() or not hashes_path.is_file():
            print(f'BLOCK:MANIFEST.json and/or HASHES.txt missing in: {cmp_dir}')
            sys.exit(3)
        try:
            manifest = json.loads(read_raw(manifest_path)[0])
        except (ValueError, OSError) as e:
            print(f'BLOCK:MANIFEST.json does not parse: {e}')
            sys.exit(3)
        hashes_map = {}
        try:
            hashes_text, _ = read_raw(hashes_path)
        except OSError as e:
            print(f'BLOCK:HASHES.txt unreadable: {e}')
            sys.exit(3)
        for line in hashes_text.split('\n'):
            t = line.rstrip('\r')
            if not t:
                continue
            m = HASHES_RE.match(t)
            if not m:
                print(f'BLOCK:HASHES.txt line has bad format: {t}')
                sys.exit(3)
            hashes_map[m.group(2)] = m.group(1)

        entries = []
        same = changed = missing = new = corrupt = 0
        for f in (manifest.get('files') or []):
            rel = f['rel']
            backup_sha = f['sha256']
            src = f['src']
            status = ''
            cur_sha = ''
            if not Path(src).is_file():
                status = 'MISSING_NOW'
                missing += 1
            else:
                cur_sha = sha256_file(src)
                if cur_sha == backup_sha:
                    status = 'SAME'
                    same += 1
                else:
                    status = 'CHANGED'
                    changed += 1
            if not args.json:
                if status == 'SAME':
                    print(f'SAME:{rel}')
                elif status == 'CHANGED':
                    print(f'CHANGED:{rel} backup={backup_sha[:8]} current={cur_sha[:8]}')
                else:
                    print(f'MISSING_NOW:{rel}')
            entries.append({'rel': rel, 'status': status,
                            'backup_sha': backup_sha, 'current_sha': cur_sha})
            disk_path = cmp_dir / rel.replace('/', os.sep)
            disk_sha = sha256_file(disk_path) if disk_path.is_file() else ''
            hashes_sha = hashes_map.get(rel)
            bad = disk_sha != backup_sha or (hashes_sha is not None and hashes_sha != backup_sha)
            if bad:
                corrupt += 1
                disk8 = disk_sha[:8] if disk_sha else '--------'
                if not args.json:
                    print(f'CORRUPT:{rel} backup={backup_sha[:8]} disk={disk8}')
                for e in entries:
                    if e['rel'] == rel:
                        e['status'] = 'CORRUPT'
        manifest_rels = {f['rel'] for f in (manifest.get('files') or [])}
        for f in sorted((live_dir / 'agents').glob('*.md')):
            rel = 'live/agents/' + f.name
            if rel not in manifest_rels:
                new += 1
                entries.append({'rel': rel, 'status': 'NEW',
                                'backup_sha': '', 'current_sha': sha256_file(f)})
                if not args.json:
                    print(f'NEW:{rel}')
        differences = changed + missing + new + corrupt
        if args.json:
            print(json.dumps({'entries': entries, 'summary': {
                'same': same, 'changed': changed, 'missing': missing,
                'new': new, 'corrupt': corrupt}}, indent=2, ensure_ascii=False))
        else:
            print(f'SUMMARY:same={same} changed={changed} missing={missing} '
                  f'new={new} corrupt={corrupt}')
            print('STATUS:IDENTICAL' if differences == 0 else 'STATUS:DIFFERENCES')
        if args.strict and differences > 0:
            sys.exit(3)
        sys.exit(0)

    # ----------------------------------------------------------------- snapshot
    mode = 'full' if args.full else 'agents'
    scope = get_scope(mode, live_dir, root)
    if not scope:
        print('ERROR:no files in scope')
        sys.exit(2)

    for f in scope:
        src = Path(f['src'])
        if not src.is_file():
            print(f"ERROR:source missing/unreadable: {f['src']}")
            sys.exit(2)
        try:
            with open(src, 'rb'):
                pass
        except OSError:
            print(f"ERROR:source missing/unreadable: {f['src']}")
            sys.exit(2)

    if args.dest:
        dest = Path(args.dest)
        if not dest.is_absolute():
            dest = root / args.dest
    else:
        dest = root / 'backup' / (datetime.now().strftime('%Y-%m-%d_%H%M%S')
                                  + (f'_{args.label}' if args.label else ''))
    try:
        dest.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        print(f'ERROR:dest already exists: {dest}')
        sys.exit(2)
    except OSError as e:
        print(f'ERROR:dest creation failed: {dest} ({e})')
        sys.exit(3)

    agents_count = len(list((live_dir / 'agents').glob('*.md')))

    failed = copied = total_bytes = 0
    hash_lines = []
    manifest_files = []
    for f in scope:
        dst = dest / f['rel'].replace('/', os.sep)
        os.makedirs(dst.parent, exist_ok=True)
        src_sha = sha256_file(f['src'])
        try:
            shutil.copyfile(f['src'], dst)
        except OSError as e:
            print(f"ERROR:copy failed: {f['rel']} {e}")
            failed += 1
            continue
        dst_sha = sha256_file(dst)
        if src_sha != dst_sha:
            print(f"ERROR:hash mismatch after copy: {f['rel']}")
            failed += 1
            continue
        nbytes = dst.stat().st_size
        copied += 1
        total_bytes += nbytes
        hash_lines.append(f"{src_sha}  {f['rel']}")
        manifest_files.append({'src': f['src'], 'rel': f['rel'],
                               'sha256': src_sha, 'bytes': nbytes})
        if not args.json:
            print(f"COPIED:{f['rel']} sha={src_sha[:8]} bytes={nbytes}")

    status = 'FAILED' if failed else 'SUCCESS'
    created_utc = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    try:
        with open(dest / 'HASHES.txt', 'w', newline='\n', encoding='utf-8') as fh:
            # Sort key = the rel part after the 'HASH  ' prefix (SKILL.md: "sorted by rel path").
            fh.write('\n'.join(sorted(hash_lines, key=lambda s: s.split('  ', 1)[1])) + '\n')
    except OSError as e:
        print(f'ERROR:HASHES.txt write failed: {e}')
        sys.exit(3)
    manifest_doc = {
        'mode': mode,
        'label': args.label,
        'created_utc': created_utc,
        'status': status,
        'expected_agents': args.expected_agents,
        'agents_count': agents_count,
        'files_count': copied,
        'total_bytes': total_bytes,
        'files': manifest_files,
    }
    try:
        with open(dest / 'MANIFEST.json', 'w', newline='\n', encoding='utf-8') as fh:
            json.dump(manifest_doc, fh, indent=2, ensure_ascii=False)
            fh.write('\n')
    except OSError as e:
        print(f'ERROR:MANIFEST.json write failed: {e}')
        sys.exit(3)

    if failed:
        print(f'STATUS:FAILED copied={copied} failed={failed} '
              '(copied files are KEPT — re-run with a fresh dest)')
        sys.exit(3)
    if agents_count != args.expected_agents:
        print(f'WARN:live agents count={agents_count} expected={args.expected_agents} '
              '(snapshot taken anyway)')
    dest_rel = rel_to_repo(dest, root)
    if args.json:
        print(json.dumps({
            'mode': mode, 'label': args.label, 'created_utc': created_utc,
            'status': status, 'dest': dest_rel, 'files_count': copied,
            'total_bytes': total_bytes,
            'files': [{'rel': f['rel'], 'sha256': f['sha256'], 'bytes': f['bytes']}
                      for f in manifest_files]}, indent=2, ensure_ascii=False))
    else:
        print(f'SUMMARY:mode={mode} files={copied} bytes={total_bytes} dest={dest_rel}')
        print('STATUS:SUCCESS')
    sys.exit(0)


if __name__ == '__main__':
    main()
