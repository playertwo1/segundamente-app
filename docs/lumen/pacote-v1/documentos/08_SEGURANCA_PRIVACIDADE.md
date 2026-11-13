# Privacidade, segurança e conformidade
## Uso profissional e dados do banco
O MVP é de trabalho, mas **não existe autorização presumida** para sincronizar dados de clientes, contas, reuniões bancárias, prints internos, dados pessoais ou planilhas corporativas para contas pessoais ou modelos externos. Piloto deve usar conteúdo sintético ou dados explicitamente liberados pela instituição. Avaliar LGPD, políticas de dispositivos, retenção, logs e fornecedores antes de qualquer dado real.

## Controles mínimos
- Criptografia em trânsito (TLS), armazenamento local conforme proteção do SO, credenciais em Keychain/Keystore/Credential Manager apropriado.
- Tokens por aparelho, pareamento autenticado, revogação, expiração e logout completo.
- Permissão explícita para câmera/microfone; nenhuma captação silenciosa.
- Logs estruturados sem corpo de notas, credenciais, transcrições ou chaves.
- Política de retenção e exportação; apagar memória/preferências por decisão do usuário.
- Backup criptografado ou protegido e restauração testada; documentar modelo de ameaça.
- Sync com autenticação e isolamento de workspace, sem assumir segurança de rede doméstica.
- E2EE é uma decisão de engenharia futura/avaliável; não usar a expressão na UI sem implementação verificada.

## Dependências e licenças
- Segunda Mente: fork de Memex, GPL-3.0 no repositório, ver `LICENSE` e `PROJECT.md`.
- Coucou: código MIT, mas a identidade Mochi, nome, gráficos e sons são protegidos separadamente; estudar `LICENSE`, `README.md` e avisos de marca. Cumprir atribuições e revisar compatibilidade quando distribuir código.
- Revisar cada crate/package importado, SBOM, licenças, modelos de fala e distribuição Windows.

## Falhas perigosas
- Reminders não disparar após reboot/Doze.
- Persona gerar tarefa definitiva sem confirmação.
- Lumen gravar áudio sem indicator claro.
- Duplicação após replay de sync.
- Falsa certeza de “sincronizado” quando apenas salvo localmente.
- Documentos profissionais enviados automaticamente ao provedor errado.

## Política de ações
Leitura de notas e consultas locais podem ser realizadas com permissões padrão; mudar horários, apagar dados, enviar e-mails ou alterar a agenda de terceiros exige confirmação apropriada. Não enviar mensagens automaticamente.
