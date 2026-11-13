# Arquitetura de referência | app único, interfaces acopladas por contrato
## Topologia
```
Windows (pacote único)
  Lumen: Tauri/Rust (shell flutuante, hotkey, ditado, tray)
      -> IPC/localhost autenticado (somente comandos tipados)
  Segunda Mente Windows: Flutter (UI completa)
      -> Repositórios de domínio + SQLite/Drift + arquivos originais
      -> Outbox local de alterações -> serviço de sincronização persistente
Android (Segunda Mente Flutter)
      -> Mesmo modelo de domínio e repositórios locais
      -> Agendador nativo Android
      -> Outbox local de alterações <-> serviço persistente de sync
Núcleo lógico: mesma memória, personas, IDs, notas, tarefas e comentários.
```

## Por que não basta o relay do Coucou?
O `docs/RELAY_LINK.md` do Coucou descreve encaminhamento stateless E2EE entre PC e celular, com frames descartados quando o outro par está offline. É útil para transporte e pareamento, mas **não** garante dados duráveis nem entrega ao Android quando PC está desligado. Para o requisito do usuário, é necessária uma fila/armazenamento intermediário persistente (ou sync já concluído antes do desligamento) com entrega quando cada cliente conectar. Não confundir transporte com sync.

## Estratégia de implementação
1. Android e Windows têm bancos locais de domínio e arquivos originais; o app opera offline.
2. Toda alteração produz evento na outbox atômica com persistência e `mutation_id` único.
3. Servidor armazena alterações criptografadas em trânsito, com autenticação e mínimo de dados. Criptografia fim a fim pode ser investigada; prometer E2EE só após modelo de chaves e recuperação aprovado.
4. Cliente recebe alterações, valida versão e aplica uma vez; agenda/cancela notificações locais.
5. Conflitos nunca são silenciosamente descartados: detectar concorrência e apresentar comparação quando semântica não permitir mesclagem segura.
6. Anexos têm hash SHA256, metadados, upload em partes e disponibilidade visível; conteúdo só carrega sob solicitação ou política definida.
7. Relógio do SO aciona notificação. IA apenas interpreta e sugere prazos; motor determinístico decide ocorrências.

## API local do Lumen (contrato conceitual)
- `POST /v1/capture/text` cria nota em Segunda Mente, devolve `note_id` e `sync_state`.
- `POST /v1/capture/voice` recebe transcrição/processo de ditado e `capture_id` deduplicável.
- `POST /v1/tasks/draft` propõe task sem confirmar prazo ambíguo.
- `POST /v1/app/open` navega para nota, comentário, tarefa ou chat selecionado.
- `GET /v1/notifications/next` retorna lembretes próximos **já persistidos**, não invenções da IA.
- `GET /v1/status` estado de núcleo e sincronização.
Todos os endpoints exigem segredo de sessão via IPC/pipe/localhost restrito; ACL do SO; rate-limit; defesa contra CSRF, injeção e apps locais maliciosos. O URL/porta exatos são ADR pendente.

## Integração de personas
Mecanismo de personas é autoridade única no núcleo da Segunda Mente. Comentário tem `persona_id`, `thread_id`, `note_id`, `source_revision`, `idempotency_key` e `origin_device`. Reabrir nota ou sincronizar não chama modelo automaticamente. Política explícita define quando cada persona comenta; deve haver botão para pedir análise e parâmetros opcionais para sugestão automática com aprovação.

## Desktop
Auditar plugins Flutter: `workmanager`, `quick_actions`, `health`, `pedometer`, `google_mlkit`, `record`, `image_picker`, `camera`, `local_auth`, storage/notifications, ML local. Adaptadores de plataforma mantêm interfaces de domínio. Build Windows do Flutter não implica que todos os plugins são compatíveis.

## Desacoplamento e persistência
O Lumen nunca abre o SQLite/Drift/JSON da Segunda Mente diretamente. A UI principal e o Lumen não escrevem nos mesmos arquivos sem coordenação. Lumen pode ter cache efêmero de estado de exibição, não uma segunda memória durável.

## Eventos exemplares
`NoteCreated`, `NoteEdited`, `TaskDrafted`, `TaskConfirmed`, `TaskCompleted`, `ReminderScheduled`, `ReminderSnoozed`, `PersonaCommentAdded`, `PreferenceConfirmed`, `DeviceRevoked`. Todos os eventos com UUID, origem, versão, timestamps UTC, fuso original e metadados mínimos.
