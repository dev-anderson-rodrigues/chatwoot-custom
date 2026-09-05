/**
 * [Fatia 8] Variaveis que um dashboard app pode usar na URL para receber o
 * contexto de quem abriu: `https://erp.exemplo.com/painel?conta={account_id}`.
 */
export const DASHBOARD_APP_URL_VARIABLES = [
  'account_id',
  'user_id',
  'user_email',
  'user_name',
  'user_token',
];

// ATENCAO ao mexer em `user_token`: ele e o access_token do usuario, credencial
// de API com o poder inteiro dele, e vai dentro da URL do iframe -- ou seja,
// para o log do host de destino, para o Referer e para o historico do navegador.
// Quem cadastra a URL e admin (DashboardAppPolicy#create?), mas quem abre o app
// e qualquer agente (index?/show? liberam todo account_user): o token entregue e
// o de cada agente, um por um, sem sinal para ele. `backend-security` classificou
// como bloqueante; a decisao de manter foi do dono do produto, porque os apps do
// sistema antigo autenticam por esta variavel e quebrariam na migracao. Risco
// aceito de olhos abertos, registrado em docs-fork/plano-port-coraxy.md.
// O caminho para fechar, quando os apps puderem mudar: token curto, assinado e
// de escopo restrito, emitido por endpoint proprio -- nao o access_token cru.

const VARIABLE_PATTERN = new RegExp(
  `\\{(${DASHBOARD_APP_URL_VARIABLES.join('|')})\\}`,
  'g'
);

/**
 * Troca as variaveis da URL de um dashboard app pelos valores de quem esta
 * usando o sistema.
 *
 * Substituicao em uma passada so, nao em `replace` encadeado como na fonte: com
 * um replace por variavel, o valor ja inserido volta a ser varrido pelos
 * seguintes, e um agente chamado "{user_token}" faria o proprio token entrar
 * numa URL que so pedia o nome.
 *
 * Todo valor sai por `encodeURIComponent`: sem isso um nome com `&` ou `#`
 * reescreve a query string de destino.
 *
 * @param {string} url URL crua, como o admin cadastrou.
 * @param {{accountId: number|string, user: object}} context Contexto atual.
 * @returns {string} URL com as variaveis resolvidas.
 */
export const interpolateDashboardAppUrl = (url, context = {}) => {
  if (!url) return url;

  const { accountId, user } = context;
  const values = {
    account_id: accountId,
    user_id: user?.id,
    user_email: user?.email,
    user_name: user?.name,
    user_token: user?.access_token,
  };

  return url.replace(VARIABLE_PATTERN, (_match, key) => {
    const value = values[key];
    // Variavel sem valor vira vazio: "undefined" na URL manda lixo para o app
    // de destino em vez de deixar claro que o dado nao existe.
    return value === undefined || value === null
      ? ''
      : encodeURIComponent(value);
  });
};

/**
 * Aplica a interpolacao em cada item do `content` de um dashboard app.
 *
 * @param {Array} config Lista de frames do app.
 * @param {{accountId: number|string, user: object}} context Contexto atual.
 * @returns {Array} Lista com as URLs resolvidas.
 */
export const interpolateDashboardAppConfig = (config, context = {}) =>
  (config || []).map(item =>
    item?.url
      ? { ...item, url: interpolateDashboardAppUrl(item.url, context) }
      : item
  );
