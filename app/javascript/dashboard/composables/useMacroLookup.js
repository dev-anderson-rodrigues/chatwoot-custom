import { computed, reactive, watch } from 'vue';

const DEBOUNCE_MS = 500;

export const isMultiLookup = field => field.type === 'lookup' && !!field.multi;

const dependsReady = (field, values) => {
  const deps = field.depends_on || [];
  if (!deps.length) return false;
  return deps.every(key => String(values[key] ?? '').trim() !== '');
};

// Aceita as formas que os webhooks de lookup ja em uso devolvem: lista crua,
// lista dentro de um envelope (`options`/`registros`/`data`/`results`), ou um
// unico objeto quando so ha um resultado. `registros` e a convencao dos
// webhooks n8n que ja estao em producao na fonte -- mantida para nao quebrar
// integracao existente no port.
const extractLookupRecords = data => {
  if (Array.isArray(data)) return data;
  if (Array.isArray(data?.options)) return data.options;
  if (Array.isArray(data?.registros)) return data.registros;
  if (Array.isArray(data?.data)) return data.data;
  if (Array.isArray(data?.results)) return data.results;
  if (data && typeof data === 'object') return [data];
  return [];
};

const mapLookupOptions = (records, field) => {
  const valueKey = field.value_key || 'value';
  const labelKey = field.label_key || 'label';
  return records.map(item => ({
    value: String(item?.[valueKey] ?? item?.value ?? item?.id ?? ''),
    label: String(
      item?.[labelKey] ?? item?.label ?? item?.name ?? item?.[valueKey] ?? ''
    ),
  }));
};

/**
 * [Fatia 5] Lookup dinamico das macros: as opcoes de um input_field do tipo
 * `lookup` vem de um POST para `lookup_url` com os valores atuais dos campos
 * em `depends_on`, disparado (debounced) sempre que qualquer valor do
 * formulario muda -- nao ha busca por texto livre, o agente digita nos
 * campos de que o lookup depende e as opcoes chegam sozinhas.
 *
 * `values` e `fields` sao passados por referencia (reactive/ref do
 * chamador): este composable le e escreve neles, mas quem os declara e
 * quem os limpa/preenche no open() do modal continua sendo o componente.
 */
export function useMacroLookup(values, fields) {
  const lookupState = reactive({});
  let lookupTimers = {};
  // Sobe a cada reset() (chamado do open() do modal ao trocar de macro). Uma
  // resposta que resolve depois de um reset pertence a uma macro que nao
  // esta mais na tela -- sem isto, duas macros com um campo de mesma chave
  // (ex.: "contrato") podem vazar a resposta de uma para o estado da outra.
  let epoch = 0;

  const lookupFields = computed(() =>
    fields.value.filter(field => field.type === 'lookup')
  );

  const isLookupLoading = field => !!lookupState[field.key]?.loading;
  const lookupOptionsFor = field => lookupState[field.key]?.options || [];

  const fetchLookup = async field => {
    if (!dependsReady(field, values)) return;
    const requestEpoch = epoch;

    const payload = {};
    (field.depends_on || []).forEach(key => {
      payload[key] = values[key];
    });

    lookupState[field.key] = { loading: true, error: false, options: [] };

    let data;
    try {
      const response = await fetch(field.lookup_url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      data = await response.json();
    } catch (error) {
      // A mensagem que chega ao agente e um texto fixo e traduzido (ver
      // lookupMessage no componente) -- o erro cru (status HTTP, falha de
      // CORS, host da URL) e detalhe de infra, nao algo para mostrar a ele.
      if (requestEpoch !== epoch) return;
      lookupState[field.key] = { loading: false, error: true, options: [] };
      return;
    }
    if (requestEpoch !== epoch) return;

    const options = mapLookupOptions(extractLookupRecords(data), field);
    lookupState[field.key] = { loading: false, error: false, options };

    // Os deps mudaram e a lista foi refeita -- uma selecao antiga que nao
    // aparece mais na resposta nova nao faz mais sentido (ex.: trocou o CPF,
    // o contrato escolhido para o CPF anterior tem que sair).
    const validValues = new Set(options.map(option => option.value));
    if (isMultiLookup(field)) {
      const current = values[field.key] || [];
      const pruned = current.filter(value => validValues.has(value));
      // So reatribui quando algo de fato foi removido. `values` e
      // reactive(): a reatividade do Vue dispara no set trap comparando
      // *referencia* (Object.is), nao conteudo -- um array novo com os
      // mesmos itens ainda conta como mudanca. Sem este guard, todo fetch
      // bem-sucedido reatribuiria um array (mesmo sem nada para podar), o
      // watch(values, ..., {deep:true}) do componente reagendaria o mesmo
      // fetch, que reatribuiria de novo -- loop infinito de POST para
      // lookup_url a cada ~500ms enquanto o modal ficasse aberto.
      if (pruned.length !== current.length) {
        values[field.key] = pruned;
      }
    } else if (values[field.key] && !validValues.has(values[field.key])) {
      values[field.key] = '';
    }
  };

  const scheduleLookup = field => {
    clearTimeout(lookupTimers[field.key]);
    lookupTimers[field.key] = setTimeout(() => fetchLookup(field), DEBOUNCE_MS);
  };

  // Dispara para todo lookup a cada mudanca em qualquer campo -- dependsReady
  // dentro de fetchLookup e que decide se ha algo a buscar. Mais simples que
  // mapear so as chaves de que cada lookup depende, e o debounce por campo
  // (scheduleLookup) evita disparo redundante de rede.
  watch(
    values,
    () => {
      lookupFields.value.forEach(scheduleLookup);
    },
    { deep: true }
  );

  // Chamado do open() do modal ao trocar (ou reabrir) de macro. Invalida
  // qualquer fetch em voo (via epoch) e descarta timers/estado da macro
  // anterior.
  const reset = () => {
    epoch += 1;
    Object.values(lookupTimers).forEach(clearTimeout);
    lookupTimers = {};
    Object.keys(lookupState).forEach(key => delete lookupState[key]);
  };

  return {
    lookupState,
    isLookupLoading,
    lookupOptionsFor,
    dependsReady: field => dependsReady(field, values),
    reset,
  };
}
