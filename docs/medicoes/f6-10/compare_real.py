"""F6-10: compara e5-small int8 e MiniLM-L12 int8 com as notas reais do dono.

Roda 100% local, sem rede (nada é baixado nem enviado). Uso:
  python compare_real.py <pasta_de_notas> <consultas.json> <pasta_dos_modelos>
- pasta_de_notas: arquivos .md/.txt, um por nota; o nome do arquivo é o id.
- consultas.json: [{"q": "texto", "gold": "nota.md"}, ...]; gold null = fora do tema.
- pasta_dos_modelos: a mesma `m/` do bench.py (e5 model_int8.onnx; MiniLM model_qint8_arm64.onnx).
Imprime só números (acerto@1/@3, MRR, corte de nota). Não grava texto das notas.
"""
import json, os, sys, numpy as np, onnxruntime as ort
from tokenizers import Tokenizer

notes_dir, qfile, mdir = sys.argv[1:4]
ids = sorted(f for f in os.listdir(notes_dir) if f.endswith(('.md', '.txt')))
docs = [open(os.path.join(notes_dir, i), encoding='utf-8', errors='replace').read() for i in ids]
Q = json.load(open(qfile, encoding='utf-8'))

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

cfgs = [
    ("e5-small int8", "multilingual-e5-small/onnx/model_int8.onnx", "multilingual-e5-small/tokenizer.json", "query: ", "passage: "),
    ("MiniLM-L12 int8", "paraphrase-multilingual-MiniLM-L12-v2/onnx/model_qint8_arm64.onnx", "paraphrase-multilingual-MiniLM-L12-v2/tokenizer.json", "", ""),
]
for name, mp, tp, qp, pp in cfgs:
    emb = make(os.path.join(mdir, mp), os.path.join(mdir, tp))
    D = emb(docs, pp); QE = emb([q['q'] for q in Q], qp); S = QE @ D.T
    h1 = h3 = mrr = n = 0; good = []; offs = []
    for k, q in enumerate(Q):
        if q['gold'] is None: offs.append(S[k].max()); continue
        rank = [ids[j] for j in np.argsort(-S[k])]; pos = rank.index(q['gold']) + 1
        h1 += pos == 1; h3 += pos <= 3; mrr += 1 / pos; n += 1; good.append(S[k, ids.index(q['gold'])])
    print(f"== {name}: n={n} acerto@1={h1/n:.2f} acerto@3={h3/n:.2f} MRR={mrr/n:.2f}")
    if offs:
        thr = max(offs)
        print(f"   fora do tema: maior nota {thr:.2f} | acertos acima do corte: {np.mean([g > thr for g in good]):.0%}")
