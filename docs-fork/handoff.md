# Handoff — estado em 2026-09-10

Documento de retomada. Leia antes de tocar em qualquer coisa: **o repositório mudou de
lugar** e o ambiente foi reconstruído.

---

## 1. Onde o código vive agora

**`/home/anderson/chatwoot`, dentro da distro WSL2 Ubuntu.** Não é mais
`D:\Documetos\baixar imagem chatwoot\chatwoot`.

A cópia em `D:` continua no disco, **desatualizada**, como plano B. Ela não tem os últimos
commits. Se for descartá-la, confirme antes que a nova está boa há alguns dias.

**Por que mudou:** o Docker Desktop no Windows serve bind mount de disco Windows por 9p.
Medido: ler os 2.287 arquivos de `app/javascript` custava **30,71 s** pelo bind mount e
**0,033 s** no ext4 do WSL2 (~930x). Na prática, a resposta HTTP do Rails caiu de **14,5 s
para 0,61 s**. Era a causa da lentidão de navegação relatada pelo usuário. Detalhes na seção
"A causa raiz da lentidão do ambiente" do `plano-port-coraxy.md`.

**Como trabalhar:** abrir pelo VS Code com a extensão WSL. Comandos de shell rodam com
`wsl -d Ubuntu -- bash -lc '...'`.

## 2. Como subir o ambiente

```bash
wsl -d Ubuntu -- bash -lc 'cd /home/anderson/chatwoot && docker compose -p chatwoot-dev \
  -f docker-compose.yaml -f docker-compose.dev.local.yaml up -d'
```

A aplicação responde em `http://localhost:3000`. Login sem senha (token vale 5 min):

```bash
wsl -d Ubuntu -- bash -lc 'cd /home/anderson/chatwoot && docker compose -p chatwoot-dev \
  exec -T rails bundle exec rails runner "u=User.first; puts \"/app/login?email=#{CGI.escape(u.email)}&sso_auth_token=#{u.generate_sso_auth_token}\""'
```

Usuário semeado: `john@acme.inc`.

**Portas mudaram:** postgres `5436` e redis `6381` (eram 5434 e 6380). O Docker Desktop
mantinha reservas fantasma nas antigas mesmo sem container algum — só o reinício do
`com.docker.backend` devolve, e a reserva vazava de novo a cada `up` que falhava. Trocar a
porta foi o contorno; as novas estão em `docker-compose.dev.local.yaml` (não versionado).

## 3. O que mudou no ambiente, e o que se perdeu

- **Imagens reconstruídas.** As tags `chatwoot-rails:development` e
  `chatwoot-vite:development` apontavam para imagens de 4 meses com **Ruby 3.3.3**, enquanto
  o projeto exige **3.4.4**. Nenhuma imagem da máquina casava com o Gemfile. Reconstruídas.
- **Volumes `bundle` e `node_modules` removidos**, porque carregavam gems e dependências da
  geração antiga de imagens e mascaravam as novas. O volume do banco não foi removido.
- **O banco de desenvolvimento foi zerado** — perda real, causada por um `docker compose
  down`. O motivo de destruir dados: o container de postgres em uso guardava tudo na própria
  camada, não em volume, porque tinha sido criado antes de o override de `PGDATA` existir. O
  volume atual grava no lugar certo, então não se repete. Schema recarregado (105 tabelas),
  seeds rodados, dados de QA recriados por `qa_setup_visual.rb`.
- **`Gemfile.lock`: `BUNDLED WITH` foi de 2.5.16 para 4.0.5.** Efeito da reconstrução — é o
  bundler que a imagem nova traz. **Revisar antes de qualquer deploy**, porque afeta CI e
  produção; não foi uma decisão de produto, foi consequência.

## 4. Estado do port

| Onda | Estado |
|---|---|
| 0 — Preparação | ✅ |
| 2 — Liberar enterprise | ✅ |
| 1 — Backend | ✅ |
| 1 — Frontend (8 fatias) | ✅ feitas, revisadas e verificadas na tela |
| 5 — Relatórios | 🔄 só o Cockpit (builder + tela) · **bloqueada por decisão** |
| 4 · 6 · 3 | pendentes |

Branch: `feature/port-coraxy`. Últimos commits relevantes: `caffd3afb9` (builder do
cockpit), `4ec0ae5e87` (tela), `9b5a2759fd` (três defeitos que só a tela renderizada pegou),
`0db2cac18b` (medição do 9p).

## 5. A decisão que trava a Onda 5

**Como separar robô de humano nas métricas.** Cinco das sete peças da onda (origem,
supervisor, fila, motivos e o `bot_summary`) dependem disso e **não devem ser portadas antes
da resposta** — cada uma escolheria um critério no escuro.

O problema, medido no código: existem **três definições diferentes de "robô"** em jogo.

1. `BotMetricsBuilder` do 4.17: toda conversa em caixa com bot.
2. `origem_builder` da fonte: caixa com bot **+** sem assignee **+** sem evento de handoff.
3. `bot_summary` da fonte: conversa com evento `conversation_bot_resolved`.

E o furo concreto: o evento `conversation_bot_handoff` **só é emitido quando o próprio bot
abre a conversa** — o guarda em `conversations_controller.rb:95` exige
`Current.user.is_a?(AgentBot)`. Se um humano abre a pendente pelo dashboard, nenhum evento é
gravado. Com bot burro (que é o plano do usuário), esse é o caso comum, não a exceção:
a conversa continua contada como robô mesmo tendo sido trabalhada por humano.

Some-se que `assignee_id` é estado atual, não histórico: atribuir hoje uma conversa que o bot
resolveu em agosto muda o número de um mês fechado.

**Recomendação registrada:** ancorar em fato imutável — conversa é do robô se está em caixa
com bot **e nenhum humano jamais enviou mensagem de saída nela** (`messages` com
`message_type = outgoing` e `sender_type = 'User'`). Resolve os três casos e unifica as
definições. Custo: os números divergem da Coraxy, onde conversa tocada por humano sem
atribuição conta como IA.

## 6. Armadilhas que custaram tempo (não repita)

- **Nunca matar o Chrome do usuário.** Ele usa o navegador. Para CDP, subir instância com
  `--user-data-dir` próprio. Ver a memória `nunca-matar-o-chrome-do-usuario`.
- **Quoting atravessando Git Bash → `wsl.exe` → `bash` perde variáveis.** `$VAR` e `$(...)`
  chegam vazios; `$event` de template Vue some em `sed`. Escreva script em arquivo e execute
  o arquivo. E use `MSYS_NO_PATHCONV=1` ou o Git Bash reescreve `/mnt/c/...`.
- **Saída de tarefa em background fica vazia até o processo terminar** (buffering). Arquivo
  vazio não significa "nada aconteceu" — verifique o efeito colateral real (arquivo criado,
  container de pé), não o log.
- **O `sso_auth_token` vale 5 minutos** e a primeira compilação de rota pelo Vite podia levar
  252 s no ambiente antigo, estourando o prazo e deixando a tela parada no login **sem
  mensagem de erro**. Menos provável agora, mas o padrão é: gerar o token só depois de a rota
  estar quente.
- **`db:prepare` só carrega o schema se o banco não existir.** Com banco criado e vazio, ele
  tenta replayar as 183 migrações e quebra numa de 2023 (`ActsAsTaggableOn::Taggable::Cache`
  não existe mais). Para banco novo: `db:schema:load` e depois `db:seed`.
- **Verificação visual acha o que teste não acha.** Nesta sessão ela pegou "1 execuções" no
  plural, três defeitos de layout do cockpit e o asterisco invisível de campo obrigatório —
  nenhum deles aparecia em teste verde nem em leitura de código.
