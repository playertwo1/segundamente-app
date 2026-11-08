# ocr_probe

App de sondagem descartável (pacote `app.segundamente.ocr_probe`) que mede motores de OCR no S25. Não faz parte do app.
Para rodar de novo, recriar `assets/tessdata/{por,porbest}.traineddata` (tessdata_fast e tessdata_best) e `assets/tessdata_config.json`,
e usar `docs/medicoes/ocr-comparativo/run_bench.py`. Build release precisa das regras de `android/app/proguard-rules.pro`
(o R8 remove classes do ONNX Runtime que o código nativo do PaddleOCR chama).
