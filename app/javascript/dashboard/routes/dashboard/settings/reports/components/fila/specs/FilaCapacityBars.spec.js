import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import FilaCapacityBars from '../FilaCapacityBars.vue';

withFullI18n();

describe('FilaCapacityBars.vue', () => {
  it('shows the empty state when there are no rows', () => {
    const wrapper = mount(FilaCapacityBars, { props: { items: [] } });

    expect(wrapper.text()).toContain('No data in this period.');
  });

  it('uses design-system tokens, not literal colors, for each usage band', () => {
    const row = overrides => ({
      id: 1,
      name: 'Suporte',
      demand: 10,
      agents: 2,
      capacity: 10,
      usagePct: 100,
      ...overrides,
    });

    const low = mount(FilaCapacityBars, {
      props: { items: [row({ usagePct: 40 })] },
    });
    const mid = mount(FilaCapacityBars, {
      props: { items: [row({ usagePct: 80 })] },
    });
    const high = mount(FilaCapacityBars, {
      props: { items: [row({ usagePct: 95 })] },
    });

    expect(low.find('.bg-n-teal-9').exists()).toBe(true);
    expect(mid.find('.bg-n-amber-9').exists()).toBe(true);
    expect(high.find('.bg-n-ruby-9').exists()).toBe(true);
  });

  it('caps the bar width at 100% even when usage exceeds it', () => {
    const wrapper = mount(FilaCapacityBars, {
      props: {
        items: [
          {
            id: 1,
            name: 'Suporte',
            demand: 20,
            agents: 1,
            capacity: 10,
            usagePct: 200,
          },
        ],
      },
    });

    const bar = wrapper.find('.bg-n-ruby-9');
    expect(bar.attributes('style')).toContain('width: 100%');
  });

  it('shows the translated label when a team has no name', () => {
    const wrapper = mount(FilaCapacityBars, {
      props: {
        items: [
          {
            id: null,
            name: null,
            demand: 1,
            agents: 0,
            capacity: 0,
            usagePct: 100,
          },
        ],
      },
    });

    expect(wrapper.text()).toContain('No team');
  });
});
