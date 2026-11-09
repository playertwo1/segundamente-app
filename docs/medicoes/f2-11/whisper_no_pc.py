# Whisper (sherpa-onnx 1.13.2) no PC: transcreve WAVs 16 kHz em blocos de 30 s, como o app; mede RTF e WER contra uma referencia.
import json, re, sys, time, unicodedata, glob, os
import numpy as np, soundfile as sf, sherpa_onnx
def rec(d, m, threads):
    return sherpa_onnx.OfflineRecognizer.from_whisper(encoder=f"{d}/{m}-encoder.int8.onnx", decoder=f"{d}/{m}-decoder.int8.onnx",
        tokens=f"{d}/{m}-tokens.txt", language="pt", task="transcribe", num_threads=threads)
def run(r, wav):
    s, sr = sf.read(wav, dtype="float32"); out = []
    for o in range(0, len(s), 16000*30):
        if len(s) - o < 1600: continue  # igual ao app: pedaco < 0,1 s derruba o decodificador
        st = r.create_stream(); st.accept_waveform(16000, s[o:o+16000*30]); r.decode_stream(st); out.append(st.result.text.strip())
    return " ".join(out), len(s)/16000
def words(t):
    t = unicodedata.normalize("NFD", t.lower()); t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9 ]", " ", t).split()
def wer(ref, hyp):
    r, h = words(ref), words(hyp); d = list(range(len(h)+1))
    for i in range(1, len(r)+1):
        p, d[0] = d[0], i
        for j in range(1, len(h)+1):
            p, d[j] = d[j], min(d[j]+1, d[j-1]+1, p+(r[i-1] != h[j-1]))
    return d[len(h)]/max(len(r), 1)
models, ref_model, threads = sys.argv[1].split(","), sys.argv[2], int(sys.argv[3])
wavs = sorted(glob.glob("audio/*.wav")); res = {}
for m in models + [ref_model]:
    t = time.time(); r = rec(f"models/sherpa-onnx-whisper-{m}", m, threads); load = time.time()-t
    for w in wavs:
        t = time.time(); txt, dur = run(r, w); res[(m, w)] = (txt, (time.time()-t)/dur)
    size = sum(os.path.getsize(f) for f in glob.glob(f"models/sherpa-onnx-whisper-{m}/*int8.onnx"))/2**20
    print(f"{m}: int8 {size:.0f} MB, carga {load:.1f}s", flush=True)
json.dump({f"{m}|{os.path.basename(w)}": v for (m, w), v in res.items()}, open(f"out_{threads}t.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
for m in models:
    ws = [wer(res[(ref_model, w)][0], res[(m, w)][0]) for w in wavs]; rt = [res[(m, w)][1] for w in wavs]
    print(f"{m}: WER vs {ref_model} " + " ".join(f"{x:.0%}" for x in ws) + f" | media {sum(ws)/len(ws):.0%} | RTF {sum(rt)/len(rt):.2f}")
print(f"{ref_model}: RTF {sum(res[(ref_model,w)][1] for w in wavs)/len(wavs):.2f}")
