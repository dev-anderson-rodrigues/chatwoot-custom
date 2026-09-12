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
| 1 — Frontend | ✅ as 8 fatias feitas e revisadas |
| 5 — Relatórios | 🔄 cockpit completo (builder + tela) · atribuição robô×humano **decidida e implementada** · 5 relatórios a portar |
| 4 · 6 · 3 | pendentes |

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
| 5 | Lookup dinâmico com `depends_on` | ✅ |
| 6 | `MacroHistory` como aba do editor | ✅ |
| 7 | `MacrosStatsPanel` no topo da lista | ✅ |
| 8 | Dashboard apps (checkboxes + interpolação de URL) — independente | ✅ |

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

#### Fatia 5 — resolvida. Lookup dinâmico com `depends_on`

Fonte (`origin/ajuste-powerbi`, `MacroExecuteModal.vue`) reexaminada antes de implementar:
não é busca por texto livre. É um `POST` para `lookup_url` com os valores atuais dos
campos em `depends_on`, disparado com debounce de 500ms sempre que qualquer valor do
formulário muda; a resposta (lista crua, ou envelopada em `options`/`registros`/`data`/
`results`, ou um objeto único quando há 1 resultado) vira as opções, mapeadas via
`value_key`/`label_key` com fallback para `value`/`id` e `label`/`name`. Isso muda o que
"reusar `ComboBox`" significava: a nota da fatia 3 sobre `useApiResults` + `@search`
pressupunha busca por texto — não existe no comportamento real. `ComboBox` (único) e
`TagMultiSelectComboBox` (`multi: true`) entram só pela filtragem local que já têm,
alimentadas pelas opções já buscadas; nenhuma das duas precisou de mudança.

**Decisão tomada, resolvendo o aviso da seção 1** (guarda de SSRF no `lookup_url`):
**opção (a)** — a checagem de DNS (`Macros::SafeUrl.public_http?`) saiu da validação do
model. Quem busca é o navegador do agente (fetch direto em `MacroExecuteModal.vue`), nunca
o servidor — a guarda nunca protegia nada e só derrubava host interno válido (ERP na VPN
do cliente) e host público momentaneamente fora do ar. A forma da URL (esquema http(s) +
host) continua validada. A guarda de verdade continua em `Macros::ExecutionService`, para
o `send_webhook_event`, que é a única URL de macro que o servidor de fato aciona.

Decisões de porte, divergindo ou completando a fonte:

- **Mensagem de erro fixa e traduzida, não o texto cru do `fetch`.** A fonte concatenava
  `error.message` (status HTTP, falha de CORS) direto no template. Nossas chaves de i18n
  (`LOOKUP_ERROR`, já portadas na fatia 1) não têm esse parâmetro, e expor detalhe de
  infra ao agente é ruído — trocado por uma mensagem fixa.
- **"Selecionar tudo" / "desmarcar tudo" do lookup múltiplo não entrou.** Já não estava
  nas chaves de i18n portadas na fatia 1 (só `LOOKUP_SELECTED_COUNT` veio, sem
  `LOOKUP_SELECT_ALL`/`LOOKUP_DESELECT_ALL`) — decisão de escopo já tomada antes desta
  fatia, só confirmada aqui.
- **Seleção antiga cai quando os deps mudam e ela não existe mais na resposta nova**
  (CPF trocado ⇒ contrato escolhido para o CPF anterior sai do campo). Mesmo
  comportamento da fonte, preservado.
- **Rótulos, não chaves cruas, na mensagem "preencha antes: X".** A fonte usava
  `depends_on.join(', ')` (as chaves internas); aqui resolve para `field.label`.
- **Timers de uma macro anterior são descartados no próximo `open()`.** Sem isso, fechar o
  modal com uma busca pendente e abrir outra macro deixaria o timer antigo escrever, mais
  tarde, no estado da macro nova — bug latente que existe na fonte e não foi portado.

`spec/models/macro_spec.rb` ganhou um teste que documenta a decisão (URL privada agora é
aceita, ao contrário da guarda do webhook). `MacroExecuteModal.spec.js` cobre: gate de
`depends_on`, POST com o payload certo após o debounce, os três formatos de resposta,
fallback de `value_key`/`label_key`, erro traduzido (sem vazar o erro cru), seleção única
e múltipla, bloqueio de obrigatório vazio, e a queda da seleção obsoleta após reconsulta.

#### Revisão da fatia 5 — três especialistas em paralelo, dois bugs reais

`backend-security`, `backend-engineering` e `frontend-design` revisaram a implementação
antes de fechar a onda. Achados:

- **`frontend-design`** (revisão de código, sem verificar renderização nesta rodada):
  achou violação de regra obrigatória — `frontend.mdc` proíbe "fetch direto em
  componentes" e "componente que coloca fetch, regra de negócio e manipulação de DOM no
  mesmo bloco". `fetchLookup`/`scheduleLookup`/`extractLookupRecords`/`mapLookupOptions`
  moravam dentro do `.vue`. **Corrigido**: extraídos para
  `app/javascript/dashboard/composables/useMacroLookup.js` (mesmo padrão de
  `useMacroExecution.js`) — o componente ficou só com a tradução de estado em texto
  (`lookupPlaceholder`/`lookupMessage`), que não é fetch nem regra de negócio.
- **`backend-security`**: decisão da opção (a) é sã como está — sem furo novo, um risco
  residual documentado (ver nota logo abaixo da decisão, seção 1).
- **`backend-engineering`** achou dois bugs reais na lógica de fetch, ambos **corrigidos e
  cobertos por teste de regressão** (confirmados batendo o teste contra o código sem a
  correção antes de fechar):
  1. **Loop infinito de refetch em lookup múltiplo.** `values[field.key] = array.filter(...)`
     sempre cria uma referência nova, mesmo quando nada é removido. `values` é `reactive()`
     e o `watch(..., {deep:true})` dispara comparando *referência*, não conteúdo — um
     array novo com o mesmo conteúdo ainda conta como mudança. Resultado: todo fetch
     bem-sucedido reatribuía o array, o watch reagendava o mesmo fetch, que reatribuía de
     novo — POST para `lookup_url` a cada ~500ms, para sempre, enquanto o modal ficasse
     aberto. Corrigido comparando o tamanho antes de reatribuir (filter só remove, nunca
     adiciona — tamanho igual implica conteúdo igual).
  2. **Fetch em voo sobrevive ao `open()`.** O `open()` já descartava os `setTimeout`
     pendentes, mas não invalidava um `fetch()` já em andamento de uma macro anterior. Duas
     macros com um campo de mesma chave (`contrato`, `cliente_id`) permitiam a resposta
     atrasada da primeira escrever no estado da segunda. Corrigido com um contador de
     geração (`epoch`) incrementado em `reset()` e checado antes de cada escrita em
     `lookupState`/`values` dentro de `fetchLookup`.

`MacroExecuteModal.spec.js` ganhou dois testes que travam exatamente esses dois bugs.

**Validação:** `bundle exec rspec spec/models/macro_spec.rb` (149 exemplos, 0 falhas,
suíte de macros completa) + `rubocop app/models/macro.rb spec/models/macro_spec.rb` (sem
ofensas) + `MacroExecuteModal.spec.js` (32 testes, incluindo os dois de regressão) via
`TZ=UTC npx vitest --no-watch --no-cache --no-coverage`. Verificação visual renderizada no
navegador ainda não feita — ver nota abaixo.

> **Tentativa de verificação visual (2026-09-05): incompleta, decisão consciente de não
> bloquear nela.** Um agente rodou o caminho de Docker + CDP da fatia 4 (login via
> `sso_auth_token`, abrir conversa, expandir o painel Macros) e chegou a capturar screenshots
> até o painel "Macros" no sidebar da conversa — mas ficou preso em "Obtendo macros"
> (carregando a lista) antes de conseguir abrir o `MacroExecuteModal` e exercitar o campo
> `lookup` de verdade. Sem indício de bug — a suspeita é só lentidão do ambiente (Puma com 5
> threads, primeira renderização de rota ~110s, já documentado). Interrompido depois de ~19
> minutos sem chegar ao estado que importa.
>
> **Decisão:** não vale a pena insistir agora — o modelo de dados e os 32 testes automatizados
> de `MacroExecuteModal.spec.js` (incluindo os dois de regressão dos bugs achados por
> `backend-engineering`) garantem a lógica; a fatia 4 mostrou que só a tela pega defeito de
> classe Tailwind/CSS que teste unitário não vê, mas isso fica como risco residual aceito,
> não como bloqueio. Verificação visual renderizada com um `lookup_url` real continua pendente
> — fazer manualmente no navegador quando for conveniente, antes de considerar a fatia 5
> definitivamente fechada para produção.

#### Fatia 6 — resolvida. `MacroHistory` como aba do editor

Fatia de frontend puro: o backend (`MacroExecution`, `MacroExecutionsController`, jbuilder,
rotas) e as chaves de i18n já tinham vindo nas ondas anteriores; faltava a tela.

**A fonte não foi copiada — foi reescrita sobre o design system.** O `MacroHistory.vue` de
`origin/ajuste-powerbi` é um componente monolítico: `fetch` dentro do `.vue`, `<select>`
cru, tabela montada à mão e data formatada com `toLocaleString('pt-BR')` fixo. Isso colide
de frente com o `frontend.mdc` (mesma violação que ele pegou na fatia 5) e com o i18n. O
porte seguiu o padrão de `routes/dashboard/settings/auditlogs/Index.vue`, que é a tela
análoga que o fork já tem:

- `composables/useMacroExecutions.js` — filtros, paginação, fetch e **normalização** do
  payload. O componente recebe registros já em formato de domínio e não conhece a API.
- `MacroHistory.vue` — só apresentação, reusando `BaseTable`/`BaseTableRow`/`BaseTableCell`,
  `Select`, `Label` (pílula de status, cores slate/teal/amber/ruby por status), `Spinner`,
  `PaginationFooter`, `Button`.
- `MacroEditor.vue` — aba via `TabBar` do design system, só no modo `EDIT`.
- Data pelo helper `messageTimestamp`, não por locale fixo.

Decisões que divergem da fonte:

- **Paginação entrou.** A fonte buscava 20 registros e mostrava a contagem total do backend
  ao lado — uma macro com 300 execuções exibia "300 execuções" sobre uma lista de 20, sem
  como chegar nas outras 280. O backend já expunha `limit`/`offset` + `meta.total`.
- **Bug do filtro "até", corrigido.** A fonte mandava a data crua; o backend compara
  `created_at <= to` e `Time.zone.parse('2026-09-05')` é meia-noite — filtrar "até 05/09"
  escondia tudo o que rodou no dia 05. Agora o composable manda `T23:59:59`. Tem teste.
- **Botão "re-executar" não entrou.** A chave `RE_EXECUTE` não foi portada na fatia 1
  (decisão de escopo anterior), e o mecanismo da fonte era pôr os `inputs` codificados na
  URL — os mesmos `inputs` que o controller trata como dado sensível (o recorte de
  `visible_executions` existe justamente porque eles podem conter CPF/CNPJ). Colocá-los no
  histórico do navegador contraria a razão daquele recorte.
- **Guarda de resposta obsoleta (`epoch`)**, o mesmo padrão que a fatia 5 adotou no
  `useMacroLookup.js`: trocar filtro e página dispara requisições em sequência rápida, e a
  resposta de uma consulta abandonada não pode sobrescrever a atual ao chegar atrasada.
- **Filtrar volta para a página 1.** Sem isso, estreitar o resultado estando na página 4
  mostraria uma lista vazia sem explicação.

Dois defeitos que só apareceram porque o teste os exigiu, ambos corrigidos:

- **`<label for>` apontando para `div`.** O `Select.vue` do design system não declara
  `inheritAttrs: false`, então o `id` passado a ele pousa na `div` raiz — o `for` não
  nomeava controle nenhum. Trocado por `<label>` envolvendo o controle (associação
  implícita).
- **Tela em branco ao sair de uma macro salva para a de criar.** O `MacroForm` fica em
  `v-show`; se `activeTab` continuasse em `'history'`, a aba sumia junto com o modo `EDIT` e
  o formulário não reaparecia. O watch de rota reseta a aba.

**Validação:** `MacroHistory.spec.js` (12 testes) + suíte de macros completa
(87 testes, 6 arquivos, 0 falhas) via `TZ=UTC npx vitest --no-watch --no-cache --no-coverage`
+ `eslint` (só warnings pré-existentes de chave de i18n dinâmica, mesmo padrão do
`MacroEditor` que já existia). Revisão de código por `frontend-design`.

> Mesma pendência da fatia 5: **verificação visual renderizada não foi feita** — decisão
> consciente de não bloquear nela nesta rodada (ver nota da fatia 5). Vale olhar na tela
> antes de produção: contraste das pílulas de status no modo escuro e a tabela em telas
> estreitas são o tipo de coisa que teste unitário não pega.

#### Fatia 7 — resolvida. `MacrosStatsPanel` no topo da lista

Fonte (`origin/ajuste-powerbi`, `MacrosStatsPanel.vue`) relida antes de implementar: um
painel acima da tabela de macros com quatro números do período (execuções, taxa de
sucesso, falhas, macros usadas), um seletor de 7/30/90 dias e o ranking das cinco macros
mais executadas. O backend já estava pronto e revisado desde a Onda 1 (`macros#stats`) e as
chaves `MACROS.STATS.*` vieram na fatia 1 — esta fatia é só a camada de tela.

Onde o painel entra: slot `#preBody` do `SettingsLayout`, que existe justamente para
renderizar algo antes do corpo. Por ficar fora do `#body`, ele não é engolido pelo estado de
carregamento nem pela mensagem "nenhuma macro" do layout — e leva um `v-if="records.length"`,
porque sem macro cadastrada não há métrica nenhuma para mostrar.

Decisões de porte, divergindo ou completando a fonte:

- **O fetch mora no composable, não no componente** (`useMacroStats.js`), como manda o
  `frontend.mdc` e como a fatia 5 acabou fazendo depois da revisão. O `.vue` fica só com a
  tradução de estado em texto e cor.
- **Guarda de resposta obsoleta (`epoch`)**, o mesmo padrão das fatias 5 e 6: trocar de
  período em sequência rápida deixava a resposta de um período abandonado sobrescrever a do
  período atual quando chegava atrasada. Tem teste de regressão, confirmado batendo contra o
  código sem a guarda antes de fechar.
- **Mensagem de erro fixa e traduzida** em vez do `error.message` cru que a fonte
  concatenava na tela: status HTTP e falha de CORS não dizem nada ao agente. Mesma decisão
  das fatias 5 e 6.
- **"Falhas" só fica vermelho quando é maior que zero.** Na fonte o número era sempre
  vermelho; zero falhas em vermelho é alarme falso.
- **Estado vazio de verdade** (`NO_DATA`): a fonte mostrava quatro zeros quando ninguém
  tinha executado nada no período.
- **`LAST_RUN` ganhou consumidor.** O backend já devolvia `last_executed_at` e a chave
  existia desde a fatia 1 sem uso; virou a linha secundária de cada macro do ranking.
- **`NEVER_RUN` saiu dos dois locales.** Ficou sem consumidor possível: o ranking só lista
  macro com execução no período, então nunca existe um "nunca executada" para exibir. Mesmo
  tratamento que o bloco `EXECUTE_MODAL` recebeu na fatia 4 — chave morta não fica.
- **Acessibilidade acima da fonte:** os botões de período viraram um `role="group"` com
  `aria-pressed` (a fonte só pintava o botão ativo, sem dizer nada ao leitor de tela), os
  quatro números viraram um `<dl>` em vez de `div`s soltas, e a cor da taxa reforça um
  número que também está escrito ao lado — nunca é o único portador da informação.
- **RTL:** `text-end` no lugar do `text-right` da fonte.
- **`Button` e `Spinner` do design system** em vez do `<button>` com classes próprias e do
  texto "carregando" da fonte.
- **Os quatro tiles saem de um `v-for`** sobre um `computed`, não de quatro blocos de markup
  repetidos como na fonte.

Detalhe da fonte que não foi portado como estava: o `totals` dela chamava
`sum('counts', 'success')` numa função cuja assinatura era `sum(key, status)` e que ignorava
o primeiro argumento — funcionava por acidente. Aqui o cálculo recebe a função de extração
direto. Pendente continua fora da taxa de sucesso, igual ao backend: contar execução que
ainda não terminou como fracasso derrubaria o número no meio de um lote grande.

**Validação:** `MacrosStatsPanel.spec.js` (11 testes) + suíte de macros completa (98 testes,
7 arquivos, 0 falhas) via `TZ=UTC npx vitest --no-watch --no-cache --no-coverage` +
`eslint` nos arquivos novos e no `Index.vue` (sobra só o warning pré-existente de chave de
i18n dinâmica, o mesmo que `MacroEditor` e `MacroHistory` já tinham).

#### Revisão da fatia 7 — um bloqueante de acessibilidade

`frontend-design` revisou a implementação final. O achado bloqueante, corrigido: o grupo de
botões de período tinha `aria-label` igual ao título da seção (`MACROS.STATS.TITLE`, "Visão
geral"). Um leitor de tela anunciava um grupo "Visão geral" dentro de uma seção "Visão
geral" — o atributo existia e comunicava a coisa errada, sem dizer que ali se escolhe o
período. Ganhou chave própria (`MACROS.STATS.PERIOD_GROUP_LABEL`) nos dois locales e um
teste que trava o rótulo.

Não bloqueante acatado: o painel agora esmaece enquanto refaz a consulta ao trocar de
período. Manter os números do período anterior na tela em vez de piscar um spinner continua
sendo o comportamento certo, mas antes só o `aria-busy` sinalizava a requisição em voo —
quem enxerga não tinha pista nenhuma. Tem teste.

Não acatados, com motivo: os `Button` do seletor ficam com props explícitas
(`:variant`/`:color`) em vez da forma abreviada por atributos que o `MacroHistory` usa,
porque aqui as duas dependem do período selecionado e a forma abreviada não expressa
condicional; e o tile "Falhas" continua somando `partial` e `failed` sob o rótulo que a
fatia 1 portou — separar os dois números pediria chave nova de i18n para um detalhe que o
histórico da macro já mostra caso a caso. O apontamento sobre a chave `NEVER_RUN` órfã já
estava resolvido antes da revisão: o revisor leu o arquivo antes da remoção.

> **Não verificado.** O revisor não subiu o ambiente nesta rodada, então contraste no modo
> escuro, comportamento em tela estreita (o container de Settings é mais estreito que o
> viewport, e o `sm:grid-cols-4` dos tiles quebra por ele) e foco visível dos botões de
> período seguem sem confirmação na tela renderizada — mesma pendência das fatias 5 e 6.

#### Fatia 8 — resolvida. Dashboard apps: variáveis na URL, barra lateral e página própria

A linha da tabela ("checkboxes + interpolação de URL") subestimava a fatia. O que a fonte
tem, e que o backend do fork já aceitava desde a Onda 1 (`show_in_sidebar` e
`pin_to_sidebar` no model, no controller e no jbuilder), são **quatro** peças de tela:

1. **Interpolação de variáveis na URL** — `{account_id}`, `{user_id}`, `{user_email}`,
   `{user_name}`, `{user_token}` — em `helper/dashboardAppHelper.js`, consumida pelo
   `Frame.vue` (app dentro da conversa) e pela página nova.
2. **Dois checkboxes no `DashboardAppModal`**, com o "fixar" desabilitado enquanto o
   "exibir na barra lateral" estiver desmarcado.
3. **`DashboardAppPage` + rota `dashboard_app_page`** (`accounts/:accountId/apps/:appId`),
   num módulo próprio (`routes/dashboard/dashboardApps/`), no padrão que o 4.17 usa para
   `calls/` e `contacts/`.
4. **Entradas na `Sidebar.vue`**: app marcado entra num grupo "Apps"; marcado *e* fixado,
   sobe para item de primeiro nível, ao lado de Relatórios e Campanhas. O 4.17 não tem o
   conceito de "seção" que a fonte usava (GERAL/FERRAMENTAS), então as entradas entram na
   lista plana de grupos, logo antes de "Portals".

Decisões de porte, divergindo ou completando a fonte:

- **Substituição em uma passada só, não `replace` encadeado.** A fonte trocava uma variável
  por vez, e cada troca varria o resultado da anterior: um agente com o nome
  `{user_token}` faria o próprio token entrar numa URL que só pedia o nome. Tem teste.
- **Todo valor sai por `encodeURIComponent`.** A fonte só codificava e-mail e nome; um nome
  com `&` ou `#` reescrevia a query string do destino. Tem teste.
- **Variável sem valor vira vazio**, não a string `"undefined"` que a fonte mandava quando
  o campo não existia.
- **Não portei o `access_token` no `postMessage`.** A fonte também colocava o token no
  objeto de contexto enviado para dentro do iframe — com destino `'*'`, que qualquer origem
  que o iframe assumir recebe. É estritamente pior que a URL, que ao menos vai só para o
  host que o admin cadastrou. A interpolação já atende quem precisa do token. **O `account:
  { id }`, que a fonte manda no mesmo objeto, foi portado** a pedido: é o id da conta, não
  credencial, e é o que o app precisa para saber em qual conta está rodando.
- **Não portei o `allow="clipboard-read; clipboard-write"`** do iframe da página. Ler a área
  de transferência do agente é permissão forte para conceder por padrão, e o `Frame.vue` da
  conversa nunca teve. Fácil de reativar se algum app precisar.
- **A página ganhou estado de carregando.** Na fonte, abrir o app por link direto (ou só
  recarregar a aba) chegava com a lista vazia no store e mostrava "app não encontrado" —
  a página agora busca a lista quando ela está vazia e mostra spinner enquanto isso.
- **Mensagem em i18n.** A fonte tinha `App não encontrado` hardcoded no template.
- **Dica das variáveis no formulário.** Sem ela o admin não tem como descobrir que a URL
  aceita variável nenhuma; o texto é gerado a partir da constante do helper, para não
  divergir dele. Confirmado em teste que o validador de URL do Vuelidate aceita
  `https://host/?c={account_id}` — se não aceitasse, a fatia inteira seria inútil na tela.
- **`Checkbox` do design system** em vez do `<input type="checkbox">` com `accent-woot-500`
  da fonte, e `ps-6` no lugar de `ltr:pl-6 rtl:pr-6`, como manda o `frontend.mdc`.

Um bug de upstream, corrigido de passagem porque a fatia mexia na mesma linha: o modal em
modo edição fazia `this.app.content = this.selectedAppData.content[0]`, guardando a
**referência** do objeto que vive no store. Editar a URL e fechar sem salvar deixava a lista
mostrando um valor que nunca foi gravado. Agora é cópia. Tem teste de regressão, confirmado
batendo contra o código sem a correção.

Armadilha de teste que vale registrar: `wrapper.vm.app.title = 'x'` **não chega** ao estado
que o componente valida — o proxy do `@vue/test-utils` devolve uma cópia destacada dos dados
para componentes com `setup()` + Options API. A escrita passou a ser pelo `$model` do
Vuelidate. Quem for testar outro modal do repo com esse formato vai tropeçar no mesmo lugar:
o sintoma é o submit não disparar e a validação parecer teimosamente inválida.

**Validação:** 22 testes (`dashboardAppHelper.spec.js` 9, `DashboardAppPage.spec.js` 7,
`DashboardAppModal.spec.js` 6) via `TZ=UTC npx vitest --no-watch --no-cache --no-coverage`
+ `eslint` limpo nos arquivos tocados. **Sem cobertura de teste: a montagem do menu no
`Sidebar.vue`** — o repo não tem spec desse componente (só dos componentes-folha), e montá-lo
exigiria um arreio de store grande demais para o valor.

#### Revisão de segurança da fatia 8 — `{user_token}` fica, com o risco escrito

`backend-security` revisou a variável e a classificou como **bloqueante**. O fato que
faltava na análise anterior estava na policy: `DashboardAppPolicy` exige `administrator?`
em `create?`/`update?`, mas `index?`/`show?` liberam **qualquer** `account_user`. Ou seja,
quem escolhe a URL é o admin e quem abre o app é cada agente — o token que vai para o log do
host de destino, para o `Referer` e para o histórico do navegador é o `access_token` de cada
agente, um por um, sem sinal nenhum para ele.

O peso não é o vazamento em si, é a fronteira que ele cruza: hoje um admin **não tem** como
obter o token de outro usuário (o jbuilder só expõe o do próprio `resource`). A interpolação
cria, por uma via lateral de UI, um jeito de personificar agente individual via API.

**Decisão do dono do produto, tomada com o parecer na mão: manter `{user_token}`.** O motivo
é migração — os apps do sistema antigo autenticam por essa variável e quebrariam sem ela.
É o mesmo tipo de decisão registrada na fatia 5 para o `lookup_url`: risco conhecido, aceito
de olhos abertos, escrito onde quem mexer no código vai ler (o comentário fica junto da
constante em `dashboardAppHelper.js`, não só aqui).

**O caminho para fechar, quando os apps puderem mudar:** um token curto, assinado e de
escopo restrito, emitido por endpoint próprio só para o app externo identificar o agente —
nunca o `access_token` cru, e nunca em querystring.

Confirmações do revisor, sem ação pendente:

- **Não portar o `access_token` no `postMessage(..., '*')` foi correto**, e pelo motivo
  suposto: o destino `'*'` entrega para qualquer origem que o iframe assumir *depois*,
  inclusive após um redirect para fora do host cadastrado. A URL, ao menos, só chega ao host
  que o admin escolheu. (O `account: { id }` que a fonte manda nesse mesmo objeto **foi**
  portado, a pedido: é o id da conta, não credencial.)
- **A substituição em passada única + `encodeURIComponent` não deixou buraco.** Como só
  admin escreve o template da URL, o único dado de menor privilégio é o valor de
  `user_name`/`user_email`, e o encoding cobre. O teste do agente chamado `{user_token}`
  trava exatamente a re-entrância que a fonte tinha.
- **Autorização e `permitted_payload` estão sãos.** `create`/`update`/`destroy` são de
  admin; `index`/`show` escopam por `Current.account.dashboard_apps`, sem IDOR entre contas;
  `show_in_sidebar`/`pin_to_sidebar` são flags de exibição, sem peso de autorização.

> **Débito registrado, anterior ao port:** mesmo sem token, o `dashboardAppContext` manda
> `currentAgent` (id, nome, e-mail), conversa e contato por `postMessage` com destino `'*'`.
> Mesmo padrão de risco em escala menor — PII, não credencial. Fechar exige mandar para a
> origem do iframe, o que mexe em código que todo dashboard app existente consome.
>
> **Não verificado:** se existe CSP restringindo `frame-src` (sem ela, qualquer domínio serve
> de destino), e se o `JSONSchemer` do model rejeita URL com unicode ou IDN homográfico que
> mascare o host de destino. Os dois pesam mais agora que a decisão foi manter o token.

#### Revisão de frontend da fatia 8 — sem bloqueantes

`frontend-design` não achou bloqueante. Três apontamentos foram acatados:

- **O composable saiu do componente.** A página decidia sozinha quando buscar a lista e fazia
  o casamento do `appId` e a filtragem dos frames — regra que o `frontend.mdc` manda tirar do
  `.vue`. Virou `composables/useDashboardApp.js`, o mesmo caminho que a fatia 5 seguiu depois
  da revisão dela.
- **O checkbox desabilitado agora explica o motivo.** Ele ficava só apagado e indentado: quem
  usa leitor de tela ouvia "desabilitado" e nada mais. O texto do porquê entrou *dentro* do
  `<label>` — `aria-describedby` no `Checkbox` pousaria na div raiz dele, longe do input, e
  não seria anunciado.
- **Os apps dentro do grupo "Apps" ganharam ícone**, que só os fixados tinham.

Não acatados, com motivo: o `focus-visible` ausente e o `cursor-pointer` fixo do
`Checkbox.vue` são do design system compartilhado, anteriores a esta fatia — mexer ali muda
todo formulário do produto e é decisão de design system, não de port. **Ficam registrados
como débito real de acessibilidade: hoje não há indicador visível de foco em nenhum checkbox
do dashboard.**

Riscos de UI que o revisor levantou e que só a tela resolve: fixar muitos apps faz a barra
lateral de primeiro nível crescer sem controle (não há limite nem agrupamento), e a lista de
configuração não mostra quais apps estão na barra lateral — o admin precisa abrir cada um
para saber. Nenhum dos dois bloqueia; os dois viram ticket se aparecerem na prática.

#### As duas pendências de segurança da fatia 8 — uma fechada, uma descartada com motivo

`backend-security` voltou às duas perguntas que tinham ficado como NÃO VERIFICADAS. As
respostas foram conferidas contra o código antes de virar decisão — a segunda não sobreviveu
à conferência.

**1. `frame-src` — não existe CSP nenhuma, e a correção proposta não serve.**

O diagnóstico está certo: `config/initializers/content_security_policy.rb` está inteiro
comentado, o nginx do `deployment/` não manda header de segurança, e o único CSP do código
é o `frame-ancestors` do `widgets_controller.rb`, que é a diretiva **inversa** (quem pode
embutir o widget) e não tem relação com o dashboard.

A correção proposta era montar uma allowlist de `frame-src` a partir dos hosts cadastrados
em `dashboard_apps`. **Não dá**, e o motivo é arquitetural: o dashboard é uma SPA — um único
documento serve todas as telas, então há uma CSP só para o produto inteiro. E há outras
telas que embutem iframe de host que não está em `dashboard_apps`:

- `components-next/message/bubbles/Embed.vue` embute `attachment.dataUrl`, ou seja, **host
  arbitrário vindo de anexo de mensagem** (é assim que embed de mídia aparece na conversa);
- `components-next/message/bubbles/Dyte.vue` embute o link da sala de videochamada.

Uma allowlist estreita o suficiente para restringir o destino dos dashboard apps quebraria
esses dois. Uma allowlist larga o bastante para mantê-los vivos teria que liberar `https:`
praticamente inteiro — que é onde já estamos, sem o custo de manter a lista. O revisor olhou
só o caminho do dashboard app e não fez esse inventário.

Fica registrado assim: **CSP não é a mitigação certa para o risco do `{user_token}` neste
produto.** Se um dia valer restringir de verdade, o caminho é servir o dashboard app em um
documento próprio (rota fora da SPA, com CSP própria), não apertar a CSP global.

**2. Userinfo na URL — confirmado e corrigido.**

Este sobreviveu. O `format: uri` + `pattern: ^https?://` do schema aceitam
`https://host-confiavel.com@host-do-atacante.com/` — o host real é o segundo, mas a string
começa pelo primeiro. Como a lista de apps mostra a URL truncada no fim
(`DashboardAppsRow.vue`), o host real é justamente a parte que some: quem audita depois vê o
prefixo confiável. Com o `{user_token}` viajando nessa URL, o custo de uma confusão de host
não detectada subiu.

Fechado com um `validate` no model, ao lado do schema, que rejeita URL com userinfo. Não
limita o admin — ele continua podendo cadastrar o host que quiser; impede é a URL **mentir**
sobre qual host ela é. A validação do schema passou a interromper antes, para uma URL
inválida não acumular as duas mensagens de erro.

O `DashboardAppsRow.vue` não precisou mudar: a truncagem corta o fim, e o host aparece logo
depois do `https://` — com o userinfo barrado no save, o que fica visível é o host real.

> **Débito de dado, não de código:** a validação vale no save. Registro criado antes dela
> com userinfo na URL continua no banco e continua sendo renderizado. Não há instalação do
> fork em produção com dashboard app cadastrado, então não vale migração agora — mas se
> houver, é uma varredura em `dashboard_apps.content`.

#### Verificação visual das fatias 5 a 8 — o que a tela mostrou

Feita em 2026-09-08, na aplicação real (Docker + Chrome do host por CDP), com dado semeado
por `qa_setup_visual.rb`: duas macros, dez execuções espalhadas em 45 dias para o filtro de
período ter o que separar, e três dashboard apps cobrindo os estados de barra lateral.

**Fatia 7 — painel de métricas: confere com o dado.** 8 execuções na janela de 30 dias (as
de 40 e 45 dias corretamente fora), taxa de 71,4% com o pendente excluído do denominador,
"falhas" somando parcial + falhou, e as cores nos limiares certos — âmbar entre 60 e 90%,
verde em 100%. O seletor de período e o ranking com "última execução" também.

**Fatia 6 — histórico: as quatro pílulas de status são legíveis no modo escuro.** Era uma
das duas coisas que a nota da fatia 6 mandava olhar antes de produção. Pendente, Sucesso,
Parcial e Falhou aparecem com contraste suficiente, e a tabela mostra as sete execuções da
macro com agente, conversa e proporção de ações.

**Fatia 8 — verificada inteira.** Grupo "Aplicativos" na barra lateral, apps fixados
promovidos a item de primeiro nível, e o **destaque de item ativo acendendo só no app
aberto** — que era risco real, já que todos os apps compartilham o mesmo nome de rota e o
casamento poderia ser por nome em vez de caminho. A página renderiza o iframe em altura
cheia com a URL interpolada de fato carregada. No modal, os dois checkboxes com a
dependência funcionando e a dica das variáveis **com as chaves literais na tela** — se elas
tivessem sido escritas direto na mensagem de i18n, o vue-i18n as trataria como interpolação
e o admin veria a lista vazia; passá-las como parâmetro era exatamente para isso.

**O defeito que só a tela pegou:** o ranking mostrava **"1 execuções"** na macro que rodou
uma vez. `STATS.RUNS` era texto fixo no plural, com o número concatenado no template,
enquanto a vizinha `HISTORY.TOTAL_COUNT` já usava mensagem de plural do vue-i18n — ou seja,
inconsistência dentro da mesma feature. Corrigido nos dois idiomas, com teste do singular
que foi confirmado falhando contra a chave antiga. **Nenhum dos 120 testes pegava isso**,
porque todos os casos existentes tinham mais de uma execução.

**Fatia 5 — lookup dinâmico: verificada na tela em 2026-09-09.** Faltava desde a rodada
anterior, que morreu antes de chegar nela. A resposta do `lookup_url` foi servida por
`Fetch.fulfillRequest` do próprio driver, em vez de subir um servidor de mentira: quem busca
é o navegador do agente, então interceptar ali é o ponto certo — e ainda deixa ler o payload
que o front monta, que é metade do que a fatia faz.

O que a tela mostrou, com o modal aberto sobre a conversa:

- **O POST sai com o payload certo:** `{"cpf":"529.982.247-25"}` — só o campo declarado em
  `depends_on`, e o CPF **mascarado**, confirmando em runtime a decisão da fatia 4 sobre qual
  valor viaja.
- **Uma única chamada** durante o minuto em que o modal ficou aberto. Isso vale como
  verificação do bug de refetch em loop que a revisão da fatia 5 corrigiu: o defeito, se
  estivesse vivo, apareceria como um POST a cada ~500ms enquanto o modal existisse. O teste
  já travava isso; agora está confirmado no app rodando.
- **As opções chegam mapeadas por `value_key`/`label_key`** (`id`/`name` da macro de QA) e
  renderizam na lista: "Contrato C-1024 - Fibra 500MB" e "Contrato C-2087 - Movel 20GB".
- **Máscara progressiva funcionando no campo de CPF** e os asteriscos vermelhos de campo
  obrigatório visíveis nos dois rótulos — a correção da fatia 4 (asterisco como `<span>`, não
  pseudo-elemento) está de pé na tela, não só no teste.
- Contraste legível no modo escuro, no modal e na lista de opções.

**Correção de diagnóstico que vale mais que a fatia:** o acordeão preso em "Obtendo macros"
**não era fila nem trava do endpoint**. O log do Rails mostra `GET /api/v1/accounts/1/macros`
completando **200 OK em 159–348ms**. O que parecia travamento era a **primeira renderização
fria da rota de conversa**, que neste ambiente leva de 5 a 10 minutos (o overlay do Vite
chegou a marcar 594s). A nota anterior, que atribuía o sintoma ao `/cable`, descrevia um
segundo problema real, mas não este: aqui as requisições chegavam ao servidor e voltavam
rápidas. **Como distinguir:** `docker compose logs rails | grep macros` — se a requisição
aparece e completa, é renderização, não fila; espere em vez de mexer no driver.

**Achado de backend, pré-existente:** o Bullet acusa N+1 no índice de macros —
`Macro => [:updated_by]` e `Macro => [:files_attachments]`, ambos a partir de
`_macro.json.jbuilder:11`. É do upstream, não do port, mas cresce com o número de macros da
conta e merece um `includes` quando alguém encostar nesse controller.

**Achado de acessibilidade, também do upstream:** a barra lateral principal não é um
landmark — não há `<nav>` nem `<aside>` na página, só `div`s. Quem usa leitor de tela não tem
como pular para a navegação. Foi assim que a primeira tentativa de driver travou (esperava
por `nav`), e a lição para quem for automatizar aqui é a mesma que já está registrada:
ancore em conteúdo, nunca em seletor genérico.

**Superfície nova que vale saber:** a dica do modal lista `{user_token}` para qualquer admin
que abra a tela de cadastro. Dado que a decisão foi manter a variável, expor é melhor do que
esconder — mas é mudança de superfície que não estava prevista quando a decisão foi tomada.

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
- ~~**Puma roda com 5 threads neste ambiente**~~ — **diagnóstico corrigido em 2026-09-08.**
  O `docker-compose.dev.local.yaml` já passa `RAILS_MAX_THREADS=32` e o container confirma
  esse valor (o `RAILS_MAX_THREADS=5` do `.env` perde para o `environment:` do compose). O
  Puma não é o gargalo.

  **A causa real é o ActionCable em long-polling.** O log do Rails mostrava
  `Started GET "/cable"` a cada ~10s, sem parar, e **nenhuma** requisição da API que a tela
  esperava — porque ela nunca saía do navegador. Cada tentativa de `/cable` segura uma das
  ~6 conexões que o navegador concede por host; com elas todas presas, o XHR fica na fila
  **dentro do Chrome**. O sintoma é idêntico ao de fila no servidor (tela presa em
  "Obtendo macros" / "Fetching macros"), mas o servidor está ocioso — dá para distinguir
  na hora: se o `docker compose logs rails` não mostra a requisição, o problema é do lado
  do navegador.

  **Solução no driver:** `Network.setBlockedURLs` com `['*/cable', '*/cable?*']` logo após
  `Network.enable`. Nada do que se verifica visualmente depende de tempo real. Com o bloqueio,
  as chamadas passaram a chegar ao Rails em segundos.

- **Espere por conteúdo específico, nunca por seletor genérico.** Dois erros custaram
  rodadas inteiras nesta sessão: `document.querySelector('tbody tr')` casou com a tabela da
  aba *Editor*, que continua no DOM atrás do `v-show` do `MacroEditor`, e a foto saiu com o
  histórico ainda carregando; e depois o mesmo seletor casou com um DOM já montado mas **sem
  CSS** (o Vite ainda compilando a rota), produzindo uma imagem em branco. Ancore em texto do
  próprio dado (`innerText.includes('[QA] ERP agrupado')`) ou num contador que só muda quando
  a resposta chega. Um `innerText.includes('macro')` também não serve: a descrição da tela já
  contém a palavra.
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
> valer fechar, o caminho é um token de escopo restrito emitido para o app. **Confirmado na
> fatia 8** com o parecer do `backend-security` na mão — ver "Revisão de segurança da fatia 8",
> que detalha por que a policy torna o risco maior do que esta nota supunha.

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

#### A causa raiz da lentidão do ambiente: o bind mount 9p — medida em 2026-09-10

O usuário relatou "muda de página e fica carregando por vários minutos", com o indicador do
Vite marcando **820 s acumulados em 55 requisições**. Medido dentro do container `vite`, sobre
os 2.287 arquivos de `app/javascript`:

| Leitura dos mesmos 2.287 arquivos | Tempo |
|---|---|
| Pelo bind mount (`D:\…` → `/app`, servido por 9p) | **30,71 s** |
| Do filesystem do container | **0,06 s** |

**~512x.** E o Vite não lê cada arquivo uma vez: transforma e resolve os imports módulo a
módulo, sob demanda, e cada resolução são várias chamadas de `stat`. Daí a navegação entre
telas custar minutos.

Não é a aplicação, não é o Puma, não é o ActionCable — é o filesystem. É **a mesma causa** que
já tinha sido contornada para o RSpec com o volume `appfast`; o frontend nunca ganhou o
contorno equivalente.

`docker inspect` confirma o desenho: `/app` é bind do disco Windows, enquanto `node_modules`,
`public/packs`, `tmp/cache` e `bundle` são volumes locais (rápidos). Ou seja, o que já estava
em volume ia bem; o código-fonte, não.

O que já existia de mitigação no `vite.config.ts` do fork (watcher em polling, `warmup`) ataca
sintomas: o `warmup` cobre só `entrypoints/dashboard.js` e `dashboard/App.vue`, então **toda
tela de rota fica de fora** e paga o custo na primeira navegação.

**Decisão: mover o repositório para dentro do WSL2** (`~/chatwoot` na distro Ubuntu). O Docker
Desktop aqui roda no backend WSL2, então arquivos em ext4 dentro da distro são lidos
nativamente, sem 9p. Conserta a causa para tudo de uma vez — Vite, RSpec, `git`, `pnpm` — em
vez de somar contornos por ferramenta.

Cuidados registrados:
- **`node_modules` não é copiado.** Tem binário compilado para Windows (esbuild e afins);
  precisa de `pnpm install` nativo dentro da distro.
- **A cópia em `D:\` fica intacta** como plano B até a nova estar validada.
- O `.pnpm-store` (542 MB) também não vai: é cache reconstruível.

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
- [x] Congelar um snapshot do clone de referência fora do repo — `.coraxy-ref/`,
      irmão de `chatwoot/` (fora do working tree, `git clone --filter=blob:none`),
      branch `ajuste-powerbi` já em checkout. Recriar com o comando de referência
      da seção 2 se for limpo.

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

> ✅ **Decidido na fatia 5: opção (a).** A checagem de `Macros::SafeUrl.public_http?` saiu
> de `Macro#validate_lookup_url` — só a forma da URL (esquema http(s) + host) continua
> validada. A guarda real ficou só no `send_webhook_event`, em `Macros::ExecutionService`,
> que é a única URL de macro que o servidor de fato aciona. Detalhe e teste que documenta a
> decisão em "Fatia 5 — resolvida" (seção 3, Onda 1 frontend).
>
> **Risco residual, revisado por `backend-security` e aceito conscientemente.** Como quem
> busca é o navegador do agente, não o servidor, "privado" passa a ser relativo à rede do
> agente, não à da instalação. Um admin malicioso ou comprometido (só admin publica macro
> `global`, ver `Macro#set_visibility`) poderia apontar um `lookup_url` para a rede local do
> agente (roteador, serviço em localhost) e o navegador do agente faria um POST cego para lá
> ao preencher os campos de que o lookup depende. Impacto limitado — é cego (só o agente vê
> a resposta), exige interação deliberada do agente, e exige um admin já malicioso, que já
> teria caminhos mais diretos de dano via `send_webhook_event` ou as demais `actions` de
> macro. É o reverso direto e inevitável da capacidade que a fatia pediu (alcançar um ERP
> interno) — não uma falha da implementação, mas aceito de olhos abertos.

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

#### Onda 5 — levantamento antes de portar (2026-09-09)

**Escala real:** 6 builders (1.277 linhas) + 5 telas (4.093 linhas: 641 a 1.062 cada) + as
ações nos controllers. Os três controllers (`reports`, `live_reports`, `summary_reports`) já
existem no 4.17, então o port **acrescenta ações**, não cria controller. Os 6 builders não
existem no nosso repo — arquivo novo, port limpo, como o plano previa.

O aviso do plano sobre divergência do módulo se confirmou, e é maior: o 4.17 **acrescentou**
uma camada que a fonte não tem (`drilldown_builder`, `inbox_label_matrix_builder`,
`label_summary_builder`, `channel_summary_builder`, `first_response_time_distribution_builder`,
`outgoing_messages_count_builder`). Portar por cima sem olhar duplicaria conceito.

**As telas não podem ser copiadas como estão.** Com 640 a 1.060 linhas cada, elas carregam
fetch, estado e regra de negócio dentro do `.vue` — o `frontend.mdc` proíbe. Cada tela vai
precisar de composable próprio, como as fatias 5 a 8 acabaram fazendo.

##### O problema de atribuição robô × humano — **decidido em 2026-09-11**

O filtro transversal Todos/Humanos/IA é o que separa as métricas, e a definição da fonte tem
furo. Levantado a pedido do usuário, antes de portar.

> **A regra, dada pelo dono do produto:** "Quando um robô é vinculado a uma caixa de entrada,
> todas as conversas iniciais começam como pendentes. Uma conversa finalizada sem ter sido
> aberta ou atribuída é do robô." **"Ter sido" é histórico**, não estado atual.
>
> Implementada em `app/finders/reports/conversation_ownership_finder.rb` (fatia 0b).

**Como o Chatwoot marca robô.** Caixa "tem bot" por `Inbox#active_bot?` —
`agent_bot_inbox&.active? || dialogflow_active?` (`app/models/concerns/inbox_bot_status.rb`),
e o enterprise sobrescreve somando o Captain (`enterprise/app/models/enterprise/inbox.rb`),
que no fork está ligado desde a Onda 2. Conversa em caixa com bot **nasce `pending`**
(`conversation.rb`, "bot conversations should start as pending"); `open` é o humano.

**O furo — e a correção de uma afirmação errada deste plano.** O evento
`conversation_bot_handoff` só é gravado quando **o próprio bot** abre a conversa; o guarda é
explícito em `conversations_controller#bot_handoff?`:
`return false unless Current.user.is_a?(AgentBot)`. Mas a conclusão que estava escrita aqui —
"se um humano abre a pendente pelo dashboard, não há evento nenhum" — **estava errada**. O
4.17 grava `conversation_opened` em toda transição para `open`
(`reporting_event_listener.rb:101`, upstream desde a v4.5.0). O que falta é só o handoff.

É essa correção que torna a regra do dono do produto implementável: "já foi aberta" tem
fonte histórica e imutável.

Cruzando com a definição da fonte — caixa com bot **+** `assignee_id IS NULL` **+** sem
evento de handoff (`origem_builder#bot_only`) — saem três formas de uma métrica roubar a
outra:

1. **Humano trabalha, robô leva o crédito.** Agente abre a pendente e responde sem se
   atribuir: sem evento e sem assignee, a conversa segue contada como robô. Com bot burro
   isso é o caso comum, não exceção — é justamente quando o bot não resolve que o humano
   entra.
2. **Número de período fechado muda depois.** `assignee_id` é estado atual, não histórico.
   Conversa que o robô resolveu sozinho sai do balde "robô" no dia em que alguém atribuir.
3. **Duas telas, dois números.** O `BotMetricsBuilder` do 4.17 conta *todas* as conversas de
   caixa com bot, inclusive atribuídas e com handoff. A tela portada contaria só as sem
   assignee e sem handoff — mesma conta, duas respostas para "conversas do bot".

Menor, mas real: a fonte usa `agent_bot_inboxes`, que ignora dialogflow e Captain; essas
conversas cairiam em "Humanos".

**O critério implementado.** A classificação é **por resolução** e lê só fatos gravados uma
vez em `reporting_events`. Um `conversation_resolved` é do robô quando:

```sql
r.user_id IS NULL                                        -- não estava atribuída ao resolver
AND EXISTS (SELECT 1 FROM reporting_events twin          -- caixa tinha robô ativo no instante
            WHERE twin.conversation_id = r.conversation_id
              AND twin.name = 'conversation_bot_resolved'
              AND twin.event_end_time = r.event_end_time)
AND NOT EXISTS (SELECT 1 FROM reporting_events ev        -- nunca aberta, nem com resposta humana
                WHERE ev.conversation_id = r.conversation_id
                  AND ev.name IN ('conversation_opened','conversation_bot_handoff','first_response')
                  AND ev.event_end_time <= r.event_end_time)
```

Humano é a negação exata. Como `IS NULL` e `EXISTS` nunca devolvem NULL, **robô + humano =
todas as resoluções**, e um spec trava essa invariante.

Por que cada peça:

- **O gêmeo `conversation_bot_resolved`** é a única prova *imutável* de que havia robô na
  caixa: `active_bot?` é estado atual, e desligar o robô depois reescreveria o passado. Como
  o gêmeo existe desde a v3.7.0, também sustenta o histórico anterior à v4.5.0, quando
  `conversation_opened` ainda não existia.
- **`first_response`** fecha o furo da coexistência do WhatsApp: resposta dada pelo celular
  entra como `outgoing` **sem remetente**, não barra o gêmeo, mas o Chatwoot a trata como
  resposta humana. Pega também resposta pública via API sem abrir a conversa.
- **`conversation_bot_handoff`** preserva o histórico da era 4.2.

**Onde o classificador diverge da regra literal** (aceito, e documentado no código):

| Caso | Regra literal | Classificador | Por quê |
|---|---|---|---|
| Humano deixa só nota privada e resolve, sem abrir | robô | humano | o gêmeo exige ausência de `outgoing` de User |
| Robô desligado antes da resolução | robô | humano | o gêmeo não sai |
| Pendente atribuída e desatribuída em silêncio | humano | robô | atribuição não deixa rastro imutável |

**Duas decisões tomadas junto, ambas reversíveis:**

- **Sem a condição "o robô mandou mensagem".** Ela só importaria para o Captain, que faz a
  conversa nascer `open` quando não engaja o contato — e o Captain não está em uso; o robô
  planejado é um agent bot simples, cuja conversa nasce `pending`. Rever na Onda 3. O cenário
  está travado em spec.
- **Sem listener `conversation_assigned`.** Ele fecharia só a terceira divergência da tabela,
  que é atribuição sem trabalho humano para creditar. É viável pelo `custom/`
  (`AsyncDispatcher` tem `prepend_mod_with`), mas só acumula histórico a partir do deploy.

**Classificação por conversa** (relatórios de volume), decidida agora e implementada com o
primeiro consumidor: avaliar **na data de corte**, que é
`GREATEST(until, primeiro desfecho da conversa)`, onde desfecho é opened, handoff,
`first_response` ou resolved. Conversa sem desfecho nenhum usa o estado atual (`pending`, sem
assignee, caixa com robô). Assim **só conversa não finalizada pode mudar de lado depois do
período fechar**, e ela congela no primeiro desfecho — que é justamente o que a regra do dono
do produto descreve.

**Custo:** os números divergem da Coraxy, onde conversa tocada por humano sem atribuição
conta como IA.

##### Fatia 4 — resolvida. Cockpit de Atendentes

Escolhida para abrir a onda por ser a única dos builders que **não toca na separação
robô × humano**, que segue em aberto — as outras quatro (origem, supervisor, fila, motivos)
dependem daquela decisão. A tela do Cockpit também não usa o filtro transversal, então ela
pode vir antes da decisão.

Duas decisões de escopo tomadas ao abrir os arquivos, ambas evitando duplicar conceito:

- **O `top_labels_builder` não será portado.** Ele existe na fonte para resolver o 429 de
  uma requisição por etiqueta, e o 4.17 já resolveu o mesmo problema com o
  `LabelSummaryBuilder`, que devolve `conversations_count` por etiqueta numa chamada só.
  Faltam apenas cor, ordenação e limite — apresentação. Portar criaria uma segunda fonte de
  verdade para "conversas por etiqueta". **Isso tira um builder e um endpoint da onda.**
- **O Cockpit não reusa o `AgentSummaryBuilder`**, apesar de repetir cinco métricas. Ele
  precisa contar conversas encerradas no período e devolver presença, time, CSAT e ranking;
  adaptar o builder do upstream mexeria num arquivo que o relatório de agentes também usa, e
  todo sync futuro pagaria o conflito. Os dois leem os mesmos `reporting_events`, então o
  risco de divergência é baixo — diferente dos casos de etiqueta e de bot, onde as
  definições eram de fato diferentes.

**Controller próprio, não o do upstream.** O `ReportsController` já estava exatamente no
teto do `Metrics/ClassLength` antes desta onda: a primeira ação adicionada estourou o cop. As
ações da onda passam a morar em `OperationReportsController`, com a URL inalterada
(`/reports/...` apontando para lá). Isso deixa espaço para as outras três ações e mantém o
arquivo do upstream intocado.

###### O que a revisão do `database-review` mudou

- **`updated_at` como data de encerramento caiu.** Era o ponto que o briefing já marcava como
  frágil, e o revisor confirmou com o argumento que faltava: além de qualquer edição da
  conversa (etiqueta, nota, reabertura) poluir a contagem, `(status, updated_at)` não tem
  índice nenhum, enquanto o evento de resolução cai num índice exato que já existe
  (`account_id, name, created_at`). "Encerradas no período" passou a sair do
  `reporting_events`, contando **conversa distinta** — reabrir e resolver de novo na mesma
  janela é uma só no volume do agente. Dois testes travam isso.
- **Duas migrations de índice.** `conversations (account_id, created_at)` e
  `csat_survey_responses (account_id, created_at, assigned_agent_id)`, ambas concorrentes. O
  detalhe não óbvio: o índice `(account_id, status, created_at)` que já existe **não** serve
  ao caminho padrão, porque sem igualdade em `status` o `created_at` não fica ordenado dentro
  do prefixo e o plano degenera para varrer a conta inteira.
- **Quatro varreduras viraram uma.** Resoluções, tempo de atendimento, primeira resposta e
  tempo de resposta saem de uma query com agregação condicional — o padrão que o upstream já
  usa em `Reports::RawDataSource`. O CSAT deixou de fazer `count` e `sum` separados. De 9
  queries por requisição para 6.

Confirmações do revisor, sem ação pendente: **não há N+1** (queries fixas, independentes do
número de agentes), e filtrar/ordenar em Ruby é adequado aqui, porque o conjunto é o quadro
de agentes da conta e todo campo vem de hash já agregado no banco.

**Débito registrado:** quando o rollup de relatórios for ligado (há um TODO em
`Reports::DataSource.for`), o `AgentSummaryBuilder` passa a ler a tabela agregada de graça e
este builder fica para trás — é a hora de revisitar a decisão de não reusar. O aviso está no
topo do arquivo, não só aqui.

**Não verificado:** os planos de execução reais. As afirmações de índice vêm da leitura do
`schema.rb` e do formato das cláusulas, não de `EXPLAIN ANALYZE` contra volume de produção.


##### Fatiamento proposto

Com a decisão tomada, o resto da onda passa a ser **vertical**: cada fatia leva builder,
ação, rota, request spec, service, composable, tela, i18n e validação renderizada — um
relatório por vez, como foi o Cockpit.

| # | Fatia | Estado |
|---|---|---|
| 4 | `cockpit_atendentes_builder` | ✅ |
| 11 | Tela do Cockpit | ✅ |
| 0a | Blindar o cockpit antes de virar molde (422 da janela, "encerradas" pelo evento, specs de autorização) | ✅ `66b004a759` |
| 0b | Classificador robô×humano (`Reports::ConversationOwnershipFinder`) + índice | ✅ `9298d63a95` |
| 0c | Front do Cockpit vira molde (service em `api/`, período e guarda reutilizáveis) | ✅ `f0157a85b4` |
| 1 | **Robô e humano** — resumo por tipo; primeiro consumidor do classificador | ✅ `db76829641` |
| 2 | **Monitoramento** — traz `active_conversations`; `in_progress` passa a incluir pending | ⏳ |
| 3 | **Recebidos e Efetuados** — traz a classificação por conversa; `LATERAL` na primeira mensagem | ⏳ |
| 4 | **Fila — Histórico** — mesma população nos três recortes; abandono só por resolução humana | ⏳ |
| 5 | **Motivos** — mistura as duas granularidades, por isso por último | ⏳ |
| — | ~~`top_labels_builder`~~ descartado (o 4.17 já resolve) | — |

As correções de performance de agosto **já estão aplicadas na fonte** nesta branch (subquery
no `handed_off`, escopo por conta no `first_message_table`) — o port precisa preservá-las, não
reinventá-las.

##### Fatia 1 — resolvida. Robô e humano

Primeiro consumidor do classificador, escolhido para abrir a sequência vertical porque só
depende da classificação **por resolução** — a parte mais simples e a que valida o predicado
com dado real antes de quatro telas dependerem dele.

Três decisões de escopo tomadas ao construir:

- **Tela própria (`/reports/ownership`), não dentro da "Visão geral".** O 4.17 já tem uma tela
  com esse nome, e o que a nossa responde é especificamente a divisão robô × humano. Herdar o
  nome criaria duas "Visão geral" no mesmo menu.
- **O `bot_summary` do upstream fica intocado.** Ele conta resolução do bot pelo evento
  `conversation_bot_resolved` sozinho, sem olhar se a conversa foi aberta ou atribuída antes.
  Mexer nele mudaria o número da tela de Robôs e pagaria conflito em todo sync. As duas telas
  convivem, e **o critério fica escrito na nossa** — dois números diferentes sem explicação
  viram desconfiança.
- **"TME do robô" não existe e não foi portado.** O `first_response` só é gravado para
  resposta humana, então por construção esse número seria sempre do humano. A fonte mostrava
  o campo, vazio.

O builder faz **uma passada por período** com `COUNT/AVG ... FILTER`, em vez de uma varredura
por métrica: o predicado do classificador roda dentro de cada uma, então repetir sai caro.

Verificado renderizado com dado semeado pelos fluxos reais (`qa_setup_ownership.rb`, não
versionado, que passa pelo `ReportingEventListener`): 7 encerradas pelo robô, 4 por gente
(3 abertas por humano + 1 transferida), fatia de 64%, tempo do robô 4min e tempo humano
37min30 — todos batendo com o seed.

**Aprendizado que vale para as próximas fatias:** o relatório filtra por
`reporting_events.created_at`, que é a hora em que a **linha foi inserida** (padrão do
upstream), não `event_end_time`. Spec que gera evento pelo listener precisa de `travel_to`,
senão tudo nasce "agora" e cai sempre na janela atual.


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

**5.6 Atribuição robô × humano — decidido pelo dono do produto.** ✅
Conversa finalizada sem nunca ter sido aberta nem atribuída é do robô. Implementado como
classificação por resolução sobre `reporting_events`, em
`Reports::ConversationOwnershipFinder`. O critério, as três divergências aceitas e as duas
decisões que vieram junto estão na Onda 5, em "O problema de atribuição robô × humano".

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
