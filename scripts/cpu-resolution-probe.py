"""Sample supplied app CPU from /proc at 20ms; keep internal load separate."""
import csv, datetime, hashlib, json, os, pathlib, re, subprocess, time

root = pathlib.Path('/var/log/agent-app/b1-2/cpu-resolution')
root.mkdir(parents=True, exist_ok=True)
os.chown(root, 1000, 1002)
app = '/home/agent-admin/agent-app/agent-leak-app'
hz = os.sysconf('SC_CLK_TCK')
for mode, limit, duration in [('before',100,60), ('after',50,170)]:
    subprocess.run(['pkill','-f',app], check=False)
    time.sleep(1)
    log = root / f'app_{mode}.log'
    stream = log.open('w')
    command = f'. /home/agent-admin/agent-app/env.sh; export MEMORY_LIMIT=512 CPU_MAX_OCCUPY={limit} MULTI_THREAD_ENABLE=false; exec {app}'
    child = subprocess.Popen(['runuser','-u','agent-admin','--','bash','-c',command], stdout=stream, stderr=subprocess.STDOUT)
    start=time.monotonic(); previous={}; peak=(0,None); ready_at=None
    csvfile=(root/f'cpu_{mode}.csv').open('w'); writer=csv.writer(csvfile)
    writer.writerow(['timestamp','elapsed_s','pid','ppid','cpu_percent_one_core','rss_kb','interval_s','utime_stime_ticks','internal_load'])
    samples=0
    while time.monotonic()-start < duration:
        tick=time.monotonic()
        text=log.read_text(errors='replace')
        if ready_at is None and 'Agent READY' in text: ready_at=tick-start
        loads=re.findall(r'Current Load: ([0-9.]+)%',text); load=loads[-1] if loads else ''
        running=0
        for statpath in pathlib.Path('/proc').glob('[0-9]*/stat'):
            try:
                raw=statpath.read_text(); fields=raw[raw.rfind(')')+2:].split(); pid=int(statpath.parent.name)
                if 'agent-leak-app' not in raw: continue
                if fields[0]=='Z': continue
                running+=1; ticks=int(fields[11])+int(fields[12]); rss=int(fields[21])*os.sysconf('SC_PAGE_SIZE')//1024
                key=(pid,fields[19]); prior=previous.get(key)
                if prior:
                    elapsed=tick-prior[0]; percent=(ticks-prior[1])/hz/elapsed*100
                    writer.writerow([datetime.datetime.now().astimezone().isoformat(),round(tick-start,4),pid,fields[1],round(percent,3),rss,round(elapsed,6),ticks,load]); samples+=1
                    if percent>peak[0]: peak=(percent,pid)
                previous[key]=(tick,ticks)
            except (FileNotFoundError,ProcessLookupError,PermissionError): pass
        csvfile.flush()
        if child.poll() is not None and not running: break
        time.sleep(max(0,.02-(time.monotonic()-tick)))
    elapsed=time.monotonic()-start
    result='TERMINATED' if child.poll() is not None else 'SURVIVED_WINDOW'
    subprocess.run(['pkill','-f',app],check=False)
    try: child.wait(timeout=5)
    except subprocess.TimeoutExpired: child.kill(); child.wait()
    stream.close(); csvfile.close()
    summary={'case':mode,'timestamp':datetime.datetime.now().astimezone().isoformat(),'MEMORY_LIMIT':512,'CPU_MAX_OCCUPY':limit,'MULTI_THREAD_ENABLE':False,'requested_seconds':duration,'observed_seconds':elapsed,'ready_at_seconds':ready_at,'result':result,'exit_code':child.returncode,'peak_cpu_percent':peak[0],'peak_pid':peak[1],'sample_rows':samples,'sampling_interval_target_seconds':.02,'USER_HZ':hz,'binary_sha256':hashlib.sha256(pathlib.Path(app).read_bytes()).hexdigest(),'note':'20ms CPU estimates are quantized at USER_HZ; app internal load is a separate value.'}
    (root/f'summary_{mode}.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary),flush=True)
