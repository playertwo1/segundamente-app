# Registro da conversa — decisões consolidadas (12/11/2026)
**Nota de fidelidade:** este documento é uma reconstrução editorial da conversa atual com citações literais de mensagens do usuário apresentadas no contexto, não uma transcrição integral linha a linha de todas as respostas do assistente. A exportação literal completa do chat não foi disponibilizada para montagem do pacote.

## 1. Origem: duas experiências integradas
O usuário queria aproveitar o Coucou como base para a parte desktop: personagem na área de trabalho, abertura de conversa, botão de ditado, relay celular e e-mail. A arquitetura evoluiu até eliminar a ideia de “app companheiro” independente. A Segunda Mente segue como produto principal e o Lumen como experiência compacta do mesmo produto.

**Usuário:** “E eu queria adicionar tambem a ideia do coucou nisso tambem nao as vezes usar ele mas ele como uma base para essa parte do computsdor, porque ele ja fica na área de trabalho, ja consigo abrir conversa com ele, com um botão consigo ditar notas, ele js tem um sistema de relay com o celular, além de conectar com o email”

**Usuário:** “Então assim, não vai ter duas ferramentas separadas. São duas ferramentas que tem que andar junto”

## 2. Nome e correção de entendimento
Primeiro houve proposta “Lume”; usuário gostou de “Lúmen”, mas corrigiu para “Lumen sem acento”. Em seguida houve confusão com o nome Umi; usuário corrigiu explicitamente e manteve Segunda Mente + Lumen.

**Usuário:** “Gostei de Lúmen”
**Usuário:** “Lumen sem acento”
**Usuário:** “Lumen nao umi, mas a ideia é essa e quando eu fizer a anotação as personas que eu ja fiz no segudsmente tambem vão poder comentar no desktop”

**Decisão:** Lumen é nome do personagem/experiência compacta no Windows, e Segunda Mente permanece nome do aplicativo completo.

## 3. Mesmo sistema de personas e documentos
Personas já criadas na Segunda Mente devem analisar/comentar anotações no desktop. Ao clicar no personagem, abre toda a Segunda Mente, contextualizada à nota atual. Comentários/histórico permanecem no mesmo núcleo e acessíveis em Android/Windows. Exportações já existentes PDF/DOCX/MD serão mantidas.

## 4. Proatividade, lembretes e aprendizado
O usuário explicitou que Lumen e Segunda Mente devem aprender com suas preferências, acompanhando compromissos e o que precisa fazer.

**Usuário:** “Sim e tambem o Lumen tem que me lembrar dos compromissos das minhas anotações, do que devo fazer e ir aprendendo comigo tanto o Lumen e o segunda mente”

**Usuário:** “Por exemplo, pois eu marquei uma reunião amanhã às oito e meia da manhã. Então ele tem que me lembrar amanhã cedo às oito e dez. Olha Rafael, você tem uma reunião com Juliana daqui a vinte minutos”

**Decisão:** IA pode interpretar e sugerir estrutura; sistema determinístico deve agendar alertas no SO, com antecedência escolhida e confirmação de dados ambíguos.

## 5. Android autônomo e Samsung Reminder como referência
**Usuário:** “Sim e ele deve funcionar tanto no computador quando no celular pois posso estar sem o notebook perto mas o celular na mao, e a ideia do remiders wue precisamos.pegar”

**Usuário:** “O samsung remiderfs basicamente é um todo list como tem varios por ai so temos que fazer ele no segundamente de forma robusta”
**Usuário:** “Que hoje nao tem”

**Decisão:** fazer um Todo robusto dentro da Segunda Mente, inspirado na categoria de produtos Reminder/To Do, com tarefas, listas, recorrência, prioridades, alertas, filtros e sync. **Não** integrar Samsung Reminder nem criar outro aplicativo. O Todo atual é básico e precisa de evolução.

## 6. Solicitação de entrega
**Usuário:** “Ta acho que esta bom ja agora vamos criar um mvp, um pos mvp e um roadmap estruturado criar um arquivo zip com essa conversa e todo os documentos necessários, ate imagens de referencia se quiser e colocar no google drive”

**Decisão de documentação:** produzir PRD/MVP/Pós-MVP/Roadmap/Arquitetura/Modelo de Dados/UX/Testes/Segurança/Decisões/Prompt Codex, junto de imagens referenciais, manual DOCX e este registro.

## 7. Restrições recuperadas da discussão
- MVP inicialmente apenas Trabalho.
- Segunda Mente é projeto existente (Flutter/Android), não greenfield.
- Aproveitar do Coucou o que realmente ajuda ao desktop; não absorver todos seus recursos de monitoramento de agentes.
- E-mail é oportunidade pós-MVP, após revisão de política de acesso.
- Não usar Hermes/Orbit como dependência do MVP.
- Conteúdo profissional deve respeitar políticas da empresa; dados reais só com permissão.
