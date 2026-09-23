#!/usr/bin/env python3
"""
add.py - POSIX mirror of add.ps1

Add ONE new subagent end-to-end across ALL synchronized places: live+deploy
agent .md (frontmatter from readonly/standard preset or --perm-template),
opencode.json agent section + primary task allow (live + deploy),
ROUTING_TABLES (plugin x3) and OPENCODE_ROUTING_TABLE (primary prompt x2),
whitelist tables and every derived counter in ARCHITECTURE.md x3 / AGENTS.md
x3 / PLUGIN.md x3 / MCP_SETUP.md x2, Subagent Models + Model Roles +
Distribution + Full Table rows, SHA256-verifies all mirrors, optional
conventional commit + push. Two-phase all-or-nothing: any failed gate/anchor
-> zero files written.

Usage:
    python add.py --agent <name> --model <provider/model-key>
                  --description <text> --primary <orchestrator|plankestrator>
                  (--permissions <readonly|standard> | --perm-template <agent>)
                  [--task-allow a,b] [--role R [--tier top|mid|low]]
                  [--body-file <path>] [--temperature 0.1]
                  [--plan-only | --apply] [--commit] [--push]

Output:
    STATUS:/PLAN:/WARN:/DIFF:/BLOCK:/CREATED:/EDITED:/VERIFY:/COMMITTED:/
    PUSHED:/ERROR: lines

Exit codes:
    0 success / plan-only
    2 usage/environment error
    3 gate block (zero writes)
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

LINE_SPLIT = re.compile(r'(\r\n|\r|\n)')
TOKEN_RX = re.compile(r'["\'][^"\']+["\']')
ROLE_ROW = re.compile(r'^\| (.+?) \| (.+?) \| (.+?) \| (.*?) \|$')
DIST_ROW = re.compile(r'^\| `(.+?)` \| (.+?) \| (\d+) \| (.*?) \|$')
SECTION_END_KONTROL = r'^\u041A\u043E\u043D\u0442\u0440\u043E\u043B\u044C \u0441\u0443\u043C\u043C\u044B:'

PRESETS = {
    'readonly': {
        'fm_yaml': [
            'edit: deny', 'write: deny', 'bash: deny', 'webfetch: deny',
            'patch: deny', 'todowrite: deny', 'question: deny',
            'read: allow', 'grep: allow', 'glob: allow',
            'serena_find_symbol: allow',
            'serena_find_referencing_symbols: allow',
            'serena_get_symbols_overview: allow',
            'serena_search_for_pattern: allow',
        ],
        'default_task': [],
        'full_table': {'edit': 'deny', 'write': 'deny', 'read': 'allow', 'bash': 'deny'},
    },
    'standard': {
        'fm_yaml': [
            'edit: deny', 'write: deny', 'read: allow', 'bash: deny',
            'unity-mcp.*: allow',
            'serena_find_symbol: allow',
            'serena_find_referencing_symbols: allow',
            'serena_get_symbols_overview: allow',
            'serena_rename_symbol: allow',
            'serena_safe_delete_symbol: allow',
            'serena_replace_symbol_body: allow',
            'serena_insert_after_symbol: allow',
        ],
        'default_task': ['view-image'],
        'full_table': {'edit': 'deny', 'write': 'deny', 'read': 'allow', 'bash': 'deny'},
    },
}


class EditError(Exception):
    pass


def read_raw(p):
    data = Path(p).read_bytes()
    bom = data.startswith(b'\xef\xbb\xbf')
    return data.decode('utf-8-sig' if bom else 'utf-8'), bom


def write_raw(p, text, bom):
    Path(p).write_bytes(text.encode('utf-8-sig' if bom else 'utf-8'))


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


def git(repo, *args):
    return subprocess.run(['git', '-C', str(repo), *args], capture_output=True, text=True)


def split_model_key(full):
    if not full:
        return None
    idx = full.find('/')
    if idx < 1 or idx >= len(full) - 1:
        return None
    return full[:idx], full[idx + 1:]


def split_lines_keep_eol(text):
    """[content, eol, content, eol, ...] - content at even indices."""
    return LINE_SPLIT.split(text)


def find_section_span(lines, start_pat, end_pat):
    start = -1
    for i in range(0, len(lines), 2):
        if re.match(start_pat, lines[i]):
            start = i
            break
    if start < 0:
        return None
    for j in range(start + 2, len(lines), 2):
        if re.match(end_pat, lines[j]):
            return start, j
    return None


def find_unique_line(lines, pattern):
    hits = [i for i in range(0, len(lines), 2) if re.match(pattern, lines[i])]
    if len(hits) != 1:
        raise EditError(f'anchor found {len(hits)} times (expected 1): {pattern}')
    return hits[0]


def split_tokens(cell):
    if not cell or not cell.strip():
        return []
    return [t.strip() for t in cell.split(',') if t.strip()]


def get_eol(lines, content_idx):
    if content_idx + 1 < len(lines):
        return lines[content_idx + 1]
    return ''


def detect_eol(text):
    crlf = len(re.findall(r'\r\n', text))
    lf = len(re.findall(r'\n', text))
    return '\r\n' if crlf >= (lf - crlf) else '\n'


def find_json_span(text, start_pattern):
    """String-aware brace scanner: returns (open, close) of the paired {...}
    starting at the first '{' at/after the start-pattern match end."""
    m = re.search(start_pattern, text)
    if not m:
        return None
    open_idx = text.find('{', m.start() + len(m.group(0)) - 1)
    if open_idx < 0:
        return None
    depth = 0
    in_str = False
    esc = False
    for i in range(open_idx, len(text)):
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == '\\':
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return (open_idx, i)
    return None


# ============================================================================
# Counter parsers (cross-check)
# ============================================================================

def count_task_allow(cfg, primary):
    try:
        node = cfg['agent'][primary]['permission']['task']
    except (KeyError, TypeError):
        return None
    if not isinstance(node, dict):
        return None
    return sum(1 for k, v in node.items() if k != '*' and v == 'allow')


def count_routing_plugin(ts_text, primary):
    outer = re.search(r'(?s)const ROUTING_TABLES = \{(.*?)\r?\n\}', ts_text)
    if not outer:
        return None
    inner = re.search(r'(?s)' + re.escape(primary) + r'\s*:\s*\[(.*?)\]', outer.group(1))
    if not inner:
        return None
    return len(TOKEN_RX.findall(inner.group(1)))


def get_routing_tokens(ts_text, primary):
    outer = re.search(r'(?s)const ROUTING_TABLES = \{(.*?)\r?\n\}', ts_text)
    if not outer:
        return None
    inner = re.search(r'(?s)' + re.escape(primary) + r'\s*:\s*\[(.*?)\]', outer.group(1))
    if not inner:
        return None
    return [m.group(0).strip('"\'') for m in TOKEN_RX.finditer(inner.group(1))]


def count_routing_line(md_text):
    m = re.search(r'(?m)^OPENCODE_ROUTING_TABLE = \[(.*)\]\r?$', md_text)
    if not m:
        return None
    toks = [t.strip('"\'') for t in split_tokens(m.group(1)) if t.strip('"\'')]
    return len(toks)


def _whitelist_header_and_table(text, primary):
    hm = re.search(r'^### ' + re.escape(primary) + r' Whitelist \((\d+) agents\)', text, re.M)
    if not hm:
        return None
    after = text[hm.end():]
    first_pipe = re.search(r'(?m)^\|', after)
    if not first_pipe:
        return int(hm.group(1)), None
    rest = after[first_pipe.start():]
    blank = re.search(r'\r?\n[ \t]*\r?\n', rest)
    tbl = rest[:blank.start()] if blank else rest
    return int(hm.group(1)), tbl


def get_whitelist_count(text, primary):
    """Numbered rows variant (ARCHITECTURE.md)."""
    ht = _whitelist_header_and_table(text, primary)
    if ht is None:
        return None
    header, tbl = ht
    if tbl is None:
        return {'header': header, 'rows': -1}
    rows = len(re.findall(r'(?m)^\|\s*\d+\s*\|', tbl))
    return {'header': header, 'rows': rows}


def get_whitelist_count_unnumbered(text, primary):
    """Unnumbered rows variant (AGENTS/PLUGIN/MCP §6)."""
    ht = _whitelist_header_and_table(text, primary)
    if ht is None:
        return None
    header, tbl = ht
    if tbl is None:
        return {'header': header, 'rows': -1}
    rows = len(re.findall(r'(?m)^\| [^-|]', tbl)) - 1
    return {'header': header, 'rows': rows}


# ============================================================================
# Anchor edit functions (raise EditError on any anchor failure)
# ============================================================================

def edit_numbered_counter(text, pattern, group_indices):
    """Universal +1 substitution of numbered capture groups in a UNIQUE match.
    Returns (new_text, old_list, new_list)."""
    ms = list(re.finditer(pattern, text))
    if len(ms) != 1:
        raise EditError(f'anchor found {len(ms)} times (expected 1): {pattern}')
    m = ms[0]
    spans = []
    old = []
    for gi in group_indices:
        g = m.group(gi)
        if g is None:
            raise EditError(f'capture group {gi} did not participate: {pattern}')
        spans.append([m.start(gi), m.end(gi), str(int(g) + 1)])
        old.append(int(g))
    spans.sort(key=lambda s: s[0])
    new = []
    new_text = text
    for s in reversed(spans):
        new_text = new_text[:s[0]] + s[2] + new_text[s[1]:]
        new.insert(0, int(s[2]))
    return new_text, old, new


def edit_routing_array(text, primary, new_name, section_heading=None):
    """Append a token to ROUTING_TABLES.<primary> (TS code blocks).
    Returns (new_text, old_count)."""
    base = 0
    if section_heading:
        h = re.search(section_heading, text, re.M)
        if not h:
            raise EditError(f'anchor: section not found: {section_heading}')
        base = h.start()
    sub = text[base:]
    outer = re.search(r'(?s)const ROUTING_TABLES = \{(.*?)\r?\n\}', sub)
    if not outer:
        raise EditError('anchor: const ROUTING_TABLES not found')
    inner = re.search(r'(?s)' + re.escape(primary) + r'\s*:\s*\[(.*?)\]', outer.group(1))
    if not inner:
        raise EditError(f'anchor: ROUTING_TABLES.{primary} array not found')
    inner_text = inner.group(1)
    tokens = list(TOKEN_RX.finditer(inner_text))
    if not tokens:
        raise EditError(f'anchor: ROUTING_TABLES.{primary} has no tokens')
    for t in tokens:
        if t.group(0).strip('"\'') == new_name:
            raise EditError(f'token already present in ROUTING_TABLES.{primary}: {new_name}')
    old_count = len(tokens)
    last = tokens[-1]
    abs_base = base + outer.start() + outer.start(1) + inner.start(1)
    insert_pos = abs_base + last.end()
    line_start = text.rfind('\n', 0, insert_pos) + 1
    lead = text[line_start:insert_pos]
    indent = lead[:len(lead) - len(lead.lstrip(' \t'))] if lead else ''
    eol_m = re.search(r'\r\n|\r|\n', text[insert_pos:])
    eol = eol_m.group(0) if eol_m else ''
    if not eol:
        eol = detect_eol(text)
    quote = last.group(0)[0]
    insert_text = ',' + eol + indent + quote + new_name + quote
    new_text = text[:insert_pos] + insert_text + text[insert_pos:]
    return new_text, old_count


def edit_whitelist_table(text, primary, new_row_content):
    """Whitelist table: header +1, append row. Returns (new_text, old_count)."""
    lines = split_lines_keep_eol(text)
    span = find_section_span(
        lines, r'^### ' + re.escape(primary) + r' Whitelist \((\d+) agents\)', r'^#{2,3} ')
    if not span:
        raise EditError(f"anchor: whitelist section not found for '{primary}'")
    hm = re.search(r'\((\d+) agents\)', lines[span[0]])
    if not hm:
        raise EditError('anchor: whitelist header count not parsed')
    old = int(hm.group(1))
    lines[span[0]] = re.sub(r'\(\d+ agents\)', f'({old + 1} agents)', lines[span[0]], count=1)
    last_row = -1
    for i in range(span[0] + 2, span[1], 2):
        if lines[i].startswith('|'):
            last_row = i
    if last_row < 0:
        raise EditError(f"anchor: whitelist table rows not found for '{primary}'")
    eol = get_eol(lines, last_row) or detect_eol(text) or '\r\n'
    lines.insert(last_row + 2, new_row_content)
    lines.insert(last_row + 3, eol)
    return ''.join(lines), old


def edit_subagent_models_append(text, new_row_content):
    """ARCH '## Subagent Models': append '| <name> | <model> |' after the last
    data row. Returns new_text."""
    lines = split_lines_keep_eol(text)
    span = find_section_span(lines, r'^## Subagent Models', r'^## ')
    if not span:
        raise EditError('anchor: ## Subagent Models section not found')
    last_row = -1
    for i in range(span[0] + 2, span[1], 2):
        if re.match(r'^\| .+? \| .+? \|$', lines[i]):
            last_row = i
    if last_row < 0:
        raise EditError('anchor: Subagent Models data rows not found')
    eol = get_eol(lines, last_row) or detect_eol(text) or '\r\n'
    lines.insert(last_row + 2, new_row_content)
    lines.insert(last_row + 3, eol)
    return ''.join(lines)


def edit_model_roles_add(text, agent, new_model, role, tier):
    """ARCH '## Model Roles': ADD branch. Returns (new_text, new_role, warns)."""
    warns = []
    lines = split_lines_keep_eol(text)
    span = find_section_span(lines, r'^## Model Roles', SECTION_END_KONTROL)
    if not span:
        raise EditError('anchor: ## Model Roles section not found')
    rows = []
    for i in range(span[0], span[1], 2):
        m = ROLE_ROW.match(lines[i])
        if m and m.group(1).strip() != 'Role':
            rows.append({'idx': i, 'role': m.group(1).strip(), 'model': m.group(2).strip(),
                         'tier': m.group(3).strip(), 'agents': m.group(4).strip()})
    if not rows:
        raise EditError('anchor: Model Roles data rows not found')
    cands = [r for r in rows if r['model'] == new_model]
    new_role = None
    if len(cands) == 1:
        if role and role != cands[0]['role']:
            raise EditError(f"-Role '{role}' does not match the single role row '{cands[0]['role']}'")
        nr = cands[0]
        toks = split_tokens(nr['agents'])
        if agent not in toks:
            toks.append(agent)
        lines[nr['idx']] = f"| {nr['role']} | {nr['model']} | {nr['tier']} | {', '.join(toks)} |"
        new_role = nr['role']
    elif len(cands) > 1:
        if not role:
            raise EditError('model maps to >1 role rows; -Role required. Candidates: '
                            + ', '.join(r['role'] for r in cands))
        m2 = [r for r in cands if r['role'] == role]
        if len(m2) != 1:
            raise EditError(f"-Role '{role}' not found among candidate rows: "
                            + ', '.join(r['role'] for r in cands))
        nr = m2[0]
        toks = split_tokens(nr['agents'])
        if agent not in toks:
            toks.append(agent)
        lines[nr['idx']] = f"| {nr['role']} | {nr['model']} | {nr['tier']} | {', '.join(toks)} |"
        new_role = nr['role']
    else:
        if not role or not tier:
            raise EditError('model has no role row; -Role and -Tier required. Available roles: '
                            + ', '.join(r['role'] for r in rows))
        warns.append(f"WARN:new role '{role}' requires CHANGELOG justification")
        last = rows[-1]
        eol = get_eol(lines, last['idx']) or '\r\n'
        insert_at = last['idx'] + 2
        lines[insert_at:insert_at] = [f'| {role} | {new_model} | {tier} | {agent} |', eol]
        new_role = role
    return ''.join(lines), new_role, warns


def edit_task_whitelist(text, primary, new_name):
    """MCP '**Task Whitelist (N agents):**' of -Primary: header +1, comma list
    append. Returns (new_text, old_count)."""
    lines = split_lines_keep_eol(text)
    hit_idx = -1
    for i in range(0, len(lines), 2):
        m = re.match(r'^\*\*Task Whitelist \((\d+) agents\):\*\*$', lines[i])
        if m:
            owner = None
            for j in range(i - 2, -1, -2):
                hm = re.match(r'^#### (orchestrator|plankestrator)$', lines[j])
                if hm:
                    owner = hm.group(1)
                    break
            if owner == primary:
                if hit_idx >= 0:
                    raise EditError(f"anchor: Task Whitelist for '{primary}' found more than once")
                hit_idx = i
    if hit_idx < 0:
        raise EditError(f"anchor: Task Whitelist header not found for '{primary}'")
    hm = re.search(r'\((\d+) agents\)', lines[hit_idx])
    old_count = int(hm.group(1))
    lines[hit_idx] = re.sub(r'\(\d+ agents\)', f'({old_count + 1} agents)',
                            lines[hit_idx], count=1)
    list_idx = -1
    for i in range(hit_idx + 2, len(lines), 2):
        if lines[i].strip():
            list_idx = i
            break
    if list_idx < 0:
        raise EditError('anchor: Task Whitelist comma list not found')
    toks = split_tokens(lines[list_idx])
    if new_name in toks:
        raise EditError(f'token already present in Task Whitelist: {new_name}')
    lines[list_idx] = lines[list_idx].rstrip() + ', ' + new_name
    return ''.join(lines), old_count


def edit_distribution_add(text, agent, new_short):
    """MCP '### Models Distribution': ADD branch.
    Returns (new_text, shorts, row_created, new_count, warns)."""
    warns = []
    lines = split_lines_keep_eol(text)
    span = find_section_span(lines, r'^### Models Distribution', r'^### ')
    if not span:
        raise EditError('anchor: ### Models Distribution section not found')

    def parse_rows(bound_extra=0):
        rows = []
        bound = min(span[1] + bound_extra, len(lines))
        for i in range(span[0], bound, 2):
            m = DIST_ROW.match(lines[i])
            if m and m.group(1).strip() != 'Model':
                rows.append({'idx': i, 'short': m.group(1).strip(),
                             'provider': m.group(2).strip(), 'count': int(m.group(3)),
                             'agents': m.group(4).strip()})
        return rows

    rows = parse_rows()
    if not rows:
        raise EditError('anchor: Models Distribution data rows not found')
    new_rows = [r for r in rows if r['short'] == new_short]
    row_created = False
    new_count = 0
    if len(new_rows) == 1:
        nr = new_rows[0]
        toks = split_tokens(nr['agents'])
        if agent not in toks:
            toks.append(agent)
        lines[nr['idx']] = (f"| `{nr['short']}` | {nr['provider']} | {len(toks)} "
                            f"| {', '.join(toks)} |")
        new_count = len(toks)
    elif len(new_rows) == 0:
        last = rows[-1]
        eol = get_eol(lines, last['idx']) or '\r\n'
        insert_at = last['idx'] + 2
        lines[insert_at:insert_at] = [f'| `{new_short}` | bifrost-litellm | 1 | {agent} |', eol]
        row_created = True
        new_count = 1
    else:
        raise EditError(f"anchor: Distribution row for '{new_short}' found "
                        f"{len(new_rows)} times (expected 1)")
    shorts = [r['short'] for r in parse_rows(bound_extra=2)]
    return ''.join(lines), shorts, row_created, new_count, warns


def edit_summary_models_row(text, shorts):
    """MCP Summary '| Models | N | ... |' regenerated from distribution shorts."""
    lines = split_lines_keep_eol(text)
    pat = re.compile(r'^\| Models \| \d+ \| bifrost-litellm \(.*\) \|$')
    hits = [i for i in range(0, len(lines), 2) if pat.match(lines[i])]
    if len(hits) != 1:
        raise EditError(f'anchor: Summary Models row found {len(hits)} times (expected 1)')
    lines[hits[0]] = f"| Models | {len(shorts)} | bifrost-litellm ({', '.join(shorts)}) |"
    return ''.join(lines)


def edit_full_table_append(text, new_row_content):
    """MCP '### Subagents - Full Table': append row after the last **agent** row."""
    lines = split_lines_keep_eol(text)
    span = find_section_span(lines, r'^### Subagents \u2014 Full Table', r'^### ')
    if not span:
        raise EditError('anchor: ### Subagents Full Table section not found')
    last_row = -1
    for i in range(span[0] + 2, span[1], 2):
        if lines[i].startswith('| **'):
            last_row = i
    if last_row < 0:
        raise EditError('anchor: Full Table data rows not found')
    eol = get_eol(lines, last_row) or detect_eol(text) or '\r\n'
    lines.insert(last_row + 2, new_row_content)
    lines.insert(last_row + 3, eol)
    return ''.join(lines)


def edit_alpha_insert(text, file_name):
    """MCP '**Subagents (N):**': alphabetical insert of '- <name>.md'."""
    lines = split_lines_keep_eol(text)
    start = find_unique_line(lines, r'^\*\*Subagents \(\d+\):\*\*$')
    end = start
    for i in range(start + 2, len(lines), 2):
        if re.match(r'^- .+\.md$', lines[i]):
            end = i
        else:
            break
    if end == start:
        raise EditError('anchor: Subagents file list not found')
    insert_at = -1
    for i in range(start + 2, end + 2, 2):
        cur = lines[i][2:]
        if cur > file_name:
            insert_at = i
            break
    eol = get_eol(lines, end) or detect_eol(text) or '\r\n'
    new_content = '- ' + file_name
    if insert_at < 0:
        lines.insert(end + 2, new_content)
        lines.insert(end + 3, eol)
    else:
        lines.insert(insert_at, new_content)
        lines.insert(insert_at + 1, eol)
    return ''.join(lines)


def edit_tree_insert(text, file_name):
    """MCP '### Agent Files List': insert a branch line before the last corner."""
    lines = split_lines_keep_eol(text)
    anchor = find_unique_line(lines, r'^### Agent Files List \((\d+) files\)$')
    last_corner = -1
    for i in range(anchor + 2, len(lines), 2):
        if re.match(r'^\u2514\u2500\u2500 ', lines[i]):
            last_corner = i
            break
    if last_corner < 0:
        raise EditError('anchor: Agent Files List tree not found')
    eol = get_eol(lines, last_corner) or detect_eol(text) or '\r\n'
    branch = '\u251C\u2500\u2500'
    lines.insert(last_corner, branch + ' ' + file_name)
    lines.insert(last_corner + 1, eol)
    return ''.join(lines)


def edit_routing_line(text, new_name):
    """Primary .md: append '["<name>"]' to the OPENCODE_ROUTING_TABLE line.
    Returns (new_text, old_count)."""
    m = re.search(r'(?m)^OPENCODE_ROUTING_TABLE = \[(.*)\]\r?$', text)
    if not m:
        raise EditError('anchor: OPENCODE_ROUTING_TABLE line not found')
    toks = [t.strip('"\'') for t in split_tokens(m.group(1)) if t.strip('"\'')]
    if new_name in toks:
        raise EditError(f'token already present in OPENCODE_ROUTING_TABLE: {new_name}')
    old_count = len(toks)
    new_inner = m.group(1).rstrip() + ', "' + new_name + '"'
    new_text = text[:m.start(1)] + new_inner + text[m.end(1):]
    return new_text, old_count


def edit_json_agent_section(text, section_text):
    """opencode.json: insert the new agent section right after '  "agent": {'."""
    lines = split_lines_keep_eol(text)
    anchor = find_unique_line(lines, r'^  "agent": \{$')
    eol = get_eol(lines, anchor) or detect_eol(text) or '\r\n'
    lines.insert(anchor + 2, section_text)
    lines.insert(anchor + 3, eol)
    return ''.join(lines)


def edit_primary_task_allow(text, primary, new_name):
    """opencode.json: add '"<name>": "allow"' to the primary task block."""
    anchor_pat = r'(?m)^    "' + re.escape(primary) + r'": \{$'
    if not re.search(anchor_pat, text):
        raise EditError(f"anchor: agent section for '{primary}' not found in opencode.json")
    sec_span = find_json_span(text, anchor_pat)
    if not sec_span:
        raise EditError(f"anchor: agent section span not resolved for '{primary}'")
    sec_text = text[sec_span[0]:sec_span[1] + 1]
    if not re.search(r'"task":\s*\{', sec_text):
        raise EditError(f"anchor: task block not found for '{primary}'")
    task_span = find_json_span(sec_text, r'"task":\s*\{')
    if not task_span:
        raise EditError(f"anchor: task span not resolved for '{primary}'")
    task_text = sec_text[task_span[0]:task_span[1] + 1]
    if re.search('"' + re.escape(new_name) + '"', task_text):
        raise EditError(f'token already present in task block of {primary}: {new_name}')
    abs_close = sec_span[0] + task_span[1]
    insert_pos = abs_close
    while insert_pos > 0 and text[insert_pos - 1].isspace():
        insert_pos -= 1
    eol = detect_eol(text)
    insert_text = ',' + eol + '          "' + new_name + '": "allow"'
    new_text = text[:insert_pos] + insert_text + text[insert_pos:]
    return new_text


def add_fm_task_extras(perm_lines, extras):
    """Insert '    <tok>: allow' lines into the frontmatter task sub-block
    (after the '"*": deny' line). Extras already present are skipped."""
    if not extras:
        return list(perm_lines)
    task_idx = -1
    for i, l in enumerate(perm_lines):
        if re.match(r'^task:\s*$', l):
            task_idx = i
            break
    if task_idx < 0:
        out = list(perm_lines)
        out.append('task:')
        out.append('    "*": deny')
        for t in extras:
            out.append(f'    {t}: allow')
        return out
    existing_allow = set()
    for l in perm_lines[task_idx + 1:]:
        m = re.match(r'^\s*"?([^:"\']+)"?:\s*allow\s*$', l)
        if m:
            existing_allow.add(m.group(1).strip())
    extras2 = [t for t in extras if t not in existing_allow]
    star_idx = -1
    for i in range(task_idx + 1, len(perm_lines)):
        if re.match(r'^\s*"\*": deny\s*$', perm_lines[i]):
            star_idx = i
    out = []
    for i, l in enumerate(perm_lines):
        out.append(l)
        if i == star_idx:
            for t in extras2:
                out.append(f'    {t}: allow')
    if star_idx < 0:
        for t in extras2:
            out.append(f'    {t}: allow')
    return out


# ============================================================================
# Main
# ============================================================================

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--agent', default='')
    parser.add_argument('--model', default='')
    parser.add_argument('--description', default='')
    parser.add_argument('--primary', default='')
    parser.add_argument('--permissions', default='')
    parser.add_argument('--perm-template', default='')
    parser.add_argument('--task-allow', default='')
    parser.add_argument('--role', default='')
    parser.add_argument('--tier', default='')
    parser.add_argument('--body-file', default='')
    parser.add_argument('--temperature', type=float, default=0.1)
    parser.add_argument('--plan-only', action='store_true')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--commit', action='store_true')
    parser.add_argument('--push', action='store_true')
    args = parser.parse_args()

    # --- Flag validation (usage errors -> exit 2) ---------------------------
    usage_line = ('USAGE: add.py --agent <name> --model <provider/model-key> '
                  '--description <text> --primary <orchestrator|plankestrator> '
                  '(--permissions <readonly|standard> | --perm-template <agent>) '
                  '[--task-allow a,b] [--role R [--tier top|mid|low]] '
                  '[--body-file <path>] [--temperature 0.1] '
                  '[--plan-only | --apply] [--commit] [--push]')
    missing = []
    if not args.agent:
        missing.append('--agent')
    if not args.model:
        missing.append('--model')
    if not args.description:
        missing.append('--description')
    if not args.primary:
        missing.append('--primary')
    if missing:
        print(usage_line)
        for m in missing:
            print(f'ERROR:missing required parameter: {m}')
        sys.exit(2)
    if not args.permissions and not args.perm_template:
        print(usage_line)
        print('ERROR:either --permissions <readonly|standard> or --perm-template <agent> is required')
        sys.exit(2)
    if args.permissions and args.perm_template:
        print('ERROR:--permissions and --perm-template are mutually exclusive')
        sys.exit(2)
    if args.permissions and args.permissions not in ('readonly', 'standard'):
        print(f"ERROR:--permissions must be readonly or standard (got '{args.permissions}')")
        sys.exit(2)
    if args.plan_only and args.apply:
        print('ERROR:--plan-only and --apply are mutually exclusive')
        sys.exit(2)
    if not args.plan_only and not args.apply:
        args.plan_only = True
    if args.push and not args.commit:
        print('ERROR:--push requires --commit')
        sys.exit(2)
    if args.tier and not args.role:
        print('ERROR:--tier requires --role')
        sys.exit(2)
    if args.tier and args.tier not in ('top', 'mid', 'low'):
        print(f"ERROR:--tier must be one of: top, mid, low (got '{args.tier}')")
        sys.exit(2)
    if args.primary not in ('orchestrator', 'plankestrator'):
        print(f"ERROR:--primary must be orchestrator or plankestrator (got '{args.primary}')")
        sys.exit(2)

    # --- Paths ----------------------------------------------------------------
    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)
    live_dir = Path.home() / '.config' / 'opencode'
    if not live_dir.is_dir():
        print(f'ERROR:live config dir not found: {live_dir}')
        sys.exit(2)

    live_agent_md = live_dir / 'agents' / f'{args.agent}.md'
    deploy_agent_md = root / 'deploy-package' / 'agents' / f'{args.agent}.md'
    live_cfg_path = live_dir / 'opencode.json'
    deploy_cfg_path = root / 'deploy-package' / 'opencode.json'
    plugin_paths = [live_dir / 'plugins' / 'workflow-enforcement.ts',
                    root / 'plugins' / 'workflow-enforcement.ts',
                    root / 'deploy-package' / 'plugins' / 'workflow-enforcement.ts']
    primary_live_md = live_dir / 'agents' / f'{args.primary}.md'
    primary_deploy_md = root / 'deploy-package' / 'agents' / f'{args.primary}.md'
    arch_paths = [root / 'ARCHITECTURE.md',
                  root / 'opencode-config' / 'ARCHITECTURE.md',
                  root / 'deploy-package' / 'project-files' / 'ARCHITECTURE.md']
    agents_md_paths = [root / 'AGENTS.md',
                       root / 'opencode-config' / 'AGENTS.md',
                       root / 'deploy-package' / 'project-files' / 'AGENTS.md']
    plugin_md_paths = [root / 'PLUGIN.md',
                       root / 'opencode-config' / 'PLUGIN.md',
                       root / 'deploy-package' / 'project-files' / 'PLUGIN.md']
    mcp_paths = [root / 'MCP_SETUP.md',
                 root / 'deploy-package' / 'project-files' / 'MCP_SETUP.md']

    # New agent files must NOT exist; all 17 edit targets must exist.
    if live_agent_md.is_file() or deploy_agent_md.is_file():
        print(f'BLOCK:agent already exists: {args.agent} (live/deploy .md file present)')
        sys.exit(3)
    edit_targets = [live_cfg_path, deploy_cfg_path] + plugin_paths + \
        [primary_live_md, primary_deploy_md] + arch_paths + agents_md_paths + \
        plugin_md_paths + mcp_paths
    for t in edit_targets:
        if not t.is_file():
            print(f'ERROR:target file not found: {t}')
            sys.exit(2)
    if args.body_file and not Path(args.body_file).is_file():
        print(f'ERROR:-BodyFile not found: {args.body_file}')
        sys.exit(2)

    def rel_path(p):
        p = Path(p).resolve()
        try:
            return 'live:' + p.relative_to(live_dir.resolve()).as_posix()
        except ValueError:
            pass
        try:
            return p.relative_to(root.resolve()).as_posix()
        except ValueError:
            return str(p)

    # --- Name validation -------------------------------------------------------
    if not re.match(r'^[a-z][a-z0-9-]*$', args.agent):
        print(f"ERROR:name malformed (expected ^[a-z][a-z0-9-]*$): '{args.agent}'")
        sys.exit(2)
    if args.agent in ('orchestrator', 'plankestrator'):
        print('BLOCK:primary agent creation is manual (orchestrator/plankestrator)')
        sys.exit(3)

    # --- Model validation --------------------------------------------------------
    key_parts = split_model_key(args.model)
    if not key_parts:
        print(f"ERROR:model key must be provider/model-key (got '{args.model}')")
        sys.exit(2)
    model_provider, model_key = key_parts
    if model_provider != 'bifrost-litellm':
        print(f"BLOCK:provider '{model_provider}' is not bifrost-litellm")
        sys.exit(3)
    try:
        cfg_text, _ = read_raw(live_cfg_path)
        cfg = json.loads(cfg_text)
    except (ValueError, OSError) as e:
        print(f'BLOCK:live opencode.json is not valid JSON: {e}')
        sys.exit(3)
    models = ((cfg.get('provider') or {}).get(model_provider) or {}).get('models')
    model_exists = isinstance(models, dict) and model_key in models
    if not model_exists:
        print(f'BLOCK:model not found in provider models: {args.model}')
        sys.exit(3)

    # --- Existence check: no routing table / json section may mention the name --
    if re.search(r'(?m)^    "' + re.escape(args.agent) + r'": \{', cfg_text):
        print(f"BLOCK:agent already exists: opencode.json agent section '{args.agent}'")
        sys.exit(3)
    for pp in plugin_paths:
        ts_text, _ = read_raw(pp)
        for p in ('orchestrator', 'plankestrator'):
            tokens = get_routing_tokens(ts_text, p)
            if tokens is not None and args.agent in tokens:
                print(f'BLOCK:agent already exists in routing table (plugin {p}): {args.agent}')
                sys.exit(3)
    other_primary = 'plankestrator' if args.primary == 'orchestrator' else 'orchestrator'
    for pm in (primary_live_md, live_dir / 'agents' / f'{other_primary}.md'):
        pm_text, _ = read_raw(pm)
        m_line = re.search(r'(?m)^OPENCODE_ROUTING_TABLE = \[(.*)\]\r?$', pm_text)
        if m_line:
            toks = [t.strip('"\'') for t in split_tokens(m_line.group(1)) if t.strip('"\'')]
            if args.agent in toks:
                print(f'BLOCK:agent already exists in OPENCODE_ROUTING_TABLE '
                      f'({pm.name}): {args.agent}')
                sys.exit(3)
    for p in ('orchestrator', 'plankestrator'):
        node = (((cfg.get('agent') or {}).get(p) or {}).get('permission') or {}).get('task')
        if isinstance(node, dict) and args.agent in node:
            print(f'BLOCK:agent already exists in opencode.json task allow of {p}: {args.agent}')
            sys.exit(3)

    print(f'STATUS:ADD_START agent={args.agent} model={args.model} primary={args.primary}')

    # --- Permission resolution (preset or template) ------------------------------
    task_allow_list = split_tokens(args.task_allow)
    warns = []
    fm_perm_lines = []
    json_perm_lines = []
    task_entries = []
    full_cells = None
    tpl_json_section = None

    if args.perm_template:
        tpl_live_md = live_dir / 'agents' / f'{args.perm_template}.md'
        if not tpl_live_md.is_file():
            print(f'ERROR:-PermTemplate agent .md not found: {tpl_live_md}')
            sys.exit(2)
        if not re.search(r'(?m)^    "' + re.escape(args.perm_template) + r'": \{', cfg_text):
            print(f'ERROR:-PermTemplate agent section not found in opencode.json: '
                  f'{args.perm_template}')
            sys.exit(2)
        tpl_anchor = r'(?m)^    "' + re.escape(args.perm_template) + r'": \{$'
        try:
            span = find_json_span(cfg_text, tpl_anchor)
        except Exception:
            span = None
        if not span:
            print(f'BLOCK:-PermTemplate section span not resolved: {args.perm_template}')
            sys.exit(3)
        am = re.search(tpl_anchor, cfg_text)
        tpl_section = cfg_text[am.start():span[1] + 1]
        tpl_md_text, _ = read_raw(tpl_live_md)
        tpl_lines = split_lines_keep_eol(tpl_md_text)
        perm_start = -1
        for i in range(0, len(tpl_lines), 2):
            if re.match(r'^permission:[ \t]*$', tpl_lines[i]):
                perm_start = i
                break
        if perm_start < 0:
            print(f'BLOCK:-PermTemplate frontmatter has no permission block: {args.perm_template}')
            sys.exit(3)
        fm_perm_lines = []
        for i in range(perm_start + 2, len(tpl_lines), 2):
            if re.match(r'^---[ \t]*$', tpl_lines[i]):
                break
            fm_perm_lines.append(re.sub(r'^  ', '', tpl_lines[i], count=1))
        mcp_root_text, _ = read_raw(mcp_paths[0])
        ft_row = re.search(r'(?m)^\| \*\*' + re.escape(args.perm_template)
                           + r'\*\* \| subagent \| .+?\| .+?\| (.+?) \| (.+?) \| (.+?) \| (.+?) \|',
                           mcp_root_text)
        if ft_row:
            full_cells = {'edit': ft_row.group(1).strip(), 'write': ft_row.group(2).strip(),
                          'read': ft_row.group(3).strip(), 'bash': ft_row.group(4).strip()}
        else:
            warns.append(f"WARN:perm-template full-table row not found for "
                         f"'{args.perm_template}' \u2014 deriving cells from JSON block")
            full_cells = {
                'edit': 'allow' if re.search(r'"edit":\s*"allow"', tpl_section) else 'deny',
                'write': 'allow' if re.search(r'"write":\s*"allow"', tpl_section) else 'deny',
                'read': 'allow' if re.search(r'"read":\s*"allow"', tpl_section) else 'deny',
                'bash': '**allow**' if re.search(r'"bash":\s*"allow"', tpl_section) else 'deny',
            }
        tpl_task = (((cfg.get('agent') or {}).get(args.perm_template) or {})
                    .get('permission') or {}).get('task')
        if isinstance(tpl_task, dict):
            task_entries = [k for k, v in tpl_task.items() if k != '*' and v == 'allow']
        for t in task_allow_list:
            if t not in task_entries:
                task_entries.append(t)
        tpl_json_section = tpl_section
    else:
        preset = PRESETS[args.permissions]
        fm_perm_lines = list(preset['fm_yaml'])
        json_perm_lines = []
        for l in preset['fm_yaml']:
            k, _, v = l.partition(': ')
            json_perm_lines.append(f'"{k}": "{v}"')
        task_entries = list(preset['default_task'])
        for t in task_allow_list:
            if t not in task_entries:
                task_entries.append(t)
        full_cells = dict(preset['full_table'])

    # --- Read all targets ----------------------------------------------------------
    live_cfg_raw = read_raw(live_cfg_path)
    deploy_cfg_raw = read_raw(deploy_cfg_path)
    plugin_raws = [read_raw(p) for p in plugin_paths]
    primary_raws = [read_raw(primary_live_md), read_raw(primary_deploy_md)]
    arch_raws = [read_raw(p) for p in arch_paths]
    agents_md_raws = [read_raw(p) for p in agents_md_paths]
    plugin_md_raws = [read_raw(p) for p in plugin_md_paths]
    mcp_raws = [read_raw(p) for p in mcp_paths]

    # --- Mirror pre-gates --------------------------------------------------------
    drifts = []
    if sha256_file(live_cfg_path) != sha256_file(deploy_cfg_path):
        drifts.append('opencode.json pair')
    if len({sha256_file(p) for p in plugin_paths}) > 1:
        drifts.append('plugin x3')
    if sha256_file(primary_live_md) != sha256_file(primary_deploy_md):
        drifts.append('primary pair')
    if len({sha256_file(p) for p in arch_paths}) > 1:
        drifts.append('ARCHITECTURE.md x3')
    if len({sha256_file(p) for p in agents_md_paths}) > 1:
        drifts.append('AGENTS.md x3')
    if len({sha256_file(p) for p in mcp_paths}) > 1:
        drifts.append('MCP_SETUP.md x2')
    if drifts:
        if args.apply:
            print(f"BLOCK:mirrors drifted \u2014 run config-sync first ({'; '.join(drifts)})")
            sys.exit(3)
        for d in drifts:
            warns.append(f'WARN:mirror drift ({d}) \u2014 run config-sync before apply')

    # --- Counter cross-check (fail-closed) ------------------------------------------
    diff_lines = []

    def add_diff(source, id_, value, expected):
        diff_lines.append(f'DIFF:{source} {id_} value={value} expected={expected}')

    wl_values = []  # (src, value)
    for i in range(3):
        v = count_routing_plugin(plugin_raws[i][0], args.primary)
        if v is None:
            add_diff(f'plugins[{i}]', 'routing_plugin', 'null', 'number')
            continue
        wl_values.append((f'plugin{i + 1}', v))
    for i in range(2):
        v = count_routing_line(primary_raws[i][0])
        if v is None:
            add_diff(f'primary_md[{i}]', 'opencode_routing_table', 'null', 'number')
            continue
        wl_values.append((f'primary_md{i + 1}', v))
    ta = count_task_allow(cfg, args.primary)
    if ta is None:
        add_diff('opencode.json', 'task_allow', 'null', 'number')
    else:
        wl_values.append(('json_task', ta))
    for i in range(3):
        wl = get_whitelist_count(arch_raws[i][0], args.primary)
        if wl is None:
            add_diff(f'arch[{i}]', 'whitelist_header', 'null', 'number')
            continue
        if wl['header'] != wl['rows']:
            add_diff(f'arch[{i}]', 'whitelist_rows', wl['rows'], wl['header'])
        wl_values.append((f'arch{i + 1}', wl['header']))
    for i in range(3):
        wl = get_whitelist_count_unnumbered(agents_md_raws[i][0], args.primary)
        if wl is None:
            add_diff(f'agents_md[{i}]', 'whitelist_header', 'null', 'number')
            continue
        if wl['header'] != wl['rows']:
            add_diff(f'agents_md[{i}]', 'whitelist_rows', wl['rows'], wl['header'])
        wl_values.append((f'agents_md{i + 1}', wl['header']))
    for i in range(3):
        wl = get_whitelist_count_unnumbered(plugin_md_raws[i][0], args.primary)
        if wl is None:
            add_diff(f'plugin_md[{i}]', 'whitelist_header', 'null', 'number')
            continue
        if wl['header'] != wl['rows']:
            add_diff(f'plugin_md[{i}]', 'whitelist_rows', wl['rows'], wl['header'])
        wl_values.append((f'plugin_md{i + 1}', wl['header']))
    for i in range(2):
        wl = get_whitelist_count_unnumbered(mcp_raws[i][0], args.primary)
        if wl is None:
            add_diff(f'mcp[{i}]', 'whitelist_s6_header', 'null', 'number')
            continue
        if wl['header'] != wl['rows']:
            add_diff(f'mcp[{i}]', 'whitelist_s6_rows', wl['rows'], wl['header'])
        wl_values.append((f'mcp_s6_{i + 1}', wl['header']))
        mcp_text = mcp_raws[i][0]
        tw_headers = re.finditer(r'(?m)^\*\*Task Whitelist \((\d+) agents\):\*\*\r?$', mcp_text)
        found = None
        for h in tw_headers:
            before = mcp_text[:h.start()]
            last_h4 = re.findall(r'(?m)^#### (orchestrator|plankestrator)\r?$', before)
            if last_h4 and last_h4[-1] == args.primary:
                found = h
        if found is None:
            add_diff(f'mcp[{i}]', 'task_whitelist_header', 'missing', args.primary)
        else:
            after_line = re.search(r'(?m)^(\S[^\r\n]*)\r?$', mcp_text[found.end():])
            if after_line:
                n_comma = len(split_tokens(after_line.group(1)))
                wl_values.append((f'mcp_taskwl_{i + 1}', int(found.group(1))))
                if n_comma != int(found.group(1)):
                    add_diff(f'mcp[{i}]', 'task_whitelist_list', n_comma, found.group(1))
            else:
                add_diff(f'mcp[{i}]', 'task_whitelist_list', 'missing', 'number')
        sum_row = re.search(r'(?m)^\| Routing tables \| 2 \| orchestrator \((\d+)\), '
                            r'plankestrator \((\d+)\) \|\r?$', mcp_text)
        if sum_row:
            g = 1 if args.primary == 'orchestrator' else 2
            wl_values.append((f'mcp_summary_routing_{i + 1}', int(sum_row.group(g))))
        else:
            add_diff(f'mcp[{i}]', 'summary_routing_row', 'missing', 'number')
    for i in range(3):
        acs = re.search(r'(?m)^\| ' + re.escape(args.primary) + r' \| (\d+)', arch_raws[i][0])
        if acs:
            wl_values.append((f'arch_agent_count_{i + 1}', int(acs.group(1))))
        else:
            add_diff(f'arch[{i}]', 'agent_count_summary', 'missing', 'number')

    # --- global counters
    g1_values = []  # unique subagents (35)
    g2_values = []  # total agents (37)
    for i in range(3):
        gt = re.search(r'(?m)^\| \*\*Grand Total\*\* \| \*\*(\d+)\*\* \| \*\*(\d+)\*\* \|\r?$',
                       arch_raws[i][0])
        if gt:
            g1_values.append((f'arch_grand_total_{i + 1}', int(gt.group(1))))
            g2_values.append((f'arch_grand_total_{i + 1}', int(gt.group(2))))
        else:
            add_diff(f'arch[{i}]', 'grand_total', 'missing', 'number')
        note = re.search(r'(?m)^Note: (\d+) whitelist entries[^\r\n]*?= (\d+) unique whitelisted '
                         r'subagents[^\r\n]*?(\d+) unique subagents \+ 2 primary agents = '
                         r'(\d+) unique agents total\.', arch_raws[i][0])
        if note:
            g1_values.append((f'arch_note_{i + 1}', int(note.group(3))))
            g2_values.append((f'arch_note_{i + 1}', int(note.group(4))))
        else:
            add_diff(f'arch[{i}]', 'note_counters', 'missing', 'number')
        kontrol = re.search(r'(?m)^\u041A\u043E\u043D\u0442\u0440\u043E\u043B\u044C \u0441\u0443\u043C\u043C\u044B: '
                            r'2 primary \+ (\d+) subagents = (\d+) \u0430\u0433\u0435\u043D\u0442\u043E\u0432;',
                            arch_raws[i][0])
        if kontrol:
            g1_values.append((f'arch_kontrol_{i + 1}', int(kontrol.group(1))))
            g2_values.append((f'arch_kontrol_{i + 1}', int(kontrol.group(2))))
        else:
            add_diff(f'arch[{i}]', 'kontrol_summy', 'missing', 'number')
        intro = re.search(r'(?m)\u043C\u043E\u0434\u0435\u043B\u0435\u0439 (\d+) '
                          r'\u0430\u0433\u0435\u043D\u0442\u0430\u043C', arch_raws[i][0])
        if intro:
            g2_values.append((f'arch_intro_{i + 1}', int(intro.group(1))))
        else:
            add_diff(f'arch[{i}]', 'model_roles_intro', 'missing', 'number')
    for i in range(3):
        prose = re.search(r'(?m)\u0432\u0441\u0435\u043C (\d+) \u0430\u0433\u0435\u043D\u0442\u0430\u043C',
                          agents_md_raws[i][0])
        if prose:
            g2_values.append((f'agents_md_prose_{i + 1}', int(prose.group(1))))
        else:
            add_diff(f'agents_md[{i}]', 'model_roles_prose', 'missing', 'number')
    for i in range(2):
        mcp_text = mcp_raws[i][0]
        ac = re.search(r'(?m)^\| Subagents \| (\d+) \|\r?$', mcp_text)
        if ac:
            g1_values.append((f'mcp_agent_count_{i + 1}', int(ac.group(1))))
        else:
            add_diff(f'mcp[{i}]', 'agent_count_subagents', 'missing', 'number')
        tu = re.search(r'(?m)^\| \*\*Total unique agents\*\* \| \*\*(\d+)\*\* \|\r?$', mcp_text)
        if tu:
            g2_values.append((f'mcp_total_unique_{i + 1}', int(tu.group(1))))
        else:
            add_diff(f'mcp[{i}]', 'total_unique_agents', 'missing', 'number')
        all_sub = re.search(r'(?m)\u0432\u0441\u0435 (\d+) subagents', mcp_text)
        if all_sub:
            g1_values.append((f'mcp_prose_{i + 1}', int(all_sub.group(1))))
        else:
            add_diff(f'mcp[{i}]', 'vse_subagents_prose', 'missing', 'number')
        sub_hdr = re.search(r'(?m)^\*\*Subagents \((\d+)\):\*\*\r?$', mcp_text)
        if sub_hdr:
            g1_values.append((f'mcp_subagents_hdr_{i + 1}', int(sub_hdr.group(1))))
        else:
            add_diff(f'mcp[{i}]', 'subagents_bold_header', 'missing', 'number')
        af = re.search(r'(?m)^### Agent Files \((\d+) total\)\r?$', mcp_text)
        if af:
            g2_values.append((f'mcp_agent_files_{i + 1}', int(af.group(1))))
        else:
            add_diff(f'mcp[{i}]', 'agent_files_total', 'missing', 'number')
        sum_sub = re.search(r'(?m)^\| Subagents \| (\d+) \| \S', mcp_text)
        if sum_sub:
            g1_values.append((f'mcp_summary_subagents_{i + 1}', int(sum_sub.group(1))))
        else:
            add_diff(f'mcp[{i}]', 'summary_subagents', 'missing', 'number')
        if sub_hdr:
            after = mcp_text[sub_hdr.end():]
            dash = list(re.finditer(r'(?m)^- [^\r\n]+\.md\r?$', after))
            stop = re.search(r'(?m)^(?!- )\S', after)
            cnt = 0
            for d in dash:
                if stop and d.start() > stop.start():
                    break
                cnt += 1
            g1_values.append((f'mcp_alpha_list_{i + 1}', cnt))
        tree_hdr = re.search(r'(?m)^### Agent Files List \((\d+) files\)\r?$', mcp_text)
        if tree_hdr and 'docs-planner.md' not in mcp_text[tree_hdr.end():]:
            warns.append('WARN:mcp tree list pre-existing drift (docs-planner.md missing) '
                         '\u2014 informational')

    def assert_group(values, group_id):
        if not values:
            return None
        ref = values[0][1]
        for src, val in values:
            if val != ref:
                add_diff(src, group_id, val, ref)
        return ref

    wl_n = assert_group(wl_values, 'whitelist')
    g1 = assert_group(g1_values, 'subagents_total')
    g2 = assert_group(g2_values, 'agents_total')
    if diff_lines:
        for d in diff_lines:
            print(d)
        print('BLOCK:counter cross-check failed \u2014 sources disagree '
              '(run integrity-check / config-sync)')
        sys.exit(3)
    if wl_n is None or g1 is None or g2 is None:
        print('BLOCK:counter cross-check failed \u2014 could not parse all counters')
        sys.exit(3)

    # --- Generated content ---------------------------------------------------------
    temp_str = str(args.temperature)
    if temp_str.endswith('.0'):
        temp_str = temp_str[:-2]
    temp_str = temp_str.replace(',', '.')
    desc_fm = args.description
    if re.search(r': ', args.description):
        desc_fm = "'" + args.description.replace("'", "''") + "'"
        warns.append('WARN:description contains ": " \u2014 auto-wrapped in single quotes '
                     'in frontmatter (YAML silent-drop guard)')
    if '|' in args.description:
        warns.append('WARN:description contains "|" \u2014 markdown table cells may render broken')

    if args.body_file:
        fm_body, _ = read_raw(args.body_file)
    else:
        warns.append('WARN:body is a stub (-BodyFile not given)')
        fm_body = (f'You are the {args.agent} agent.\n\n'
                   f'TODO: prompt body (generated stub - author the real prompt).\n')

    # Frontmatter permission lines: preset or template; task extras per plan H7(4)
    # (template block already embeds its own task tokens - only -TaskAllow extras added).
    fm_extras = task_allow_list if args.perm_template else task_entries
    perm_l = add_fm_task_extras(fm_perm_lines, fm_extras)
    fm_lines = ['---',
                'description: ' + desc_fm,
                'mode: subagent',
                'model: ' + args.model,
                'temperature: ' + temp_str,
                'permission:']
    for l in perm_l:
        fm_lines.append('  ' + l)
    fm_lines.append('---')
    fm_lines.append('')
    agent_file_text = '\n'.join(fm_lines) + fm_body
    if not agent_file_text.endswith('\n'):
        agent_file_text += '\n'

    eol_j = detect_eol(live_cfg_raw[0])
    if tpl_json_section is not None:
        sec = re.sub(r'^(\s*")' + re.escape(args.perm_template) + r'("\s*:\s*\{)',
                     r'\g<1>' + args.agent + r'\g<2>', tpl_json_section, count=1)
        if task_allow_list:
            try:
                tspan = find_json_span(sec, r'"task":\s*\{')
            except Exception:
                tspan = None
            if tspan:
                extra_lines = ['          "' + t + '": "allow"' for t in task_allow_list]
                insert = ',' + eol_j + ((',' + eol_j).join(extra_lines))
                sec = sec[:tspan[1]] + insert + sec[tspan[1]:]
            else:
                warns.append('WARN:perm-template has no JSON task block \u2014 '
                             '-TaskAllow extras not added to opencode.json')
        json_section = sec + ','
    else:
        sec_lines = ['    "' + args.agent + '": {',
                     '      "mode": "subagent",',
                     '      "temperature": ' + temp_str + ',',
                     '      "permission": {']
        for l in json_perm_lines:
            sec_lines.append('        ' + l + ',')
        sec_lines.append('        "task": {')
        sec_lines.append('          "*": "deny"')
        for t in task_entries:
            sec_lines[-1] += ','
            sec_lines.append('          "' + t + '": "allow"')
        sec_lines.append('        }')
        sec_lines.append('      },')
        sec_lines.append('      "options": {}')
        sec_lines.append('    },')
        json_section = eol_j.join(sec_lines)

    en_dash = '\u2013'
    extras_cell = ', '.join(task_entries)
    if not extras_cell:
        extras_cell = en_dash
    bash_cell = full_cells['bash']
    if bash_cell == 'allow':
        bash_cell = '**allow**'
    full_table_row = ('| **' + args.agent + '** | subagent | ' + args.model + ' | ' + temp_str
                      + ' | ' + full_cells['edit'] + ' | ' + full_cells['write'] + ' | '
                      + full_cells['read'] + ' | ' + bash_cell + ' | ' + extras_cell + ' |')
    desc_cell = args.description

    # --- Compute ALL edits in memory (two-phase: zero writes on any error) ------------
    pending = []  # (path, new_text, bom, rel)
    plan_lines = []

    def block(msg):
        print(f'BLOCK:{msg}')
        print('WARN:zero files written (two-phase all-or-nothing)')
        sys.exit(3)

    try:
        # groups 3-4: opencode.json live + deploy
        r_text = edit_json_agent_section(live_cfg_raw[0], json_section)
        r_text = edit_primary_task_allow(r_text, args.primary, args.agent)
        try:
            json.loads(r_text)
        except ValueError as e:
            block(f'new live opencode.json does not parse: {e}')
        new_live_cfg = r_text
        pending.append((live_cfg_path, new_live_cfg, live_cfg_raw[1], rel_path(live_cfg_path)))
        plan_lines.append(f'PLAN:{rel_path(live_cfg_path)} agent_section+task_allow')

        r_text = edit_json_agent_section(deploy_cfg_raw[0], json_section)
        r_text = edit_primary_task_allow(r_text, args.primary, args.agent)
        try:
            json.loads(r_text)
        except ValueError as e:
            block(f'new deploy opencode.json does not parse: {e}')
        pending.append((deploy_cfg_path, r_text, deploy_cfg_raw[1], rel_path(deploy_cfg_path)))
        plan_lines.append(f'PLAN:{rel_path(deploy_cfg_path)} agent_section+task_allow')

        # group 5: plugin x3
        for i in range(3):
            new_text, old_count = edit_routing_array(plugin_raws[i][0], args.primary, args.agent)
            pending.append((plugin_paths[i], new_text, plugin_raws[i][1], rel_path(plugin_paths[i])))
            plan_lines.append(f"PLAN:{rel_path(plugin_paths[i])} "
                              f"routing_array[{args.primary}] old={old_count} new={old_count + 1}")

        # group 6: primary .md x2
        for i in range(2):
            path = primary_live_md if i == 0 else primary_deploy_md
            new_text, old_count = edit_routing_line(primary_raws[i][0], args.agent)
            pending.append((path, new_text, primary_raws[i][1], rel_path(path)))
            plan_lines.append(f'PLAN:{rel_path(path)} opencode_routing_table '
                              f'old={old_count} new={old_count + 1}')

        # group 7: ARCHITECTURE.md x3
        numbered_row = f'| {wl_n + 1} | {args.agent} | {desc_cell} |'
        plain_row = f'| {args.agent} | {desc_cell} |'
        for i in range(3):
            t = arch_raws[i][0]
            t, old_count = edit_whitelist_table(t, args.primary, numbered_row)
            plan_lines.append(f'PLAN:{rel_path(arch_paths[i])} whitelist header+row '
                              f'old={old_count} new={old_count + 1}')
            t, old, new = edit_numbered_counter(
                t, r'(?m)^\| ' + re.escape(args.primary) + r' \| (\d+) \| (\d+) \('
                + re.escape(args.primary) + r' \+ (\d+) subagents\) \|\r?$', [1, 2, 3])
            plan_lines.append(f"PLAN:{rel_path(arch_paths[i])} agent_count_summary "
                              f"old={'/'.join(str(x) for x in old)} "
                              f"new={'/'.join(str(x) for x in new)}")
            t, old, new = edit_numbered_counter(
                t, r'(?m)^\| \*\*Grand Total\*\* \| \*\*(\d+)\*\* \| \*\*(\d+)\*\* \|\r?$', [1, 2])
            plan_lines.append(f"PLAN:{rel_path(arch_paths[i])} grand_total "
                              f"old={'/'.join(str(x) for x in old)} "
                              f"new={'/'.join(str(x) for x in new)}")
            t, old, new = edit_numbered_counter(
                t, r'(?m)^Note: (\d+) whitelist entries[^\r\n]*?= (\d+) unique whitelisted '
                r'subagents[^\r\n]*?(\d+) unique subagents \+ 2 primary agents = '
                r'(\d+) unique agents total\.', [1, 2, 3, 4])
            plan_lines.append(f"PLAN:{rel_path(arch_paths[i])} note_counters "
                              f"old={'/'.join(str(x) for x in old)} "
                              f"new={'/'.join(str(x) for x in new)}")
            t = edit_subagent_models_append(t, f'| {args.agent} | {args.model} |')
            plan_lines.append(f'PLAN:{rel_path(arch_paths[i])} subagent_models_row '
                              f'model={args.model}')
            t, old, new = edit_numbered_counter(
                t, r'(?m)\u043C\u043E\u0434\u0435\u043B\u0435\u0439 (\d+) '
                r'\u0430\u0433\u0435\u043D\u0442\u0430\u043C', [1])
            plan_lines.append(f'PLAN:{rel_path(arch_paths[i])} model_roles_intro '
                              f'old={old[0]} new={new[0]}')
            t, new_role, w = edit_model_roles_add(t, args.agent, args.model, args.role, args.tier)
            warns += w
            plan_lines.append(f'PLAN:{rel_path(arch_paths[i])} model_roles_agents role={new_role}')
            t, old, new = edit_numbered_counter(
                t, r'(?m)^\u041A\u043E\u043D\u0442\u0440\u043E\u043B\u044C \u0441\u0443\u043C\u043C\u044B: '
                r'2 primary \+ (\d+) subagents = (\d+) \u0430\u0433\u0435\u043D\u0442\u043E\u0432;',
                [1, 2])
            plan_lines.append(f"PLAN:{rel_path(arch_paths[i])} kontrol_summy "
                              f"old={'/'.join(str(x) for x in old)} "
                              f"new={'/'.join(str(x) for x in new)}")
            pending.append((arch_paths[i], t, arch_raws[i][1], rel_path(arch_paths[i])))

        # group 8: AGENTS.md x3
        for i in range(3):
            t = agents_md_raws[i][0]
            t, old_count = edit_whitelist_table(t, args.primary, plain_row)
            plan_lines.append(f'PLAN:{rel_path(agents_md_paths[i])} whitelist header+row '
                              f'old={old_count} new={old_count + 1}')
            t, old, new = edit_numbered_counter(
                t, r'(?m)\u0432\u0441\u0435\u043C (\d+) \u0430\u0433\u0435\u043D\u0442\u0430\u043C', [1])
            plan_lines.append(f'PLAN:{rel_path(agents_md_paths[i])} model_roles_prose '
                              f'old={old[0]} new={new[0]}')
            pending.append((agents_md_paths[i], t, agents_md_raws[i][1], rel_path(agents_md_paths[i])))

        # group 9: PLUGIN.md x3
        for i in range(3):
            t = plugin_md_raws[i][0]
            t, old_count = edit_whitelist_table(t, args.primary, plain_row)
            plan_lines.append(f'PLAN:{rel_path(plugin_md_paths[i])} whitelist header+row '
                              f'old={old_count} new={old_count + 1}')
            t, old_count = edit_routing_array(t, args.primary, args.agent,
                                              r'^### Routing Table Implementation')
            plan_lines.append(f"PLAN:{rel_path(plugin_md_paths[i])} "
                              f"routing_code_block[{args.primary}] "
                              f"old={old_count} new={old_count + 1}")
            pending.append((plugin_md_paths[i], t, plugin_md_raws[i][1], rel_path(plugin_md_paths[i])))

        # group 10: MCP_SETUP.md x2
        new_short = model_key
        for i in range(2):
            t = mcp_raws[i][0]
            t, _, _ = edit_numbered_counter(t, r'(?m)^\| Subagents \| (\d+) \|\r?$', [1])
            t, _, _ = edit_numbered_counter(
                t, r'(?m)^\| \*\*Total unique agents\*\* \| \*\*(\d+)\*\* \|\r?$', [1])
            t, _, _ = edit_numbered_counter(t, r'(?m)\u0432\u0441\u0435 (\d+) subagents', [1])
            t, old_count = edit_task_whitelist(t, args.primary, args.agent)
            plan_lines.append(f'PLAN:{rel_path(mcp_paths[i])} task_whitelist '
                              f'old={old_count} new={old_count + 1}')
            t, old_count = edit_whitelist_table(t, args.primary, plain_row)
            plan_lines.append(f'PLAN:{rel_path(mcp_paths[i])} whitelist_s6 header+row '
                              f'old={old_count} new={old_count + 1}')
            t, old_count = edit_routing_array(t, args.primary, args.agent,
                                              r'^### Routing Tables in Plugin')
            plan_lines.append(f"PLAN:{rel_path(mcp_paths[i])} "
                              f"routing_plugin_block[{args.primary}] "
                              f"old={old_count} new={old_count + 1}")
            t, shorts, row_created, new_count, w = edit_distribution_add(
                t, args.agent, new_short)
            warns += w
            if row_created:
                t = edit_summary_models_row(t, shorts)
            plan_lines.append(f'PLAN:{rel_path(mcp_paths[i])} distribution short={new_short} '
                              f'count={new_count} row_created={row_created}')
            t = edit_full_table_append(t, full_table_row)
            plan_lines.append(f'PLAN:{rel_path(mcp_paths[i])} full_table_row')
            t, _, _ = edit_numbered_counter(t, r'(?m)^### Agent Files \((\d+) total\)\r?$', [1])
            t, _, _ = edit_numbered_counter(t, r'(?m)^\*\*Subagents \((\d+)\):\*\*\r?$', [1])
            t = edit_alpha_insert(t, args.agent + '.md')
            t, _, _ = edit_numbered_counter(t, r'(?m)^### Agent Files List \((\d+) files\)\r?$', [1])
            t = edit_tree_insert(t, args.agent + '.md')
            t, _, _ = edit_numbered_counter(t, r'(?m)^\| Subagents \| (\d+) \| \S', [1])
            routing_groups = [1] if args.primary == 'orchestrator' else [2]
            t, _, _ = edit_numbered_counter(
                t, r'(?m)^\| Routing tables \| 2 \| orchestrator \((\d+)\), '
                r'plankestrator \((\d+)\) \|\r?$', routing_groups)
            pending.append((mcp_paths[i], t, mcp_raws[i][1], rel_path(mcp_paths[i])))
            plan_lines.append(f'PLAN:{rel_path(mcp_paths[i])} agent_files/list/tree/summary counters')
    except EditError as e:
        block(str(e))

    # --- Plan output -------------------------------------------------------------
    for pl in plan_lines:
        print(pl)
    seen = set()
    for w in warns:
        if w not in seen:
            seen.add(w)
            print(w)

    if args.plan_only:
        print('STATUS:PLAN_ONLY')
        sys.exit(0)

    # --- Apply (two-phase write) ----------------------------------------------------
    print('STATUS:APPLY_START')
    write_raw(live_agent_md, agent_file_text, False)
    print(f'CREATED:{rel_path(live_agent_md)}')
    write_raw(deploy_agent_md, agent_file_text, False)
    print(f'CREATED:{rel_path(deploy_agent_md)}')
    for path, new_text, bom, rel in pending:
        write_raw(path, new_text, bom)
        print(f'EDITED:{rel}')

    # --- Verify (re-read from disk) ---------------------------------------------------
    try:
        json.loads(read_raw(live_cfg_path)[0])
    except ValueError as e:
        print(f'ERROR:live opencode.json no longer parses: {e}')
        print('WARN:partial state \u2014 restore from backup-snapshot / config-sync')
        sys.exit(3)
    try:
        json.loads(read_raw(deploy_cfg_path)[0])
    except ValueError as e:
        print(f'ERROR:deploy opencode.json no longer parses: {e}')
        print('WARN:partial state \u2014 restore from backup-snapshot / config-sync')
        sys.exit(3)
    verify_groups = [
        ('agent pair', [live_agent_md, deploy_agent_md]),
        ('json pair', [live_cfg_path, deploy_cfg_path]),
        ('plugin x3', plugin_paths),
        ('primary pair', [primary_live_md, primary_deploy_md]),
        ('architecture x3', arch_paths),
        ('agents-md x3', agents_md_paths),
        ('mcp-setup x2', mcp_paths),
    ]
    for name, paths in verify_groups:
        hashes = {sha256_file(p) for p in paths}
        if len(hashes) == 1:
            print(f'VERIFY:{name} identical')
        else:
            print(f'ERROR:SHA256 mismatch: {name}')
            print('WARN:partial state \u2014 restore from backup-snapshot / config-sync')
            sys.exit(3)
    cfg2 = json.loads(read_raw(live_cfg_path)[0])
    ta2 = count_task_allow(cfg2, args.primary)
    if ta2 != wl_n + 1:
        print(f'ERROR:post-apply counter check failed: json task allow = {ta2} '
              f'expected {wl_n + 1}')
        sys.exit(3)
    plug2 = count_routing_plugin(read_raw(plugin_paths[0])[0], args.primary)
    if plug2 != wl_n + 1:
        print(f'ERROR:post-apply counter check failed: plugin routing = {plug2} '
              f'expected {wl_n + 1}')
        sys.exit(3)
    rl2 = count_routing_line(read_raw(primary_live_md)[0])
    if rl2 != wl_n + 1:
        print(f'ERROR:post-apply counter check failed: OPENCODE_ROUTING_TABLE = {rl2} '
              f'expected {wl_n + 1}')
        sys.exit(3)
    wl2 = get_whitelist_count(read_raw(arch_paths[0])[0], args.primary)
    if wl2 is None or wl2['header'] != wl_n + 1:
        print('ERROR:post-apply counter check failed: ARCH whitelist header')
        sys.exit(3)
    mcp2 = read_raw(mcp_paths[0])[0]
    ac2 = re.search(r'(?m)^\| Subagents \| (\d+) \|\r?$', mcp2)
    if not ac2 or int(ac2.group(1)) != g1 + 1:
        print('ERROR:post-apply counter check failed: MCP Agent Count Subagents')
        sys.exit(3)
    tu2 = re.search(r'(?m)^\| \*\*Total unique agents\*\* \| \*\*(\d+)\*\* \|\r?$', mcp2)
    if not tu2 or int(tu2.group(1)) != g2 + 1:
        print('ERROR:post-apply counter check failed: MCP Total unique agents')
        sys.exit(3)
    print('VERIFY:counters re-parsed old+1')
    for pp in plugin_paths:
        ts3 = read_raw(pp)[0]
        outer3 = re.search(r'(?s)const ROUTING_TABLES = \{(.*?)\r?\n\}', ts3)
        inner3 = re.search(r'(?s)' + re.escape(args.primary) + r'\s*:\s*\[(.*?)\]',
                           outer3.group(1))
        tok_count = sum(1 for m in TOKEN_RX.finditer(inner3.group(1))
                        if m.group(0).strip('"\'') == args.agent)
        if tok_count != 1:
            print(f'ERROR:post-apply routing token count != 1 in {pp}')
            sys.exit(3)
    print('VERIFY:routing token-exact once')

    # --- Manual follow-ups (always) --------------------------------------------------
    print('WARN:restart required (config is read at session start \u2014 the new agent '
          'is visible in a NEW opencode session)')
    print('WARN:CHANGELOG.md [Unreleased] entry is a manual step')
    print('WARN:consistency-checker.md counts (25/10/37 in the prompt) \u2014 '
          'manual edit live+deploy')
    print('WARN:verify.ps1 requiredAgents \u2014 manual update')
    print('WARN:deploy README.md/DEPLOYMENT_GUIDE.md counts \u2014 manual update')
    print('WARN:integrity-check defaults (37/25/10) in check.ps1+check.py+SKILL.md \u2014 '
          'manual update')
    print('WARN:live AGENTS.md \u2014 run config-sync -Apply -Group agents-md')
    print('WARN:SEVERITY_AGENTS/CONTEXT_FILE_AGENTS \u2014 manual update '
          '(only if the new agent is a reviewer)')
    print('WARN:MCP_SETUP unity-note prose \u2014 manual update '
          '(only if unity-mcp is not allowed for the new agent)')

    # --- Optional conventional commit of the 16 repo files -----------------------------
    if args.commit:
        git_name = git(root, 'config', 'user.name').stdout.strip()
        git_email = git(root, 'config', 'user.email').stdout.strip()
        if not git_name or not git_email:
            print(f"ERROR: git identity missing (user.name='{git_name}' "
                  f"user.email='{git_email}') - set it with: "
                  f'git config user.name "..."; git config user.email "..."')
            sys.exit(3)
        commit_msg = f'feat(agents): add {args.agent} ({args.model}, {args.primary} whitelist)'
        tmp_dir = Path(tempfile.gettempdir()) / 'opencode'
        tmp_dir.mkdir(parents=True, exist_ok=True)
        msg_file = tmp_dir / 'commit-msg-agents.txt'
        msg_file.write_text(commit_msg, encoding='utf-8')
        print('STATUS:COMMIT_START')
        repo_rel_paths = [
            f'deploy-package/agents/{args.agent}.md',
            'deploy-package/opencode.json',
            'plugins/workflow-enforcement.ts',
            'deploy-package/plugins/workflow-enforcement.ts',
            'ARCHITECTURE.md',
            'opencode-config/ARCHITECTURE.md',
            'deploy-package/project-files/ARCHITECTURE.md',
            'AGENTS.md',
            'opencode-config/AGENTS.md',
            'deploy-package/project-files/AGENTS.md',
            'PLUGIN.md',
            'opencode-config/PLUGIN.md',
            'deploy-package/project-files/PLUGIN.md',
            'MCP_SETUP.md',
            'deploy-package/project-files/MCP_SETUP.md',
            f'deploy-package/agents/{args.primary}.md',
        ]
        add_res = git(root, 'add', *repo_rel_paths)
        if add_res.returncode != 0:
            print('ERROR:git add failed')
            sys.exit(3)
        res = git(root, 'commit', '-F', str(msg_file))
        if res.returncode != 0:
            print('ERROR:git commit failed')
            sys.exit(3)
        commit_hash = git(root, 'rev-parse', 'HEAD').stdout.strip()
        print(f'COMMITTED:hash={commit_hash} msg={commit_msg}')
        if args.push:
            print('STATUS:PUSH_START')
            branch = git(root, 'branch', '--show-current').stdout.strip()
            if not branch:
                print('ERROR: could not determine current branch')
                sys.exit(3)
            res = git(root, 'push', 'origin', branch)
            if res.returncode != 0:
                print('ERROR:git push failed')
                sys.exit(3)
            print(f'PUSHED:branch={branch}')

    print(f'STATUS:SUCCESS agent={args.agent} primary={args.primary} '
          f'whitelist={wl_n}->{wl_n + 1} total={g2}->{g2 + 1}')
    sys.exit(0)


if __name__ == '__main__':
    main()
