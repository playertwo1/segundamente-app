"""Synthetic pt-BR pages with known text, in three conditions: clean, scan, phone photo."""
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
FONTS = {
    'arial': 'C:/Windows/Fonts/arial.ttf',
    'times': 'C:/Windows/Fonts/times.ttf',
    'courier': 'C:/Windows/Fonts/cour.ttf',
}

PROSE = [
    'Contrato de prestação de serviços firmado em 12 de setembro de 2026.',
    'A contratada deve entregar o relatório mensal até o dia 10 de cada mês,',
    'sob pena de multa de 2,5% sobre o valor de R$ 18.450,00 por atraso.',
    'Ficou decidido que o orçamento será revisado pelo Conselho de Administração',
    'na próxima reunião ordinária, com a presença de João, Conceição e Antônio.',
    'Observação: a cláusula 7ª não se aplica às obrigações já cumpridas.',
]
TABLE = [
    'Nota fiscal nº 004521        Emissão: 03/11/2026',
    'Item   Descrição                  Qtd    Valor',
    '001    Serviço de consultoria      12    1.200,00',
    '002    Manutenção mensal            3      450,75',
    '003    Deslocamento e hospedagem    1      980,10',
    'Total geral                               2.630,85',
    'Vencimento: 20/11/2026   Pix: 11.222.333/0001-44',
]
DENSE = [
    'Art. 5º Todos são iguais perante a lei, sem distinção de qualquer natureza,',
    'garantindo-se aos brasileiros e aos estrangeiros residentes no País a',
    'inviolabilidade do direito à vida, à liberdade, à igualdade, à segurança',
    'e à propriedade, nos termos seguintes: I - homens e mulheres são iguais',
    'em direitos e obrigações; II - ninguém será obrigado a fazer ou deixar de',
    'fazer alguma coisa senão em virtude de lei; III - ninguém será submetido a',
    'tortura nem a tratamento desumano ou degradante; IV - é livre a manifestação',
    'do pensamento, sendo vedado o anonimato; V - é assegurado o direito de resposta.',
]
PAGES = {
    'prosa_arial': (PROSE, 'arial', 34),
    'prosa_times': (PROSE, 'times', 36),
    'tabela_courier': (TABLE, 'courier', 30),
    'denso_arial_pequeno': (DENSE, 'arial', 22),
}


def render(lines, font, size):
    f = ImageFont.truetype(FONTS[font], size)
    w, h = 1654, 2339  # A4 at 200 dpi
    img = Image.new('L', (w, h), 255)
    d = ImageDraw.Draw(img)
    y = 160
    for line in lines:
        d.text((130, y), line, font=f, fill=20)
        y += int(size * 1.9)
    return img


def scan(img, rnd):
    img = img.rotate(rnd.uniform(-1.2, 1.2), resample=Image.BICUBIC, fillcolor=250)
    a = np.asarray(img, dtype=np.float32)
    a += np.random.default_rng(rnd.randint(0, 9999)).normal(0, 9, a.shape)
    img = Image.fromarray(np.clip(a, 0, 255).astype('uint8')).filter(ImageFilter.GaussianBlur(0.8))
    return img


def photo(img, rnd):
    img = img.rotate(rnd.uniform(-3.5, 3.5), resample=Image.BICUBIC, fillcolor=235)
    w, h = img.size
    a = np.asarray(img, dtype=np.float32)
    yy, xx = np.mgrid[0:h, 0:w]
    light = 0.78 + 0.22 * (xx / w) * (1 - 0.4 * yy / h)  # uneven lighting
    a = a * light + np.random.default_rng(rnd.randint(0, 9999)).normal(0, 7, a.shape)
    img = Image.fromarray(np.clip(a, 0, 255).astype('uint8')).filter(ImageFilter.GaussianBlur(1.4))
    return img.resize((int(w * 0.55), int(h * 0.55)), Image.BILINEAR)


truth = {}
rnd = random.Random(7)
for name, (lines, font, size) in PAGES.items():
    clean = render(lines, font, size)
    for cond, fn in (('limpo', lambda i: i), ('scan', lambda i: scan(i, rnd)), ('foto', lambda i: photo(i, rnd))):
        key = f'{name}__{cond}'
        img = fn(clean)
        quality = {'limpo': 95, 'scan': 70, 'foto': 60}[cond]
        img.convert('RGB').save(os.path.join(OUT, key + '.jpg'), quality=quality)
        truth[key] = ' '.join(lines)
with open(os.path.join(OUT, 'truth.json'), 'w', encoding='utf-8') as f:
    json.dump(truth, f, ensure_ascii=False, indent=1)
print(len(truth), 'images')
