import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import DashboardAppModal from '../DashboardAppModal.vue';

withFullI18n();

const dispatch = vi.fn();

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const mountModal = (props = {}) =>
  mount(DashboardAppModal, {
    props: { show: true, mode: 'CREATE', ...props },
    global: {
      mocks: { $store: { dispatch } },
      stubs: {
        'woot-modal': { template: '<div><slot /></div>' },
        'woot-modal-header': true,
        WootInput: true,
        NextButton: true,
      },
    },
  });

const fillForm = async wrapper => {
  // Escrever pelo `$model` do Vuelidate, nao por `wrapper.vm.app`: o proxy do
  // test-utils devolve uma copia destacada dos dados, e a escrita nao chega ao
  // estado que o componente valida e submete.
  const v = wrapper.vm.v$;
  v.app.title.$model = 'Painel do ERP';
  v.app.content.url.$model = 'https://erp.exemplo.com/?c={account_id}';
  await flushPromises();
};

const checkboxes = wrapper => wrapper.findAll('input[type="checkbox"]');
const showCheckbox = wrapper => checkboxes(wrapper)[0];
const pinCheckbox = wrapper => checkboxes(wrapper)[1];

const payloadOfLastCall = () => dispatch.mock.calls.at(-1)[1];

describe('DashboardAppModal', () => {
  beforeEach(() => {
    dispatch.mockReset();
    dispatch.mockResolvedValue({});
  });

  it('sends both sidebar flags when the app is created', async () => {
    const wrapper = mountModal();
    await fillForm(wrapper);
    await showCheckbox(wrapper).setValue(true);
    await pinCheckbox(wrapper).setValue(true);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('dashboardApps/create', {
      title: 'Painel do ERP',
      show_in_sidebar: true,
      pin_to_sidebar: true,
      content: [
        { type: 'frame', url: 'https://erp.exemplo.com/?c={account_id}' },
      ],
    });
  });

  it('defaults both flags to false', async () => {
    const wrapper = mountModal();
    await fillForm(wrapper);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(payloadOfLastCall()).toMatchObject({
      show_in_sidebar: false,
      pin_to_sidebar: false,
    });
  });

  it('cannot pin an app that is not in the sidebar', async () => {
    const wrapper = mountModal();

    expect(pinCheckbox(wrapper).attributes('disabled')).toBeDefined();

    await showCheckbox(wrapper).setValue(true);
    expect(pinCheckbox(wrapper).attributes('disabled')).toBeUndefined();
  });

  it('drops the pin when the app leaves the sidebar', async () => {
    const wrapper = mountModal();
    await fillForm(wrapper);
    await showCheckbox(wrapper).setValue(true);
    await pinCheckbox(wrapper).setValue(true);

    // Fixado sem estar na barra lateral nao significa nada: o item fixado e a
    // propria entrada de primeiro nivel.
    await showCheckbox(wrapper).setValue(false);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(payloadOfLastCall()).toMatchObject({
      show_in_sidebar: false,
      pin_to_sidebar: false,
    });
  });

  it('starts from the saved flags when editing', async () => {
    const wrapper = mountModal({
      mode: 'UPDATE',
      selectedAppData: {
        id: 3,
        title: 'Painel do ERP',
        show_in_sidebar: true,
        pin_to_sidebar: true,
        content: [{ type: 'frame', url: 'https://erp.exemplo.com' }],
      },
    });
    await flushPromises();

    expect(showCheckbox(wrapper).element.checked).toBe(true);
    expect(pinCheckbox(wrapper).element.checked).toBe(true);
  });

  it('does not touch the stored record while the form is being edited', async () => {
    const selectedAppData = {
      id: 3,
      title: 'Painel do ERP',
      content: [{ type: 'frame', url: 'https://erp.exemplo.com' }],
    };
    const wrapper = mountModal({ mode: 'UPDATE', selectedAppData });

    await flushPromises();
    wrapper.vm.v$.app.content.url.$model = 'https://outro.exemplo.com';
    await flushPromises();

    // O modal editava o proprio objeto do store: fechar sem salvar deixava a
    // lista mostrando a URL que nunca foi gravada.
    expect(selectedAppData.content[0].url).toBe('https://erp.exemplo.com');
  });
});
