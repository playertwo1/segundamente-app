"""One run per engine on the S25: wall time, peak PSS, CPU seconds, battery stats."""
import glob
import json
import os
import re
import subprocess
import sys
import time

PKG = 'app.segundamente.ocr_probe'
SER = 'RQCY10934YV'
EXT = f'/sdcard/Android/data/{PKG}/files'


def adb(*a, check=False, text=True):
    env = dict(os.environ, MSYS_NO_PATHCONV='1')
    r = subprocess.run(['adb', '-s', SER, *a], capture_output=True, text=text, env=env,
                       encoding='utf-8' if text else None, errors='replace' if text else None)
    return r.stdout if text else r.stdout


def sh(cmd):
    return adb('shell', cmd)


def pid():
    return sh(f'pidof {PKG}').strip().split()[0] if sh(f'pidof {PKG}').strip() else ''


def cpu_seconds(p):
    f = sh(f'cat /proc/{p}/stat').split(')')[-1].split()
    return (int(f[11]) + int(f[12])) / 100.0  # utime + stime, ticks at 100 Hz


def peak_pss(p):
    out = sh(f'dumpsys meminfo {p}')
    m = re.search(r'TOTAL PSS:\s+(\d+)', out) or re.search(r'TOTAL\s+(\d+)', out)
    return int(m.group(1)) // 1024 if m else 0


def run(engine, timeout=1500):
    sh(f'am force-stop {PKG}')
    sh(f'rm -f {EXT}/results_*.json {EXT}/done.txt')
    sh(f"echo {engine} > {EXT}/only.txt; chmod 666 {EXT}/only.txt")
    sh('dumpsys batterystats --reset')
    adb('logcat', '-c')
    t0 = time.time()
    sh(f'am start -n {PKG}/.MainActivity')
    peak = 0
    while time.time() - t0 < timeout:
        time.sleep(3)
        if 'done.txt' in sh(f'ls {EXT}'):
            break
        p = pid()
        if p:
            peak = max(peak, peak_pss(p))
    wall = time.time() - t0
    p = pid()
    cpu = cpu_seconds(p) if p else -1
    peak = max(peak, peak_pss(p)) if p else peak
    bat = sh(f'dumpsys batterystats {PKG}')
    open(f'bat_{engine}.txt', 'w', encoding='utf-8').write(bat)
    res = {}
    for f in sh(f'ls {EXT}').split():
        if f.startswith('results_'):
            raw = adb('exec-out', 'cat', f'{EXT}/{f}')
            res = json.loads(raw)
    return {'engine': engine, 'wall_s': round(wall, 1), 'cpu_s': cpu, 'peak_pss_mb': peak, 'results': res}


if __name__ == '__main__':
    engines = sys.argv[1:]
    summary = {}
    for e in engines:
        r = run(e)
        json.dump(r, open(f'run_{e}.json', 'w', encoding='utf-8'), ensure_ascii=False)
        print(e, {k: v for k, v in r.items() if k != 'results'}, flush=True)
