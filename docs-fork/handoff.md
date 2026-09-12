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
| 5 — Relatórios | 🔄 fundação pronta · 3 telas de 6 · **destravada** |
| 4 · 6 · 3 | pendentes |

Branch: `feature/port-coraxy`.

**Onda 5 em detalhe.** A decisão de atribuição foi tomada e implementada (ver seção 5), e a
fatia 0 (fundação) está fechada:

| | Commit | O que é |
|---|---|---|
| 0a | `66b004a759` | Cockpit devolve 422 sem janela; "encerradas" passa a ser de quem resolveu |
| 0b | `9298d63a95` | `Reports::ConversationOwnershipFinder` + índice em `reporting_events` |
| 0c | `f0157a85b4` | Front do cockpit vira molde; `api/reports.js` volta a ser igual ao upstream |
| 1 | `db76829641` | Tela **Robô e humano** (`/reports/ownership`), primeiro consumidor |
| — | `d5f13751ce`, `423bcf1e51`, `f5ba73abbc` | defeitos de releitura, caminho do Captain, teto de 6 meses na janela |
| 2 | `013719dd04`, `699cfc0083`, `808af92295` | Tela **Monitoramento** (`/reports/supervisor`); recorte Todos/Humanos/IA por estado atual, não pelo classificador por resolução |
| — | `a362de8756`, `b7b1227fc8` | `ReportTile` adotado em Cockpit e Robô/humano; teste trava ausência de N+1 no Monitoramento |

**2026-09-12 — fatia 2 fechada.** Chegou pela metade, deixada por outro agente (Antigravity)
sem commitar: encanamento certo (rota, endpoint, i18n, menu), mas builder cobrindo uma fração
do escopo (6 contadores inventados, não os KPIs do produto) e com N+1 real
(`inbox.active_bot?` por conversa). Portada completa nesta sessão — decisões e débito
registrado na seção "Fatia 2" da Onda 5 em `plano-port-coraxy.md`.

**Faltam três telas:** Recebidos e Efetuados, Fila — Histórico e Motivos. A ordem e o que
cada uma precisa de especial estão no `plano-port-coraxy.md`.

**Como rodar teste aqui:** `MSYS_NO_PATHCONV=1 wsl -d Ubuntu -- bash /home/anderson/bin/cw-rspec <arquivos>`
e `.../cw-vitest <arquivos>`. **Não rode RSpec por outro caminho:** o ambiente de teste lê
`POSTGRES_DATABASE`, que no container vale `chatwoot_dev`, e a suíte truncaria o banco de
desenvolvimento. Os scripts já carregam o override.

**Revisões pendentes (fatia 1) — parcialmente resolvidas em 2026-09-12.** A pergunta sobre os
tiles está fechada: nenhuma tela usa o `ReportMetricCard` do upstream, e o `ReportTile.vue`
próprio (que já existia extraído, mas não adotado) agora está em uso no Cockpit, no Robô/
humano e no Monitoramento (commit `a362de8756`). Seguem em aberto, e valem antes da fatia 3:
o custo do classificador em volume real de produção (a revisão de banco desta sessão mediu
a query do Monitoramento, não a das fatias 0/1) e a validação de tema claro/375px do Cockpit
e do Robô/humano especificamente (a revisão de frontend desta sessão validou o
Monitoramento).

## 5. A decisão que travava a Onda 5 — resolvida em 2026-09-11

**Regra do dono do produto:** conversa em caixa com robô nasce pendente; **conversa
finalizada sem nunca ter sido aberta nem atribuída é do robô** ("nunca" é histórico, não
estado atual).

Implementada em `app/finders/reports/conversation_ownership_finder.rb`. O critério completo,
as três divergências aceitas e as duas decisões que vieram junto (sem exigir mensagem do
robô; sem listener de atribuição) estão em `plano-port-coraxy.md`, na Onda 5.

**Uma afirmação deste documento estava errada** e vale registrar, porque foi ela que fez a
decisão parecer mais difícil do que era: dizia que "se um humano abre a pendente pelo
dashboard, nenhum evento é gravado". O 4.17 grava `conversation_opened` em toda transição
para `open` (upstream desde a v4.5.0); o que falta é só o `conversation_bot_handoff`, que
exige `Current.user.is_a?(AgentBot)`. É essa gravação que dá à regra uma fonte histórica
imutável.

Continua valendo o resto do diagnóstico: `assignee_id` é estado atual, então nenhum critério
pode depender dele; e "resolvido pelo robô" tem três números diferentes no sistema
(`BotMetricsBuilder` do upstream, os outcomes do Captain e o nosso), o que exige tooltip
explicando o critério em cada tela.

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
