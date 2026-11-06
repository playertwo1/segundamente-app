"""F9-03: manda os prompts do corpus F9-02 ao modelo via `codex exec` e grava as respostas.

Uso: python rodar.py prompts.json respostas.json
Só texto fictício. O Codex CLI acrescenta as próprias instruções, então é um
substituto do cliente do app (mesmo modelo, mesma conta), não o mesmo caminho.
"""
import json, subprocess, sys, tempfile, os
from concurrent.futures import ThreadPoolExecutor

prompts = json.load(open(sys.argv[1], encoding='utf-8'))
work = tempfile.mkdtemp(prefix='f903_')

def ask(p):
    out = os.path.join(work, p['id'] + '.txt')
    text = p['system'] + '\n\nSegments:\n' + p['user']
    subprocess.run(['codex', 'exec', '--skip-git-repo-check', '--sandbox', 'read-only',
                    '-C', work, '-c', 'model_reasoning_effort="low"', '-o', out, '-'],
                   input=text, text=True, encoding='utf-8', capture_output=True, timeout=300)
    return p['id'], open(out, encoding='utf-8').read() if os.path.exists(out) else ''

with ThreadPoolExecutor(4) as ex:
    done = dict(ex.map(ask, prompts))
json.dump(done, open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('respostas:', sum(bool(v) for v in done.values()), '/', len(done))
