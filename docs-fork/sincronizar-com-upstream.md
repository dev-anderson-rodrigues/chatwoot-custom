# Sincronizar com o Chatwoot oficial (upstream)

Este fork acompanha o repositório público do Chatwoot. Este documento descreve como trazer
as atualizações oficiais sem perder as customizações.

> **Por que `docs-fork/`?** Esta pasta não existe no repositório oficial. Arquivos aqui
> nunca geram conflito de merge, porque conflito só acontece quando os dois lados editam
> o *mesmo caminho*. Toda documentação nossa mora aqui.

---

## Como os remotes estão configurados

```
origin    -> github.com/dev-anderson-rodrigues/chatwoot-custom   (fetch + push)
upstream  -> github.com/chatwoot/chatwoot                        (somente fetch)
```

O push para o `upstream` está **desabilitado de propósito** (a URL de push é
`DISABLED_use_origin`). Isso impede o envio acidental de código proprietário para o
repositório público do Chatwoot. Não reative isso.

Conferir a qualquer momento:

```bash
git remote -v
```

Se o `upstream` não existir (clone novo da equipe):

```bash
git remote add upstream https://github.com/chatwoot/chatwoot.git
git remote set-url --push upstream DISABLED_use_origin
```

---

## Fluxo padrão

### 1. Comece com a árvore limpa

```bash
git status          # não deve haver alterações pendentes
git checkout develop
git pull origin develop
```

Se houver trabalho em andamento, faça commit ou `git stash` antes. Um merge sobre árvore
suja mistura as suas mudanças com as do upstream e vira um nó difícil de desfazer.

### 2. Veja o que mudou antes de puxar

```bash
git fetch upstream
git log --oneline develop..upstream/develop          # commits novos do Chatwoot
git diff --stat develop..upstream/develop            # arquivos afetados
```

Vale checar o changelog oficial para mudanças que quebram compatibilidade:
https://github.com/chatwoot/chatwoot/releases

### 3. Faça o merge numa branch, nunca direto na develop

```bash
git checkout -b sync/upstream-$(date +%Y-%m-%d)
git merge upstream/develop
```

Merge numa branch separada permite abandonar tudo (`git merge --abort` ou apagar a branch)
se der errado, sem sujar a `develop`.

> **Merge, não rebase.** O histórico do Chatwoot tem milhares de commits. Rebase reescreve
> os *seus* commits em cima deles, o que força push com `--force` e quebra o repositório
> de quem já baixou. Use merge.

### 4. Resolva os conflitos

Ver o que conflitou:

```bash
git status --short | grep '^UU'
```

Depois de resolver cada arquivo:

```bash
git add <arquivo>
git commit                  # mensagem de merge já vem preenchida
```

Para desistir e voltar ao estado anterior:

```bash
git merge --abort
```

### 5. Valide antes de integrar

Rode o checklist da seção *Depois do merge* abaixo. Só então:

```bash
git checkout develop
git merge --no-ff sync/upstream-AAAA-MM-DD
git push origin develop
```

---

## Onde os conflitos são mais prováveis

| Arquivo | Por que conflita | Como resolver |
|---|---|---|
| `db/schema.rb` | Gerado automaticamente; conflita sempre que os dois lados criam migrations | Ver seção específica abaixo |
| `Gemfile` / `Gemfile.lock` | Se adicionarmos gems | Resolver o `Gemfile` na mão; **regerar** o `.lock` com `bundle install` |
| `package.json` / `pnpm-lock.yaml` | Se adicionarmos dependências JS | Resolver o `package.json`; regerar o lock com `pnpm install` |
| `config/routes.rb` | Rotas novas nossas e deles no mesmo arquivo | Manter os dois blocos |
| `config/locales/*.yml` e `app/javascript/dashboard/i18n/` | Traduções que alteramos | Manter os dois; atenção a chaves duplicadas |
| Componentes Vue que customizarmos | Edição direta em arquivo do upstream | Ver *Como reduzir conflitos* |

### `db/schema.rb` — caso especial

Nunca resolva esse arquivo na mão. Ele é **gerado**. Aceite a versão do upstream e deixe o
Rails regerar rodando as migrations (as nossas e as deles):

```bash
git checkout --theirs db/schema.rb
git add db/schema.rb
# depois de fechar o merge, regenerar de verdade:
docker compose ... run --rm rails bundle exec rails db:migrate
git add db/schema.rb && git commit --amend --no-edit
```

Confira no diff final que **nenhuma tabela nossa sumiu** do schema.

---

## Depois do merge: checklist

Nesta ordem — um passo depende do anterior:

```bash
# 1. dependências (se Gemfile.lock ou pnpm-lock.yaml mudaram)
docker compose ... run --rm rails bundle install
pnpm install

# 2. migrations novas do upstream
docker compose ... run --rm rails bundle exec rails db:migrate

# 3. subir e validar
docker compose ... up -d
curl http://localhost:3000/api          # deve retornar queue_services e data_services "ok"
```

Verificar também:

- [ ] `docker compose ... logs rails` sem erro de boot
- [ ] `docker compose ... logs sidekiq` processando jobs
- [ ] As telas que customizamos continuam funcionando (o merge pode ter revertido ajuste nosso)
- [ ] Testes relevantes: `bundle exec rspec spec/<área tocada>`
- [ ] `.env` — comparar com `.env.example` do upstream; releases novas às vezes exigem
      variáveis novas, e a ausência delas só aparece em runtime

Os comandos completos do compose estão em [ambiente-local.md](ambiente-local.md).

---

## Comportamento do upstream de que dependemos

Conflito de merge o git avisa. **Isto aqui é o contrário: são coisas que continuam
compilando e passando no boot, mas mudam número de relatório em silêncio.** Depois de cada
sync, rodar os specs citados — eles existem para travar exatamente este contrato.

| Dependemos de | Onde, no upstream | Quebra se | Spec que avisa |
|---|---|---|---|
| `conversation_bot_resolved` só é gravado com `inbox.active_bot?` e sem `outgoing` de `User` | `app/listeners/reporting_event_listener.rb`, `create_bot_resolved_event` | Mudarem a condição, o nome do evento, ou pararem de copiar `event_end_time` do gêmeo | `spec/finders/reports/conversation_ownership_finder_spec.rb` |
| `conversation_opened` gravado em toda transição para `open` | mesmo listener, `conversation_opened` | Removerem o evento ou passarem a gravá-lo também no create | idem |
| `first_response` marca resposta humana, inclusive o eco do celular | mesmo listener, `first_reply_created` | Mudarem quem conta como primeira resposta | idem |
| `conversation_resolved.user_id` = assignee **no instante** da resolução | mesmo listener, linha do `user_id` | Passarem a gravar quem executou a ação em vez do assignee | `spec/builders/v2/reports/cockpit_atendentes_builder_spec.rb` |

Por que isso importa: toda a separação robô × humano da suíte de relatórios é construída
sobre esses quatro fatos, e nenhum deles é uma API pública do Chatwoot — são detalhes de
implementação que eles podem mudar sem aviso. O critério completo está em
`plano-port-coraxy.md`, na Onda 5.

---

## Como reduzir conflitos no futuro

A regra que mais economiza trabalho: **adicionar arquivos novos custa zero em merge;
editar arquivos do upstream custa em todo sync.**

Na prática:

1. **Código novo em pastas nossas.** Ex.: `app/services/agents_ia/`, `app/javascript/dashboard/custom/`.
   Nada que o upstream cria vai colidir com esses caminhos.
2. **Preferir estender a sobrescrever.** Um componente Vue novo que envolve o original
   sobrevive a atualizações; um componente original editado conflita a cada mudança deles.
3. **Quando editar arquivo do upstream for inevitável**, marque a alteração:
   ```ruby
   # [FORK] motivo da alteração
   ```
   Assim `git grep '\[FORK\]'` lista toda a superfície de customização — que é exatamente
   a lista de onde procurar problema depois de um sync.
4. **Commits separados.** Não misture customização nossa com merge do upstream no mesmo commit.
5. **Sincronize com frequência.** Cinco merges pequenos ao longo de meses são muito mais
   fáceis que um merge gigante de um ano acumulado.

---

## Restrição de licença — leia antes de sincronizar

A pasta `enterprise/` **não é open source**. A licença
(`enterprise/LICENSE`) permite copiar e modificar **apenas para desenvolvimento e teste**;
**uso em produção exige assinatura Chatwoot Enterprise**. O restante do código é MIT.

Como este fork é base de um produto comercial, isso precisa de decisão: remover a pasta
`enterprise/` ou contratar a licença. Enquanto não for decidido, não construa
funcionalidade de produto em cima do que está lá dentro.

---

## Referência rápida

```bash
git fetch upstream                                   # buscar novidades
git log --oneline develop..upstream/develop          # o que mudou
git checkout -b sync/upstream-$(date +%Y-%m-%d)      # branch de sync
git merge upstream/develop                           # merge
git merge --abort                                    # desistir
git grep '\[FORK\]'                                  # listar customizações
```
