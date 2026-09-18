import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import FilaTeamTable from '../FilaTeamTable.vue';

withFullI18n();

describe('FilaTeamTable.vue', () => {
  it('shows the empty state when there are no rows', () => {
    const wrapper = mount(FilaTeamTable, { props: { items: [] } });

    expect(wrapper.text()).toContain('No data in this period.');
  });

  it('shows the translated label when a row has no team name', () => {
    const wrapper = mount(FilaTeamTable, {
      props: {
        items: [
          {
            id: null,
            name: null,
            total: 3,
            avgWaitSeconds: 60,
            maxWaitSeconds: 120,
            abandoned: 0,
          },
        ],
      },
    });

    expect(wrapper.text()).toContain('No team');
  });

  it('renders the row data', () => {
    const wrapper = mount(FilaTeamTable, {
      props: {
        items: [
          {
            id: 1,
            name: 'Suporte',
            total: 10,
            avgWaitSeconds: 90,
            maxWaitSeconds: 300,
            abandoned: 2,
          },
        ],
      },
    });

    expect(wrapper.text()).toContain('Suporte');
    expect(wrapper.text()).toContain('10');
    expect(wrapper.text()).toContain('2');
  });
});
