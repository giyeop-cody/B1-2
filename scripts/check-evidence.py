"""Verify current submission evidence without running destructive experiments."""
from pathlib import Path
import csv
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

extra=json.loads((root/'evidence/supplemental-manifest.json').read_text())
for item in extra:
    data=(root/item['path']).read_bytes()
    assert len(data)==item['bytes']
    assert hashlib.sha256(data).hexdigest()==item['sha256'],item['path']
before=json.loads((root/'evidence/cpu-resolution/summary_before.json').read_text())
after=json.loads((root/'evidence/cpu-resolution/summary_after.json').read_text())
assert before['CPU_MAX_OCCUPY']==100 and after['CPU_MAX_OCCUPY']==50
assert before['result']=='TERMINATED' and after['result']=='SURVIVED_WINDOW'
assert after['observed_seconds']>=170
assert before['binary_sha256']==after['binary_sha256']
assert before['peak_cpu_percent']>80
with (root/'evidence/cpu-resolution/cpu_before.csv').open() as f:
    samples=list(csv.DictReader(f))
worker_samples=[row for row in samples if int(row['pid'])==before['peak_pid'] and float(row['elapsed_s'])>1]
assert max(float(row['cpu_percent_one_core']) for row in worker_samples)>80
assert before['MEMORY_LIMIT']==after['MEMORY_LIMIT']==512
assert before['MULTI_THREAD_ENABLE']==after['MULTI_THREAD_ENABLE']==False
signal=(root/'evidence/policy-scheduling/signals.17834').read_text()
assert 'kill(17834, SIGTERM)' in signal and 'si_pid=17834' in signal
assert 'setpriority(PRIO_PROCESS, 0, 10) = 0' in signal
assert 'CPU Threshold Violated!' in (root/'evidence/policy-scheduling/cpu-policy-before.log').read_text()
assert 'SCHED_OTHER' in (root/'evidence/policy-scheduling/policies.txt').read_text()
trace=(root/'evidence/policy-scheduling/sched-trace.txt').read_text()
assert 'sched_switch:' in trace and 'sched_wakeup:' in trace
control=json.loads((root/'evidence/policy-scheduling/priority-control.json').read_text())
assert control['nice_values']==[0,10] and control['cpu_share_ratio']>4
assert 'PASS=36 FAIL=0' in (root/'evidence/policy-scheduling/restore-final.txt').read_text()
print(f'PASS: {len(extra)} supplemental hashes, high-resolution CPU, self-SIGTERM, scheduler trace, nice controls and final restoration.')
