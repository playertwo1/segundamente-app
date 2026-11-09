# Compara modelos de voz do sherpa-onnx 1.13.2 em pt: blocos de 30 s como o app, 4 threads, WER contra o Whisper large-v3.
import glob, json, os, re, sys, time, unicodedata
import soundfile as sf, sherpa_onnx as so
T = 4
def f(d, pat): return glob.glob(f"models/{d}/{pat}")[0]
def build(name):
    if name == "fastconformer-pt":
        d = "sherpa-onnx-nemo-stt_pt_fastconformer_hybrid_large_pc-int8"
        return d, so.OfflineRecognizer.from_nemo_ctc(model=f(d, "model*.onnx"), tokens=f(d, "tokens.txt"), num_threads=T)
    if name == "parakeet-v3":
        d = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
        return d, so.OfflineRecognizer.from_transducer(encoder=f(d, "encoder*.onnx"), decoder=f(d, "decoder*.onnx"), joiner=f(d, "joiner*.onnx"),
                                                       tokens=f(d, "tokens.txt"), num_threads=T, model_type="nemo_transducer")
    if name == "omnilingual-300m":
        d = "sherpa-onnx-omnilingual-asr-1600-languages-300M-ctc-v2-int8-2026-02-05"
        return d, so.OfflineRecognizer.from_omnilingual_asr_ctc(model=f(d, "model*.onnx"), tokens=f(d, "tokens.txt"), num_threads=T)
    if name == "cohere":
        d = "sherpa-onnx-cohere-transcribe-14-lang-int8-2026-04-01"
        return d, so.OfflineRecognizer.from_cohere_transcribe(encoder=f(d, "encoder*.onnx"), decoder=f(d, "decoder*.onnx"), tokens=f(d, "tokens.txt"), num_threads=T, language="pt")
    m = name.replace("whisper-", ""); d = f"sherpa-onnx-whisper-{m}"
    return d, so.OfflineRecognizer.from_whisper(encoder=f(d, f"{m}-encoder.int8.onnx"), decoder=f(d, f"{m}-decoder.int8.onnx"), tokens=f(d, f"{m}-tokens.txt"),
                                                language="pt", task="transcribe", num_threads=T)
def run(r, wav):
    s, _ = sf.read(wav, dtype="float32"); out = []; worst = 0
    for o in range(0, len(s), 16000*30):
        if len(s) - o < 1600: continue
        st = r.create_stream(); st.accept_waveform(16000, s[o:o+16000*30]); t = time.time(); r.decode_stream(st); worst = max(worst, time.time()-t)
        out.append(st.result.text.strip())
    return " ".join(out), len(s)/16000, worst
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
names, ref = sys.argv[1].split(","), "whisper-large-v3"
wavs = sorted(glob.glob("audio/*.wav")); cache = "out_all.json"
res = json.load(open(cache, encoding="utf-8")) if os.path.exists(cache) else {}
for n in [ref] + names:
    if all(f"{n}|{w}" in res for w in wavs): continue
    t = time.time(); d, r = build(n); load = time.time()-t
    size = sum(os.path.getsize(x) for x in glob.glob(f"models/{d}/*.onnx"))/2**20
    for w in wavs:
        t = time.time(); txt, dur, worst = run(r, w); res[f"{n}|{w}"] = [txt, (time.time()-t)/dur, worst, size, load]
    json.dump(res, open(cache, "w", encoding="utf-8"), ensure_ascii=False, indent=1); del r
for n in names:
    ws = [wer(res[f"{ref}|{w}"][0], res[f"{n}|{w}"][0]) for w in wavs]; v = [res[f"{n}|{w}"] for w in wavs]
    print(f"{n:18s} disco {v[0][3]:5.0f} MB | carga {v[0][4]:4.1f}s | WER vs large-v3 " + " ".join(f"{x:4.0%}" for x in ws)
          + f" | media {sum(ws)/len(ws):4.0%} | RTF {sum(x[1] for x in v)/len(v):.2f} | pior bloco 30s {max(x[2] for x in v):.1f}s")
