import subprocess, time, re, xml.etree.ElementTree as ET
D = 'RQCY10934YV'
def adb(*a, **k):
    return subprocess.run(['adb', '-s', D, *a], capture_output=True, **k)
def dump():
    adb('shell', 'uiautomator', 'dump', '/sdcard/ui_f9.xml')
    r = adb('exec-out', 'cat', '/sdcard/ui_f9.xml')
    try:
        return ET.fromstring(r.stdout.decode('utf-8', 'replace'))
    except ET.ParseError:
        return None
def nodes(root):
    for n in root.iter('node'):
        b = re.findall(r'\d+', n.get('bounds', ''))
        if len(b) == 4:
            x1, y1, x2, y2 = map(int, b)
            yield n, (x1 + x2) // 2, (y1 + y2) // 2, (x1, y1, x2, y2)
def find(root, sub, exact=False):
    for n, cx, cy, bb in nodes(root):
        for t in (n.get('text', ''), n.get('content-desc', '')):
            if t and ((t == sub) if exact else (sub in t)):
                return cx, cy, bb
    return None
def tap(x, y):
    adb('shell', 'input', 'tap', str(x), str(y))
def tap_text(sub, tries=6, wait=1.5, exact=False):
    for _ in range(tries):
        r = dump()
        if r is not None:
            f = find(r, sub, exact)
            if f:
                tap(f[0], f[1]); return True
        time.sleep(wait)
    return False
def has(sub):
    r = dump()
    return r is not None and find(r, sub) is not None
def swipe_up():
    adb('shell', 'input', 'swipe', '700', '2400', '700', '900', '350')

def tap_text_scroll(sub, rounds=10, exact=False):
    """Like tap_text, but scrolls the list down when the text is not on screen."""
    for _ in range(rounds):
        r = dump()
        if r is not None:
            f = find(r, sub, exact)
            if f:
                tap(f[0], f[1]); return True
            if find(r, 'Abrir de'):  # picker drawer is open over the list
                adb('shell', 'input', 'keyevent', 'KEYCODE_BACK'); time.sleep(1); continue
        adb('shell', 'input', 'swipe', '1600', '1150', '1600', '450', '400')
        time.sleep(1)
    return False
def back_to_app(pkg='app.segundamente.dev'):
    for _ in range(4):
        out = adb('shell', 'dumpsys window | grep mCurrentFocus', text=True).stdout
        if pkg in out and 'Picker' not in out and 'documentsui' not in out: return True
        adb('shell', 'input', 'keyevent', 'KEYCODE_BACK'); time.sleep(1)
    return False
