import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import FilaAgentTable from '../FilaAgentTable.vue';

withFullI18n();

const agent = (id, overrides = {}) => ({
  id,
  name: `Agente ${id}`,
  total: 1,
  avgWaitSeconds: 60,
  maxWaitSeconds: 120,
  loadPct: 10,
  ...overrides,
});

describe('FilaAgentTable.vue', () => {
  it('shows the empty state when there are no rows', () => {
    const wrapper = mount(FilaAgentTable, { props: { items: [] } });

    expect(wrapper.text()).toContain('No data in this period.');
  });

  it('shows the translated label when a row has no agent name', () => {
    const wrapper = mount(FilaAgentTable, {
      props: { items: [agent(1, { name: null })] },
    });

    expect(wrapper.text()).toContain('Unassigned');
  });

  it('cuts at 10 rows and reveals the rest with "show all"', async () => {
    const items = Array.from({ length: 15 }, (_, i) => agent(i + 1));
    const wrapper = mount(FilaAgentTable, { props: { items } });

    expect(wrapper.findAll('tbody tr')).toHaveLength(10);
    expect(wrapper.text()).toContain('10 / 15');

    await wrapper.find('button').trigger('click');

    expect(wrapper.findAll('tbody tr')).toHaveLength(15);
  });

  it('shows the bot hint only when the bot filter is active', () => {
    const wrapper = mount(FilaAgentTable, {
      props: { items: [], botHint: true },
    });

    expect(wrapper.text()).toContain(
      'The AI split considers conversations without an assigned agent'
    );
  });
});
