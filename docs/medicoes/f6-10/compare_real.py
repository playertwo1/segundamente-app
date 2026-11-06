"""F6-10: compara e5-small int8 e MiniLM-L12 int8 com as notas reais do dono.

Roda 100% local, sem rede (nada é baixado nem enviado). Uso:
  python compare_real.py <pasta_de_notas> <consultas.json> <pasta_dos_modelos>
- pasta_de_notas: arquivos .md/.txt, um por nota; o nome do arquivo é o id.
- consultas.json: [{"q": "texto", "gold": ["nota.txt"], "kind": "lex|par|off"}, ...]; gold null = fora do tema.
- pasta_dos_modelos: onde estão multilingual-e5-small/ e paraphrase-multilingual-MiniLM-L12-v2/ (ONNX + tokenizer.json).
Imprime só números (acerto@1/@3, MRR por tipo, corte de nota). Não grava texto das notas.
"""
import json, os, re, sqlite3, sys, numpy as np, onnxruntime as ort
from tokenizers import Tokenizer

notes_dir, qfile, mdir = sys.argv[1:4]
ids = sorted(f for f in os.listdir(notes_dir) if f.endswith(('.md', '.txt')))
docs = [open(os.path.join(notes_dir, i), encoding='utf-8', errors='replace').read() for i in ids]
Q = json.load(open(qfile, encoding='utf-8'))

def metrics(ranks):
    for kind in ('lex', 'par'):
        rs = [(q, r) for q, r in zip(Q, ranks) if q['kind'] == kind]
        pos = [min([r.index(g) + 1 for g in q['gold'] if g in r] or [99]) for q, r in rs]
        n = len(pos)
        print(f"   {kind}: n={n} acerto@1={sum(p==1 for p in pos)/n:.2f} acerto@3={sum(p<=3 for p in pos)/n:.2f} MRR={sum(1/p for p in pos if p<99)/n:.2f}")

def fts(q):
    db = sqlite3.connect(':memory:')
    db.execute("create virtual table t using fts5(id unindexed, body, tokenize='unicode61 remove_diacritics 2')")
    for i, d in zip(ids, docs): db.execute("insert into t values(?,?)", (i, d))
    toks = re.findall(r'\w+', q.lower())
    if not toks: return []
    m = ' OR '.join('"%s"' % t for t in toks)
    return [r[0] for r in db.execute("select id from t where t match ? order by bm25(t) limit 10", (m,))]

def make(path, tokp, maxlen=128):
    tok = Tokenizer.from_file(tokp); tok.enable_truncation(maxlen); tok.enable_padding()
    s = ort.InferenceSession(path, providers=['CPUExecutionProvider'])
    names = {i.name for i in s.get_inputs()}
    def emb(texts, prefix):
        e = tok.encode_batch([prefix + t for t in texts])
        ii = np.array([x.ids for x in e]); am = np.array([x.attention_mask for x in e])
        feed = {'input_ids': ii, 'attention_mask': am}
        if 'token_type_ids' in names: feed['token_type_ids'] = np.zeros_like(ii)
        h = s.run(None, feed)[0]; m = am[..., None]; v = (h * m).sum(1) / m.sum(1)
        return v / np.linalg.norm(v, axis=1, keepdims=True)
    return emb

print("== busca textual FTS5 (qualquer palavra)")
fr = [fts(q['q']) for q in Q]; metrics(fr)
print(f"   fora do tema com algum resultado: {sum(1 for q, r in zip(Q, fr) if q['kind']=='off' and r)}/{sum(q['kind']=='off' for q in Q)}")
M = "paraphrase-multilingual-MiniLM-L12-v2/onnx/"
mini = next(p for p in ("model_qint8_arm64.onnx", "model_quint8_avx2.onnx") if os.path.exists(os.path.join(mdir, M, p)))
cfgs = [
    ("e5-small int8", "multilingual-e5-small/onnx/model_int8.onnx", "multilingual-e5-small/tokenizer.json", "query: ", "passage: "),
    ("MiniLM-L12 int8", M + mini, "paraphrase-multilingual-MiniLM-L12-v2/tokenizer.json", "", ""),
]
for name, mp, tp, qp, pp in cfgs:
    emb = make(os.path.join(mdir, mp), os.path.join(mdir, tp))
    D = emb(docs, pp); QE = emb([q['q'] for q in Q], qp); S = QE @ D.T
    ranks = [[ids[j] for j in np.argsort(-S[k])] for k in range(len(Q))]
    print(f"== {name}"); metrics(ranks)
    offs = [S[k].max() for k, q in enumerate(Q) if q['kind'] == 'off']
    good = [max(S[k, ids.index(g)] for g in q['gold']) for k, q in enumerate(Q) if q['gold']]
    thr = max(offs)
    print(f"   fora do tema: maior nota {thr:.2f} | acertos acima do corte: {np.mean([g > thr for g in good]):.0%}")
