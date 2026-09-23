#!/usr/bin/env python3
"""
visualize.py - POSIX mirror of visualize.ps1

Fast LLM-free ASCII visualization of all orchestration pipelines parsed from
root ARCHITECTURE.md section '## 2. Pipelines': step-chain diagrams annotated
with frontmatter model keys and Model Roles role/tier per agent step, prewalk
pairs highlighted (==>), tier drops (~->), inversions (!->), rework loops and
parallel waves as grouped nodes.

Usage:
    python visualize.py [--pipeline SUBSTR] [--format ascii|markdown|json]
                        [--source live|deploy] [--agents-dir DIR] [--no-models]
                        [--arch PATH]

Output:
    STATUS:/PIPELINE:/PREWALK:/INFO:/WARN:/ERROR:/SUMMARY: lines or a JSON document

Exit codes:
    0 rendered (WARN/INFO allowed)
    2 usage/environment error

No exit 3: visualization does not gate. Output is ASCII-only (unicode arrows
U+2192/U+2225 are INPUT syntax, never printed). Strictly read-only.
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ARROW = '\u2192'
PARALLEL = '\u2225'
SKIP_HEADINGS = ['Pipeline Notation', 'DEV Complexity Classification', 'Auto-DOCS Hook']
EXPECTED_LABELS = ['BUGFIX (SIMPLE)', 'BUGFIX DEEP', 'DEV SIMPLE', 'DEV COMPLEX',
                   'DEV SUPERCOMPLEX', 'DEVOPS', 'DOCS', 'PLAN', 'RESEARCH']
TIER_RANK = {'low': 1, 'mid': 2, 'top': 3}


def read_raw(p):
    """Byte-safe read: decode UTF-8 (strip BOM if present), report BOM state."""
    data = Path(p).read_bytes()
    bom = data.startswith(b'\xef\xbb\xbf')
    return data.decode('utf-8-sig' if bom else 'utf-8'), bom


def get_fm_model(text):
    m = re.match(r'(?s)\A---\r?\n(.*?)\r?\n---', text)
    if not m:
        return None
    mm = re.search(r'(?m)^model:[ \t]*(.*)$', m.group(1))
    if not mm:
        return None
    return mm.group(1).strip()


def split_model_key(full):
    if not full:
        return None
    idx = full.find('/')
    if idx < 1 or idx >= len(full) - 1:
        return None
    return {'provider': full[:idx], 'key': full[idx + 1:]}


def split_tokens(cell):
    if not cell or not cell.strip():
        return []
    return [t.strip() for t in cell.split(',') if t.strip()]


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


def get_section_text(text, start_pat, end_pat):
    m = re.search(start_pat, text, re.M)
    if not m:
        return None
    after = text[m.end():]
    e = re.search(end_pat, after, re.M)
    if e:
        return after[:e.start()]
    return after


def get_model_role_map(arch_text):
    sec = get_section_text(arch_text, r'^## Model Roles', r'^## ')
    if sec is None:
        return None
    amap = {}
    roles = []
    for ln in re.split(r'\r?\n', sec):
        if not ln.startswith('|'):
            continue
        cells = [c.strip() for c in ln.split('|')]
        if len(cells) < 5:
            continue
        r, m, t, ags = cells[1], cells[2], cells[3], cells[4]
        if not r or r == 'Role' or re.match(r'^-+$', r):
            continue
        if t not in ('top', 'mid', 'low'):
            continue
        roles.append({'role': r, 'model': m, 'tier': t})
        for a in split_tokens(ags):
            amap[a] = {'role': r, 'tier': t, 'arch_model': m}
    if not roles:
        return None
    return {'map': amap, 'roles': roles}


def get_pipeline_chains(sec_text):
    """Linear scanner of section 2 - mirrors Get-PipelineChains in visualize.ps1."""
    chains = []
    label = ''
    skip = False
    buf = None
    pending = None
    for ln in re.split(r'\r?\n', sec_text):
        hm = re.match(r'^###\s+(.+?)\s*$', ln)
        if hm:
            if buf:
                chains.append(buf)
                buf = None
            label = hm.group(1)
            skip = any(label.startswith(sh) for sh in SKIP_HEADINGS)
            pending = None
            continue
        if skip:
            continue
        if 'TRIAGE_RESULT' in ln:
            if buf:
                chains.append(buf)
                buf = None
            pending = None
            continue
        t = ln.strip()
        if not t:
            continue
        t = re.sub(r'^[-*]\s+', '', t)
        t = t.replace('`', '')
        t = t.replace('**', '')
        if not t:
            continue
        if t.startswith('|'):
            cells = [c.strip() for c in t.split('|') if c.strip()]
            arrow_cells = [c for c in cells if re.search(r'\u2192|->', c)]
            if arrow_cells:
                if buf:
                    chains.append(buf)
                    buf = None
                head_cell = ''
                for c in cells:
                    if not re.search(r'\u2192|->', c):
                        head_cell = c
                        break
                buf = {'label': label, 'variant': head_cell, 'raw': ' '.join(arrow_cells)}
            pending = None
            continue
        is_cont = re.match(r'^(?:\u2192|->)', t) is not None
        has_arrow = re.search(r'\u2192|->', t) is not None
        if is_cont:
            if buf:
                buf['raw'] = buf['raw'] + ' ' + t
                continue
            if pending:
                buf = {'label': label, 'variant': pending['variant'],
                       'raw': pending['raw'] + ' ' + t}
                pending = None
                continue
            buf = {'label': label, 'variant': '', 'raw': t}
            continue
        if buf:
            chains.append(buf)
            buf = None
        variant, raw = '', t
        vm = re.match(r'^([^\u2192:]{1,60}):\s*(.+)$', t)
        if vm:
            variant, raw = vm.group(1).strip(), vm.group(2)
        if has_arrow:
            buf = {'label': label, 'variant': variant, 'raw': raw}
            pending = None
        else:
            pending = {'variant': variant, 'raw': raw}
    if buf:
        chains.append(buf)
    return chains


def convert_raw_to_nodes(raw, agent_names):
    loops = {}
    waves = {}
    i = 0
    while True:
        idx = raw.find('[rework loop:')
        if idx < 0:
            break
        end = raw.find(']', idx)
        if end < 0:
            break
        inner = raw[idx + 13:end]
        loops['L%d' % i] = inner.strip()
        raw = raw[:idx] + '<<L%d>>' % i + raw[end + 1:]
        i += 1
    i = 0
    while True:
        m = re.search(r'\[[^\[\]]*\u2225[^\[\]]*\]', raw)
        if not m:
            break
        waves['W%d' % i] = m.group(0)[1:-1]
        raw = raw[:m.start()] + '<<W%d>>' % i + raw[m.end():]
        i += 1
    raw = re.sub(r'\([^)]*\)', '', raw)
    raw = re.sub(r'[\[\]"]', '', raw)
    parts = re.split(r'\s*(?:\u2192|->)\s*', raw)
    nodes = []
    for p in parts:
        s = p.strip().strip(',').strip()
        if not s:
            continue
        lm = re.match(r'^<<L(\d+)>>$', s)
        if lm:
            inner = loops['L' + lm.group(1)]
            mm = re.search(r',?\s*max\s+(\d+)\s*$', inner)
            if mm:
                max_n = int(mm.group(1))
                body = inner[:mm.start()].strip()
            else:
                max_n, body = 0, inner
            nodes.append({'kind': 'loop', 'text': body, 'max': max_n})
            continue
        wm = re.match(r'^<<W(\d+)>>$', s)
        if wm:
            members = [x.strip() for x in waves['W' + wm.group(1)].split(PARALLEL) if x.strip()]
            nodes.append({'kind': 'wave', 'members': members})
            continue
        if re.match(r'^[a-z][a-z0-9-]*$', s) and s in agent_names:
            nodes.append({'kind': 'agent', 'name': s})
            continue
        pc = re.match(r'^([a-z][a-z0-9-]+)-\*$', s)
        if pc:
            prefix = pc.group(1) + '-'
            hits = [n for n in agent_names if n.startswith(prefix)]
            if hits:
                nodes.append({'kind': 'wildcard', 'name': s, 'matches': hits})
                continue
        nodes.append({'kind': 'pseudo', 'name': s})
    return nodes


def get_prewalk_pairs(nodes, role_map):
    pairs = []
    for i in range(len(nodes) - 1):
        a, b = nodes[i], nodes[i + 1]
        if a['kind'] != 'agent' or b['kind'] != 'agent':
            continue
        if a['name'] not in role_map or b['name'] not in role_map:
            continue
        ra, rb = role_map[a['name']], role_map[b['name']]
        if ra['tier'] not in TIER_RANK or rb['tier'] not in TIER_RANK:
            continue
        ta, tb = TIER_RANK[ra['tier']], TIER_RANK[rb['tier']]
        is_planner = ra['role'].startswith('plan') or ra['role'] == 'docs-plan'
        if is_planner and ta >= tb:
            pairs.append({'kind': 'prewalk', 'i': i, 'a': a['name'], 'b': b['name']})
        elif is_planner:
            pairs.append({'kind': 'inversion', 'i': i, 'a': a['name'], 'b': b['name']})
        elif ta > tb:
            pairs.append({'kind': 'drop', 'i': i, 'a': a['name'], 'b': b['name']})
    return pairs


def render_node_box(node, idx, info, no_models):
    content = []
    kind = node['kind']
    if kind == 'agent':
        content.append('%d. %s' % (idx, node['name']))
        if not no_models:
            mk = '-'
            if info['model']:
                sp = split_model_key(info['model'])
                if sp:
                    mk = sp['key']
            content.append(mk)
        content.append(info['tier'] if info['tier'] else '?')
    elif kind == 'wildcard':
        content.append('%d. %s' % (idx, node['name']))
        content.append('%d agents' % len(node['matches']))
    elif kind == 'pseudo':
        content.append(node['name'])
    elif kind == 'loop':
        txt = node['text'].replace(ARROW, '->')
        content.append('LOOP max %d:' % node['max'])
        content.append(txt)
    elif kind == 'wave':
        content.append('WAVE (parallel):')
        content.append(' | '.join(node['members']))
    inner = max(len(c) for c in content)
    boxed = ['+' + '-' * (inner + 2) + '+']
    for c in content:
        boxed.append('| ' + c.ljust(inner) + ' |')
    boxed.append('+' + '-' * (inner + 2) + '+')
    return {'lines': boxed, 'height': len(boxed)}


def join_boxes(boxes, conns):
    max_h = max(b['height'] for b in boxes)
    mid = (max_h - 1) // 2
    lines = []
    for h in range(max_h):
        row = ''
        for i, b in enumerate(boxes):
            bl = b['lines']
            if h < len(bl):
                row += bl[h]
            else:
                row += ' ' * len(bl[0])
            if i < len(boxes) - 1:
                row += conns[i] if h == mid else '     '
        lines.append(row)
    return lines


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pipeline', default='')
    parser.add_argument('--format', choices=['ascii', 'markdown', 'json'], default='ascii')
    parser.add_argument('--source', choices=['live', 'deploy'], default='live')
    parser.add_argument('--agents-dir', default='')
    parser.add_argument('--no-models', action='store_true')
    parser.add_argument('--arch', default='')
    args = parser.parse_args()

    if args.source != 'live' and args.agents_dir:
        print('ERROR:COMBINATION -Source and -AgentsDir are mutually exclusive')
        sys.exit(2)

    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)
    live_dir = Path.home() / '.config' / 'opencode'

    arch_path = Path(args.arch) if args.arch else root / 'ARCHITECTURE.md'
    arch_name = args.arch if args.arch else 'ARCHITECTURE.md'
    if not arch_path.is_file():
        print(f'ERROR:ENV ARCHITECTURE.md not found: {arch_path}')
        sys.exit(2)
    arch_text, _ = read_raw(arch_path)

    sec2 = get_section_text(arch_text, r'^## 2\. Pipelines', r'^## ')
    if sec2 is None:
        print('ERROR:ANCHOR pipelines (## 2. Pipelines section not found)')
        sys.exit(2)
    role_info = get_model_role_map(arch_text)
    if not role_info:
        print('ERROR:ANCHOR model_roles (## Model Roles table not parsed)')
        sys.exit(2)

    if args.agents_dir:
        agents_dir = Path(args.agents_dir)
        if not agents_dir.is_absolute():
            agents_dir = root / agents_dir
    elif args.source == 'deploy':
        agents_dir = root / 'deploy-package' / 'agents'
    else:
        agents_dir = live_dir / 'agents'
    if not agents_dir.is_dir():
        print(f'ERROR:ENV agents dir not found: {agents_dir}')
        sys.exit(2)
    agent_files = list(agents_dir.glob('*.md'))
    if not agent_files:
        print(f'ERROR:ENV agents dir empty: {agents_dir}')
        sys.exit(2)
    agent_names = sorted(f.stem for f in agent_files)
    model_by_name = {f.stem: get_fm_model(read_raw(f)[0]) for f in agent_files}

    # Parse chains -> pipelines
    parsed = []
    seen_seq = set()
    for chain in get_pipeline_chains(sec2):
        nodes = convert_raw_to_nodes(chain['raw'], agent_names)
        if len(nodes) < 2:
            continue
        resolved = 0
        for nd in nodes:
            if nd['kind'] in ('agent', 'wildcard'):
                resolved += 1
            elif nd['kind'] == 'wave':
                if any(m in agent_names for m in nd['members']):
                    resolved += 1
        if resolved == 0:
            continue
        seq_parts = []
        for nd in nodes:
            k = nd['kind']
            if k == 'agent':
                seq_parts.append('a:' + nd['name'])
            elif k == 'wildcard':
                seq_parts.append('w:' + nd['name'])
            elif k == 'pseudo':
                seq_parts.append('p:' + nd['name'])
            elif k == 'loop':
                seq_parts.append('l:%d:%s' % (nd['max'], nd['text']))
            elif k == 'wave':
                seq_parts.append('W:' + '|'.join(nd['members']))
        seq_key = ' > '.join(seq_parts)
        if seq_key in seen_seq:
            continue
        seen_seq.add(seq_key)
        disp = chain['variant'] if chain['variant'] else chain['label']
        parsed.append({'label': disp, 'nodes': nodes})

    # Duplicate display labels get ' #N' suffixes (appearance order)
    label_count = {}
    for pl in parsed:
        label_count[pl['label']] = label_count.get(pl['label'], 0) + 1
        if label_count[pl['label']] > 1:
            pl['label'] = '%s #%d' % (pl['label'], label_count[pl['label']])

    # Expected-label check
    global_warns = []
    for exp in EXPECTED_LABELS:
        low = exp.lower()
        if not any(low in pl['label'].lower() for pl in parsed):
            global_warns.append('WARN:PIPELINE_NOT_FOUND name=%s' % exp)

    # -Pipeline filter
    render_list = parsed
    if args.pipeline:
        low = args.pipeline.lower()
        render_list = [pl for pl in parsed if low in pl['label'].lower()]
        if not render_list:
            print(f'ERROR:NO_MATCH no pipeline label contains: {args.pipeline}')
            sys.exit(2)

    gen_utc = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    # Enrich + collect
    blocks = []
    sums = {'steps': 0, 'agents': 0, 'pseudo': 0, 'loops': 0, 'waves': 0,
            'prewalk': 0, 'inv': 0, 'drops': 0, 'unresolved': 0}
    for pl in render_list:
        warns = []
        boxes = []
        json_steps = []
        for idx, nd in enumerate(pl['nodes'], 1):
            info = {'model': None, 'role': None, 'tier': None}
            disp_name = ''
            loop_obj = None
            wave_obj = None
            kind = nd['kind']
            if kind == 'agent':
                disp_name = nd['name']
                info['model'] = model_by_name.get(nd['name'])
                if not info['model']:
                    warns.append('WARN:STEP_NO_MODEL pipeline=%s step=%s' % (pl['label'], nd['name']))
                if nd['name'] in role_info['map']:
                    info['role'] = role_info['map'][nd['name']]['role']
                    info['tier'] = role_info['map'][nd['name']]['tier']
                else:
                    warns.append('WARN:ROLE_UNMAPPED pipeline=%s step=%s' % (pl['label'], nd['name']))
            elif kind == 'wildcard':
                disp_name = nd['name']
                warns.append('WARN:STEP_UNRESOLVED pipeline=%s step=%s kind=wildcard matches=%d'
                             % (pl['label'], nd['name'], len(nd['matches'])))
            elif kind == 'pseudo':
                disp_name = nd['name']
                warns.append('WARN:STEP_UNRESOLVED pipeline=%s step=%s kind=pseudo'
                             % (pl['label'], nd['name']))
            elif kind == 'loop':
                txt = nd['text'].replace(ARROW, '->')
                loop_obj = {'text': txt, 'max': nd['max']}
                disp_name = txt
            elif kind == 'wave':
                wave_obj = list(nd['members'])
                disp_name = ' | '.join(nd['members'])
            disp_model = None
            if info['model']:
                sp = split_model_key(info['model'])
                if sp:
                    disp_model = sp['key']
            json_steps.append({'kind': kind, 'name': disp_name, 'model': disp_model,
                               'role': info['role'], 'tier': info['tier'],
                               'loop': loop_obj, 'wave': wave_obj})
            boxes.append(render_node_box(nd, idx, info, args.no_models))
        pairs = get_prewalk_pairs(pl['nodes'], role_info['map'])
        conns = []
        for i in range(len(boxes) - 1):
            conn = ' --> '
            for pr in pairs:
                if pr['i'] != i:
                    continue
                if pr['kind'] == 'prewalk':
                    conn = ' ==> '
                elif pr['kind'] == 'inversion':
                    conn = ' !-> '
                elif pr['kind'] == 'drop':
                    conn = ' ~-> '
            conns.append(conn)
        diagram = join_boxes(boxes, conns)

        n = {k: 0 for k in ('agent', 'wildcard', 'pseudo', 'loop', 'wave')}
        for nd in pl['nodes']:
            n[nd['kind']] += 1
        n_pre = sum(1 for p in pairs if p['kind'] == 'prewalk')
        n_inv = sum(1 for p in pairs if p['kind'] == 'inversion')
        n_drop = sum(1 for p in pairs if p['kind'] == 'drop')

        blocks.append({
            'label': pl['label'], 'diagram': diagram, 'steps': json_steps,
            'pairs': pairs, 'warns': warns,
            'n': len(pl['nodes']), 'n_agents': n['agent'], 'n_pseudo': n['pseudo'],
            'n_loops': n['loop'], 'n_waves': n['wave'],
            'n_pre': n_pre, 'n_inv': n_inv, 'n_drop': n_drop,
        })
        sums['steps'] += len(pl['nodes'])
        sums['agents'] += n['agent']
        sums['pseudo'] += n['pseudo']
        sums['loops'] += n['loop']
        sums['waves'] += n['wave']
        sums['prewalk'] += n_pre
        sums['inv'] += n_inv
        sums['drops'] += n_drop
        sums['unresolved'] += sum(1 for w in warns if w.startswith('WARN:STEP_UNRESOLVED'))
    total_warn = len(global_warns) + sum(len(b['warns']) for b in blocks)

    # Render
    if args.format == 'json':
        pl_json = []
        for b in blocks:
            pre_arr, drop_arr = [], []
            for pr in b['pairs']:
                entry = {'from': pr['a'], 'to': pr['b'],
                         'from_tier': role_info['map'][pr['a']]['tier'],
                         'to_tier': role_info['map'][pr['b']]['tier']}
                if pr['kind'] == 'prewalk':
                    pre_arr.append(entry)
                elif pr['kind'] == 'drop':
                    drop_arr.append(entry)
            pl_json.append({'label': b['label'], 'steps': b['steps'],
                            'prewalk': pre_arr, 'tier_drops': drop_arr})
        all_warns = list(global_warns)
        for b in blocks:
            all_warns.extend(b['warns'])
        doc = {
            'generated_utc': gen_utc,
            'arch': arch_name,
            'source': args.source,
            'pipelines': pl_json,
            'warnings': all_warns,
            'summary': {
                'pipelines': len(blocks), 'steps': sums['steps'], 'agents': sums['agents'],
                'pseudo': sums['pseudo'], 'loops': sums['loops'], 'waves': sums['waves'],
                'prewalk': sums['prewalk'], 'inversions': sums['inv'],
                'drops': sums['drops'], 'unresolved': sums['unresolved'],
                'warn': total_warn,
            },
        }
        print(json.dumps(doc, ensure_ascii=False, indent=2))
        sys.exit(0)

    print('STATUS:VIS_START arch={0} pipelines={1} agents_source={2}'.format(
        arch_name, len(parsed), args.source))
    for w in global_warns:
        print(w)

    for b in blocks:
        if args.format == 'markdown':
            print('### %s' % b['label'])
            print('')
            print('```text')
        else:
            print('=== %s (%d steps) ===' % (b['label'], b['n']))
        for line in b['diagram']:
            print(line)
        if args.format == 'markdown':
            print('```')
            print('')
            print('| # | Step | Kind | Model | Role | Tier |')
            print('|---|---|---|---|---|---|')
            for si, st in enumerate(b['steps'], 1):
                m = st['model'] if st['model'] is not None else '-'
                r = st['role'] if st['role'] is not None else '-'
                t = st['tier'] if st['tier'] is not None else '-'
                print('| {0} | {1} | {2} | {3} | {4} | {5} |'.format(si, st['name'], st['kind'], m, r, t))
            print('')
            pre = [p for p in b['pairs'] if p['kind'] == 'prewalk']
            if pre:
                print('**Prewalk:**')
                for pr in pre:
                    print('- {0}({1},{2}) ==> {3}({4},{5})'.format(
                        pr['a'], role_info['map'][pr['a']]['role'], role_info['map'][pr['a']]['tier'],
                        pr['b'], role_info['map'][pr['b']]['role'], role_info['map'][pr['b']]['tier']))
            dr = [p for p in b['pairs'] if p['kind'] == 'drop']
            if dr:
                print('**Tier drops:**')
                for pr in dr:
                    print('- {0}({1}) -> {2}({3})'.format(
                        pr['a'], role_info['map'][pr['a']]['tier'],
                        pr['b'], role_info['map'][pr['b']]['tier']))
            print('')
        print('PIPELINE:{0} steps={1} agents={2} pseudo={3} loops={4} waves={5} prewalk={6} drops={7}'.format(
            b['label'], b['n'], b['n_agents'], b['n_pseudo'], b['n_loops'], b['n_waves'],
            b['n_pre'], b['n_drop']))
        for pr in b['pairs']:
            if pr['kind'] == 'prewalk':
                print('PREWALK:{0} {1}({2},{3}) ==> {4}({5},{6})'.format(
                    b['label'], pr['a'], role_info['map'][pr['a']]['role'],
                    role_info['map'][pr['a']]['tier'], pr['b'],
                    role_info['map'][pr['b']]['role'], role_info['map'][pr['b']]['tier']))
            elif pr['kind'] == 'inversion':
                print('WARN:PREWALK_INVERSION:{0} {1}({2},{3}) !-> {4}({5},{6})'.format(
                    b['label'], pr['a'], role_info['map'][pr['a']]['role'],
                    role_info['map'][pr['a']]['tier'], pr['b'],
                    role_info['map'][pr['b']]['role'], role_info['map'][pr['b']]['tier']))
            elif pr['kind'] == 'drop':
                print('INFO:TIER_DROP:{0} {1}({2}) -> {3}({4})'.format(
                    b['label'], pr['a'], role_info['map'][pr['a']]['tier'],
                    pr['b'], role_info['map'][pr['b']]['tier']))
        for w in b['warns']:
            print(w)

    print('LEGEND: --> seq | ==> prewalk | ~-> tier drop | !-> INVERSION | LOOP/WAVE boxes')
    print('SUMMARY:pipelines={0} steps={1} agents={2} pseudo={3} loops={4} waves={5} '
          'prewalk={6} inversions={7} drops={8} unresolved={9} warn={10}'.format(
              len(blocks), sums['steps'], sums['agents'], sums['pseudo'], sums['loops'],
              sums['waves'], sums['prewalk'], sums['inv'], sums['drops'],
              sums['unresolved'], total_warn))
    print('STATUS:SUCCESS')
    sys.exit(0)


if __name__ == '__main__':
    main()
