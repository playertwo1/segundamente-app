"""F9-02: gera os 5 PDFs fictícios dos casos pdf_pagina (c36 a c40), sem dependências.
Uso: python gerar_pdfs.py <pasta_de_saida>. Texto selecionável em Helvetica/WinAnsi; c39 é só imagem (sem texto)."""
import json, os, sys

NEUTRO = "Pagina sem itens para o relatorio."
CASOS = {
    "c36": {1: "Ata da reunião de 12/09. Presentes: Ana, Rui, Paulo.",
            2: "Ficou decidido que o orçamento será revisado. Paulo envia a versão final até 20/09."},
    "c37": {1: "Contrato de prestação de serviços.", 2: NEUTRO,
            3: "A contratada deve entregar o relatório mensal até o dia 10 de cada mês."},
    "c38": {1: "Relatório trimestral.", 2: "No trimestre anterior, foram vendidas 120 unidades.", 3: NEUTRO,
            4: "Recomenda-se avaliar um novo canal de vendas."},
    "c39": {1: None},  # None = página só com imagem
    "c40": {1: NEUTRO, 2: "Prazo: 15/10.", 3: NEUTRO, 4: NEUTRO, 5: "Prazo: 15/10."},
}

def esc(s):
    b = chr(92)
    return s.encode("cp1252").decode("latin-1").replace(b, b + b).replace("(", b + "(").replace(")", b + ")")

def build(pages):
    objs = []  # corpo de cada objeto, na ordem 1..n
    n = len(pages)
    font, img = 3 + 2 * n, 4 + 2 * n
    kids = " ".join(f"{3 + 2 * i} 0 R" for i in range(n))
    objs.append("<< /Type /Catalog /Pages 2 0 R >>")
    objs.append(f"<< /Type /Pages /Kids [{kids}] /Count {n} >>")
    for i, t in enumerate(pages):
        content_id = 4 + 2 * i
        objs.append(f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents {content_id} 0 R "
                    f"/Resources << /Font << /F1 {font} 0 R >>" + (f" /XObject << /Im1 {img} 0 R >>" if t is None else "") + " >> >>")
        if t is None:
            stream = "q 400 0 0 300 100 400 cm /Im1 Do Q"
        else:
            stream = f"BT /F1 12 Tf 72 760 Td ({esc(t)}) Tj ET"
        objs.append(f"<< /Length {len(stream)} >>\nstream\n{stream}\nendstream")
    objs.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    # imagem 8x8 em tons de cinza (hex), lembra um texto escaneado; não contém texto selecionável
    pix = "".join(("30" if (x + y) % 3 == 0 else "E0") for y in range(8) for x in range(8))
    objs.append(f"<< /Type /XObject /Subtype /Image /Width 8 /Height 8 /ColorSpace /DeviceGray "
                f"/BitsPerComponent 8 /Filter /ASCIIHexDecode /Length {len(pix) + 1} >>\nstream\n{pix}>\nendstream")
    out = bytearray(b"%PDF-1.4\n")
    offs = []
    for i, body in enumerate(objs, 1):
        offs.append(len(out))
        out += f"{i} 0 obj\n".encode("latin-1") + body.encode("latin-1") + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    for o in offs:
        out += f"{o:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)

if __name__ == "__main__":
    dest = sys.argv[1]; os.makedirs(dest, exist_ok=True)
    for cid, pages in CASOS.items():
        with open(os.path.join(dest, f"{cid}.pdf"), "wb") as f:
            f.write(build([pages[k] for k in sorted(pages)]))
    json.dump({cid: {str(k): v for k, v in p.items()} for cid, p in CASOS.items()},
              open(os.path.join(dest, "paginas_esperadas.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("ok", sorted(CASOS))
