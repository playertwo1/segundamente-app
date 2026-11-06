"""Confere os PDFs gerados: texto por página igual ao esperado e imagem só no c39.
Uso (precisa de `pip install pypdf`, só para conferir, não é dependência do app):
  python conferir_pdfs.py test/fixtures/f9"""
import json, sys
from pypdf import PdfReader
d = sys.argv[1]
exp = json.load(open(f"{d}/paginas_esperadas.json", encoding="utf-8"))
ok = True
for cid, pages in exp.items():
    r = PdfReader(f"{d}/{cid}.pdf")
    got = [(p.extract_text() or "").strip() for p in r.pages]
    want = [(pages[k] or "") for k in sorted(pages)]
    imgs = sum(len(p.images) for p in r.pages)
    good = got == want and (imgs == 1) == (cid == "c39")
    ok &= good
    print(cid, len(r.pages), "paginas", "OK" if good else f"FALHOU {got} {imgs}")
sys.exit(0 if ok else 1)
