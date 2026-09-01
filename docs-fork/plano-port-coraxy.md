# Plano de ação — portar customizações do `chat-coraxy` para o fork atual

> Fonte: `SiriusDevelopment-SDA/chat-coraxy` (privado) · Chatwoot **4.2.0**
> Destino: `dev-anderson-rodrigues/chatwoot-custom`, branch `develop` · Chatwoot **4.17.1**

---

## 1. Diagnóstico

### 1.1 O que existe no repositório de origem

O repo tem 2 linhas de trabalho relevantes, com **históricos independentes** (não há merge-base entre elas):

| Branch | Commits | Conteúdo |
|---|---|---|
| `main` | 20 | Import squashed do Chatwoot 4.2.0 + customizações Coraxy/MAESTRO (mai–jun/2026) |
| `ajuste-powerbi` | 13 | Import próprio já **contendo tudo da `main`** + suíte completa de relatórios (ago/2026) |
| `update-chat` | 0 | Sem commits além da `main` — ignorar |

**Conclusão: a fonte do port é `origin/ajuste-powerbi`, não `main`.**
Verificado: `git diff main origin/ajuste-powerbi` = 24 modificados + 14 novos, **zero deleções** — é superset limpo. Portar da `main` significaria perder 13 commits de relatórios e as correções de performance de agosto.

### 1.2 Tamanho do delta

Diff `v4.2.0 → origin/ajuste-powerbi`, descontando ruído (swagger, fixtures, ícones, workflows, `.lh/`):

- **~277 arquivos** de customização real
- ~189 em `app/javascript` (o grosso é UI)
- 6 migrations, 15 models, 9 controllers, 6 builders de relatório

### 1.3 O problema central: 15 versões de distância

O commit raiz da origem é um squash de 6468 arquivos — **não há base comum com o upstream utilizável para cherry-pick**. Além disso, 30 dos arquivos customizados **não existem mais** no 4.17.1.

> **Cherry-pick / merge está descartado.** O port é temático, feature a feature, usando o diff contra `v4.2.0` apenas como *referência de intenção*.

### 1.4 O que o upstream já resolveu (NÃO portar)

Esta é a economia mais importante do plano. Confirmado no 4.17.1 local:

| Customização Coraxy | Situação no 4.17.1 |
|---|---|
| Migrar para NextSidebar fixo, remover sidebar legada (commit `2a51729`) | **Feito pelo upstream.** `components-next/sidebar/` já tem Sidebar, SidebarGroup, SidebarSubGroup, ChannelLeaf, CollapsedPopover, SortMenu, atalhos de teclado |
| Badge de conversas não lidas na sidebar | **Existe**: `SidebarUnreadBadge.vue` |
| Endpoint custom `/conversations/unread_count` | **Existe upstream**: `conversations/unread_counts#index` — validar se cobre o caso antes de reimplementar |
| Filtro `unattended` no ConversationFinder | **Existe** nativo |
| Remoção do Dyte | **Feito pelo upstream** |
| `CAPTAIN_OPEN_AI_URI_BASE` (base URL custom da OpenAI) | **Existe** como `CAPTAIN_OPEN_AI_ENDPOINT`, já editável no super admin |
| Administração de marca | **Existe**: grupo `custom_branding` no super admin com 10 chaves — só está atrás do gate de plano |
| Esvaziar o `ReconcilePlanConfigService` | **Desnecessário**: com plano `enterprise` ele já retorna cedo sozinho |
| Fixes de loop de login / rotas / spinner eterno | Provavelmente corrigidos — **revalidar no 4.17.1 antes de portar** |

Ainda **não** existe upstream (confirmado): `my_teams_only`, separadores de data no MessageList, skeletons de conversa, wallpaper do chat.

### 1.5 Estado do repositório local

Working tree tem 16 arquivos modificados, mas é **ruído do gem `annotate`** (reordenação de comentários de schema) + `vite.config.ts` e `db/schema.rb`. Nada substantivo. Há também `docker-compose.local.yaml` e `docker-compose.dev.local.yaml` untracked (pendência já conhecida).

---

## 2. Estratégia

### Regra de ouro: override de Ruby mora em `custom/`

Decidido e implementado na Onda 2. O Chatwoot tem uma camada de extensão herdada do GitLab que o upstream nunca ligou: `ChatwootApp.extensions` já devolve `['enterprise', 'custom']`, e o `prepend_mod_with` carrega `Custom::` **depois** de `Enterprise::` — deixando o módulo do fork na frente dos dois na cadeia de ancestrais, com `super` caindo no Enterprise.

Faltava apenas ligar os autoload paths (`config/application.rb`, espelhando o que já existia para `enterprise/`).

| Tipo de mudança | Onde mora |
|---|---|
| Override de classe/módulo Ruby | `custom/app/...` como `Custom::<Constante>` |
| YAML de config (`features.yml`, `installation_config.yml`) | arquivo do upstream, editado direto |
| Vue / SCSS / frontend | arquivo do upstream, editado direto |

Isso não cobre tudo — mas cobre o backend, que é onde o merge com o upstream mais dói. Toda vez que der para colocar em `custom/`, colocar.

> ⚠️ Quando a camada quebra, o override **para de valer em silêncio**. Por isso existe `spec/custom/custom_extension_layer_spec.rb`, que falha alto se o `Custom::` sair da frente do `Enterprise::`.

### Demais regras

1. **Uma branch por onda**, PR por onda, revisada pelos especialistas relevantes.
2. **Um commit por feature**, com a mensagem original da Coraxy referenciada (`Ref: coraxy@<sha>`), preservando a documentação que já existe nos commits deles — as mensagens são excelentes e devem sobreviver ao port.
3. **Backend antes de frontend.** O backend é quase todo arquivo novo → conflito baixo. O frontend é onde o upstream reescreveu tudo.
4. **Na UI: reimplementar a intenção, não aplicar o patch.** Os componentes de mensagem, composer e lista foram reescritos entre 4.2 e 4.17. Copiar diff vai gerar código quebrado e difícil de manter no próximo sync com upstream.
5. **Cada onda entra com teste.** A Coraxy já escreveu specs para cores de mensagem, cadeado IA, pin_to_sidebar, MessagesLoader, LoadingState, DropdownMenu e macros — portar junto.

### Comando de referência durante o port

```bash
# clone de referência (já feito no scratchpad, ou refazer):
git clone --filter=blob:none https://github.com/SiriusDevelopment-SDA/chat-coraxy.git
cd chat-coraxy
git remote add cw <caminho-do-fork-local>
git fetch cw tag v4.2.0 --no-tags

# diff de uma feature específica:
git diff v4.2.0 origin/ajuste-powerbi -- app/models/macro.rb app/services/macros/
```

---

## 3. Ondas

### Status

| Onda | Estado |
|---|---|
| 0 — Preparação | ✅ concluída |
| 2 — Liberar enterprise | ✅ concluída e verificada |
| 1 — Backend (macros, dashboard apps, my_teams_only) | ✅ concluída e revisada |
| 1 — Frontend | 🔄 fatias 0 e 1 feitas (API + i18n) · 6 restantes |
| 4 · 5 · 6 · 3 | pendentes |

#### Fatias do frontend da Onda 1

Plano detalhado veio da revisão do `frontend-design`. Achado que muda o trabalho: o
**4.17 reescreveu o editor de macro como flow builder** (`MacroNode`, `MacroNodes`,
`MacroProperties`), então `MacroEditor.vue` e `MacroForm.vue` da fonte estão obsoletos —
as peças novas entram *dentro* dessa estrutura.

| # | Fatia | Estado |
|---|---|---|
| 0 | `api/macros.js` — inputs, executions, stats | ✅ |
| 1 | i18n (en + pt_BR) | ✅ |
| 2 | `MacroInputFieldsBuilder` dentro do `MacroForm` | ✅ |
| 3 | `MacroExecuteModal` + fusão dos dois portões em `useMacroExecution` | ✅ |
| 4 | Máscara e validação de CPF/CNPJ/telefone | ✅ |
| 5 | Lookup dinâmico com `depends_on` | |
| 6 | `MacroHistory` como aba do editor | |
| 7 | `MacrosStatsPanel` no topo da lista | |
| 8 | Dashboard apps (checkboxes + interpolação de URL) — independente | |

**Colisão da fatia 3 — resolvida.** O `useMacroExecution.js` do 4.17 já tinha um portão de
pré-execução (atributos obrigatórios quando a macro resolve a conversa). O de `input_fields`
é um segundo, no mesmo ponto de entrada. Viraram um fluxo só dentro do composable:

- `execute` devolve `null` (já despachou) ou `{ kind, ... }` dizendo qual modal abrir;
- `submitInputs` continua o fluxo e devolve no **mesmo formato**, porque preencher os campos
  pode esbarrar no portão seguinte;
- os três chamadores — lista de macros, `ReplyBox` e command bar — só roteiam pelo `kind`.

Sem isso, cada uma das três telas reimplementaria a ordem dos portões.

> **Armadilha que virou bug:** o `Dialog` emite `close` também ao fechar *depois* do
> confirm. Sem distinguir os dois casos, o `close` chegava depois do `submit` e limpava a
> execução pendente que o portão de atributos acabara de guardar — o segundo modal abria
> sem nada para submeter. O `MacroExecuteModal` marca o confirm e só emite `close` quando
> é desistência de verdade.

**Componentes a reusar** em vez de recriar: `Dialog`, `Input`, `TextArea`, `Select`,
`ComboBox` (tem `useApiResults` + `@search`, que é o caso do lookup), `PhoneNumberInput`
(substitui a máscara manual inteira), `BaseTable` + `PaginationFooter`, `Checkbox`,
`Spinner`. O `ConversationResolveAttributesModal.vue` resolve o mesmo problema do
`MacroExecuteModal` e serve de esqueleto.

**Lacuna real:** não há biblioteca de máscara nem validador de CPF/CNPJ no projeto. Vai
virar helper próprio plugado no Vuelidate — e com dígito verificador, não só contagem de
dígitos como na fonte.

**Fatia 4 — resolvida.** `brazilianDocuments.js` (helper próprio, dígito verificador +
máscara progressiva) plugado no `MacroExecuteModal` via Vuelidate; telefone usa o
`PhoneNumberInput` puro, sem máscara manual.

- **Valor submetido de CPF/CNPJ vai mascarado** (`529.982.247-25`), igual à fonte: é
  interpolado via `{{chave}}` em mensagem e em payload de webhook, e mascarado é legível e
  trivial de limpar no servidor.
- **`Input` é controlado por `:model-value`, não por `v-model`**, para o campo de
  documento: o handler de `@input` recalcula o valor mascarado e, quando o valor bruto
  digitado diverge do formatado (o agente digitou uma letra, que a máscara descarta),
  escreve `event.target.value` direto no elemento antes de gravar no modelo — senão o
  caractere descartado sobrevive na tela porque o valor formatado não mudou e o Vue não
  repinta. Caret ainda pula pro fim ao editar no meio do número — mesma limitação da fonte,
  não vale o custo de resolver nesta fatia.
- **Telefone: `role="group"` em vez de `<label for>`.** O `PhoneNumberInput` é um composto
  (botão de país + input) sem um único campo focável para o `id` do label apontar, e não
  aceita `id`/`required`/`message` como prop (a raiz dele é uma `div`, atributo solto não
  desce pro `<input>` interno). O label ganha `id` e o container do controle vira
  `role="group"` com `aria-labelledby` apontando pra ele.
- **Bug de `default_value` do telefone fechado na normalização, não no componente:** o
  watcher `immediate` do `PhoneNumberInput` faz `parsePhoneNumber(modelValue)` sem DDI; um
  default como `"11999999999"` (sem `+`) não parseia, o campo aparece vazio na tela, mas
  sem tratar isso `values[key]` continuaria com o default e o agente submeteria o valor
  antigo por baixo de um campo que parecia em branco. `open()` agora só aceita o default de
  telefone quando ele de fato parseia como número válido (`parsed?.isValid()`), senão
  começa vazio.
- **Achado que importa para a fatia 5 (lookup — também usa componente com validação
  própria): `useVuelidate()` aninhado vaza para o `$invalid` da raiz.** O `PhoneNumberInput`
  chama `useVuelidate(rules, state)` por conta própria, e o Vuelidate registra esse
  resultado no coletor do ancestral mais próximo que também use `useVuelidate` — nesse caso,
  o próprio `MacroExecuteModal`. O estado interno do filho (o DDI que o componente deriva do
  fuso horário do navegador, sem relação nenhuma com o campo declarado pela macro) entra
  *flat* no `$invalid` agregado, mesmo para um telefone opcional e nunca tocado pelo agente.
  Isso reprovava o formulário inteiro **em silêncio** — botão vivo, clique sem efeito,
  nenhuma mensagem nossa — exatamente o modo de falha do bug de `close`/`submit` da fatia 3.
  Em produção passa despercebido porque o DDI quase sempre resolve a partir do fuso do
  navegador, mas em qualquer cenário onde não resolver (inclusive a suíte de teste, que roda
  com `TZ=UTC`) o formulário trava. **Regra fixada:** `handleConfirm` nunca usa
  `v$.value.$invalid` da raiz — o portão itera `fields.value` e olha só
  `v$.value[field.key]?.$invalid`, campo a campo. `$touch()` continua na raiz (propagar pro
  filho é desejável, é o que faz o erro interno do telefone aparecer). Quem for fazer a
  fatia 5 precisa do mesmo cuidado se o controle do lookup também tiver validação própria.
  Não mexemos no `PhoneNumberInput.vue` — o raio de impacto pega o `ContactsForm.vue`, que
  tem exatamente o mesmo padrão (`useVuelidate` pai + `PhoneNumberInput` filho) e continua
  exposto ao mesmo risco. Não é para consertar agora, é para não se perder quando aparecer.

#### Verificação visual da fatia 4 — o asterisco que os 113 testes não pegaram

A suíte inteira passava, mas nenhum campo obrigatório do `MacroExecuteModal` mostrava o
asterisco vermelho no rótulo. Só apareceu olhando a tela renderizada.

**A causa, e a regra que ela ensina — vale além deste componente.** O asterisco vinha de
`:class="{ 'after:content-[\'*\'] ...': field.required }"`: uma arbitrary value do Tailwind
(`content-['*']`) escrita com aspas escapadas porque o objeto do `:class` mora dentro de um
atributo de template com aspas duplas. O escape é válido em JS/Vue — em runtime o Vue monta a
string certa e a classe aparece no `classList` do elemento — mas **o scanner estático do
Tailwind não executa o template, ele varre o arquivo cru** procurando o padrão da arbitrary
value, e não casa `\'*\'` com `'*'`. A regra nunca é gerada; a classe fica no DOM sem CSS
correspondente. Confirmado em runtime: `getComputedStyle(label, '::after').content` saía
`""` (vazio) com a classe presente no elemento. Vale para **qualquer arbitrary value com
aspas** (`content-[...]`, `before:content-[...]`, etc.), não só este caso — e todo o resto do
projeto escreve isso sem escapar porque usa atributo de classe estático
(`content-['✓']` em `NotificationCheckBox.vue` e `InboxDisplayMenu.vue`, por exemplo); este
era o único caso escapado do repositório.

**O corolário que dói: nenhum teste unitário pega isso.** jsdom não carrega CSS de verdade,
então `getComputedStyle` de um `::after` nunca reflete uma regra do Tailwind — o teste
poderia passar com a classe certa ou com uma completamente inventada, sem diferença. Só a
verificação visual pega este tipo de defeito. Correção: trocado o pseudo-elemento por um
`<span v-if="field.required" aria-hidden="true">*</span>` real — sai da dependência do
extrator do JIT e passa a ser testável de verdade (`MacroExecuteModal.spec.js` agora trava a
presença do `<span>` em campo obrigatório e a ausência em opcional).

**Achado de design system, não desta fatia:** o botão "Executar macro" desabilitado usa
`disabled:opacity-50` sobre um azul saturado (`bg-n-brand`) — funciona certo
(`disabled: true`, clique não dispara), mas em fundo escuro os 50% de opacidade não leem
como "desabilitado" a olho nu; visualmente quase se confunde com o estado ativo. Não é bug,
não vira tarefa aqui — só fica registrado para quem for mexer no design system.

##### Verificação visual neste projeto — caminho provado

**Histoire está fora de cogitação neste repo, não tente de novo sem migrar a versão.**
`histoire@0.17.15` contra `vue@3.5.12`: toda story trava na coleta com
`TypeError: resolveComponent is not a function` dentro do `_stubComponent` que o próprio
Histoire gera para o SSR de metadados — incompatibilidade de versão do Histoire com o Vue
instalado, não falta de configuração. Antes de chegar nesse erro real havia dois problemas
mascarando-o (resolvidos, mas irrelevantes sem o upgrade):
`histoire.config.ts` referenciava `setupFile: './histoire.setup.ts'` desde o commit que
introduziu o Histoire, e esse arquivo nunca existiu no histórico do repo — toda coleta
falhava silenciosamente (`e.stack` vazio ao atravessar o `Tinypool`/`worker_threads`) até
para stories triviais como `Button.story.vue`; e `postcss.config.js` fazia
`require('postcss-import')` sem a dependência declarada no `package.json` (transitiva via
`tailwindcss`, nunca linkada no topo do `node_modules` — o pnpm só expõe ali o que está
declarado). O `postcss-import` **é pré-requisito real do upstream, não só do Histoire**, e
virou commit próprio (`0e669957e5`). Já o `histoire.setup.ts` que destrava o *setup file*
ficou em disco, **não commitado**: escrito para testar a hipótese, nunca validado de fato,
porque a incompatibilidade de versão trava a coleta antes de chegar lá. Só faz sentido
revisitar se alguém for atualizar o Histoire.

**O caminho que funcionou: aplicação real em Docker + Chrome do host por CDP**
(`--headless=new --remote-debugging-port=9333`, sem puppeteer, WebSocket nativo do Node).
Detalhes que custaram rodadas inteiras:

- **`sso_auth_token` tem TTL de 5 minutos** (`SsoAuthenticatable#generate_sso_auth_token`,
  Redis com `setex`). Gerar o token numa rodada e usar noutra estoura o prazo — o sintoma é
  `POST /auth/sign_in` voltando **401** e a tela de login girando para sempre. Gere o token
  **no mesmo script que navega**, o mais perto possível da navegação.
- **`ui_settings` do usuário abre o painel e o acordeão sem clique frágil.** O
  `ContactPanel` fica fechado por padrão (`is_contact_sidebar_open`) e o acordeão de Macros
  também (`is_macro_open`) — sem setar os dois via `rails runner`
  (`User#ui_settings = (ui_settings || {}).merge(...)`), a automação precisa clicar num botão
  sem `aria-label` (só tooltip) para abrir o painel.
- **Clicar no texto "Macros" pode levar para Configurações por engano.** O mesmo texto
  existe no acordeão da conversa *e* no item do menu lateral de Configurações; um seletor por
  texto solto (`querySelectorAll('*').find(el => el.textContent === 'Macros')`) casa com
  qualquer um dos dois e pode navegar para longe da conversa sem erro nenhum. Prefira mirar
  pelo `id`/`for` dos campos do modal ou por um container mais específico.
- **Puma roda com 5 threads neste ambiente** (`config/puma.rb`, sem workers). Abas de Chrome
  acumuladas ao longo de várias rodadas de investigação — cada uma com WebSocket do
  ActionCable aberto — saturam o pool: `GET /api/v1/accounts/1/macros` que roda em 120ms
  quando a fila está livre passou a levar **~12s** com o pool ocupado, e a rota raiz chegou a
  **17s**. Sintoma na tela: acordeão preso em "Obtendo macros" sem nunca resolver. Não é bug
  do backend nem do frontend — é fila. Feche o Chrome de rodadas anteriores antes de cada
  nova tentativa, não só no final.
- **`curl http://127.0.0.1:9333` sozinho não confirma nada** se o Chrome estiver bindado só
  em `[::1]` (IPv6 loopback) — `netstat -ano` mostra o `LISTENING` real; aponte o driver para
  `http://[::1]:PORTA/` ou `http://localhost:PORTA/`.
- Digitação em campo mascarado (CPF/CNPJ) **precisa disparar o evento `input` nativo** — a
  máscara do `MacroExecuteModal` lê `event.target.value` no handler; setar `.value` via script
  sem `el.dispatchEvent(new Event('input', { bubbles: true }))` não testa nada.

> ⚠️ **`{user_token}` na URL do iframe** (fatia 8): o `Frame.vue` interpola o token de
> acesso do agente na URL do dashboard app. Ele aparece no histórico do navegador, nos logs
> do app de terceiro e possivelmente no `Referer`, e permite chamar a API do Chatwoot como
> aquele agente. **Decisão tomada: portar como está**, porque os apps em produção dependem
> dele para autenticar. Fica registrado como risco conhecido, não como descuido — se um dia
> valer fechar, o caminho é um token de escopo restrito emitido para o app.

Branch: `feature/port-coraxy`

```
97418c0  chore(macros): atualiza anotacao de indices do MacroExecution
b4f8f3b  feat(backend): flags de sidebar nos dashboard apps e filtro my_teams_only
758c8de  fix(macros): fecha vazamento entre inboxes e ajustes da revisao
cdb3485  feat(macros): campos de entrada, substituicao de variaveis e auditoria
dc6b74b  fix(fork): corrige ordem de boot e layout do spec da camada custom/
616f761  feat(enterprise): opera a instalacao no plano enterprise
b95eaeb  feat(fork): ativa a camada de extensao custom/
d482d5d  fix(dev): hot reload no Docker Desktop para Windows
6b83939  fix(husky): nao abortar o commit quando os linters nao estao no host
```

#### Como rodar a suíte nesta máquina (importante)

O bind mount do Docker Desktop no Windows é servido por **9p** e é ordens de grandeza
mais lento que o filesystem do container. Sem tratar isso, a suíte fica praticamente
parada (o processo trava em `p9_client_rpc`).

Duas correções, ambas necessárias:

1. **Escritas** — `docker-compose.dev.local.yaml` ganhou `rails_tmp:/app/tmp`. O Rails
   martela essa pasta: cache do bootsnap e, em `RAILS_ENV=test`, os blobs do
   ActiveStorage (`config/storage.yml` aponta `test` → `tmp/storage`).
2. **Leituras** — copiar o fonte para um volume local e rodar de lá:

```bash
# uma vez (a cópia atravessa o 9p; ~2 min)
MSYS_NO_PATHCONV=1 docker compose -p chatwoot-dev -f docker-compose.yaml -f docker-compose.dev.local.yaml \
  run --rm --no-deps -v appfast:/appfast rails sh -c \
  'rm -rf /appfast/*; tar -C /app --exclude=./.git --exclude=./node_modules --exclude=./.lh \
     --exclude=./tmp --exclude=./log -cf - . | tar -C /appfast -xf -; mkdir -p /appfast/tmp /appfast/log'

# depois, cada rodada (rápida)
MSYS_NO_PATHCONV=1 docker compose -p chatwoot-dev -f docker-compose.yaml -f docker-compose.dev.local.yaml \
  run --rm --no-deps -v appfast:/appfast -e RAILS_ENV=test -e POSTGRES_DATABASE=chatwoot_test rails sh -c \
  'cp -r /app/app /app/spec /appfast/ && cd /appfast && bundle exec rspec <arquivos>'
```

Medido: `macros_controller_spec` levava ~40 min projetados pelo bind mount; do volume,
**44 exemplos em 30 s**. `MSYS_NO_PATHCONV=1` é necessário porque o Git Bash converte
`/appfast` para caminho Windows.

#### Tela branca no dashboard: timeout do proxy do Vite

Sintoma: a aplicação abre em branco e o console mostra **500** em
`GET /vite-dev/dashboard/App.vue?vue&type=style&index=0&lang.scss` e em
`.../flag/Flag.vue?vue&type=style&index=0&lang.css`.

Não é erro de compilação. O log do Rails mostra a exceção real: **`Net::ReadTimeout`**.
O `vite_rails` instala o `ViteRuby::DevServerProxy` (subclasse de `Rack::Proxy`), que
usa `opts.fetch(:read_timeout, 60)` — 60 s fixos, sem knob em `config/vite.json`. No
primeiro acesso o Vite ainda está fazendo o **pre-bundling de dependências**, que
bloqueia todas as requisições; o Rails desiste antes e devolve 500. Do lado do Vite não
aparece erro nenhum, o que despista o diagnóstico.

Medições que fecham a conta:

| o quê | tempo |
| --- | --- |
| cadeia completa do PostCSS sobre `flag-icons.min.css` (540 `url()`) | **3,5 s** — não é o gargalo |
| `tailwindcss` sozinho, por módulo CSS | 2,9 s |
| `entrypoints/dashboard.js` a frio, **com** cache de deps preservado | 11 s |
| qualquer CSS a frio **sem** cache de deps | > 200 s (estoura o proxy) |

Duas correções:

1. `config/initializers/vite_dev_server_proxy_timeout.rb` — sobe o timeout para 300 s
   (`VITE_PROXY_READ_TIMEOUT`). Usa `prepend` no construtor, **não**
   `config.middleware.swap`: o `vite_rails` só insere o proxy na pilha depois que os
   initializers rodam, então o swap falha com `No such middleware to insert before`.
2. `docker-compose.dev.local.yaml` — a limpeza de `/app/node_modules/.vite` no entrypoint
   virou **opt-in** (`VITE_CLEAR_CACHE=true`). Ela existe porque o descriptor cache do
   plugin do Vue às vezes corrompe e passa a servir o bloco errado do `.vue` (o PostCSS
   recebe o `<script>` onde esperava o `<style>` e devolve `Unknown word computed`). Mas
   rodando a cada start ela destruía o cache de pre-bundling e **causava** o timeout
   acima. Note o `$$` no `if [ "$$VITE_CLEAR_CACHE" = "true" ]`: sem escapar, o compose
   interpola a variável antes do shell ver.

Depois de recriar o container do vite, o cache passa a sobreviver aos restarts.

#### O culpado real da tela branca: `Flag.vue`

As correções acima são legítimas, mas **nenhuma delas resolvia o problema** — só
mascaravam o resto enquanto um módulo seguia travando tudo. O que isolou foi
percorrer o grafo de imports a partir do entrypoint:

> **3.582 módulos, 122 s, zero falhas — exceto um.**

`dashboard/components-next/flag/Flag.vue?vue&type=style&index=0&lang.css` **nunca
completava**: 765 s numa medição, 1062 s noutra, sem responder. O `<style>` do SFC
fazia `@import 'flag-icons/css/flag-icons.min.css'`, e esse CSS tem **540 `url()`**
para SVGs — cada uma vira uma resolução de asset individual no Vite, e sobre o 9p
isso não termina.

Como `Flag.vue` entra no grafo do entrypoint (via `ContactsCard` e
`SearchResultContactItem`), ele derrubava a **aplicação inteira**, não só as telas
de contatos e busca.

Correção: o CSS saiu do pipeline do Vite. Os arquivos foram copiados de
`node_modules/flag-icons` para `public/flag-icons/` e são carregados por
`stylesheet_link_tag` no `app/views/layouts/vueapp.html.erb`. `Flag.vue` passou a
responder em **1 s** sem pedir bloco de style, e o crawl completo não acusa mais
falha. Vale em produção também, onde o build economiza as mesmas 540 resoluções.

Dois cuidados que vieram junto:

- `Flag.story.vue` renderiza fora do layout do Rails, então injeta o mesmo `<link>`
  — sem isso as bandeiras apareceriam em branco no Histoire.
- Os 540 SVGs (3,1 MB) ficaram versionados em `public/`. É ruído em merge com o
  upstream; a alternativa é gerar a cópia num `postinstall`, ao custo de depender
  de o deploy rodar o install.

**Lição de método:** o diagnóstico só andou quando parei de inferir a partir de
quem importa o quê e passei a medir o grafo de verdade. A afirmação de que
"`Flag.vue` não afeta a tela de macros" era falsa e custou horas.

#### A causa raiz de tudo: saturação do threadpool do libuv

Corrigir o `Flag.vue` tirou o pior sintoma, mas o ambiente seguia lento. A causa
real só apareceu no **CPU profile** do processo do Vite travado:

> main thread **97,1% ociosa**, maior self-time de JS: **2ms**.

Nenhum plugin era o gargalo — o processo estava *esperando*. As 4 threads do
pool do libuv estavam em estado `D` com ~37s de tempo de kernel cada.

A origem: `FORCE_POLLING_FILE_WATCHER=true` faz o chokidar criar **um
`fs.watchFile` por arquivo** — 5.921 pollers para os 5.122 arquivos de
`app/javascript`. Cada ciclo dispara um `stat()` no mesmo pool de 4 threads.
A conta não fecha: 5.122 × 2,05ms (custo real de um `stat` no 9p) = **10,5s de
trabalho exigido por ciclo de 1s**, ou 2,6x mais demanda que capacidade. A fila
cresce sem limite e **toda** operação de filesystem do Vite passa a esperar nela.

| `fs.promises.stat` | dentro do Vite saturado | processo node limpo, mesmo container |
| --- | --- | --- |
| volume nomeado (rápido) | 3.445 ms/op | **0,20 ms/op** |
| bind mount 9p | 3.633 ms/op | 2,05 ms/op |

Repare que até o volume *rápido* levava 3,4s: não era o 9p no caminho crítico,
era a **fila**. Isso fecha a aritmética dos sintomas — 540 `url()` × ~1,4s
efetivos = 765s, e `App.vue` a 213s ≈ 60 operações de fs.

A/B controlado, mesmo CSS de 540 `url()`: com polling **4ms**; sem correção,
nem terminava.

Três frentes, todas necessárias:

1. `UV_THREADPOOL_SIZE=64` (compose) — aumenta a capacidade;
2. `VITE_POLL_INTERVAL=3000` (era 300ms) — reduz a demanda;
3. watcher ignora locales fora de uso — `dashboard/i18n/locale` sozinho tem
   **2.704 dos 5.122 arquivos**, um diretório por idioma (`VITE_WATCHED_LOCALES`).

Também: `RAILS_MAX_THREADS=32`. Uma carga da tela de macros faz **3.606
requisições** de módulo, todas pelo proxy do `vite_ruby`, cada uma ocupando uma
thread do Puma bloqueada num `Net::HTTP`. Com as 5 padrão, o TTFB do próprio
documento chegava a 21s.

Resultado no grafo completo do dashboard (3.581 módulos):

| momento | tempo | falhas |
| --- | --- | --- |
| antes | não completava | 1 (travava para sempre) |
| flag-icons fora do Vite | 122s | 0 |
| threadpool corrigido | 7s | 0 |
| quente | **3s** | 0 |

**Beco sem saída, testado e revertido:** `server.origin` no Vite, para o navegador
buscar módulos direto na 3036 sem passar pelo Puma. Melhorou o `domReady` de 28s
para 24s e estabilizou, mas não mexeu no tempo até a tela renderizar, e
introduziu `net::ERR_FAILED`. Não vale a superfície cross-origin.

#### Procedimento: como verificar depois de recriar o container do vite

O cache em memória do Vite **não** sobrevive ao `--force-recreate`, só o de disco.
A primeira passada depois de recriar mede aquecimento, não regressão — já
aconteceu de um crawl acusar 76s e 2 falhas e a segunda rodada dar 3s e zero.

Então: **rode duas vezes e confie na segunda.** Se a falha se repetir na segunda,
aí sim é bug. Classifique pelo tipo — erro de conexão em poucos segundos é
rajada com cache frio; abort no teto do timeout é outra coisa.

O que continua custando: a **primeira visita a cada rota** leva de 110s a 140s no
cliente. Não é o servidor (o grafo serve em 3s e as APIs respondem entre 21ms e
407ms) — é o navegador processando o waterfall de módulos, que em dev não são
empacotados. Some nas visitas seguintes. A saída definitiva seria o repositório
no filesystem do WSL2, onde o polling deixa de ser necessário e nada disso existe.

#### Verificação da Onda 2 ✅

Tudo executado no container (`chatwoot-dev`). O host tem Ruby 3.4.5 e Bundler, mas não
serve: sem gems instaladas e com o Ruby divergindo do Gemfile (3.4.5 vs 3.4.4).

| O quê | Resultado |
|---|---|
| `bundle exec rubocop` nos 4 arquivos | **sem ofensas** |
| `bundle exec rspec` (custom + enterprise jobs + reconcile service) | **12 exemplos, 0 falhas** |
| Zeitwerk autocarrega `Custom::Internal::CheckNewVersionsJob` | OK |
| Ancestrais de `Internal::CheckNewVersionsJob` | `[Custom, Enterprise, Internal]` — Custom ganha |
| `ChatwootApp.extensions` | `["enterprise", "custom"]` |
| `ChatwootHub.pricing_plan` / `self_hosted_enterprise?` | `"enterprise"` / `true` |
| Grupos enterprise no super admin | **6/6 habilitados**, incluindo `custom_branding` |
| Glob não recursa (namespace seguro) | `Dir["custom/app/**"]` → só `custom/app/jobs` |
| YAMLs parseiam | 69 features (18 premium, 8 ligadas); 106 configs, `PLAN="enterprise"` |

> **Bug encontrado pelo boot real** (commit `dc6b74b`): `if ChatwootApp.custom?` estourava
> `NameError` no `application.rb` — nesse ponto do boot o `lib/chatwoot_app.rb` ainda não
> foi carregado. As linhas de `enterprise/` logo acima adicionam os paths
> incondicionalmente e nunca tocam a constante, por isso o upstream nunca esbarrou nisso.
> Trocado por `Rails.root.join('custom').exist?`.
>
> Vale o registro: a revisão por leitura tinha dado esse ponto como correto.

**Banco de dev**: o `installation_config.yml` só vale para instalação nova (o `ConfigLoader`
roda com `reconcile_only_new`). O banco de dev existente foi atualizado à mão para
`DEPLOYMENT_ENV=self-hosted` / `INSTALLATION_PRICING_PLAN=enterprise`. **Produção precisa do
mesmo passo** — via super admin ou `rake chatwoot:dev:toggle_variant` (essa task é
interativa e só roda em development).

Falta só olhar a aba `custom_branding` renderizada no browser.

### Onda 0 — Preparação ✅

- [x] Criar branch `feature/port-coraxy` a partir de `develop`
- [x] Commitar as correções de hot reload que estavam soltas no working tree
- [x] Corrigir o hook de pre-commit, que abortava todo commit feito do host
- [x] Resolver as decisões da seção 5 (marca, licença enterprise, teams)
- [ ] Congelar um snapshot do clone de referência fora do repo

> Ficou fora de propósito: o ruído do `annotate` nos models e a regeneração do
> `db/schema.rb` (Rails 7.2 local vs 7.1 do upstream) seguem sem commit no working tree.
> Não são customização — commitá-los sujaria o diff contra o upstream.

---

### Onda 1 — Backend autocontido · risco baixo, valor alto

Quase tudo arquivo novo. Melhor relação esforço/retorno do port inteiro.

**1.1 Sistema de macros avançado** — o maior diferencial de backend

| Novo | Modificado |
|---|---|
| `app/models/macro_execution.rb` | `app/models/macro.rb` (validação de `input_fields`) |
| `app/services/macros/variable_substitutor.rb` | `app/controllers/.../macros_controller.rb` (`stats`, `inputs`, permitted_params) |
| `app/services/macros/safe_url.rb` | `app/services/macros/execution_service.rb` (auditoria + guarda SSRF no webhook) |
| `app/controllers/.../macro_executions_controller.rb` | `app/jobs/macros_execution_job.rb` (repassa `inputs`) |
| 4 jbuilders (`macro_executions`, `macros/stats`, `_macro_execution`) | `app/views/api/v1/models/_macro.json.jbuilder` |
| Migrations `add_input_fields_to_macros`, `create_macro_executions` | `config/routes.rb` |

Frontend correspondente: `MacroExecuteModal.vue`, `MacroInputFieldsBuilder.vue`, `MacroHistory.vue`, `MacrosStatsPanel.vue` + ajustes em `MacroForm`, `MacroEditor`, `MacroItem`, `macros/Index.vue`, `api/macros.js`.

O que ele entrega: campos de entrada tipados na macro (`text, textarea, number, email, date, phone, cpf, cnpj, select, lookup`), com `lookup` fazendo busca remota; substituição de variáveis nas ações; histórico de execução auditado (`pending/success/partial/failed`, ações executadas vs total, mensagem de erro); painel de estatísticas com taxa de sucesso.

> ⚠️ Incluir o fix `380e707`: a validação de `inputs` **não** pode ser `presence: true` (`{}.blank?` é `true` no Rails → toda macro sem campos falhava em silêncio dentro do job). Já está correta no código-fonte a portar.

**Decisões tomadas no port do backend de macros** (divergem da fonte):

- **Sem FK para `conversations`.** A Coraxy usava `t.references :conversation, foreign_key: true`. No 4.17.1 não existe nenhuma FK para essa tabela, a PK dela é `serial` (integer) e `foreign_key: true` no Rails gera `NO ACTION` — apagar uma conversa com execução registrada passaria a **estourar erro**. Ficou só a coluna + índice; o registro de auditoria sobrevive à conversa e o serializer já trata `conversation` nula.
- **FKs de account/macro/user com `on_delete` explícito** (`cascade`/`cascade`/`nullify`), seguindo `campaign_recipients`, que é a migration mais recente do upstream.
- **`Macros::SafeUrl` endurecido**: a lista original não cobria CGNAT (`100.64/10`), multicast, reservado, `192.0.0.0/24`, `198.18/15` nem **loopback escrito como IPv4-mapped IPv6** (`::ffff:127.0.0.1`), que passava batido. Todas fechadas e cobertas por spec.
- **Env var renomeada** de `MAESTRO_ALLOW_PRIVATE_WEBHOOKS` para `ALLOW_PRIVATE_WEBHOOK_URLS` — nada de marca hardcoded.
- **Bug de shadowing corrigido** no `json_actions_format`: a variável local `actions` sombreava o atributo do model e a mensagem de erro listava a lista errada.
- **Filtro de data ignora valor inválido** em vez de montar um range degenerado e devolver a lista errada em silêncio.
- O spec do upstream de `ExecutionService` passou a stubar o `SafeUrl`: sem isso o guarda faz **resolução DNS real dentro do teste**.

**1.2 Dashboard Apps**
- Migrations `show_in_sidebar` + `pin_to_sidebar`
- `dashboard_app.rb`, `dashboard_apps_controller.rb`, `_dashboard_app.json.jbuilder`
- Interpolação de variáveis na URL: `{account_id}`, `{user_id}`, `{user_email}`, `{user_name}`, `{user_token}`
- Frontend: `DashboardAppModal.vue`, `DashboardAppPage.vue`, `Frame.vue`

**1.3 Filtro `my_teams_only`** no `ConversationFinder` (`team_id IN my_teams OR NULL`) + `ConversationApi.myTeamsOnly`

**1.4 Teams: `color` / `text_color`** — ❌ **descartado por decisão.** Usar `teams.icon` / `teams.icon_color` nativos do 4.17.1. Não portar as migrations `add_color_to_teams` e `add_text_color_to_teams`.

#### Dívida deixada em aberto no backend das macros

Levantada pelas revisões de `backend-security`, `backend-engineering` e `database-review`, e
conscientemente não resolvida nesta onda:

| Item | Por que ficou |
|---|---|
| **DNS rebinding** no `SafeUrl` — o guarda resolve o DNS e o `WebhookJob` resolve de novo no request | Fechar exige fixar o IP resolvido no request, mexendo no `WebhookJob` |
| **Sem chave de idempotência** no payload do webhook — o receptor não consegue deduplicar um replay | Precisa de decisão de contrato com quem consome o webhook |
| **`actions_run` conta no-op como sucesso** — macro rodada em conversa de tweet, ou `assign_agent` para quem não é membro da inbox, terminam sem erro e a auditoria mostra 100% | Exige os métodos de ação sinalizarem no-op de volta; mexe em `ActionService`, compartilhado |
| **`pending` eterno em SIGKILL** — o `ensure` cobre exceção, não morte do processo | Falta uma varredura periódica de pendentes antigos |
| **Sem retenção** em `macro_executions` — cresce ~1 linha por macro por conversa, sem TTL | Medir volume real antes de decidir entre expurgo periódico e particionamento |
| **Paginação por offset** no histórico degrada em offset alto | Padrão do resto do Chatwoot; migrar para keyset se virar problema |
| **`inputs` sem allow-list** contra as chaves declaradas em `input_fields`, e sem limite de tamanho | Fechar junto com a UI, que é quem monta o payload |

> ⚠️ **Rever na fatia 5 — agora com evidência, não suposição.** Hoje nada no servidor
> consome o `lookup_url`: quem busca é o browser do agente. O guarda de SSRF nesse campo é
> defesa em profundidade, mas medi o efeito real contra a API rodando:
>
> | `lookup_url` | Resultado |
> |---|---|
> | `https://api.github.com/...` | 200 — passa |
> | `https://api.example.com/...` | **422** — o host não resolve, e a política é fail-closed |
> | `http://192.168.1.10/...` | 422 — IP privado, bloqueio correto |
> | `http://erp.interno.local/...` | **422** — sufixo interno |
>
> As duas linhas em negrito são o problema: um ERP interno acessível só pela VPN do cliente
> — que é o caso de uso natural de um campo "consulta" — **não pode ser configurado**. E um
> host público que esteja momentaneamente fora do ar também trava o salvamento da macro.
>
> O guarda protege o servidor de uma requisição que o servidor nunca faz. Decidir na fatia 5
> entre: (a) remover a checagem desse campo, mantendo-a só no `send_webhook_event`, que o
> servidor de fato dispara; (b) manter e aceitar que lookup interno não funciona; (c) tornar
> configurável por instalação.
>
> Nota de UX independente da decisão: a validação do cliente não replica essa regra (depende
> de DNS), então o agente só descobre no 422 do save.

**Validação:** `bundle exec rspec spec/models/macro* spec/services/macros spec/controllers/api/v1/accounts/macro*` + `rubocop` + revisão por `backend-engineering`, `database-review` e `backend-security` (o `SafeUrl` é guarda anti-SSRF — tem que ser revisado a sério).

---

### Onda 2 — Liberar o Enterprise completo · **decidido: sim** · promovida para logo após a Onda 1

Esta onda destravou de posição: ela é **pré-requisito da Onda 6**, porque a administração de marca no super admin está atrás do mesmo gate de plano.

#### O mecanismo real no 4.17.1

Mapeei a cadeia inteira. Ela é mais simples do que a Coraxy assumiu:

```
Enterprise::Internal::CheckNewVersionsJob  (job agendado)
  └─ ChatwootHub.sync_with_hub             → pergunta o plano ao hub da Chatwoot
     └─ update_installation_config('INSTALLATION_PRICING_PLAN', @instance_info['plan'])   ← SOBRESCREVE
     └─ Internal::ReconcilePlanConfigService.new.perform
          └─ return if ChatwootHub.pricing_plan != 'community'    ← no-op se for enterprise
          └─ (senão) reseta configs premium + disable_features! em TODAS as contas
```

E o que o gate libera (`app/helpers/super_admin/features.yml`, condição `ChatwootHub.pricing_plan != 'community'`):

`custom_branding` · `agent_capacity` · `audit_logs` · `disable_branding` · `voice_calls`
(`saml` usa `ChatwootApp.enterprise?`, que já é `true` porque a pasta `enterprise/` existe)

**Consequência: com `INSTALLATION_PRICING_PLAN = 'enterprise'`, o `ReconcilePlanConfigService` já vira no-op sozinho.** A Coraxy esvaziou aquele service (`b82103a`) — no 4.17.1 isso é desnecessário. O único adversário real é o job sobrescrevendo a config.

#### Abordagem recomendada — diferente da Coraxy

A Coraxy hardcodou `ChatwootHub.pricing_plan` para `'enterprise'` e `pricing_plan_quantity` para `999_999`. Funciona, mas tem dois problemas: some com a config como fonte de verdade (o super admin passa a mostrar um valor que não vale nada), e **`ChatwootApp.self_hosted_enterprise?` lê `GlobalConfig.get_value('INSTALLATION_PRICING_PLAN')` direto, não o `ChatwootHub.pricing_plan`** — então o hardcode sozinho deixa esse método `false` quando o job resetar a config.

Recomendo atacar a origem, não o sintoma:

1. **Setar a config**: `INSTALLATION_PRICING_PLAN = 'enterprise'`, `DEPLOYMENT_ENV = 'self-hosted'`, `INSTALLATION_PRICING_PLAN_QUANTITY` alto.
   Já existe rake nativo para isso: `lib/tasks/dev/variant_toggle.rake` → `configure_enterprise_variant`. Usar o caminho oficial em vez de inventar.
2. **Neutralizar o clobber**: sobrescrever `Enterprise::Internal::CheckNewVersionsJob#update_installation_config` para ignorar as chaves `INSTALLATION_PRICING_PLAN` e `INSTALLATION_PRICING_PLAN_QUANTITY`. É o único ponto que reverte a config.
3. **`config/features.yml`**: virar `enabled: true` nas premium que devem vir ligadas por padrão em conta nova — a Coraxy ligou `disable_branding`, `audit_logs`, `sla`, `custom_roles`. Sem isso elas existem mas nascem desligadas (dá para ligar por conta no super admin).
4. **`plan_usage_and_limits`**: avaliar se o `PLAN_QUANTITY` alto já resolve os limites de agentes/inboxes/Captain antes de portar o override da Coraxy.

> ❌ **Não portar** `featurable#feature_enabled?` retornando `true` para tudo (exceto `captain_integration`). É marreta: mata o toggle por conta de **todas** as features, inclusive as não-premium, e quebra qualquer segmentação de plano futura no produto. Com os passos 1–3 ela é desnecessária.

#### Demais itens da onda

- Captain desativado por padrão, ativável por super admin por conta
- ✅ `CAPTAIN_OPEN_AI_URI_BASE` — **resolvido**: o 4.17.1 já tem `CAPTAIN_OPEN_AI_ENDPOINT` no grupo `captain` do super admin. Não portar, usar o nativo.
- `contact.rb`: remoção da validação de unicidade de e-mail (+ `contact_spec` que garante a remoção)
- Notificações de e-mail de conversa desativadas por padrão para novos agentes (`account_user.rb`)
- Remoção da notificação de atualização do Chatwoot (`versionCheckHelper.js`)

> **Licença.** Já registrei a ressalva: a pasta `enterprise/` tem licença restritiva e o fork vai a produto comercial. Decisão tomada e reafirmada — seguir. Fica documentado aqui como escolha consciente, não como descuido.
>
> ⚠️ `enterprise/.../base_open_ai_service.rb` **não existe mais** no 4.17.1 — remapear.

**Validação:** `bundle exec rspec spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb spec/enterprise/jobs spec/lib/chatwoot_hub_spec.rb` + conferir no super admin que as 6 abas premium aparecem + revisão `backend-engineering`.

---

### Onda 3 — Fluxo de atendimento IA (MAESTRO) · o diferencial do produto

- **Cadeado da IA no composer**: na categoria IA o input fica bloqueado por overlay; o operador segura 1,5s (barra de progresso) para assumir → abre a conversa, atribui a ele, redireciona para "Minhas". (`ReplyBox.vue` + `ReplyBoxAiLock.spec.js`)
- **Redirecionamentos no `ResolveAction`**: "Abrir" → abre + atribui + vai para "Minhas" (com pulso amarelo quando ainda não está aberta); "Deixar pendente" → pendente + vai para o filtro IA
- **Rotas de fila customizadas** (`mine`, `ai`, `resolved`) em `routeHelpers.js` e `conversation.routes.js` — necessárias para o `ReconnectService` e o `ContactInfo` reconhecerem as filas
- **Aba "Aguardando humano"**: admin vê todas as abertas, agente filtra por time; filtro de inbox na view
- Renomear Bot → Agente Virtual no i18n

> ⚠️ Maior risco de reescrita: `ReplyBox.vue` e `ResolveAction.vue` mudaram muito no upstream. Reimplementar sobre a versão 4.17, não aplicar patch.
> ⚠️ Revalidar se os fixes de rota/loop ainda são necessários (seção 1.4).

---

### Onda 4 — UI/UX do chat · maior volume, maior conflito

Ordenado por relação valor/risco:

**4.1 Autocontidas (podem ir cedo)**
- **Cores de mensagem por usuário**: `useMessageColors.js` + `MessageColors.vue` em Perfil, salvo em `ui_settings` (sem backend), cor do texto por contraste automático, player de áudio herdando a cor do balão. Tem spec pronta.
- **Composer simples em todas as inboxes exceto e-mail** (mudança de 8 linhas, alto impacto de UX)
- **Loaders**: `MessagesLoader.vue` (3 pontinhos), `LoadingState.vue` com mascote corvo, `ConversationCardSkeleton.vue` — todas com spec

**4.2 Lista de conversas**
- Coluna redimensionável por arraste (largura persistida, 280–600px, duplo-clique reseta)
- Fixar conversas no topo (pin, persistido no navegador)
- Densidade comfortable/compact com toggle
- Busca inline (nome, número, mensagens) com debounce 300ms + skeleton
- Cards arredondados estilo WhatsApp, faixa lateral de prioridade, badge de não lidas em `#25d366`

**4.3 Mensagens e tema**
- Wallpaper contínuo atrás das mensagens **e** do input (tema claro em tom creme, opacidades 0.9/0.6)
- Bolha com "bracinho" (tail) via pseudo-elemento herdando a cor
- Player de áudio redesenhado (progresso por `requestAnimationFrame`, download, controle de velocidade)
- Separadores de data, destaque âmbar ao navegar para mensagem, microinterações de hover
- Scrollbar global fino e arredondado
- Sidebar da conversa redimensionável
- CSAT: renderizar formatação do WhatsApp (`*negrito*`, quebras, link clicável) mantendo o texto compatível

**4.4 Gravador de áudio**
- Enviar áudio durante a gravação; waveform 100px → 30px; cancelar vira lixeira vermelha pulsante

**Validação:** obrigatória com o app rodando (`/run`) + revisão do `frontend-design` sobre o resultado renderizado, claro e escuro, desktop e mobile. Não fechar item de UI sem print.

---

### Onda 5 — Suíte de relatórios (`ajuste-powerbi`) · maior valor isolado

Praticamente tudo arquivo novo → port limpo. **6 builders + 5 telas + 3 componentes + endpoints.**

| Tela | Builder | Endpoint |
|---|---|---|
| Visão geral (`PainelGeralMetrics`, `GraficoAtendimentosDia`, `TopMotivos`) | `top_labels_builder.rb` + `metric_builder.rb` (bot_summary com TMA/TME por tipo) | `/reports/top_labels` |
| Monitoramento em tempo real | `supervisor_builder.rb` | `/live_reports/supervisor` |
| Recebidos e Efetuados | `origem_builder.rb` | `/reports/origem` |
| Fila — Histórico | `fila_historico_builder.rb` | `/reports/fila` |
| Cockpit de Atendentes | `cockpit_atendentes_builder.rb` | `/reports/cockpit_atendentes` |
| Motivos | `motivos_builder.rb` | `/reports/motivos` |

Transversal: filtro Todos/Humanos/IA em todas as telas (IA = conversa em caixa com bot, sem agente atribuído e sem handoff), badge de recorte ativo com critério no tooltip, tooltips explicando o cálculo de cada métrica, estado de erro visível e filtros travados durante carregamento, exportação CSV no Cockpit.

**As correções de performance de agosto são obrigatórias no port** (foram achadas em produção):
- `origem_builder`: escopar a subquery `first_message_table` por `account_id` — sem isso o `DISTINCT ON` varre a tabela `messages` inteira e estoura o `statement_timeout`
- `handed_off_conversation_ids`: subquery SQL em vez de `pluck(:conversation_id)` — evita `NOT IN` gigante (Origem, Supervisor, FilaHistorico, Motivos)
- `TopLabelsBuilder` substituindo `Promise.all` por etiqueta (causava 429)
- `supervisor_builder`: contar `open + pending` nos KPIs (mesmo critério da tabela)

> ⚠️ O módulo de relatórios mudou entre 4.2 e 4.17 — revalidar `reports.routes.js`, `ReportsWrapper`, `DateRange`, `ChartStats` e o `metric_builder` contra a versão atual.

**Validação:** `database-review` nos 6 builders (são queries pesadas, multi-tenant) + `backend-engineering` nos endpoints + `frontend-design` nas telas renderizadas com dados reais.

---

### Onda 6 — Administração de marca no super admin + infraestrutura

**Decisão: marca administrável em runtime, não hardcoded.** Isso muda a natureza da onda — deixa de ser "portar assets Coraxy" e vira "expor controle de marca no console".

#### A boa notícia: quase tudo já existe

O 4.17.1 já tem o grupo **`custom_branding`** no super admin (`enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb`), com 10 chaves editáveis pela UI:

`INSTALLATION_NAME` · `BRAND_NAME` · `LOGO` · `LOGO_DARK` · `LOGO_THUMBNAIL` · `BRAND_URL` · `WIDGET_BRAND_URL` · `TERMS_URL` · `PRIVACY_URL` · `DISPLAY_MANIFEST`

Ele está atrás de `ChatwootHub.pricing_plan != 'community'` → **a Onda 2 já o destrava, sem escrever uma linha de branding.** O que a Coraxy fez (`INSTALLATION_NAME` fixo como `"Echo"` no YAML + 24 ícones hardcoded em `public/`) é exatamente o oposto do que foi pedido aqui: **não portar.**

#### O que falta construir

- [ ] Validar a aba `custom_branding` renderizada após a Onda 2 (é código enterprise pouco exercitado em self-hosted)
- [ ] **Favicon e manifest**: hoje o conjunto em `public/` é estático. Para marca trocável, servir a partir de `LOGO_THUMBNAIL` em vez dos arquivos fixos — é a maior lacuna real
- [ ] **Estender `custom_branding_options`** com o que o produto precisa e ainda não é config: cor de destaque da marca, wallpaper do chat, mascote do loader
- [ ] Trocar os assets hardcoded que a Coraxy adicionou (`crow-loader.gif`, `chat-pattern*.png`) por referências a config, para não amarrar o produto a uma marca
- [ ] Conferir `RESTART_REQUIRED_CONFIG_KEYS`: parte das chaves de marca exige restart — a UI já avisa, mas confirmar quais entram nesse conjunto
- [ ] `theme/colors.js`, `theme/icons.js` — decidir o que é tema do produto (código) e o que é marca do cliente (config)

> Vale separar desde já dois conceitos que vão se confundir: **tema do produto** (design system, fixo no código) e **marca da instalação** (logo, nome, URLs, cor de destaque — em config). Misturar os dois é o que obriga a rebuild a cada cliente.

#### Infra e i18n (independentes da marca)

- Locales `pt_BR` completos (chatlist, conversation, macros, report, settings, sla, integrations, generalSettings) + `config/locales/pt_BR.yml` (texto do CSAT no WhatsApp)
- Ocultar aba Campanhas; remover Dialogflow das integrações
- `docker/Dockerfile`, `docker-compose*.yaml`, `start.sh`, `docker/entrypoints/*`, `.dockerignore` (incluindo o fix de permitir `.gitignore` no build context), `config/initializers/sidekiq_throttled.rb`, `DEPLOY.md`

---

## 4. Ordem sugerida de execução

```
Onda 0 (prep)
   ↓
Onda 2 (liberar enterprise)  ← promovida: destrava a administração de marca
   ↓
Onda 1 (backend autocontido)  ──┐
Onda 5 (relatórios)           ──┤ paralelizáveis, tocam áreas distintas
Onda 6a (marca no super admin)──┘ depende só da Onda 2
   ↓
Onda 4 (UI/UX) — a mais longa, quebrar em vários PRs
   ↓
Onda 6b (infra e i18n)
   ↓
Onda 3 (fluxo IA) — POR ÚLTIMO, por decisão
```

A Onda 2 subiu para o começo: são poucas linhas, e é ela que faz aparecer a aba de branding, os audit logs, o agent capacity e o voice calls no console.

A Onda 3 (fluxo IA) foi para o fim por decisão. Ajuda tecnicamente: é a que mais depende de `ReplyBox` e `ResolveAction`, que serão mexidos na Onda 4 — chegar nela com esses componentes já adaptados ao 4.17 reduz retrabalho.

---

## 5. Decisões tomadas

**5.1 Marca — administrável no super admin.** ✅
Nada de nome hardcoded. Aproveitar o grupo `custom_branding` que já existe no 4.17.1 (destravado pela Onda 2) e estendê-lo com o que falta: favicon/manifest dinâmicos, cor de destaque, wallpaper, mascote. Ver Onda 6.

**5.2 Enterprise completo — liberar.** ✅
Ressalva de licença registrada na Onda 2 e reafirmada. Abordagem recomendada difere da Coraxy: config + neutralizar o job que a sobrescreve, em vez de hardcode; e **sem** a marreta no `feature_enabled?`.

**5.3 Teams — usar o nativo por enquanto.** ✅
Não portar `add_color_to_teams` nem `add_text_color_to_teams`. Usar `teams.icon` / `teams.icon_color` do 4.17.1.

### Ainda em aberto

**5.4 Nível de fidelidade da UI** — afeta Onda 4.
"Igual ao que está lá" vs "mesma intenção, adaptado ao design system do 4.17". Recomendo a segunda: o upstream mudou os componentes e a primeira opção vira dívida a cada sync. Dá para decidir quando a Onda 4 chegar.

**5.5 Endpoint de unread count** — afeta Onda 1.3.
Verificar se o `conversations/unread_counts#index` nativo do 4.17.1 já atende, antes de portar o `/conversations/unread_count` custom. Resolve-se na implementação.

---

## 6. Riscos

| Risco | Mitigação |
|---|---|
| 15 versões de distância — patches não aplicam | Port temático, reimplementação sobre o 4.17 |
| Volume de UI (189 arquivos JS) | Quebrar Onda 4 em PRs pequenos, validar renderizado a cada um |
| Queries de relatório pesadas em multi-tenant | Portar as correções de agosto **junto** com os builders, nunca depois; `database-review` obrigatório |
| `SafeUrl` / `lookup_url` das macros = superfície SSRF | `backend-security` obrigatório na Onda 1 |
| Job agendado reverte o plano para `community` e derruba features em todas as contas | Neutralizar `update_installation_config` das chaves de plano no `CheckNewVersionsJob` (Onda 2, passo 2) — é o único ponto de reversão |
| Marca hardcoded obriga rebuild por cliente | Separar tema do produto (código) de marca da instalação (config) desde a Onda 6 |
| Divergir mais do upstream dificulta o próximo sync | Manter `docs-fork/sincronizar-com-upstream.md` atualizado a cada onda |
| Perder o contexto dos commits originais | Referenciar `coraxy@<sha>` em cada commit do port |
