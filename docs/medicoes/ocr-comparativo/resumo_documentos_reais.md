# OCR em documentos reais de teste, S25 (2026-11-08)

39 imagens: 26 páginas de 4 PDFs escaneados, 8 páginas de PDFs digitais (gabarito = camada de texto), 3 fotos (2 sem texto, 1 cheque manuscrito). Páginas renderizadas em 1700 px. Sem o texto dos documentos neste arquivo.

| Motor | s/página | 1ª chamada | CPU 39 pág. | Energia CPU (mAh, modelo do Android) | Pico de memória | Páginas vazias (de 26) | Âncoras certas (de 43) | CER digitais | Peso novo no APK (arm64) |
|---|---|---|---|---|---|---|---|---|---|
| ML Kit | 0,23 | 0,27 s | 16 s | 1,7 | 469 MB | 0 | 41 | 6,9% (3,8% com linhas reagrupadas) | ≈13 MB (já no app) |
| Tesseract fast | 1,66 | 0,65 s | 219 s | 11,9 | 465 MB | 0 | 43 | 4,5% | ≈10 MB |
| Tesseract best | 3,23 | 1,1 s | 460 s | 18,2 | 477 MB | 0 | 42 | 4,3% | ≈16 MB |
| PaddleOCR padrão | 5,53 | 3,4 s | 690 s | n/d | 1248 MB | 11 | 31 | 3,9% | ≈55 MB |
| PaddleOCR lote 1 | 7,30 | n/d | 1084 s | 33,8 | 751 MB | 0 | 43 | 3,9% | ≈55 MB |
| PaddleOCR 1536 px + lote 1 | 6,88 | n/d | 1015 s | n/d | 1059 MB | 0 | 43 | 3,8% | ≈55 MB |
| PaddleOCR 1536 px | 10,35 | n/d | 1229 s | n/d | 1764 MB | 3 | 37 | 15,0% | ≈55 MB |
| PaddleOCR página em 2 metades | 8,96 | n/d | 1010 s | n/d | 1541 MB | 8 | 31 | 18,4% | ≈55 MB |

Linha de base do app vazio: 0,17 mAh e 0,5 s de CPU. Energia = estimativa do Android (`dumpsys battery unplug` + `batterystats`), só CPU, sem tela.
Fotos: gatos sem texto, todos devolveram vazio (Tesseract inventou 9 caracteres em uma). Cheque manuscrito: ML Kit 221 caracteres, PaddleOCR 180, Tesseract 11.
