# Ambiente local (Docker)

Como subir este fork do Chatwoot na máquina de desenvolvimento. Os comandos aqui são os
mesmos referenciados pelo [guia de sincronização](sincronizar-com-upstream.md).

> **Por que Docker e não `bundle exec rails s`?** O Chatwoot depende de Postgres com a
> extensão `pgvector` e de Redis com senha. O compose entrega os dois já configurados e
> na versão certa, o que evita divergência entre a máquina de cada um e produção.

---

## ⚠️ Existem dois stacks, e só um roda o seu código

Esta é a distinção mais importante desta página. Confundir os dois custa horas de
"editei e não mudou nada".

| | **Stack de produção** | **Stack de desenvolvimento** |
|---|---|---|
| Arquivos | `docker-compose.production.yaml` + `docker-compose.local.yaml` | `docker-compose.yaml` + `docker-compose.dev.local.yaml` |
| Nome do projeto | `chatwoot` (padrão) | `chatwoot-dev` (via `-p`) |
| Origem do código | `image: chatwoot/chatwoot:latest` — **imagem pronta do Docker Hub** | `build:` a partir de `docker/Dockerfile` |
| Código do repo | **NÃO** entra no container | Montado em `/app` — **roda o seu código** |
| Hot reload | Não | Sim (Rails + Vite) |
| `RAILS_ENV` | `production` | `development` |
| Banco | `chatwoot_production`, porta 5433 | `chatwoot_dev`, porta 5434 |
| Serve para | Ter o produto de pé, explorar, validar integrações | Escrever código |

Os dois usam a porta **3000** no host, então **não rodam ao mesmo tempo**. Pare um antes de
subir o outro.

### Como saber qual está rodando

O Dockerfile grava o commit de origem em `/app/.git_sha`
([docker/Dockerfile:90](../docker/Dockerfile)):

```bash
docker exec chatwoot-rails-1 cat /app/.git_sha   # stack de producao
git rev-parse HEAD                               # seu repo
```

No stack de produção esses dois SHAs **diferem** — é o sintoma de estar rodando o Chatwoot
oficial e não o fork. No stack de desenvolvimento a pergunta nem se aplica: o código é
montado do disco, então é sempre o que está na sua árvore de trabalho, inclusive alterações
não commitadas.

---

## Pré-requisitos

| Requisito | Observação |
|---|---|
| Docker Desktop rodando | No Windows depende de WSL2 — ver *Problemas conhecidos* |
| Arquivo `.env` na raiz do repo | **Não versionado** (`.gitignore:31`). Ver seção *O arquivo `.env`* |
| Arquivo `docker-compose.local.yaml` na raiz | Ver seção *O override local* |

Confirmar que o Docker responde antes de qualquer coisa:

```bash
docker ps
```

Se der `failed to connect to the docker API`, o daemon não está de pé — abra o Docker
Desktop e espere ele terminar de iniciar.

---

## Os dois arquivos de compose

O ambiente sobe com **dois** arquivos sobrepostos:

```
docker-compose.production.yaml   (versionado, vem do upstream)
docker-compose.local.yaml        (nosso, ajustes desta máquina)
```

O arquivo do upstream não roda como está nesta máquina, por dois motivos concretos:

1. **`POSTGRES_PASSWORD` vem vazio.** O `docker-compose.production.yaml` fixa
   `POSTGRES_PASSWORD=` (linha 48) com um comentário pedindo que você preencha. Como o
   `environment` do serviço tem precedência sobre o `env_file`, o Postgres subiria sem a
   senha que `rails` e `sidekiq` usam para conectar.
2. **A porta 5432 já está ocupada.** Existe um Postgres nativo instalado no host desta
   máquina. Publicar o container na 5432 falha no `up`.

O override resolve os dois:

```yaml
services:
  postgres:
    environment:
      - POSTGRES_DB=chatwoot_production
      - POSTGRES_USER=${POSTGRES_USERNAME}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    ports: !override
      - '127.0.0.1:5433:5432'
```

Detalhes que valem entender:

- **`!override` na chave `ports`.** Sem essa tag, o compose *soma* as listas dos dois
  arquivos e tentaria publicar na 5432 **e** na 5433 — o conflito continuaria. `!override`
  substitui a lista inteira.
- **A mudança de porta é só na publicação para o host.** `rails` e `sidekiq` falam com o
  Postgres pela rede interna do compose, no hostname `postgres`, porta 5432. Por isso
  `POSTGRES_HOST=postgres` no `.env` e nada muda para a aplicação. A 5433 serve para você
  conectar de fora (DBeaver, `psql`, etc.).
- **`POSTGRES_DB=chatwoot_production`** precisa bater com `POSTGRES_DATABASE` do `.env`.
  O upstream usa `chatwoot`; nós usamos `chatwoot_production`. Se divergir, o Rails sobe e
  quebra na primeira query.
- **Não mate o Postgres do host** para "liberar" a 5432. Ele é usado por outras coisas
  nesta máquina.

### O override local está no repositório

`docker-compose.local.yaml` e `docker-compose.dev.local.yaml` são commitados
(`a14c821848`) — os ajustes que carregam (senha vinda do `.env`, `restart: unless-stopped`)
valem para qualquer máquina. A única parte específica desta máquina são as portas de
publicação (5433/5434/5436/6380/6381 etc., escolhidas para não colidir com serviços já
rodando aqui) — se colidir na sua, ajuste as portas localmente e não commite essa mudança
por cima, para não empurrar o conflito para quem já está com o ambiente de pé.

---

## O arquivo `.env`

Não é versionado. Para criar um novo, parta do exemplo do upstream:

```bash
cp .env.example .env
```

As variáveis que precisam de atenção nesta configuração:

| Variável | Valor local | Por quê |
|---|---|---|
| `POSTGRES_HOST` | `postgres` | Hostname do serviço na rede do compose, não `localhost` |
| `POSTGRES_USERNAME` | `postgres` | Consumido também pelo override, via `${POSTGRES_USERNAME}` |
| `POSTGRES_PASSWORD` | *(defina uma)* | Consumido pelo override; se vazio, o Postgres sobe sem senha e o Rails não conecta |
| `POSTGRES_DATABASE` | `chatwoot_production` | Precisa bater com `POSTGRES_DB` do override |
| `REDIS_URL` | `redis://:<senha>@redis:6379` | A senha embutida na URL tem que ser igual a `REDIS_PASSWORD` |
| `REDIS_PASSWORD` | *(defina uma)* | O comando do serviço redis usa `--requirepass` |
| `SECRET_KEY_BASE` | *(gerar)* | `openssl rand -hex 64` |
| `ACTIVE_RECORD_ENCRYPTION_*` | *(gerar as 3)* | `rails db:encryption:init` gera o trio |
| `FRONTEND_URL` | `http://localhost:3000` | Usado nos links dos e-mails e nos redirects |
| `RAILS_ENV` / `NODE_ENV` | `production` | A imagem `chatwoot/chatwoot:latest` é build de produção |

> Depois de todo sync com o upstream, compare o seu `.env` com o `.env.example` novo.
> Releases às vezes exigem variáveis novas, e a falta delas só aparece em runtime.

---

## Primeira execução

Na primeira vez o banco está vazio, e **o entrypoint não roda migrations**. Olhando
`docker/entrypoints/rails.sh`: ele espera o Postgres aceitar conexão, roda `bundle install`
e chama o comando do container — nada de `db:migrate`. Se pular este passo, o Rails sobe e
falha em toda requisição com erro de relação inexistente.

```bash
# 1. criar o banco, carregar o schema e semear os dados iniciais
docker compose -f docker-compose.production.yaml -f docker-compose.local.yaml \
  run --rm rails bundle exec rails db:chatwoot_prepare

# 2. subir tudo
docker compose -f docker-compose.production.yaml -f docker-compose.local.yaml up -d
```

`db:chatwoot_prepare` é uma task do próprio Chatwoot (`lib/tasks/db_enhancements.rake`).
Ela olha se a tabela `ar_internal_metadata` existe: se **não** existe, carrega o schema e
roda os seeds; se existe, roda só as migrations pendentes. Ou seja, é o mesmo comando para
o primeiro `up` e para depois de um sync com o upstream — rodar de novo não quebra nada.

Rodando de fora da pasta do repositório, acrescente `--project-directory`:

```bash
docker compose --project-directory "d:/Documetos/baixar imagem chatwoot/chatwoot" \
  -f "d:/Documetos/baixar imagem chatwoot/chatwoot/docker-compose.production.yaml" \
  -f "d:/Documetos/baixar imagem chatwoot/chatwoot/docker-compose.local.yaml" up -d
```

O `--project-directory` importa: é a partir dele que o compose resolve o `env_file: .env`
e o nome do projeto (o prefixo dos containers e dos volumes). Sem ele, o compose usa o
diretório do primeiro `-f` — e um nome de projeto diferente criaria **volumes novos**, ou
seja, um banco vazio.

### Validar que subiu

```bash
curl http://localhost:3000/api
```

Resposta esperada:

```json
{"version":"4.17.1","queue_services":"ok","data_services":"ok"}
```

- `data_services: ok` → Postgres respondendo
- `queue_services: ok` → Redis respondendo

Qualquer um deles fora de `ok` aponta o serviço a investigar. Com `ENABLE_ACCOUNT_SIGNUP=true`
no `.env`, a primeira conta é criada pela própria tela de cadastro em
http://localhost:3000/app/auth/signup.

---

## Comandos do dia a dia

Como a linha do compose é longa, vale um alias na sessão do terminal:

```bash
# bash / WSL
alias cwc='docker compose -f docker-compose.production.yaml -f docker-compose.local.yaml'
```

```powershell
# PowerShell
function cwc { docker compose -f docker-compose.production.yaml -f docker-compose.local.yaml @args }
```

Com o alias no lugar:

```bash
cwc up -d                    # subir em background
cwc ps                       # o que está rodando
cwc logs -f rails            # acompanhar o log do Rails
cwc logs -f sidekiq          # acompanhar os jobs
cwc restart rails            # reiniciar só a aplicação
cwc down                     # parar (volumes preservados)

cwc run --rm rails bundle exec rails c          # console Rails
cwc run --rm rails bundle exec rails db:migrate # migrations novas
cwc run --rm rails bundle exec rspec spec/...   # testes
```

`run --rm` cria um container descartável em vez de usar o que está de pé. É o certo para
tarefas pontuais: não interfere no processo do servidor e não deixa container parado para
trás.

### Conectar no banco de fora

```bash
psql -h localhost -p 5433 -U postgres -d chatwoot_production
```

Note a **5433** — a 5432 é o Postgres nativo do host, outro banco.

---

# Stack de desenvolvimento

Este é o stack que **roda o código deste repositório**, com hot reload. Use-o para
escrever código; o de produção acima serve para ter o produto de pé.

## Arquivos e por que existe um override

O `docker-compose.yaml` (versionado, do upstream) já monta o código local e sobe um
servidor Vite para o front. Ele não roda como está nesta máquina, por quatro motivos:

1. **`POSTGRES_PASSWORD` vazio** — mesmo problema do compose de produção (linha 95).
2. **Porta 5432** — ocupada pelo Postgres nativo do host. O override move para **5434**
   (5433 já é do stack de produção).
3. **Volumes montados no caminho errado.** O upstream monta `postgres:/data/postgres`, mas
   o `PGDATA` da imagem é `/var/lib/postgresql/data`. Do jeito dele o volume não guarda
   nada e **o banco some no primeiro `down`**. Mesmo erro no redis (`redis:/data/redis`,
   sendo que o caminho certo é `/data`). O override corrige os dois.
4. **Portas expostas em `0.0.0.0`** — o compose do upstream publica sem prefixo de host,
   deixando Postgres, Redis e Mailhog acessíveis pela rede local. O override prende tudo
   em `127.0.0.1`.

Além disso, o override aponta o banco de dev para `chatwoot_dev`. Sem isso o
`POSTGRES_DATABASE=chatwoot_production` do `.env` faria o ambiente de desenvolvimento
escrever num banco com nome de produção — confuso na hora de depurar.

> **Sempre com `-p chatwoot-dev`.** Sem o `-p`, o Compose deriva o nome do projeto do nome
> da pasta (`chatwoot`) — o mesmo do stack de produção — e os dois passam a disputar os
> mesmos containers e volumes. Subir um destruiria o outro.

## Primeira execução

### 1. Construir a imagem base — nesta ordem

`docker/dockerfiles/rails.Dockerfile` e `vite.Dockerfile` começam com
`FROM chatwoot:development`. Essa imagem não existe em registry nenhum: ela é produzida
pelo serviço `base`, e precisa ser construída **antes**. Pular esta etapa dá:

```
pull access denied, repository does not exist: chatwoot:development
```

```bash
docker compose -p chatwoot-dev -f docker-compose.yaml -f docker-compose.dev.local.yaml \
  build base
```

Demora bastante — instala as gems incluindo os grupos `development` e `test` (o build de
produção os exclui) e as dependências JS. É uma vez só; depois o cache do Docker cobre.

### 2. Construir rails e vite

```bash
docker compose -p chatwoot-dev -f docker-compose.yaml -f docker-compose.dev.local.yaml \
  build rails vite
```

### 3. Preparar o banco de desenvolvimento

O banco de dev é **separado** do de produção (volume `postgres_dev_data`), então começa
vazio e precisa do prepare — e o entrypoint continua não rodando migrations:

```bash
docker compose -p chatwoot-dev -f docker-compose.yaml -f docker-compose.dev.local.yaml \
  run --rm rails bundle exec rails db:chatwoot_prepare
```

### 4. Subir

Pare o stack de produção antes — os dois disputam a porta 3000:

```bash
docker compose -f docker-compose.production.yaml -f docker-compose.local.yaml down
docker compose -p chatwoot-dev -f docker-compose.yaml -f docker-compose.dev.local.yaml up -d
```

## O que roda onde

| Serviço | URL | Para quê |
|---|---|---|
| Rails | http://localhost:3000 | A aplicação |
| Vite | http://localhost:3036 | Servidor de assets do front (não abra direto) |
| Mailhog | http://localhost:8025 | Caixa de entrada falsa — todo e-mail enviado cai aqui |
| Postgres | `localhost:5434` | Banco `chatwoot_dev` |
| Redis | `localhost:6380` | Filas do Sidekiq |

O **Mailhog** é a diferença mais útil do ambiente de dev: convites de agente, reset de
senha e notificações não saem para a internet, aparecem na interface dele.

## Hot reload — o que recarrega sozinho e o que não

| Alteração | Precisa reiniciar? |
|---|---|
| `.rb` em `app/` (controllers, models, services) | Não — o Rails recarrega a cada request |
| `.vue`, `.js` em `app/javascript/` | Não — o Vite atualiza o navegador |
| `config/`, `Gemfile`, initializers | **Sim** — `restart rails sidekiq` |
| Migration nova | **Sim** — rodar `db:migrate` e reiniciar |

```bash
# alias sugerido para a sessao
alias cwd='docker compose -p chatwoot-dev -f docker-compose.yaml -f docker-compose.dev.local.yaml'

cwd logs -f rails
cwd restart rails sidekiq
cwd run --rm rails bundle exec rails c
cwd run --rm rails bundle exec rspec spec/models/account_spec.rb
cwd down
```

## Alternar entre os dois stacks

```bash
# ir para desenvolvimento
docker compose -f docker-compose.production.yaml -f docker-compose.local.yaml down
cwd up -d

# voltar para producao
cwd down
docker compose -f docker-compose.production.yaml -f docker-compose.local.yaml up -d
```

`down` sem `-v` preserva os dados dos dois lados — são volumes distintos, um stack não
apaga o banco do outro.

---

## Resetar o ambiente

`down` sozinho preserva os dados; os volumes são nomeados (`postgres_data`, `redis_data`,
`storage_data`) e sobrevivem ao container.

```bash
cwc down            # para tudo, mantém o banco
cwc down -v         # DESTRÓI os volumes: banco, redis e uploads
```

Depois de `down -v` o ambiente volta ao zero — é preciso rodar `db:chatwoot_prepare` de
novo. Só use quando quiser exatamente isso.

---

## Problemas conhecidos

**`failed to connect to the docker API ... dockerDesktopLinuxEngine`**
O Docker Desktop não está rodando. Abra e espere inicializar.

**Docker Desktop não inicia (Windows)**
Depende do WSL2. Nesta máquina foi preciso habilitar dois componentes num terminal
**elevado** e reiniciar:

```powershell
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
```

**`port is already allocated` na 5432**
O override não foi carregado — confira se os **dois** `-f` estão na linha de comando. Só o
`docker-compose.production.yaml` tenta a 5432, que está ocupada pelo Postgres do host.

**`password authentication failed for user "postgres"`**
`POSTGRES_PASSWORD` do `.env` e a senha com que o volume do Postgres foi inicializado estão
diferentes. A senha só é aplicada na **criação** do volume; mudá-la depois no `.env` não
altera o banco existente. Ou volte a senha antiga no `.env`, ou recrie o volume com
`cwc down -v` (perde os dados).

**Rails sobe mas toda página dá erro de relação inexistente**
Faltou o `db:chatwoot_prepare` da primeira execução.

**Container em restart loop**
`cwc logs rails` mostra a causa real. Depois de um sync com o upstream, quase sempre é
`bundle install` ou migration pendente — ver o checklist em
[sincronizar-com-upstream.md](sincronizar-com-upstream.md).
