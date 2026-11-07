# Driver da serie F9-03 pelo app no S25. Uso: python rodar_app.py <segundos> <rodadas> c01,c02,... [c09:0,c03:1] (id:indice reaproveita sessao ja importada). Rolagem do seletor adicionada em 2026-11-07 (nao testada no aparelho ainda); ui_s25.py deve ser salvo como ui.py na mesma pasta.
import sys, json, time
sys.path.insert(0, '.')
from ui import *
BUDGET = float(sys.argv[1]); ROUNDS = int(sys.argv[2]); IDS = sys.argv[3].split(',')
t0 = time.time()
left = lambda: BUDGET - (time.time() - t0)
R = r'C:\Users\notefael\projetos\segundamente'
corp = {c['id']: c for c in json.load(open(R + r'\docs\medicoes\f9-02\corpus.json', encoding='utf-8'))['casos']}
BASE = 'app_flutter/workspace/_Rafael/SessionReports'
def ra(*c):
    return adb('shell', 'run-as', 'app.segundamente.dev', *c, text=True, encoding='utf-8').stdout
def sessions(): return set(ra('ls', BASE).split())
def mtime(sid): return ra('stat', '-c', '%Y', f'{BASE}/{sid}/report.json').strip()
def menu_to_history():
    r = dump()
    f = r is not None and find(r, 'Menu', exact=True)
    if not f: return False
    tap(f[0], f[1]); time.sleep(1.5)
    for _ in range(3):
        adb('shell', 'input', 'swipe', '500', '1200', '500', '400', '400'); time.sleep(0.8)
        r = dump()
        g = r is not None and find(r, 'Histórico de chat')
        if g: tap(g[0], g[1]); time.sleep(2); return True
    return False
def goto_history():
    for _ in range(6):
        r = dump()
        if r is None: time.sleep(1); continue
        w = find(r, 'Enviar o PDF para ler')
        if w:  # confirmacao de um envio anterior que ficou aberta: cancela
            v = find(r, 'Voltar', exact=True)
            if v: tap(v[0], v[1])
            time.sleep(1.5); continue
        f = find(r, 'Histórico de chat')
        if f and f[1] < 300: return True
        if find(r, 'Gerar com o modelo'):
            v = find(r, 'Voltar', exact=True)
            if v: tap(v[0], v[1])
            else: adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
            time.sleep(1.5); continue
        if f: tap(f[0], f[1]); time.sleep(2); continue
        if not menu_to_history(): back_to_app()
    return False
def abre_relatorio(k=0):
    for _ in range(8):
        r = dump()
        if r is not None and find(r, 'Gerar com o modelo'): return True
        if r is not None:
            btn = sorted((cy, cx) for n, cx, cy, bb in nodes(r) if 'Abrir relat' in (n.get('content-desc') or n.get('text') or ''))
            if len(btn) > k: tap(btn[k][1], btn[k][0]); time.sleep(2.5); continue
        time.sleep(2)
    return False
def importa(cid):
    ext = 'pdf' if corp[cid]['origem'] == 'pdf' else 'txt'
    if not goto_history(): return False
    if not tap_text('Importar transcri'): return False
    time.sleep(2)
    tap_text('f9corpus', tries=2)  # o seletor costuma reabrir dentro da pasta: entao nao ha o que tocar
    time.sleep(1.5)
    if not tap_text_scroll(f'f9c_{cid}.{ext}'):
        back_to_app(); return False
    time.sleep(2)
    if not tap_text('Enviar PDF' if ext == 'pdf' else 'Enviar', tries=4, exact=(ext == 'pdf')): return False  # 'Enviar agora' / 'Enviar PDF'
    time.sleep(8 if ext == 'pdf' else 3)
    return abre_relatorio(0)
def gera(sid):
    before = sessions()
    old = mtime(sid) if sid else None
    if not tap_text('Gerar com o modelo', tries=3): return sid, None
    time.sleep(1.2)
    if not tap_text('Enviar agora', tries=3): return sid, None
    for _ in range(45):
        time.sleep(2)
        if sid is None:
            new = sessions() - before
            if len(new) == 1: sid = next(iter(new)); time.sleep(3); break
        elif mtime(sid) not in ('', old): break
    else:
        return sid, None
    time.sleep(1)
    try: return sid, json.loads(ra('cat', f'{BASE}/{sid}/report.json'))
    except Exception: return sid, None
def score(cid, rep):
    exp = [e for e in corp[cid]['esperado'] if e['tipo'] == 'tarefa']
    tasks = [i for i in rep['items'] if i['kind'] == 'task']
    return dict(esp=len(exp), achou=min(len(tasks), len(exp)), falsas=max(0, len(tasks) - len(exp)),
                itens=len(rep['items']), paginas_ok=all(i['source']['clock'] for i in rep['items']))
out = open(r'C:\Users\notefael\projetos\segundamente\docs\medicoes\f9-03\app_rodadas.jsonl', 'a', encoding='utf-8')
REUSE = dict(x.split(':') for x in (sys.argv[4].split(',') if len(sys.argv) > 4 else []))
for cid in IDS:
    adb('shell', 'settings', 'put', 'system', 'accelerometer_rotation', '0'); adb('shell', 'settings', 'put', 'system', 'user_rotation', '1')  # o driver so conhece a tela em paisagem
    back_to_app()
    if left() < 70: print('sem tempo antes de', cid); break
    ok = abre_relatorio(int(REUSE[cid])) if cid in REUSE and goto_history() else importa(cid)
    print(cid, 'relatorio aberto', ok, round(time.time() - t0))
    if not ok: continue
    sid = None
    for rd in range(1, ROUNDS + 1):
        if left() < 45: break
        sid, rep = gera(sid)
        row = dict(caso=cid, sessao=sid, rodada=rd, tipo=(rep or {}).get('kind'), **(score(cid, rep) if rep else {'erro': 'sem_resposta'}))
        out.write(json.dumps(row, ensure_ascii=False) + chr(10)); out.flush()
        print(row, round(time.time() - t0))
