"""Read-only evaluator evidence display; never runs the target application."""
from pathlib import Path
import csv, json, re, sys
root=Path(__file__).resolve().parent.parent
case=sys.argv[1] if len(sys.argv)>1 else 'all'
assert case in ('all','oom','cpu','deadlock','bonus')
def display(path, pattern=None, tail=None):
    print(f'\n=== {path} ===')
    lines=(root/path).read_text().splitlines()
    if pattern: lines=[line for line in lines if re.search(pattern,line)]
    if tail: lines=lines[-tail:]
    print('\n'.join(lines))
for scenario in ('oom','cpu','deadlock'):
    if case not in ('all',scenario): continue
    for mode in ('before','after'):
        display(f'evidence/{scenario}/metadata_{mode}.txt')
        display(f'evidence/{scenario}/app_{mode}.log',r'CRITICAL|LOCK ACQUIRED|WAITING|Current Heap|Current Load',8)
    display(f'evidence/{scenario}/monitor_before.log',tail=5)
    if scenario=='cpu':
        for mode in ('before','after'): display(f'evidence/cpu-resolution/summary_{mode}.json')
        rows=list(csv.DictReader((root/'evidence/cpu-resolution/cpu_before.csv').open()))
        print('\n=== strongest post-boot worker CPU samples ===')
        for row in sorted((r for r in rows if float(r['elapsed_s'])>1),key=lambda r:float(r['cpu_percent_one_core']),reverse=True)[:6]: print(json.dumps(row))
        display('evidence/policy-scheduling/cpu-policy-before.log',r'CRITICAL|Current Load',3)
        display('evidence/policy-scheduling/signals.17834')
    if scenario=='deadlock':
        display('evidence/deadlock/process-samples_before.txt',r'11287.*futex',6)
        display('evidence/deadlock/stacktrace_before.txt',r'PyThread_acquire_lock_timed|total_threads|판정:')
if case in ('all','bonus'):
    display('evidence/policy-scheduling/log-pattern.json')
    display('evidence/policy-scheduling/policies.txt',r'SCHED_|NI PRI| TS ')
    display('evidence/policy-scheduling/priority-control.json')
    display('evidence/policy-scheduling/sched-trace.txt',r'entries-in-buffer|sched_switch|sched_wakeup',8)
display('evidence/policy-scheduling/restore-final.txt',r'RESULT:|VERIFICATION:')
