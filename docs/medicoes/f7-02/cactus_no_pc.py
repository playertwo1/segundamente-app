# Cactus (pip cactus-compute 4.1.0, Needle 3) nos 40 casos da F9-02 + teste de embeddings. Rodar com CACTUS_TELEMETRY=0.
import json, re, sys, time, unicodedata, math
from cactus import Cactus
TIPOS = ["tarefa","ideia","decisao","duvida","followup","resumo"]
TOOL = {"name":"registrar_itens","description":"Registra os itens do texto. Tipos: tarefa (compromisso claro de fazer algo), ideia, decisao (algo decidido), duvida (pergunta em aberto), followup (retomar depois), resumo (fato ja ocorrido). Opiniao ou hipotese sem compromisso nao vira item; se nada se aplica, lista vazia.",
 "parameters":{"type":"object","properties":{"itens":{"type":"array","items":{"type":"object","properties":{
   "tipo":{"type":"string","enum":TIPOS},"texto":{"type":"string"},"responsavel":{"type":"string"},"prazo":{"type":"string"}},"required":["tipo","texto"]}}},"required":["itens"]}}
def norm(s):
    s = unicodedata.normalize("NFD", str(s).lower()); return re.sub(r"[^a-z0-9 ]", "", "".join(c for c in s if unicodedata.category(c) != "Mn")).strip()
corpus = json.load(open(sys.argv[1], encoding="utf-8"))["casos"]
a = Cactus(tools=[TOOL], stateless=True)
ok=0; lat=[]; cats={}; ram=0; texto_ok=0
for c in corpus:
    t=time.time(); r=a.complete(c["texto"]); lat.append(time.time()-t); ram=max(ram, r.get("peak_ram_mb") or 0)
    calls = r.get("function_calls") or r.get("suppressed_calls") or []
    pred = (calls[0].get("arguments") or {}).get("itens", []) if calls else []
    pred = [p for p in pred if isinstance(p, dict)]
    tipos = lambda L: sorted(norm(x.get("tipo","")) for x in L)
    good = tipos(pred) == tipos(c["esperado"]); ok += good; cats.setdefault(c["categoria"], []).append(good)
print(f"casos={len(corpus)} tipos_e_contagem_certos={ok}")
for k,v in sorted(cats.items()): print(f"  {k}: {sum(v)}/{len(v)}")
print(f"latencia media {sum(lat)/len(lat):.2f}s; pico RAM {ram} MB")
cos = lambda x,y: sum(i*j for i,j in zip(x,y))/math.sqrt(sum(i*i for i in x)*sum(j*j for j in y))
e = Cactus(stateless=True)
for lang, q, par, out in [("pt","Preciso renovar o seguro do carro","Tenho que pagar a renovação da apólice do automóvel","A reunião com o fornecedor foi ótima"),
                          ("en","I need to renew the car insurance","I have to pay the renewal of the auto policy","The meeting with the supplier was great")]:
    v=[e.embed(x) for x in (q,par,out)]
    print(f"embed {lang}: dim={len(v[0])} parafrase={cos(v[0],v[1]):.3f} nao_relacionado={cos(v[0],v[2]):.3f}")
