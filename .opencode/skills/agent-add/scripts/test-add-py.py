#!/usr/bin/env python3
"""test-add-py.py - unit tests for add.py pure edit functions (no live config
is read or written except the read-only T6 regression probe).

Covers the two historically broken generators:
  1. edit_routing_array      - insertion must land inside the addressed
                               ROUTING_TABLES array (position arithmetic bug
                               once routed tokens into the WRONG array and
                               corrupted the TypeScript source).
  2. add_fm_task_extras +    - generated agent frontmatter must be valid YAML
     frontmatter assembly      with one permission per line and consistent
                               task-block indentation.

Usage:
    python test-add-py.py

Exit codes:
    0 all tests passed
    1 at least one test failed
    2 environment error (add.py / PyYAML missing)
"""

import importlib.util
import re
import sys
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
ADD_PY = HERE / 'add.py'

try:
    import yaml
except ImportError:
    yaml = None

spec = importlib.util.spec_from_file_location('add_under_test', ADD_PY)
if spec is None or spec.loader is None:
    print(f'FAIL: cannot load {ADD_PY}')
    sys.exit(2)
add = importlib.util.module_from_spec(spec)
spec.loader.exec_module(add)

PASS = 0
FAIL = 0


def check(name, condition, detail=''):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f'PASS: {name}')
    else:
        FAIL += 1
        print(f'FAIL: {name} -- {detail}')


# The fixture has a realistic prefix so 'const ROUTING_TABLES' is NOT at
# position 0 of the text - position-0 fixtures hide the double-count bug.
TS_FIXTURE = '\r\n'.join([
    'import type { Plugin } from "@opencode-ai/plugin"',
    '',
    'const ROUTING_TABLES = {',
    '  orchestrator: [',
    '    "orchestrator-identity-probe",',
    '    "dev-reviewer",',
    '    "codebase-analyzer"',
    '  ],',
    '  plankestrator: [',
    '    "plankestrator-identity-probe",',
    '    "view-image"',
    '  ]',
    '}',
])

TEMPLATE_MD = '\r\n'.join([
    '---',
    'description: T',
    'mode: subagent',
    'model: m',
    'temperature: 0.1',
    'permission:',
    '  edit: deny',
    '  write: deny',
    '  read: allow',
    '  task:',
    '    "*": deny',
    '    "advisor": allow',
    '---',
    '',
    'body',
])


def build_frontmatter(agent, model, description, perm_l, body='BODY\n'):
    """Replicates main()'s frontmatter assembly."""
    fm_lines = ['---',
                'description: ' + description,
                'mode: subagent',
                'model: ' + model,
                'temperature: 0.1',
                'permission:']
    for l in perm_l:
        fm_lines.append('  ' + l)
    fm_lines.append('---')
    fm_lines.append('')
    return '\n'.join(fm_lines) + body


def parse_frontmatter(text):
    """Extracts and parses the YAML block between the first two '---' lines.
    Returns (data, error_message)."""
    if yaml is None:
        return None, 'pyyaml-not-installed'
    parts = text.split('\n---\n', 1)
    if len(parts) != 2 or not parts[0].startswith('---\n'):
        return None, 'frontmatter delimiters not found'
    try:
        return yaml.safe_load(parts[0][4:]), None
    except Exception as ex:
        return None, f'{type(ex).__name__}: {str(ex).splitlines()[0]}'


def extract_template_perm_lines(tpl_text):
    """Replicates main()'s -perm-template permission-block extraction."""
    tpl_lines = add.split_lines_keep_eol(tpl_text)
    perm_start = -1
    for i in range(0, len(tpl_lines), 2):
        if re.match(r'^permission:[ \t]*$', tpl_lines[i]):
            perm_start = i
            break
    assert perm_start >= 0, 'fixture: permission: line not found'
    fm = []
    for i in range(perm_start + 2, len(tpl_lines), 2):
        if re.match(r'^---[ \t]*$', tpl_lines[i]):
            break
        fm.append(re.sub(r'^  ', '', tpl_lines[i], count=1))
    return fm


def array_span(text, key):
    start = text.find(key + ': [')
    close = text.find(']', start)
    return start, close


# ============================================================================
# TEST 1: edit_routing_array inserts into the CORRECT array (orchestrator)
# ============================================================================
try:
    new_text, old_count = add.edit_routing_array(TS_FIXTURE, 'orchestrator', 'new-agent')
except add.EditError as e:
    new_text, old_count = None, -1
    check('T1 no error', False, f'EditError: {e}')
else:
    check('T1 no error', True)

if new_text is not None:
    tok_pos = new_text.find('"new-agent"')
    s, e = array_span(new_text, '  orchestrator')
    check('T1 token position inside orchestrator array bounds',
          s < tok_pos < e, f'tokPos={tok_pos} span={s}..{e}')
    check('T1 orchestrator token count 3 -> 4',
          add.count_routing_plugin(new_text, 'orchestrator') == 4,
          f"got {add.count_routing_plugin(new_text, 'orchestrator')}")
    check('T1 plankestrator token count unchanged (2)',
          add.count_routing_plugin(new_text, 'plankestrator') == 2,
          f"got {add.count_routing_plugin(new_text, 'plankestrator')}")
    check('T1 new-agent in orchestrator exactly once',
          add.get_routing_tokens(new_text, 'orchestrator').count('new-agent') == 1,
          f"orch={add.get_routing_tokens(new_text, 'orchestrator')}")
    check('T1 new-agent NOT in plankestrator',
          add.get_routing_tokens(new_text, 'plankestrator').count('new-agent') == 0,
          f"plank={add.get_routing_tokens(new_text, 'plankestrator')}")
    check('T1 existing token "codebase-analyzer" intact',
          new_text.count('"codebase-analyzer"') == 1, 'token corrupted')
    check('T1 existing token "view-image" intact',
          new_text.count('"view-image"') == 1, 'token corrupted')

# ============================================================================
# TEST 2: edit_routing_array inserts into the CORRECT array (plankestrator)
# ============================================================================
try:
    new_text, old_count = add.edit_routing_array(TS_FIXTURE, 'plankestrator', 'new-agent')
    err = None
except add.EditError as e:
    new_text = None
    err = str(e)
check('T2 no error', err is None, f'EditError: {err}')
if new_text is not None:
    tok_pos = new_text.find('"new-agent"')
    s, e = array_span(new_text, '  plankestrator')
    check('T2 token position inside plankestrator array bounds',
          s < tok_pos < e, f'tokPos={tok_pos} span={s}..{e}')
    check('T2 plankestrator token count 2 -> 3',
          add.count_routing_plugin(new_text, 'plankestrator') == 3,
          f"got {add.count_routing_plugin(new_text, 'plankestrator')}")
    check('T2 orchestrator token count unchanged (3)',
          add.count_routing_plugin(new_text, 'orchestrator') == 3,
          f"got {add.count_routing_plugin(new_text, 'orchestrator')}")

# ============================================================================
# TEST 3: duplicate insert is rejected
# ============================================================================
new_text, _ = add.edit_routing_array(TS_FIXTURE, 'orchestrator', 'new-agent')
try:
    add.edit_routing_array(new_text, 'orchestrator', 'new-agent')
    check('T3 duplicate rejected', False, 'no EditError raised')
except add.EditError:
    check('T3 duplicate rejected', True)

# ============================================================================
# TEST 4: frontmatter preset path - valid YAML, one permission per line
# ============================================================================
perm_l = add.add_fm_task_extras(list(add.PRESETS['standard']['fm_yaml']),
                                ['view-image', 'utility'])
fm = build_frontmatter('new-agent', 'bifrost-litellm/x', 'Test agent', perm_l)
merged = [l for l in fm.splitlines()
          if len(re.findall(r': (deny|allow)', l)) > 1]
check('T4 no merged multi-permission lines', not merged, f'merged: {merged}')
check('T4 single permission: block', fm.count('\npermission:\n') == 1,
      'permission: header missing or duplicated')
data, err = parse_frontmatter(fm)
check('T4 frontmatter parses as YAML', err is None, err or '')
if data is not None:
    check('T4 permission block is a mapping',
          isinstance(data.get('permission'), dict), f"got {type(data.get('permission'))}")
    check('T4 permission keys preserved',
          data['permission'].get('edit') == 'deny'
          and data['permission'].get('read') == 'allow',
          f"permission={data.get('permission')}")
    check('T4 task block present with extras',
          data['permission'].get('task', {}).get('view-image') == 'allow'
          and data['permission']['task'].get('utility') == 'allow',
          f"task={data['permission'].get('task')}")

# ============================================================================
# TEST 5: frontmatter template path - task block from the template must keep
#         consistent indentation after extras are inserted (invalid YAML
#         regression: "mapping values are not allowed here")
# ============================================================================
fm_perm_lines = extract_template_perm_lines(TEMPLATE_MD)
check('T5 template perm lines = 6', len(fm_perm_lines) == 6, f'got {len(fm_perm_lines)}')
perm_l = add.add_fm_task_extras(fm_perm_lines, ['extra-agent'])
check('T5 line count = 7 (template 6 + 1 extra)', len(perm_l) == 7, f'got {len(perm_l)}: {perm_l}')
check('T5 first line is "edit: deny"', perm_l[0] == 'edit: deny', f'got <{perm_l[0]}>')
fm = build_frontmatter('new-agent', 'bifrost-litellm/x', 'Test agent', perm_l)
task_entries = [l for l in fm.splitlines() if l.startswith('    ') and ':' in l]
indents = {len(l) - len(l.lstrip()) for l in task_entries}
check('T5 task-block entries share one indent level', len(indents) == 1,
      f'indents={sorted(indents)} lines={task_entries}')
data, err = parse_frontmatter(fm)
check('T5 frontmatter parses as YAML', err is None, err or '')
if data is not None:
    task = data['permission'].get('task', {})
    check('T5 template task entry preserved (advisor: allow)',
          task.get('advisor') == 'allow', f'task={task}')
    check('T5 extra inserted (extra-agent: allow)',
          task.get('extra-agent') == 'allow', f'task={task}')
    check('T5 star deny preserved', task.get('*') == 'deny', f'task={task}')

# ============================================================================
# TEST 6: real live plugin (regression on the actual file, read-only)
# ============================================================================
live_plugin = Path.home() / '.config' / 'opencode' / 'plugins' / 'workflow-enforcement.ts'
if live_plugin.is_file():
    ts = live_plugin.read_text(encoding='utf-8-sig')
    orch_before = add.count_routing_plugin(ts, 'orchestrator')
    plank_before = add.count_routing_plugin(ts, 'plankestrator')
    try:
        new_text, _ = add.edit_routing_array(ts, 'orchestrator', 'zz-regression-probe')
        err = None
    except add.EditError as e:
        new_text, err = None, str(e)
    check('T6 no error on real plugin', err is None, f'EditError: {err}')
    if new_text is not None:
        check('T6 orchestrator count +1',
              add.count_routing_plugin(new_text, 'orchestrator') == orch_before + 1,
              f'before={orch_before} after={add.count_routing_plugin(new_text, "orchestrator")}')
        check('T6 plankestrator count unchanged',
              add.count_routing_plugin(new_text, 'plankestrator') == plank_before,
              f'before={plank_before} after={add.count_routing_plugin(new_text, "plankestrator")}')
        check('T6 probe NOT in plankestrator',
              add.get_routing_tokens(new_text, 'plankestrator').count('zz-regression-probe') == 0,
              'probe leaked into plankestrator')
        check('T6 probe exactly once in orchestrator',
              add.get_routing_tokens(new_text, 'orchestrator').count('zz-regression-probe') == 1,
              'probe missing from orchestrator')
        # no collateral damage: everything outside the orchestrator array is
        # byte-identical (the plugin legitimately references "research-reviewer"
        # in other tables, so per-token counts alone cannot prove integrity)
        orch_key = ts.find('orchestrator: [')
        plank_key = '  plankestrator: ['
        check('T6 text before orchestrator array byte-identical',
              ts[:orch_key] == new_text[:orch_key], 'prefix changed')
        check('T6 plankestrator array byte-identical',
              ts[ts.find(plank_key):] == new_text[new_text.find(plank_key):],
              'plankestrator array changed')
else:
    print('SKIP: live plugin not found')

# ============================================================================
print()
print(f'RESULT: pass={PASS} fail={FAIL}')
sys.exit(1 if FAIL else 0)
