import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import RoboHumano from '../RoboHumano.vue';

withFullI18n();

const getOwnershipSummary = vi.fn();

const emptyOwnership = () => ({
  botResolutions: 0,
  humanResolutions: 0,
  botAvgResolutionSeconds: 0,
  humanAvgResolutionSeconds: 0,
  humanAvgFirstResponseSeconds: 0,
  handoffs: 0,
});

vi.mock('dashboard/api/operationReports', () => ({
  default: {
    getOwnershipSummary: (...args) => getOwnershipSummary(...args),
  },
  emptyOwnership: () => ({
    botResolutions: 0,
    humanResolutions: 0,
    botAvgResolutionSeconds: 0,
    humanAvgResolutionSeconds: 0,
    humanAvgFirstResponseSeconds: 0,
    handoffs: 0,
  }),
}));

const summary = (overrides = {}) => ({ ...emptyOwnership(), ...overrides });

const respondWith = (current, previous = {}) =>
  getOwnershipSummary.mockResolvedValue({
    current: summary(current),
    previous: summary(previous),
  });

const mountScreen = async () => {
  const wrapper = mount(RoboHumano);
  await flushPromises();
  return wrapper;
};

const tile = (wrapper, label) =>
  wrapper.findAll('dl > div').find(node => node.text().includes(label));

const periodButton = (wrapper, label) =>
  wrapper.findAll('button').find(node => node.text() === label);

const windowDays = ({ from, to }) => Math.round((to - from) / 86400);

describe('RoboHumano', () => {
  beforeEach(() => {
    getOwnershipSummary.mockReset();
    respondWith({ botResolutions: 8, humanResolutions: 2, handoffs: 3 });
  });

  it('shows how much each side closed', async () => {
    const wrapper = await mountScreen();

    expect(tile(wrapper, 'Closed by the bot').text()).toContain('8');
    expect(tile(wrapper, 'Closed by people').text()).toContain('2');
    expect(tile(wrapper, 'Handed to people').text()).toContain('3');
  });

  it('turns the split into a share of the total', async () => {
    const wrapper = await mountScreen();

    // 8 de 10 encerradas.
    expect(tile(wrapper, 'Bot share').text()).toContain('80%');
  });

  it('does not invent a share when nothing was closed', async () => {
    respondWith({});
    const wrapper = await mountScreen();

    // Zero por cento diria "o robo nao resolveu nada"; o certo e "nao houve
    // atendimento".
    expect(tile(wrapper, 'Bot share').text()).not.toContain('0%');
    expect(wrapper.text()).toContain('No conversation was closed');
  });

  it('compares each side with the previous period', async () => {
    respondWith({ botResolutions: 8 }, { botResolutions: 4 });
    const wrapper = await mountScreen();

    expect(tile(wrapper, 'Closed by the bot').text()).toContain('+100%');
  });

  it('omits the comparison when there was no previous base', async () => {
    respondWith({ botResolutions: 8 }, { botResolutions: 0 });
    const wrapper = await mountScreen();

    // Crescer a partir de zero nao tem percentual que signifique algo.
    expect(tile(wrapper, 'Closed by the bot').text()).not.toContain('%');
  });

  it('asks for the last 30 days on mount and refetches with the chosen period', async () => {
    const wrapper = await mountScreen();

    expect(windowDays(getOwnershipSummary.mock.calls.at(-1)[0])).toBe(30);

    await periodButton(wrapper, '7 days').trigger('click');
    await flushPromises();

    expect(windowDays(getOwnershipSummary.mock.calls.at(-1)[0])).toBe(7);
    expect(periodButton(wrapper, '7 days').attributes('aria-pressed')).toBe(
      'true'
    );
  });

  it('always states the criterion, because the Bots report counts differently', async () => {
    const wrapper = await mountScreen();

    expect(wrapper.text()).toContain('without ever being opened or assigned');
  });

  it('shows a translated message when the request fails', async () => {
    getOwnershipSummary.mockRejectedValue(new Error('Request failed with 500'));
    const wrapper = await mountScreen();

    expect(wrapper.text()).toContain('Could not load the report');
    expect(wrapper.text()).not.toContain('500');
  });
});
