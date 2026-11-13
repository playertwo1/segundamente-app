# Referências verificadas | edição 12/11/2026
## Repositórios
1. Segunda Mente (repositório privado do usuário): https://github.com/playertwo1/segundamente-app
   - Arquivos consultados diretamente: `README.md`, `PROJECT.md`, `ROADMAP.md`, `AGENTS.md`, `pubspec.yaml`.
   - Fatos observados: Flutter/Android, fork Memex GPL-3.0; exportação PDF/DOCX/MD; memória F6 DONE; F9 Meeting Decoder IN_PROGRESS com `TodoService`; F10 criação nos comentários IN_PROGRESS; redesign F5V IN_PROGRESS. **Arquivos do repositório podem mudar após esta data.**
2. Memex upstream: https://github.com/memex-lab/memex
3. Coucou: https://github.com/Louis-CFM/coucou
   - `README.md`: https://github.com/Louis-CFM/coucou/blob/main/README.md
   - Windows: https://github.com/Louis-CFM/coucou/blob/main/windows/README.md
   - Tauri Windows/Cargo: https://github.com/Louis-CFM/coucou/blob/main/windows/src-tauri/Cargo.toml
   - Comunicação Android: https://github.com/Louis-CFM/coucou/blob/main/docs/ANDROID_LINK.md
   - Relay: https://github.com/Louis-CFM/coucou/blob/main/docs/RELAY_LINK.md
   - Licença: https://github.com/Louis-CFM/coucou/blob/main/LICENSE
   - Conclusão: janela flutuante, chat, atalhos e comunicação celular são referências técnicas; relay stateless não é sincronização durável.

## Documentação técnica útil para execução
- Flutter desktop: https://docs.flutter.dev/platform-integration/desktop
- Flutter deploy Windows: https://docs.flutter.dev/deployment/windows
- Tauri 2: https://v2.tauri.app/
- Android alarms: https://developer.android.com/develop/background-work/services/alarms
- Android notifications: https://developer.android.com/develop/ui/views/notifications
- Microsoft Windows app notifications: https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/
- Drift docs: https://drift.simonbinder.eu/
- RFC 5545 (recorrência iCalendar): https://www.rfc-editor.org/rfc/rfc5545

## Padrões de comparação funcional, não integrações
Samsung Reminder, Microsoft To Do, Todoist: categorização, checklists, avisos, recorrência, prioridades e views Hoje/Atrasadas. Nenhum desses precisa ser instalado nem conectado ao MVP.

## Observações sobre licença
Rever textos de licença no momento da implementação; não copiar nome, identidade visual ou sons do Coucou. Respeitar licença GPL-3.0 do projeto existente e MIT de código Coucou elegível, com atribuição. Parecer jurídico separado caso haja distribuição comercial.
