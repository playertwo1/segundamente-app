# Registro de decisões e riscos (ADR)
## Decisões consolidadas da conversa
ADR-001 | Nome: **Lumen** (sem acento) para assistente desktop; **Segunda Mente** para aplicativo completo. **NÃO Umi**.
ADR-002 | Duas experiências funcionais que trabalham juntas em um único produto; na instalação Windows Lumen abre a interface completa, sem dados/autenticação/config duplicados.
ADR-003 | As personas existentes na Segunda Mente comentam também pelo desktop e mantêm histórico e regras.
ADR-004 | Samsung Reminder é referência funcional de Todo; não haverá integração nem dependência do aplicativo da Samsung.
ADR-005 | Android independente do notebook para lembretes locais e notas previamente sincronizadas.
ADR-006 | Sincronização deve ser possível entre redes e com dispositivo desligado, exigindo persistência de mudanças remotas e entrega posterior.
ADR-007 | Aprendizado é memória/preferências estruturadas, revisáveis, com confirmação; não é fine-tuning automático.
ADR-008 | MVP escopo inicial só Trabalho; Pessoal depois, isolado.
ADR-009 | E-mail, automação Windows extensa, geolocalização e demais recursos do Coucou ficam pós-MVP.
ADR-010 | Motor de IA interpreta; o domínio calcula, confirma, agenda e persiste; o sistema operacional notifica.

## Decisões técnicas pendentes (devem ser prototipadas em F0)
T-001 escolher sync remoto persistente (serviço próprio, backend gerenciado ou outra alternativa), custos, criptografia, conflito, backup.
T-002 escolher manter UI Flutter Windows com microprocesso Tauri Lumen ou abordagem mais simples sob mesmo instalador.
T-003 escolher migração `TodoService` / `todo.json` sem quebra do domínio existente.
T-004 avaliar reconhecimento de voz offline Windows, licenças dos modelos e fallback.
T-005 definir regras de disparo automático de personas e deduplicação.
T-006 decidir se persona auto-comenta no momento do registro ou só mediante comando/critério já configurado.

## Riscos classificados
| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Drift entre mobile/desktop | Alta | Crítico | Sync delta testado, IDs imutáveis, outbox e tombstones |
| Alarmes em segundo plano Android | Média | Crítico | Teste físico Doze/reboot/permissões e scheduler nativo |
| Plugin Flutter sem Windows | Alta | Alto | Matriz F0, adapters, feature flags |
| Duas pilhas Flutter/Tauri | Média | Alto | Tauri apenas shell; IPC tipado; medir RAM/CPU |
| Confidencialidade bancária | Alta | Crítico | Sintético até autorização, isolamento e políticas |
| Licença/branding de Coucou | Média | Alto | MIT attribution, IP original, auditoria de assets |
| Escopo excessivo | Alta | Alto | Gates P0 e pós-MVP estrito |
| Comentário IA duplicado | Média | Alto | Idempotency keys e fonte/revisão |
