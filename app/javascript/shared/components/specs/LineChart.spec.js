import { shallowMount } from '@vue/test-utils';
import LineChart from '../charts/LineChart.vue';

vi.mock('@chatwoot/viz', () => ({
  LineChart: {
    name: 'VizLineChart',
    props: ['data', 'ariaLabel', 'pointDescription', 'onItemClick'],
    template: '<button @click="onItemClick?.({ pointIndex: 0 })" />',
  },
}));

describe('LineChart.vue', () => {
  const data = {
    categories: ['20-May'],
    series: [{ id: 'conversations', data: [3] }],
  };

  it('emits the clicked chart item when clickable', () => {
    const pointDescription = point => point.description;
    const wrapper = shallowMount(LineChart, {
      props: {
        clickable: true,
        data,
        ariaLabel: 'Conversations by day',
        pointDescription,
      },
    });

    const chart = wrapper.findComponent({ name: 'VizLineChart' });
    chart.props('onItemClick')({ pointIndex: 0 });

    expect(chart.props('data')).toEqual(data);
    expect(chart.props('ariaLabel')).toBe('Conversations by day');
    expect(chart.props('pointDescription')).toBe(pointDescription);
    expect(wrapper.emitted('itemClick')[0][0]).toEqual({ pointIndex: 0 });
  });

  it('does not attach an item handler when chart is not clickable', () => {
    const wrapper = shallowMount(LineChart, {
      props: {
        clickable: false,
        data,
        ariaLabel: 'Conversations by day',
      },
    });

    expect(
      wrapper.findComponent({ name: 'VizLineChart' }).props('onItemClick')
    ).toBeUndefined();
  });
});
