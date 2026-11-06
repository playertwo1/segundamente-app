import json, re, sys, time, unicodedata, urllib.request
corpus = json.load(open(sys.argv[1], encoding="utf-8"))["casos"]
SYS = ("Classifique o texto em itens. Tipos permitidos: tarefa (compromisso claro de fazer algo), ideia, decisao (algo decidido), "
       "duvida (pergunta em aberto), followup (retomar depois), resumo (fato ja ocorrido ou contexto). "
       "Opiniao ou hipotese sem compromisso NAO vira item. Nao repita itens iguais. Responsavel e prazo so se ditos, senao \"nao informado\". "
       "Responda APENAS um JSON: lista de objetos com chaves tipo, texto, responsavel, prazo. Se nada se aplica, responda [].")
def norm(s):
    s = unicodedata.normalize("NFD", str(s).lower()); return re.sub(r"[^a-z0-9 ]", "", "".join(c for c in s if unicodedata.category(c) != "Mn")).strip()
def ask(text):
    body = json.dumps({"messages":[{"role":"system","content":SYS},{"role":"user","content":text}],"temperature":0,"max_tokens":400}).encode()
    t = time.time(); r = json.load(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8099/v1/chat/completions", body, {"Content-Type":"application/json"}), timeout=300))
    return r["choices"][0]["message"]["content"], time.time()-t, r["usage"]["completion_tokens"]
res = []; lat = []
for c in corpus:
    out, dt, nt = ask(c["texto"]); lat.append((dt, nt))
    m = re.search(r"\[.*\]", out, re.S)
    try: pred = json.loads(m.group(0)) if m else None
    except Exception: pred = None
    exp = c["esperado"]
    ok_json = isinstance(pred, list) and all(isinstance(p, dict) for p in pred)
    tipos = lambda L: sorted(norm(x.get("tipo","")) for x in L)
    tipo_ok = ok_json and tipos(pred) == tipos(exp)
    resp_ok = None
    if ok_json and tipo_ok and exp:
        resp_ok = all(any(norm(e.get("responsavel","")) in norm(p.get("responsavel","")) or norm(p.get("responsavel","")) in norm(e.get("responsavel","")) for p in pred) for e in exp if norm(e.get("tipo",""))=="tarefa")
    res.append((c["id"], c["categoria"], ok_json, tipo_ok, resp_ok))
n = len(res)
print(f"casos={n} json_valido={sum(r[2] for r in res)} tipos_e_contagem_certos={sum(r[3] for r in res)}")
rr = [r[4] for r in res if r[4] is not None]; print(f"responsavel_certo={sum(rr)}/{len(rr)}")
cats = {}
for r in res: cats.setdefault(r[1], []).append(r[3])
for k, v in sorted(cats.items()): print(f"  {k}: {sum(v)}/{len(v)}")
print("falhas:", [r[0] for r in res if not r[3]])
print(f"latencia media {sum(l[0] for l in lat)/n:.1f}s; tokens/s {sum(l[1] for l in lat)/max(sum(l[0] for l in lat),1e-9):.1f}")
