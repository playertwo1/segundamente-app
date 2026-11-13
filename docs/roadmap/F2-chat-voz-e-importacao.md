> Parte do [ROADMAP](../../ROADMAP.md): regras, estados, ordem de trabalho e mapa das fases. Estado atual e próxima ação: [STATE.md](../../STATE.md).

## F2 — Chat, voz e importação

| ID | Entrega verificável | Prio | Depende de | Estado | Evidência de aceite |
|---|---|---:|---|---|---|
| F2-01 | Chat de texto com histórico persistente | P0 | F1 | DONE | Sessão relida após reinicialização do armazenamento |
| F2-02 | Conversa em turnos: fala pt-BR, transcrição e resposta; áudio de resposta é opcional no MVP | P0 | F0-05, F2-01 | IN_PROGRESS | Microfone transcreveu fala real para o campo no S25; falta concluir um turno após revisão/envio e registrar qualidade; TTS não bloqueia o MVP |
| F2-03 | Importar TXT real do Gravador Samsung por Compartilhar ou seletor, sem copiar/colar | P0 | F2-01 | IN_PROGRESS | TXT real de aproximadamente 50 min aberto no S25, relógios preservados e fluxo até o relatório conferido |
| F2-04 | Manter original imutável e guardar separadamente o texto normalizado | P1 | F2-03 | DONE | Teste confirma bytes originais inalterados |
| F2-05 | Anexar JPG/PNG e analisar com provedor com visão; avisar quando o modelo não tem visão | P0 | F1-03, F2-01 | NOT_RUN | Foto real analisada em um provedor e aviso observado em provedor sem visão |
| F2-06 | Criar sessão por texto digitado ou colado | P1 | F2-01 | DONE | Texto colado persiste como sessão; leitura de PDF para gerar relatório pertence à F9; o anexo de chat existente permanece em F2-08 |
| F2-07 | Antes de qualquer envio remoto, mostrar o conteúdo e destino e pedir confirmação explícita | P0 | F2-03, F2-08 | IN_PROGRESS | Prévia e confirmação para TXT/arquivos importados e para o relatório com modelo; cancelar não envia. Anexos do chat (foto, PDF, áudio) ficam visíveis na caixa de mensagem e só saem ao tocar em enviar, sem segunda confirmação (D-038) |
| F2-08 | Menu único de anexos no chat: câmera, galeria, TXT, PDF e áudio, sem faixa de fotos recentes | P1 | F2-01 | DONE | Menu validado no S25; TXT chega ao agente; limites de PDF são descritos separadamente |
| F2-09 | Transcrever áudio anexado/compartilhado em pt-BR; enviar ao modelo somente o texto após ação do usuário (D-011) | P0 | F2-08 | IN_PROGRESS | Áudios sintéticos de 8 s, 100 s e aproximadamente 50 min processados no S25; falta validar amostra real e limites/qualidade do serviço |
| F2-10 | Abrir chat com o anexo ao compartilhar TXT, PDF ou áudio com o app | P1 | F2-08 | IN_PROGRESS | TXT validado no S25; PDF e áudio compartilhados ainda precisam de prova |
| F2-11 | Transcrição local multilíngue, em português, com sherpa_onnx e Whisper como alternativa offline ao caminho D-011 | P1 | F2-09 | IN_PROGRESS | Comparar o mesmo áudio nos dois caminhos; medir tempo, memória e qualidade em áudio de aproximadamente 50 min no S25; registrar modelo escolhido |
| F2-12 | Importar legendas SRT/VTT preservando relógios e texto | P2 | F2-03 | IN_PROGRESS | Testes de parser para cabeçalho, numeração, intervalos e etiquetas de locutor; prévia validada no S25; parser, seletor e compartilhamento feitos, falta a prévia no aparelho |
| F2-13 | Dicionário local editável de nomes, siglas e produtos para prompts | P1 | F3-08 | DONE | Limite documentado e testado; termos aparecem na prévia de envio; nome próprio corrigido em resumo real |

**Definição do F2-11:** usar modelo Whisper multilíngue com idioma pt e tarefa de transcrição. Processar o áudio em blocos para limitar memória e preservar o tempo aproximado de cada bloco. Não inclui tradução, diarização nem timestamps por palavra. A transcrição local deve entrar na mesma prévia e confirmação do caminho remoto.

**Definição do F2-12:** aceitar SRT e VTT no seletor e no Compartilhar; remover numeração, cabeçalho WEBVTT e marcação de locutor sem apagar timestamps. Não gerar nem separar falantes.

**Portão F2:** comprovar os critérios MVP 1–3 e o consentimento para envio. O caminho de TXT e a prévia de um TXT sintético foram observados; falta o TXT real de aproximadamente 50 min, a análise real de foto, as verificações restantes de voz e os formatos de compartilhamento ainda marcados NOT_RUN. Não tratar o PDF lido pelo ChatGPT como aceite do relatório PDF da F9.
