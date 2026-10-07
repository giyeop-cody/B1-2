"""Collect original app termination signals and scoped scheduler trace, plus nice controls."""
import datetime, hashlib, json, os, pathlib, subprocess, time

out=pathlib.Path('/var/log/agent-app/b1-2/policy-scheduling')
out.mkdir(parents=True,exist_ok=True)
app='/home/agent-admin/agent-app/agent-leak-app'
command='. /home/agent-admin/agent-app/env.sh; export MEMORY_LIMIT=512 CPU_MAX_OCCUPY={limit} MULTI_THREAD_ENABLE=false; exec '+app
subprocess.run(['pkill','-f',app],check=False); time.sleep(1)
with (out/'cpu-policy-before.log').open('w') as log:
    before=subprocess.Popen(['strace','-ff','-tt','-e','trace=kill,tgkill,exit,exit_group,setpriority','-o',str(out/'signals'),'runuser','-u','agent-admin','--','bash','-c',command.format(limit=100)],stdout=log,stderr=subprocess.STDOUT)
    try: code=before.wait(timeout=60)
    except subprocess.TimeoutExpired:
        subprocess.run(['pkill','-f',app],check=False); before.wait(timeout=10); raise RuntimeError('CPU policy did not terminate')
    (out/'termination.json').write_text(json.dumps({'timestamp':datetime.datetime.now().astimezone().isoformat(),'exit_code':code,'MEMORY_LIMIT':512,'CPU_MAX_OCCUPY':100,'MULTI_THREAD_ENABLE':False,'binary_sha256':hashlib.sha256(pathlib.Path(app).read_bytes()).hexdigest()},indent=2)+'\n')

trace=pathlib.Path('/sys/kernel/tracing/instances/b12-eval')
trace.mkdir(exist_ok=True)
def write(name,value): (trace/name).write_text(value)
write('tracing_on','0'); write('trace',''); write('buffer_size_kb','4096')
write('events/sched/sched_switch/filter','prev_comm == "agent-leak-app" || next_comm == "agent-leak-app"')
write('events/sched/sched_switch/enable','1')
write('events/sched/sched_wakeup/filter','comm == "agent-leak-app"')
write('events/sched/sched_wakeup/enable','1')
with (out/'normal-app.log').open('w') as log:
    normal=subprocess.Popen(['runuser','-u','agent-admin','--','bash','-c',command.format(limit=50)],stdout=log,stderr=subprocess.STDOUT)
    try:
        for _ in range(100):
            if 'Agent READY' in (out/'normal-app.log').read_text(): break
            time.sleep(.1)
        processes=[]
        for path in pathlib.Path('/proc').glob('[0-9]*/stat'):
            try:
                data=path.read_text()
                if '(agent-leak-app)' in data: processes.append(int(path.parent.name))
            except FileNotFoundError: pass
        with (out/'policies.txt').open('w') as f:
            subprocess.run(['uname','-a'],stdout=f)
            for pid in processes:
                subprocess.run(['ps','-L','-p',str(pid),'-o','pid,tid,cls,rtprio,ni,pri,wchan:24,cmd'],stdout=f)
                for task in pathlib.Path(f'/proc/{pid}/task').iterdir():
                    subprocess.run(['chrt','-p',task.name],stdout=f)
                    f.write((task/'sched').read_text());f.flush()
            f.write('kernel scheduler features: '+pathlib.Path('/sys/kernel/debug/sched/features').read_text())
        write('tracing_on','1'); time.sleep(45); write('tracing_on','0')
        (out/'sched-trace.txt').write_text((trace/'trace').read_text())
    finally:
        write('tracing_on','0'); write('events/sched/sched_switch/enable','0'); write('events/sched/sched_wakeup/enable','0')
        subprocess.run(['pkill','-f',app],check=False); normal.wait(timeout=10)

# Separate saturated controls: same CPU, same cgroup, differing only in nice.
cpu=min(os.sched_getaffinity(0)); hz=os.sysconf('SC_CLK_TCK')
def ticks(pid):
    fields=pathlib.Path(f'/proc/{pid}/stat').read_text().split(); return int(fields[13])+int(fields[14])
controls=[]
try:
    for nice in (0,10):
        def setup(n=nice): os.sched_setaffinity(0,{cpu}); os.nice(n)
        p=subprocess.Popen(['python3','-c','while True: pass'],preexec_fn=setup);controls.append(p)
    time.sleep(1); t0=time.monotonic(); initial=[ticks(p.pid) for p in controls]; time.sleep(12)
    elapsed=time.monotonic()-t0; deltas=[ticks(p.pid)-a for p,a in zip(controls,initial)]
    result={'timestamp':datetime.datetime.now().astimezone().isoformat(),'kind':'separate_busy_loop_control_not_app','same_cpu':cpu,'elapsed_seconds':elapsed,'nice_values':[0,10],'pids':[p.pid for p in controls],'tick_deltas':deltas,'cpu_percent':[d/hz/elapsed*100 for d in deltas],'cpu_share_ratio':deltas[0]/max(1,deltas[1])}
    (out/'priority-control.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result),flush=True)
finally:
    for p in controls: p.terminate();p.wait()
print('Policy signals, app scheduler trace and priority control collected.',flush=True)
