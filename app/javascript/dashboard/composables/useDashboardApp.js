import { computed, onMounted, toValue } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { interpolateDashboardAppConfig } from 'dashboard/helper/dashboardAppHelper';

/**
 * [Fatia 8] Um dashboard app resolvido para a tela: o registro, os frames com as
 * variaveis da URL ja substituidas e o estado de carregamento.
 *
 * @param {import('vue').MaybeRefOrGetter<string|number>} appId Id vindo da rota.
 */
export function useDashboardApp(appId) {
  const store = useStore();

  const apps = useMapGetter('dashboardApps/getRecords');
  const uiFlags = useMapGetter('dashboardApps/getUIFlags');
  const currentUser = useMapGetter('getCurrentUser');
  const currentAccountId = useMapGetter('getCurrentAccountId');

  // O id vem da URL, entao chega como string; o do registro e numero.
  const app = computed(() =>
    apps.value.find(record => String(record.id) === String(toValue(appId)))
  );

  const frames = computed(() =>
    interpolateDashboardAppConfig(app.value?.content, {
      accountId: currentAccountId.value,
      user: currentUser.value,
    }).filter(item => item.type === 'frame' && item.url)
  );

  const isLoading = computed(() => uiFlags.value.isFetching);

  onMounted(() => {
    // Chegar por link direto, ou so recarregar a aba, nao passa pela tela que
    // carrega a lista: sem isto um app existente apareceria como indisponivel.
    if (!apps.value.length) store.dispatch('dashboardApps/get');
  });

  return { app, frames, isLoading };
}
