"""Harder cases: strong phone-photo conditions. Appends to <out>/truth.json."""
import json
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
F = {'arial': 'C:/Windows/Fonts/arial.ttf', 'times': 'C:/Windows/Fonts/times.ttf', 'courier': 'C:/Windows/Fonts/cour.ttf'}
exec(open(os.path.join(os.path.dirname(__file__), 'texts.py'), encoding='utf-8').read())
rnd = random.Random(11)


def page(lines, font, size, cols=1, bg=255, w=1654, h=2339):
    f = ImageFont.truetype(F[font], size)
    img = Image.new('RGB', (w, h), (bg, bg, bg) if isinstance(bg, int) else bg)
    d = ImageDraw.Draw(img)
    if cols == 2:
        half = (len(lines) + 1) // 2
        groups = [(lines[:half], 100), (lines[half:], 880)]
    else:
        groups = [(lines, 130)]
    for ls, x in groups:
        y = 160
        for line in ls:
            if cols == 2:
                line = line[:38]
            d.text((x, y), line, font=f, fill=(20, 20, 20))
            y += int(size * 1.9)
    return img


def persp(img, k, rnd):
    w, h = img.size
    dx = int(w * k)
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    dst = [(dx, int(h * 0.02)), (w - dx // 3, 0), (w, h), (0, int(h * 0.97))]
    # find coefficients mapping output->input
    A = []
    for (X, Y), (x, y) in zip(dst, src):
        A += [[X, Y, 1, 0, 0, 0, -x * X, -x * Y], [0, 0, 0, X, Y, 1, -y * X, -y * Y]]
    b = [c for p in src for c in p]
    co = np.linalg.solve(np.array(A, float), np.array(b, float))
    return img.transform((w, h), Image.PERSPECTIVE, co, Image.BICUBIC, fillcolor=(90, 70, 50))


def shade(img, strength, noise, blur, rnd):
    a = np.asarray(img, dtype=np.float32)
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    light = 1 - strength * ((xx / w) * 0.7 + (yy / h) * 0.5)
    a = a * light[..., None] + np.random.default_rng(rnd.randint(0, 9999)).normal(0, noise, a.shape)
    return Image.fromarray(np.clip(a, 0, 255).astype('uint8')).filter(ImageFilter.GaussianBlur(blur))


cases = {}
cases['prosa_arial__perspectiva'] = (shade(persp(page(PROSE, 'arial', 34), 0.07, rnd).rotate(4, fillcolor=(90, 70, 50)), 0.25, 8, 1.2, rnd).resize((827, 1170)), PROSE)
cases['denso_arial__baixaluz'] = (shade(page(DENSE, 'arial', 24), 0.55, 18, 1.8, rnd).resize((1100, 1558)), DENSE)
cases['tabela_courier__fundoamarelo'] = (shade(page(TABLE, 'courier', 30, bg=(250, 238, 150)), 0.1, 6, 1.0, rnd), TABLE)
cases['prosa_times__girado90'] = (page(PROSE, 'times', 36).rotate(90, expand=True), PROSE)
cases['denso_times__duascolunas'] = (page(DENSE, 'times', 30, cols=2), [l[:38] for l in DENSE[:4]] + [l[:38] for l in DENSE[4:]])
cases['prosa_arial__foto12mp'] = (shade(persp(page(PROSE, 'arial', 34).resize((1400, 1980)).copy(), 0.04, rnd), 0.2, 6, 1.0, rnd).resize((3000, 4000)).convert('RGB'), PROSE)

truth = json.load(open(os.path.join(OUT, 'truth.json'), encoding='utf-8'))
for k, (img, lines) in cases.items():
    img.convert('RGB').save(os.path.join(OUT, k + '.jpg'), quality=65)
    truth[k] = ' '.join(lines)
json.dump(truth, open(os.path.join(OUT, 'truth.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(len(cases), 'hard images')
