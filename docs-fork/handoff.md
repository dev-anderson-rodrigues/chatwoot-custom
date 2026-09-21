# Handoff — estado em 2026-09-19

Documento de retomada. Leia antes de tocar em qualquer coisa: **o repositório mudou de
lugar** e o ambiente foi reconstruído.

**2026-09-17 — Onda 5 fechada e enviada ao remote.** A fatia 5 (Motivos) foi portada,
revisada pelos três especialistas e verificada na tela. Suíte de relatórios completa: 5
telas de 5. Commitado e com push feito para `origin/feature/port-coraxy`.

**2026-09-17 — Onda 6a fechada e enviada ao remote.** Favicon/manifest dinâmicos e cor de
destaque da marca (seção 4a).

**2026-09-19 — Onda 7 aberta: Campanhas de cobrança (feature nova, fora do port).** O dono
decidiu **manter e evoluir** Campanhas (a Coraxy ocultava a aba) para disparar templates de
cobrança por WhatsApp, e-mail ou outra caixa. Fatia 1 pronta e **ainda não commitada**:
WhatsApp também pelo provider 360dialog. Ver seção 4b.

Próximo passo natural: commitar a fatia 1 da Onda 7 e decidir com o dono as perguntas
abertas (e-mail em texto ou HTML, o que é "outra caixa", de onde vem o dado da cobrança).
**Antes de cobrar em volume**, fazer a "fatia 3" da Onda 7 (endurecimento: campanha trava em
`processing` se o job morrer, sem retry para 429, sem timeout) — está detalhada no plano.
Depois, a ordem do plano segue: Onda 4 (UI/UX do chat), 6b (infra/i18n), e a Onda 3 por último.

**Decisão de produto registrada (2026-09-19), ainda não implementada:** esconder "Empresas"
(Companies) do menu lateral. No produto cada empresa é uma **conta**; a entidade nativa
(PR upstream #12842) só faria sentido para filiais. Entra na Onda 6b.

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
| 5 — Relatórios | ✅ completa · 5 telas de 5 (a 6ª foi descartada com motivo) · push feito |
| 6a — Marca no super admin | ✅ completa · 2 fatias, commitadas e com push |
| 7 — Campanhas de cobrança | 🔄 feature nova · fatia 1 (WhatsApp também pelo 360dialog) pronta, ainda não commitada |
| 4 · 6b · 3 | pendentes |

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
| 3 | `6a7c66ee0e`, `1e190410f4` | Tela **Recebidos e Efetuados** (`/reports/origem`); primeiro consumidor de `customRange` em `useReportPeriod` |
| — | `157b892443`, `5e3bfa52ce`, `20556a865f` | `Intl.DateTimeFormat` com locale cru (`pt_BR`) derrubava 4 seções da tela; consultas de total/efetuado sem snapshot compartilhado podiam gerar `recebidos` negativo; índice novo para `first_message_table`; mesmo bug de locale corrigido à parte em `ResolutionTrendCard.vue` (Captain, não relacionado a esta onda) |
| 4 | `cce4ad4dd2`, `36a6b8f721` | Tela **Fila — Histórico** (`/reports/fila`); abandono vira fato histórico (`Reports::ConversationOwnershipFinder`), não `conversations.status` mutável |
| — | `48bd596d33`, `98b1a2b6d5` | `by_team`/`queue_by_team` ignoravam `params[:team_id]` (mesmo defeito corrigido de passagem em `supervisor_builder`, fatia 2, achado em produção); `event_end_time` nulo classificava abandono errado; cartão assimétrico removido de 2 das 5 seções da tela |

**2026-09-12 — fatia 2 fechada.** Chegou pela metade, deixada por outro agente (Antigravity)
sem commitar: encanamento certo (rota, endpoint, i18n, menu), mas builder cobrindo uma fração
do escopo (6 contadores inventados, não os KPIs do produto) e com N+1 real
(`inbox.active_bot?` por conversa). Portada completa nesta sessão — decisões e débito
registrado na seção "Fatia 2" da Onda 5 em `plano-port-coraxy.md`.

**2026-09-12 — fatia 3 fechada.** Recebidos e Efetuados portada completa, revisada pelos três
especialistas sobre a implementação final. Achado mais importante: a verificação visual (não
os specs, que mockam `@chatwoot/viz`) pegou um `RangeError` no `Intl.DateTimeFormat` do
gráfico de evolução diária que derrubava o render de quatro seções da tela inteiras — mesmo
bug encontrado, à parte, em `ResolutionTrendCard.vue` (feature anterior, não relacionada). A
revisão de banco também achou uma corrida real (duas consultas sem snapshot compartilhado
podiam gerar contagem negativa) e a falta de índice para o `first_message_table`, ambas
corrigidas. Detalhe completo na seção "Fatia 3" da Onda 5 em `plano-port-coraxy.md`.

**2026-09-16 — fatia 4 fechada.** Fila — Histórico portada completa, revisada pelos três
especialistas sobre a implementação final. Achado mais importante: `by_team`/
`capacity_vs_demand` ignoravam o filtro de equipe da própria tela (enumeravam a conta
inteira), e o `backend-engineering` confirmou que o mesmo defeito já existia em produção
desde a fatia 2 (`supervisor_builder#queue_by_team`) — corrigido nos dois builders no mesmo
commit. A revisão de banco achou um caso de borda real (`event_end_time` nulo classificando
abandono errado) e a de frontend, um cartão assimétrico em 2 das 5 seções sem justificativa
registrada. Detalhe completo na seção "Fatia 4" da Onda 5 em `plano-port-coraxy.md`.

**2026-09-17 — fatia 5 fechada, e com ela a Onda 5.** Motivos portada completa, revisada
pelos três especialistas sobre a implementação final. **Ainda não commitada** — está na
working tree.

Arquivos novos: `app/builders/v2/reports/motivos_builder.rb`,
`app/finders/reports/tagged_conversation_finder.rb`,
`.../reports/Motivos.vue`, `.../reports/components/motivos/` (4 componentes),
`.../composables/useMotivosReport.js`, `spec/builders/v2/reports/motivos_builder_spec.rb`.
Alterados: `conversation_ownership_finder.rb` (dois predicados novos no fim,
`handed_off_condition` e `single_resolution_condition` — o resto intocado),
`operation_reports_controller.rb`, `config/routes.rb`, `operationReports.js`,
`reports.routes.js`, `Sidebar.vue`, os 4 arquivos de i18n e o spec do controller.

Três achados que valem lembrar:

- **Bloqueante achado pela revisão de banco:** volume e resolução saíam de duas consultas sem
  snapshot compartilhado; etiquetar uma conversa no meio da requisição fazia `resolved_count`
  passar `total` e o percentual estourar 100%. Virou **uma leitura só** com `LEFT JOIN`.
- **`tags` é tabela GLOBAL** no acts_as_taggable — sem `account_id`, com índice único no nome.
  Contas diferentes compartilham a linha da etiqueta "financeiro". O isolamento vem inteiro de
  todo escopo partir de `@account.conversations`. A revisão de segurança confirmou que se
  sustenta; há spec provando. **Quem mexer em relatório por etiqueta precisa saber disso.**
- **Armadilha de seed:** `conversation.update!(status: :resolved)` num script de QA dispara o
  dispatcher real, que grava um SEGUNDO `conversation_resolved` pelo Sidekiq minutos depois —
  o relatório então via 2 resoluções e zerava o FCR. `qa_setup_motivos.rb` usa
  `update_columns` por isso. **Os seeds das fatias anteriores têm o mesmo padrão e
  provavelmente o mesmo artefato** — se um número de QA antigo parecer errado, é o primeiro
  lugar a olhar.

**Decisão de produto registrada:** motivo é escolha explícita. Sem etiqueta selecionada não há
relatório (e nenhuma consulta é feita); a tela mostra estado de configuração, não "sem dados".

**2026-09-17 — Onda 6a, fatia 1 pronta (favicon/manifest dinâmicos), ainda não commitada.**
`manifest.json` e os ícones `apple-touch-icon*` liam sempre o logo/nome do Chatwoot, hardcoded
— agora leem `LOGO_THUMBNAIL`/`INSTALLATION_NAME`/`BRAND_NAME` da config, sem restart.

Arquivo novo: `app/controllers/manifests_controller.rb` (rota pública, sem sessão — mesmo
padrão de `widgets_controller.rb`). Alterados: `config/routes.rb`, `app/views/layouts/
vueapp.html.erb`, `.rubocop.yml` (exceção nova), `spec/controllers/dashboard_controller_spec.rb`.
Novo: `spec/controllers/manifests_controller_spec.rb`. **24 arquivos PNG/JSON removidos de
`public/`** (confirmado via grep no repo inteiro que nada mais os referenciava).

Achado técnico que vale lembrar: **`config.public_file_server.enabled` roda antes do
router** — com `public/manifest.json` existindo, uma rota Rails para `/manifest.json` nunca
seria alcançada. Precisou remover o arquivo estático para a rota funcionar. Mesma lógica para
`apple-touch-icon.png`/`apple-touch-icon-precomposed.png` (convenção do Safari/iOS, path fixo
sem `<link>`).

Achado que **derrubou uma hipótese minha**: achei que `DISPLAY_MANIFEST` não tinha seed
padrão (banco de teste "limpo" devolvia nil). O `backend-engineering` achou a causa real —
`db:migrate` roda `ConfigLoader.new.process` via `db_enhancements.rake`, populando toda
config ausente com o default do YAML, em qualquer instalação real. O "banco limpo" é só como
o RSpec prepara o schema de teste (via `schema.rb`, que pula esse hook) — padrão já conhecido
no projeto, não dívida nova. **Lição: não generalizar do banco de teste para produção sem
checar o mecanismo de seed real.**

Bug real que a revisão achou (corrigido): `icon_mime_type` quebrava com query string na URL
(`logo.svg?v=2` virava mime `image/png` em vez de `svg+xml`) — comum em qualquer CDN com
cache-busting. E um edge case (corrigido): `LOGO_THUMBNAIL` vazio faria o redirect do
apple-touch-icon virar loop; agora devolve 404.

Não tocado, de propósito: o mecanismo de favicon com "badge" de notificação
(`faviconHelper.js`), que depende de 3 pares de arquivo fixo e não pode virar dinâmico sem
composição de imagem real — fora do escopo desta fatia.

Detalhe completo na seção "Fatia 1" da Onda 6a em `plano-port-coraxy.md`.

**2026-09-17 — Onda 6a, fatia 2 pronta (cor de destaque da marca), ainda não commitada.**
`manifest.json` e as meta tags `theme-color`/`msapplication-TileColor` tinham `#2781F6` fixo
— agora leem `BRAND_ACCENT_COLOR`, nova opção de marca no super admin.

Alterados: `app/models/installation_config.rb` (validação de formato hex, mesma regex que
`Portal#color` já usa), `config/installation_config.yml`, `enterprise/.../app_configs_controller.rb`,
`app/controllers/manifests_controller.rb`, `app/controllers/dashboard_controller.rb`,
`app/views/layouts/vueapp.html.erb`. Specs novos/alterados em `installation_config_spec.rb`,
`manifests_controller_spec.rb`, `dashboard_controller_spec.rb`.

Achado da revisão que vale lembrar: diferente do `LOGO_THUMBNAIL` (fatia 1), aqui o
`ManifestsController` e o `vueapp.html.erb` precisam concordar no **mesmo valor exato** de
fallback (`#2781F6`), não só na mesma lógica — imagem ausente vira array vazio, cor ausente
precisa de uma cor de verdade. O ERB agora referencia `ManifestsController::DEFAULT_ACCENT_COLOR`
em vez de repetir o literal, para não ter duas fontes de verdade divergindo em silêncio.

Verificado: busca no repo inteiro por `update_column`/`insert`/`upsert` sobre
`InstallationConfig` fora de specs não achou nada — os dois únicos caminhos de escrita (form
do super admin, seed via `ConfigLoader`) rodam validação. 29 exemplos, 0 falhas. Rubocop
limpo. Testado contra o servidor real e no navegador.

**2026-09-19 — Onda 7, fatia 1 pronta (campanha de WhatsApp também pelo 360dialog), ainda
não commitada.** O upstream só deixava disparar em massa por `whatsapp_cloud`, e o flag
`whatsapp_campaign` vinha desligado — por isso "dispara para WhatsApp" era falso na prática.

Arquivos novos, todos na camada `custom/` (sem editar upstream):
`custom/app/services/custom/whatsapp/oneoff_campaign_service.rb` (libera `default`+`whatsapp_cloud`),
`custom/app/services/custom/whatsapp/providers/base_service.rb` (motivo de falha do 360dialog),
`db/migrate/20260919000000_enable_whatsapp_campaign_for_existing_accounts.rb` (liga o flag nas
contas existentes — **roda no deploy**, e como cada empresa é uma conta isso importa),
`spec/custom/services/custom/whatsapp/providers/base_service_spec.rb`.
Alterados: `config/features.yml` (flag `enabled: true`; a edição era do dono, ainda não
commitada), `db/schema.rb` (só a linha de versão), e um teste **upstream** em
`spec/services/whatsapp/oneoff_campaign_service_spec.rb` que afirmava o comportamento antigo
(pode dar conflito em sync).

Achados que valem lembrar:

- **O `ContactDrop` expõe `custom_attribute`**, então `{{ contact.custom_attribute.valor }}`
  já funciona no template: cobrança por atributo customizado é viável hoje — mas **alguém
  precisa gravar valor/vencimento no contato** (importação, API, integração financeira). É a
  pergunta 3 do plano.
- O Enterprise (ativo) já tem **rastreio de entrega por destinatário** e tela de analytics de
  campanha WhatsApp — o que falta é bem menos do que "escrever do zero".
- O 360dialog devolve erro em formato diferente da Meta (`meta.developer_message` e lista
  `errors`); sem o override, o motivo real da falha se perdia. O segundo formato **não foi
  validado contra conta real**.
- Um revisor apontou `namespace` como bloqueante; **conferi no código e não é** (o formulário
  usa o namespace do template sincronizado). Vale lembrar de não aceitar achado sem checar.
- **Armadilha de ambiente:** `rails db:migrate` no container roda o hook do `annotate` e
  reescreve comentários de 14 models não relacionados. Reverter com `git checkout` nesses
  arquivos (conferi que eram só linhas de comentário) e manter só `db/schema.rb` (versão).
- Banco de teste: depois de uma migration nova, subir a versão em `db/schema.rb` e rodar
  `bash /home/anderson/bin/cw-testdb` (só `chatwoot_test`), senão o RSpec para com
  "Migrations are pending".

Dívida de volume (lease de campanha em `processing`, retry/backoff para 429, timeout, reenvio
na retomada) e as perguntas abertas: seção "Onda 7" de `plano-port-coraxy.md`.

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
