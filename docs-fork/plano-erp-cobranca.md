# Plano — Integração nativa com ERP, painel do cliente e cobrança (Onda 8)

Estado: **plano para aprovação, nada implementado.** Criado em 2026-09-21 a pedido do dono.
Contexto e decisões anteriores: `plano-port-coraxy.md` (Ondas 7, 8 e 9).

## 0. O que estamos construindo

Para quem atende clientes pelo chat **e tem um ERP**: o registro que está no ERP aparece
**direto na conversa**, e o que o operador registra na conversa volta para o ERP. O operador
não sai do chat para saber se o cliente deve, para registrar uma promessa, abrir um chamado
ou disparar uma cobrança.

Princípio que decide os casos duvidosos: **o ERP é a fonte da verdade; o chat é a superfície
de trabalho.** O chat nunca "corrige" o ERP por conta própria, e uma escrita só conta como
feita quando o ERP confirmou.

> ⚠️ **Os prints que embasam este plano trazem dados reais de clientes** (nome, CPF, telefone,
> valores). Nada disso foi copiado para este documento. Recomendo **não versionar esses
> prints** no repositório e usar dado fictício em qualquer material de QA.

## 1. Referência de produto: o que os prints mostram → o que vira nativo

| Elemento no print | Capacidade nativa | Onde vive no Chatwoot | Fatia |
|---|---|---|---|
| Cartão do cliente (nome, telefone, documento, contrato, faturas em aberto, valor, dias vencidos) | Painel do cliente na conversa; lista de inadimplentes | `ContactPanel` + tela de lista | F2, F4 |
| Modal → aba **Faturas** (contrato, vencimento, valor, status) | Aba de faturas do painel | painel | F2 |
| Modal → aba **Promessas** + "Nova promessa" (data prometida, valor opcional) | Registrar e listar promessas | painel + ERP | F3 |
| Modal → aba **Atendimentos** + "Novo atendimento" (canal, resultado, descrição) | Registrar atendimento fora do chat (ligação etc.); conversas do chat entram sozinhas | painel + ERP | F3 |
| Botão **Disparar** e "63 cobranças enviadas / último disparo" | Disparo de cobrança por campanha; histórico por cliente | Campanhas (Onda 7) | F5 |
| KPIs (inadimplência %, responderam, retorno em cobrança) | Relatórios de cobrança | Relatórios (molde da Onda 5) | F6 |
| Aba **Inadimplência** (inadimplência × pagamentos por mês; funil cobrados → responderam → convertidos) | idem | Relatórios | F6 |
| Aba **Promessas** (cumpridas/quebradas/pendentes/canceladas; previsão de recebimento) | idem | Relatórios | F6 |
| Aba **Recuperação** (faturas vencidas por faixa; conversão por faixa) | Relatório + **segmentação** para o disparo | Relatórios + Campanhas | F5, F6 |
| Aba **Disparos & Respostas** (disparos × respostas; taxa mensal) | idem | Relatórios | F6 |
| Aba **Campanhas** | Analytics de campanha (já existe para WhatsApp no 4.17) | Campanhas | Onda 7 |
| Aba **Análise** (perfil de pagamento: pontual, atrasa 1–15d, 15–30d, crônico) | Perfil derivado do histórico de pagamento | Relatórios + segmento | F4, F6 |

## 2. O que já existe no Chatwoot e reaproveitamos (verificado no código)

- **Hook de integração por conta** (`Integrations::Hook`, `hook_type: account`). O segredo
  vai em `access_token`, que é **cifrado** (`encrypts ... deterministic`) — mas **só se as chaves
  de criptografia estiverem configuradas** (há um guard `Chatwoot.encryption_configured?`). O
  `settings` (jsonb) **não é cifrado**: **nenhuma credencial do ERP pode ir lá.** Pré-requisito:
  confirmar que a criptografia está ativa em produção.
- **Molde da integração com Shopify:** entrada em `config/integration/apps.yml`, controller que
  consulta o sistema externo por contato (`shopify_controller#orders`), e um acordeão no
  `ContactPanel.vue` (`ShopifyOrdersList.vue`) ligado por `integrations/getIntegration`. O painel
  do ERP segue esse desenho — com a diferença de que o Shopify acha o cliente por
  e-mail/telefone **a cada consulta e não guarda o vínculo**; aqui o vínculo tem de ser
  persistido e auditável.
- **Painel de Aplicativos** (Dashboard Apps, Onda 1.2): embute uma URL externa na conversa.
  Caminho barato para um primeiro painel, mas as variáveis são de conta/usuário, não do contato.
- **Campanhas + `campaign_recipients`** (rastreio de entrega por destinatário) — Onda 7.
- **Relatórios:** builders + telas + composables da Onda 5 (mesmo molde).
- **Audit logs enterprise** (`Enterprise::Audit::*`) para trilha de escrita.
- **Contato:** `custom_attributes` (jsonb), etiquetas. **Cuidado com `identifier`:** é único por
  conta e é usado pela identificação do widget/SDK — **não usar para guardar CPF.**
- **Mensagens de atividade** (`message_type: activity`): é o que faz "o registro aparecer
  direto na conversa" ("Promessa registrada para 25/09 por Fulano").

**O que NÃO existe e precisa ser construído:** tabela de vínculo contato↔cliente do ERP;
espelho de dados do ERP; segmentação por regra (a audiência de campanha hoje é só por
etiqueta); **limite de vazão para chamadas externas** (não há `sidekiq-throttled` neste
repositório — a Coraxy tinha um inicializador para isso, ainda não portado).

## 3. Arquitetura

### 3.1 Camadas

```
Painel (Vue)  ─►  API do Chatwoot  ─►  Serviços de domínio  ─►  Adaptador do ERP  ─►  ERP
                                              │
                        jobs de sync ─►  Espelho local ─►  Relatórios / Segmentos / Campanha
```

Nada acima do adaptador sabe qual ERP está por baixo. **Trocar ou somar um ERP não pode
mexer no painel, na campanha nem nos relatórios.**

### 3.2 Contrato do adaptador

Um adaptador por ERP, com uma interface única e **capacidades declaradas** (nem todo ERP
escreve, nem todo ERP tem assinatura):

- leitura: buscar cliente (por documento, por telefone), contratos, faturas em aberto,
  histórico de pagamento, chamados;
- listagem incremental para sincronismo (inadimplentes, alterados desde X);
- escrita: registrar promessa, registrar atendimento, abrir chamado;
- (F7) assinatura de contrato.

O **IXC é o primeiro adaptador.** O segundo (F8) é o teste de que a abstração é real.

### 3.3 Credenciais e multi-tenant

Cada empresa é uma **conta** com o **seu** ERP. Um hook de conta (`app_id` do ERP) guarda o
provedor e o endereço em `settings` e o token em `access_token`. Dado e credencial **nunca
cruzam contas**; isolamento tem teste próprio (spec que tenta ler cliente de outra conta).

### 3.4 Vínculo contato ↔ cliente do ERP

Tabela própria (ex.: `erp_customer_links`): conta, contato, provedor, id externo, documento
normalizado, **como casou** (`documento`, `telefone`, `manual`), estado (`vinculado`,
`ambíguo`, `sem correspondência`) e quem/quando confirmou.

- Chave preferencial: **CPF/CNPJ**; telefone é fallback (e é fraco: família/empresa
  compartilham número).
- **Ambíguo e não achado são estados de primeira classe**, com uma tela de resolução manual —
  chutar o primeiro resultado numa cobrança é o pior erro possível.
- Um contato pode ter mais de um contrato; um cliente do ERP pode aparecer em mais de um
  contato (mesma pessoa, dois canais). O modelo tem de suportar as duas direções.

### 3.5 Dados: leitura ao vivo **e** espelho — os dois, com papéis diferentes

- **Painel (conversa):** leitura **ao vivo com cache curto.** Fatura desatualizada numa
  cobrança é pior que uma consulta lenta. Mostra sempre "dados de HH:MM".
- **Espelho local** (tabelas sincronizadas de forma incremental): necessário porque os
  relatórios e a segmentação **agregam milhares de faturas** — não dá para fazer isso por
  chamada ao vivo. Sem espelho não existe "faturas vencidas por faixa" nem "audiência: +120
  dias sem promessa".
- **Atalho para a primeira entrega de cobrança:** o sync grava **etiquetas** (faixa de atraso)
  e **atributos** (`valor_em_aberto`, `vencimento_mais_antigo`) no contato. Isso reaproveita a
  audiência por etiqueta e as variáveis Liquid da campanha **sem** esperar o espelho completo.

### 3.6 Escrita: o ERP primeiro, e nunca perder o registro

Promessa e atendimento nascem no chat. Ordem: **gravar no ERP → confirmar → espelhar → mostrar
na conversa como atividade.** Se o ERP estiver fora, o registro vai para uma **caixa de saída
com retry** e **chave de idempotência** (o mesmo registro não pode virar duas promessas no
ERP). O operador vê o estado ("pendente de envio ao ERP"), não um erro seco.

### 3.7 Resiliência e limites

Timeout curto em toda chamada, retry com backoff para 429/5xx respeitando `Retry-After`, **limite
por conta** (balde de tokens em Redis — não há biblioteca pronta no repo), e degradação
visível: se o ERP cair, o painel mostra o último dado conhecido com aviso, não uma tela vazia.
Nenhuma chamada ao ERP sem timeout dentro de requisição do operador.

### 3.8 Segurança, LGPD e regras de cobrança

- Dado financeiro e CPF: **permissão por papel** (quem vê valor de fatura; agente x supervisor),
  CPF **mascarado por padrão**, e **trilha de auditoria** de: vínculo manual, promessa,
  atendimento, disparo. Decidir se **visualização** também é auditada (custa volume, protege
  contra bisbilhotice).
- Minimização: espelhar só o que os relatórios, a segmentação e as variáveis usam.
- Disparo de cobrança: **opt-out**, horário permitido e **limite de frequência por cliente**
  (o print mostra 63 cobranças para um só cliente — é o tipo de coisa que gera reclamação).
- **Validar com jurídico** antes de disparar em escala: regras de cobrança (CDC, art. 42 —
  não expor nem constranger o devedor) e política de mensagens de cobrança do WhatsApp.
  Isto é um lembrete de que a validação é necessária, **não** uma orientação jurídica.

## 4. Fatias

Cada fatia entrega algo usável, tem verificação própria e passa pelas revisões de
especialista (banco, segurança, integração, frontend) sobre a **implementação final** — o
mesmo rigor da Onda 5.

| # | Fatia | Depende de | Verificação |
|---|---|---|---|
| **F0** | **Fundação:** decisões da seção 6, **acesso ao ambiente de teste do IXC**, contrato de dados (seção 5), confirmar criptografia de segredos em produção | — | Decisões registradas; token de teste funcionando |
| **F1** | **Conector IXC somente leitura** + hook por conta + **vínculo** (casar por documento/telefone, ambíguo, resolução manual) | F0 | Specs com resposta gravada do IXC; isolamento entre contas; revisão de segurança dos segredos |
| **F2** | **Painel do cliente na conversa:** resumo (valor em aberto, dias vencidos), faturas, contratos; estados carregando/erro/vazio/não vinculado | F1 | Verificação renderizada em tema claro/escuro, desktop e 375px; ERP fora do ar |
| **F3** | **Escrita controlada:** nova promessa, novo atendimento (e abertura de chamado, se o dono quiser), com **atividade na conversa**, caixa de saída, idempotência, permissão e auditoria | F1, F2 | Teste de reenvio sem duplicar; ERP fora e volta; revisão de segurança |
| **F4** | **Espelho + sincronização incremental**; etiquetas/atributos derivados (faixa de atraso, valor em aberto, perfil de pagamento) | F1 | Sync idempotente; custo de consulta (`EXPLAIN`); revisão de banco |
| **F5** | **Disparo de cobrança:** segmento por regra (faixa, valor, sem promessa), variáveis do ERP, **limite de frequência e opt-out**, histórico por cliente | F4, **Onda 7 (fatias 2 e 3)** | Nenhum envio real sem o endurecimento de volume; revisão de integração |
| **F6** | **Relatórios de cobrança** (as seis abas do print) no molde da Onda 5 | F4, F5 | Números conferidos contra o ERP com dado semeado; tela renderizada |
| **F7** | **Assinatura de contrato** (seção 5) | F3 | Fluxo completo em ambiente de teste do provedor |
| **F8** | **Segundo ERP/CRM** pelo mesmo adaptador | F1–F3 | Nenhuma alteração no painel, na campanha nem nos relatórios |

Ordem recomendada: **F0 → F1 → F2** entrega valor cedo e sem risco (só leitura). **F3** vem
antes de qualquer disparo. **F5 não começa antes do endurecimento de volume da Onda 7** (campanha
presa em `processing`, sem retry, sem timeout — ver plano principal).

## 5. Assinatura de contrato (pedido do dono em 2026-09-21)

**Ideia:** pegar o contrato do cliente no ERP, mandar o link de assinatura pela conversa,
acompanhar o estado e gravar o resultado de volta no ERP.

- **Achado:** o IXC tem produto próprio de assinatura, o **IXC Assina**, com API publicada — é o
  candidato natural quando o ERP é IXC. Existem também provedores independentes (Clicksign,
  D4Sign, ZapSign, Autentique, DocuSign…); **não pesquisei nenhuma dessas APIs**.
- **Desenho:** entra como **capacidade do adaptador** (`assinatura`), pelo mesmo motivo do
  ERP: o provedor de assinatura pode ser o do ERP ou outro, e o chat não deve saber.
- **Estados:** rascunho → enviado → visualizado → assinado / recusado / expirado, atualizados
  por **webhook** do provedor e refletidos como atividade na conversa.
- **Decisões que dependem do dono:** qual provedor (só o do ERP, ou vários); **validade
  jurídica** exigida (assinatura eletrônica simples, avançada ou com certificado ICP-Brasil —
  Lei 14.063/2020) — **validar com jurídico**; onde o PDF assinado e a trilha de evidência
  ficam guardados; quem pode enviar contrato.

## 6. Decisões abertas (do dono)

1. **Acesso ao IXC** para desenvolver: endereço, usuário, token e um **ambiente de teste** (não
   desenvolver contra produção).
2. **Primeira versão do painel:** só leitura (F2) ou já promessa e atendimento (F3)? Abertura
   de chamado entra agora ou depois?
3. **Chave do vínculo:** CPF/CNPJ do contato. E o que fazer quando o contato não tem documento
   (pedir ao operador? buscar por telefone e confirmar com o cliente?).
4. **Regras de negócio dos relatórios** — os números do print dependem delas e ainda não
   estão definidas:
   - *Respondeu*: mensagem recebida em até quantos dias depois do disparo?
   - *Convertido / retorno em cobrança*: fatura paga em até quantos dias depois do disparo, e
     qual disparo leva o crédito quando houve vários?
   - *Promessa cumprida / quebrada*: paga até a data prometida (com tolerância de quantos dias)?
     Quem cancela uma promessa?
   - *Perfil de pagamento*: os cortes (pontual, 1–15d, 15–30d, crônico) valem como estão?
5. **Régua de cobrança automática** (lembrete antes do vencimento, +1, +7…): fora deste plano
   por enquanto — é um motor de fluxo, não um disparo. O print mostra "follow-ups abertos", então
   vale decidir se entra numa onda própria.
6. **Permissões:** quais papéis veem valor e documento; quem pode disparar cobrança.
7. **Atendimento fora do chat:** o histórico de "atendimentos" do print inclui ligação. No
   chat, uma conversa vira atendimento no ERP sozinha (protocolo ao resolver) ou só por ação do
   operador?

## 7. Riscos

- **Vínculo errado** (achar o cliente errado e cobrar a pessoa errada) — mitigação: ambíguo e
  não-achado como estados explícitos; casar por documento; nunca escolher automaticamente
  entre vários.
- **Dado desatualizado** numa cobrança — mitigação: painel ao vivo com cache curto e horário
  visível.
- **Volume:** disparo sem endurecimento trava ou duplica — mitigação: F5 só depois da Onda 7
  fatia 3.
- **Vazamento entre contas** (multi-tenant com ERP por conta) — mitigação: teste de isolamento
  desde a F1.
- **Segredo em texto puro** se a criptografia não estiver ativa — mitigação: verificar em F0.
- **API do IXC:** campos e regras (contas a receber, status, filtros) **não foram verificados
  contra o ambiente**; o que se sabe hoje vem da documentação pública e de bibliotecas da
  comunidade (autenticação por token em formato Basic, consulta genérica por tabela, busca por
  CPF/CNPJ). Tudo isso é **hipótese até a F0**.
- **Custo de manutenção por ERP:** cada ERP novo é um adaptador a manter — por isso o contrato
  do adaptador e a F8 vêm como parte do plano, não como extra.

## 8. Fora de escopo por enquanto

Editor de contrato; motor de régua de cobrança; vários ERPs simultâneos na mesma conta;
gateway de pagamento (gerar/baixar boleto ou PIX pelo chat) — pode ser uma capacidade futura do
adaptador, mas não está pedida.
