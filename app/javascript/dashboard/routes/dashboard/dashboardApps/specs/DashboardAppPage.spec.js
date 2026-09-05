import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import DashboardAppPage from '../pages/DashboardAppPage.vue';

withFullI18n();

const dispatch = vi.fn();
const records = ref([]);
const uiFlags = ref({ isFetching: false });
const currentUser = ref({
  id: 42,
  name: 'Ana Souza',
  email: 'ana@exemplo.com',
  access_token: 'tok_abc123',
});
const currentAccountId = ref(7);

const getters = {
  'dashboardApps/getRecords': records,
  'dashboardApps/getUIFlags': uiFlags,
  getCurrentUser: currentUser,
  getCurrentAccountId: currentAccountId,
};

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: key => getters[key],
}));

const app = (overrides = {}) => ({
  id: 3,
  title: 'Painel do ERP',
  show_in_sidebar: true,
  pin_to_sidebar: false,
  content: [{ type: 'frame', url: 'https://erp.exemplo.com/?c={account_id}' }],
  ...overrides,
});

const mountPage = async (appId = 3) => {
  const wrapper = mount(DashboardAppPage, { props: { appId } });
  await flushPromises();
  return wrapper;
};

describe('DashboardAppPage', () => {
  beforeEach(() => {
    dispatch.mockReset();
    records.value = [app()];
    uiFlags.value = { isFetching: false };
  });

  it('embeds the app with the url variables already resolved', async () => {
    const wrapper = await mountPage();
    const frame = wrapper.find('iframe');

    expect(frame.attributes('src')).toBe('https://erp.exemplo.com/?c=7');
    // O titulo nomeia o iframe para quem usa leitor de tela.
    expect(frame.attributes('title')).toBe('Painel do ERP');
  });

  it('matches the app even though the id comes from the url as a string', async () => {
    const wrapper = await mountPage('3');

    expect(wrapper.find('iframe').exists()).toBe(true);
  });

  it('fetches the list when the store is empty, as on a direct link', async () => {
    records.value = [];
    await mountPage();

    expect(dispatch).toHaveBeenCalledWith('dashboardApps/get');
  });

  it('does not refetch when the list is already loaded', async () => {
    await mountPage();

    expect(dispatch).not.toHaveBeenCalled();
  });

  it('waits instead of claiming the app is gone while the list loads', async () => {
    records.value = [];
    uiFlags.value = { isFetching: true };
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'Spinner' }).exists()).toBe(true);
    expect(wrapper.text()).not.toContain('not available');
  });

  it('says the app is gone when no record matches', async () => {
    const wrapper = await mountPage(99);

    expect(wrapper.text()).toContain('not available');
    expect(wrapper.find('iframe').exists()).toBe(false);
  });

  it('ignores a content entry that is not a usable frame', async () => {
    records.value = [
      app({
        content: [
          { type: 'frame' },
          { type: 'frame', url: 'https://erp.exemplo.com/?u={user_id}' },
        ],
      }),
    ];
    const wrapper = await mountPage();
    const frames = wrapper.findAll('iframe');

    expect(frames).toHaveLength(1);
    expect(frames[0].attributes('src')).toBe('https://erp.exemplo.com/?u=42');
  });
});
