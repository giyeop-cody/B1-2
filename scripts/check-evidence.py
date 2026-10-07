"""Verify current submission evidence without running destructive experiments."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent
items = json.loads((root / 'evidence/manifest.json').read_text())
assert len(items) == 30
for item in items:
    data = (root / item['path']).read_bytes()
    assert len(data) == item['bytes'], item['path']
    assert hashlib.sha256(data).hexdigest() == item['sha256'], item['path']

presets = {'oom': ('MEMORY_LIMIT', '256', '512'),
           'cpu': ('CPU_MAX_OCCUPY', '100', '50'),
           'deadlock': ('MULTI_THREAD_ENABLE', 'true', 'false')}
variables = ('MEMORY_LIMIT', 'CPU_MAX_OCCUPY', 'MULTI_THREAD_ENABLE')
for scenario, (changed, before_value, after_value) in presets.items():
    states = []
    for mode in ('before', 'after'):
        text = (root / f'evidence/{scenario}/metadata_{mode}.txt').read_text()
        meta = dict(line.split('=', 1) for line in text.splitlines() if '=' in line)
        assert meta['host'] == 'b1-lab'
        assert meta['timestamp'].startswith('2026-10-07T21:')
        expected = 'SURVIVED_170s' if mode == 'after' else (
            'HUNG_THEN_KILLED' if scenario == 'deadlock' else 'TERMINATED')
        assert meta['result'] == expected
        states.append(meta)
    assert states[0][changed] == before_value
    assert states[1][changed] == after_value
    for variable in variables:
        if variable != changed:
            assert states[0][variable] == states[1][variable]

markers = {'oom/app_before.log': 'Memory limit exceeded',
           'cpu/app_before.log': 'CPU Threshold Violated!',
           'deadlock/app_before.log': 'Status: BLOCKED',
           'deadlock/stacktrace_before.txt': 'PyThread_acquire_lock_timed',
           '40-scheduling-probe.txt': '6.17.8-orbstack',
           '30-restore-b1-1.txt': 'PASS=36 FAIL=0',
           'b1-1/verification.txt': 'PASS=36 FAIL=0'}
for path, marker in markers.items():
    assert marker in (root / 'evidence' / path).read_text(), path
print('PASS: 30 original evidence hashes, six scenarios, controlled variables, stacks and restoration.')
