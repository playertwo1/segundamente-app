"""Scores {image: text} results against truth.json: character error rate after
collapsing whitespace, plus word hit rate. Usage: score.py results.json [truth.json]"""
import json
import re
import sys
import unicodedata
from collections import defaultdict

import editdistance


def norm(s):
    return re.sub(r'\s+', ' ', s).strip()


def fold(s):
    return ''.join(c for c in unicodedata.normalize('NFD', s) if unicodedata.category(c) != 'Mn')


def score(results, truth):
    rows = defaultdict(list)
    for key, ref in truth.items():
        got = norm(results.get(key, {}).get('text', ''))
        ref = norm(ref)
        cer = editdistance.eval(got, ref) / max(1, len(ref))
        cer_fold = editdistance.eval(fold(got), fold(ref)) / max(1, len(ref))
        words = ref.split()
        gw = set(got.split())
        hit = sum(w in gw for w in words) / max(1, len(words))
        cond = key.split('__')[1]
        rows[cond].append((cer, hit, results.get(key, {}).get('ms', 0), cer_fold))
    out = {}
    for cond, v in rows.items():
        out[cond] = {
            'cer_%': round(100 * sum(r[0] for r in v) / len(v), 1),
            'cer_sem_acento_%': round(100 * sum(r[3] for r in v) / len(v), 1),
            'words_ok_%': round(100 * sum(r[1] for r in v) / len(v), 1),
            'ms_per_page': round(sum(r[2] for r in v) / len(v)),
        }
    return out


if __name__ == '__main__':
    res = json.load(open(sys.argv[1], encoding='utf-8'))
    tr = json.load(open(sys.argv[2] if len(sys.argv) > 2 else 'set/truth.json', encoding='utf-8'))
    for cond, m in score(res, tr).items():
        print(f'{cond:6}', m)
