#!/usr/bin/env python3
"""
apply.py — POSIX mirror of apply.ps1

Usage:
    python apply.py --paste-json <path> [--plan-only] [--apply] [--push]

Output:
    STATUS:/DIFF:/EDITED:/SYNCED:/SHA256:/COMMITTED:/PUSHED:/ERROR: lines

Exit codes:
    0 success
    2 usage/environment error
    3 gate block
"""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


# Secret patterns (mirror git-commit gates).
SECRET_PATTERNS = [
    ('OpenAI-style key', re.compile(r'sk-[A-Za-z0-9_-]{20,}')),
    ('GitHub token', re.compile(r'gh[pousr]_[A-Za-z0-9]{30,}')),
    ('GitHub PAT', re.compile(r'github_pat_[A-Za-z0-9_]{22,}')),
    ('AWS access key', re.compile(r'AKIA[0-9A-Z]{16}')),
    ('Private key block', re.compile(r'-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----')),
    ('Slack token', re.compile(r'xox[baprs]-[A-Za-z0-9-]{10,}')),
    ('Google API key', re.compile(r'AIza[0-9A-Za-z_-]{35}')),
    ('Bearer literal', re.compile(r'Bearer\s+[A-Za-z0-9]{30,}')),
]


def find_secrets(text):
    hits = []
    for name, pattern in SECRET_PATTERNS:
        count = len(pattern.findall(text))
        if count:
            hits.append(f'{name} (x{count})')
    return hits


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


def git(repo, *args, check=False):
    return subprocess.run(['git', '-C', str(repo), *args], capture_output=True, text=True, check=check)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--paste-json', required=True)
    parser.add_argument('--plan-only', action='store_true')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--push', action='store_true')
    args = parser.parse_args()

    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)

    deployed = Path.home() / '.config' / 'opencode' / 'opencode.json'
    package = root / 'deploy-package' / 'opencode.json'
    diff_script = skill_dir / 'diff.js'

    # Validate inputs
    if not Path(args.paste_json).exists():
        print(f"ERROR: PasteJson not found: {args.paste_json}")
        sys.exit(2)

    if not deployed.exists():
        print(f"ERROR: deployed opencode.json not found: {deployed}")
        sys.exit(2)

    if not package.exists():
        print(f"ERROR: deploy-package/opencode.json not found: {package}")
        sys.exit(2)

    # Gate: secret scan on the raw paste (BLOCK before any edit).
    paste_text = Path(args.paste_json).read_text(encoding='utf-8', errors='replace')
    secret_hits = find_secrets(paste_text)
    if secret_hits:
        for hit in secret_hits:
            print(f"BLOCK: secret pattern in paste: {hit}")
        print(f"ERROR: paste blocked by {len(secret_hits)} secret gate(s)")
        sys.exit(3)

    # Step 1: Diff
    print("STATUS:DIFF_START")
    result = subprocess.run(
        ['node', str(diff_script), '-PasteJson', args.paste_json, '-Current', str(deployed)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"ERROR:diff failed: {result.stderr}")
        sys.exit(3 if result.returncode == 3 else 2)

    diff = json.loads(result.stdout)
    added = len(diff['added'])
    removed = len(diff['removed'])
    modified = len(diff['modified'])

    print(f"DIFF:added={added} removed={removed} modified={modified}")

    if added == 0 and removed == 0 and modified == 0:
        print("STATUS:NO_CHANGES")
        sys.exit(0)

    if args.plan_only:
        print("STATUS:PLAN_ONLY")
        print(f"DIFF:{json.dumps(diff, indent=2)}")
        sys.exit(0)

    if not args.apply:
        print("STATUS:DRY_RUN (use --apply to apply)")
        sys.exit(0)

    # Step 2: Apply merged edits (preserve all non-model sections)
    print("STATUS:APPLY_START")

    tmp_dir = Path(tempfile.gettempdir()) / 'opencode'
    tmp_dir.mkdir(parents=True, exist_ok=True)
    merged_temp = tmp_dir / 'merged-opencode.json'

    # diff.js performs the per-model merge into a temporary full config.
    merge_result = subprocess.run(
        ['node', str(diff_script), '-PasteJson', args.paste_json, '-Current', str(deployed),
         '-Merge', '-Out', str(merged_temp)],
        capture_output=True, text=True
    )
    if merge_result.returncode != 0:
        print(f"ERROR:merge failed: {merge_result.stderr}")
        sys.exit(3)

    # Per-edit JSON validation of the merged config before replacing the deployed one.
    try:
        json.loads(merged_temp.read_text(encoding='utf-8-sig'))
    except (json.JSONDecodeError, OSError) as e:
        print(f"ERROR: merged JSON failed validation: {e}")
        sys.exit(3)

    shutil.copy2(merged_temp, deployed)
    print(f"EDITED:deployed={deployed}")

    # Step 3: Sync to deploy-package
    shutil.copy2(deployed, package)
    print(f"SYNCED:package={package}")

    # Step 4: SHA256 verify
    def sha256(path):
        h = hashlib.sha256()
        with open(path, 'rb') as f:
            h.update(f.read())
        return h.hexdigest().upper()

    hash1 = sha256(deployed)
    hash2 = sha256(package)
    if hash1 != hash2:
        print(f"ERROR:SHA256 mismatch: deployed={hash1} package={hash2}")
        sys.exit(3)
    print(f"SHA256:identical={hash1}")

    # Step 5: Generate commit message
    parts = []
    if added > 0:
        parts.append(f"add {added} model(s)")
    if removed > 0:
        parts.append(f"remove {removed} model(s)")
    if modified > 0:
        parts.append(f"modify {modified} model(s)")
    summary = ", ".join(parts)

    commit_msg = f"feat(provider): {summary}"

    # Step 6: Commit (user's configured identity)
    name_res = git(root, 'config', 'user.name')
    email_res = git(root, 'config', 'user.email')
    git_name = name_res.stdout.strip()
    git_email = email_res.stdout.strip()
    if not git_name or not git_email:
        print(f"ERROR: git identity missing (user.name='{git_name}' user.email='{git_email}') "
              "- set it with: git config user.name \"...\"; git config user.email \"...\"")
        sys.exit(3)

    print("STATUS:COMMIT_START")
    commit_msg_file = tmp_dir / 'commit-msg.txt'
    commit_msg_file.write_text(commit_msg, encoding='utf-8')

    add_res = git(root, 'add', 'deploy-package/opencode.json')
    if add_res.returncode != 0:
        print(f"ERROR:git add failed: {add_res.stderr}")
        sys.exit(3)

    result = git(root, 'commit', '-F', str(commit_msg_file))
    if result.returncode != 0:
        print(f"ERROR:git commit failed: {result.stderr}")
        sys.exit(3)

    commit_hash = git(root, 'rev-parse', 'HEAD').stdout.strip()
    print(f"COMMITTED:hash={commit_hash} msg={commit_msg}")

    # Step 7: Push (optional, current branch)
    if args.push:
        print("STATUS:PUSH_START")
        branch = git(root, 'branch', '--show-current').stdout.strip()
        if not branch:
            print("ERROR: could not determine current branch")
            sys.exit(3)
        result = git(root, 'push', 'origin', branch)
        if result.returncode != 0:
            print(f"ERROR:git push failed: {result.stderr}")
            sys.exit(3)
        print(f"PUSHED:branch={branch}")

    print("STATUS:SUCCESS")
    sys.exit(0)


if __name__ == '__main__':
    main()