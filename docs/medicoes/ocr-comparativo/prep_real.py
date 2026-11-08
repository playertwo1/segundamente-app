"""Renders the real PDFs like the app does (1700 px on the longest side), converts
the photos, and writes truth only where the PDF has a text layer."""
import glob
import json
import os
import re
import subprocess

import pymupdf
from PIL import Image

OUT = 'real_png'
os.makedirs(OUT, exist_ok=True)
for f in glob.glob(OUT + '/*'):
    os.remove(f)

names = {
    'CamScanner': 'camscanner',
    'E-book': 'ebook',
    'Exame_Saint': 'exame',
    'consorcio': 'consorcio',
    'giro500v2': 'giro500',
    'pobj2309': 'pobj',
}
truth = {}
for f in sorted(glob.glob('real/pdf/*.pdf')):
    short = next(v for k, v in names.items() if os.path.basename(f).startswith(k))
    doc = pymupdf.open(f)
    pages = range(len(doc))
    if short == 'ebook':  # 19 pages: the ones with most text, 6 of them
        pages = sorted(sorted(pages, key=lambda i: -len(doc[i].get_text()))[:6])
    for i in pages:
        page = doc[i]
        scale = 1700 / max(page.rect.width, page.rect.height)
        pix = page.get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=False)
        key = f'{short}__p{i + 1:02d}'
        pix.save(f'{OUT}/{key}.png')
        text = page.get_text().strip()
        if short in ('ebook', 'exame') and len(text) > 200:
            truth[key] = re.sub(r'\s+', ' ', text)

for i, f in enumerate(sorted(glob.glob('real/foto/*'))):
    key = f'foto{i + 1}__{os.path.splitext(os.path.basename(f))[0][-6:]}'
    if f.lower().endswith('.heic'):
        subprocess.run(['magick', f, '-auto-orient', '-quality', '92', f'{OUT}/{key}.jpg'], check=True)
    else:
        Image.open(f).convert('RGB').save(f'{OUT}/{key}.jpg', quality=92)

json.dump(truth, open('real_truth.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(len(os.listdir(OUT)), 'images;', len(truth), 'with text-layer truth')
for f in sorted(os.listdir(OUT)):
    if f.startswith('foto'):
        print(f, Image.open(f'{OUT}/{f}').size)
