<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import subDays from 'date-fns/subDays';
import startOfDay from 'date-fns/startOfDay';
import endOfDay from 'date-fns/endOfDay';
import getUnixTime from 'date-fns/getUnixTime';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import ReportTile from '../../settings/reports/components/ReportTile.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import IxcAPI from '../../../../api/integrations/ixc';

const router = useRouter();

// ─── período ──────────────────────────────────────────────────────────────────

const PERIOD_OPTIONS = ['7d', '30d', '90d'];
const DAYS_BY_PERIOD = { '7d': 6, '30d': 29, '90d': 89 };
const period = ref('30d');

const range = computed(() => {
  const days = DAYS_BY_PERIOD[period.value] ?? 29;
  return {
    from: getUnixTime(startOfDay(subDays(new Date(), days))),
    to: getUnixTime(endOfDay(new Date())),
  };
});

// ─── abas ─────────────────────────────────────────────────────────────────────

const TABS = ['inadimplencia', 'atendimentos', 'promessas'];
const activeTab = ref('inadimplencia');

// ─── Tab 1: Inadimplência ──────────────────────────────────────────────────────

const inadimplenciaLoading = ref(false);
const inadimplenciaError = ref('');
const inadimplenciaRecords = ref([]);

const AGING_BUCKETS = [
  { label: '1–30d', min: 1, max: 30 },
  { label: '31–60d', min: 31, max: 60 },
  { label: '61–90d', min: 61, max: 90 },
  { label: '+90d', min: 91, max: 180 },
  { label: '+180d', min: 181, max: 360 },
  { label: '+360d', min: 361, max: null },
];

const DEBT_BUCKETS = [
  { label: 'até R$200', min: 0, max: 200 },
  { label: 'R$200–500', min: 200, max: 500 },
  { label: 'R$500–1k', min: 500, max: 1000 },
  { label: 'R$1k+', min: 1000, max: null },
];

const inCountForBucket = bucket =>
  inadimplenciaRecords.value.filter(r => {
    const d = r.max_overdue_days;
    return d >= bucket.min && (bucket.max === null || d <= bucket.max);
  }).length;

const inDebtForBucket = bucket =>
  inadimplenciaRecords.value.filter(r => {
    const v = r.total_debt;
    return v >= bucket.min && (bucket.max === null || v < bucket.max);
  }).length;

const inadimplenciaKpis = computed(() => {
  const rs = inadimplenciaRecords.value;
  const total = rs.length;
  const totalDebt = rs.reduce((s, r) => s + (r.total_debt || 0), 0);
  const high = rs.filter(r => r.max_overdue_days > 90).length;
  return {
    total,
    totalDebt,
    avgDebt: total > 0 ? totalDebt / total : 0,
    high,
  };
});

const agingChartData = computed(() => ({
  categories: AGING_BUCKETS.map(b => b.label),
  series: [
    {
      id: 'aging',
      label: 'Clientes',
      color: 'rgb(var(--ruby-9))',
      valueColor: 'rgb(var(--ruby-11))',
      data: AGING_BUCKETS.map(b => inCountForBucket(b)),
    },
  ],
}));

const debtChartData = computed(() => ({
  categories: DEBT_BUCKETS.map(b => b.label),
  series: [
    {
      id: 'debt',
      label: 'Clientes',
      color: 'rgb(var(--amber-9))',
      valueColor: 'rgb(var(--amber-11))',
      data: DEBT_BUCKETS.map(b => inDebtForBucket(b)),
    },
  ],
}));

const fetchInadimplencia = async () => {
  inadimplenciaLoading.value = true;
  inadimplenciaError.value = '';
  try {
    const { data } = await IxcAPI.getOverdueCustomers(1, 9999);
    inadimplenciaRecords.value = data.records || [];
  } catch {
    inadimplenciaError.value = 'Não foi possível carregar os dados de inadimplência.';
  } finally {
    inadimplenciaLoading.value = false;
  }
};

// ─── Tab 2: Atendimentos ──────────────────────────────────────────────────────

const atendimentosLoading = ref(false);
const atendimentosError = ref('');
const atendimentosData = ref(null);

const atendimentosKpis = computed(() => {
  const d = atendimentosData.value;
  if (!d) return [];
  return [
    { key: 'total', label: 'Total de atendimentos', value: d.total },
    { key: 'contacted', label: 'Clientes contatados', value: d.contacted },
    { key: 'contact_rate', label: 'Taxa de contato', value: `${d.contact_rate}%` },
    { key: 'agreements', label: 'Acordos realizados', value: `${d.agreement_rate}%` },
  ];
});

const canalChartData = computed(() => {
  const d = atendimentosData.value;
  if (!d) return null;
  const entries = Object.entries(d.by_canal || {});
  if (!entries.length) return null;
  return {
    categories: entries.map(([k]) => k || 'N/D'),
    series: [
      {
        id: 'canal',
        label: 'Atendimentos',
        color: 'rgb(var(--blue-9))',
        valueColor: 'rgb(var(--blue-11))',
        data: entries.map(([, v]) => v),
      },
    ],
  };
});

const resultadoChartData = computed(() => {
  const d = atendimentosData.value;
  if (!d) return null;
  const entries = Object.entries(d.by_resultado || {});
  if (!entries.length) return null;
  return {
    categories: entries.map(([k]) => k || 'N/D'),
    series: [
      {
        id: 'resultado',
        label: 'Atendimentos',
        color: 'rgb(var(--teal-9))',
        valueColor: 'rgb(var(--teal-11))',
        data: entries.map(([, v]) => v),
      },
    ],
  };
});

const atendDailyChartData = computed(() => {
  const d = atendimentosData.value;
  if (!d?.by_day?.length) return null;
  return {
    categories: d.by_day.map(r => r.date.slice(5)),
    series: [
      {
        id: 'daily',
        label: 'Atendimentos/dia',
        color: 'rgb(var(--blue-9))',
        valueColor: 'rgb(var(--blue-11))',
        data: d.by_day.map(r => r.count),
      },
    ],
  };
});

const fetchAtendimentos = async () => {
  atendimentosLoading.value = true;
  atendimentosError.value = '';
  try {
    const { data } = await IxcAPI.getAttendanceStats(range.value.from, range.value.to);
    atendimentosData.value = data;
  } catch {
    atendimentosError.value = 'Não foi possível carregar os dados de atendimentos.';
  } finally {
    atendimentosLoading.value = false;
  }
};

// ─── Tab 3: Promessas ─────────────────────────────────────────────────────────

const promessasLoading = ref(false);
const promessasError = ref('');
const promessasData = ref(null);

const promessasKpis = computed(() => {
  const d = promessasData.value;
  if (!d) return [];
  return [
    { key: 'total', label: 'Promessas criadas', value: d.total },
    { key: 'amount', label: 'Valor total prometido', value: fmtBRL(d.total_amount) },
    { key: 'avg', label: 'Valor médio', value: fmtBRL(d.avg_amount) },
    { key: 'week', label: 'Vencem em 7 dias', value: d.upcoming_week },
  ];
});

const promDailyChartData = computed(() => {
  const d = promessasData.value;
  if (!d?.by_day?.length) return null;
  return {
    categories: d.by_day.map(r => r.date.slice(5)),
    series: [
      {
        id: 'prom-daily',
        label: 'Promessas/dia',
        color: 'rgb(var(--violet-9))',
        valueColor: 'rgb(var(--violet-11))',
        data: d.by_day.map(r => r.count),
      },
    ],
  };
});

const fetchPromessas = async () => {
  promessasLoading.value = true;
  promessasError.value = '';
  try {
    const { data } = await IxcAPI.getPromiseStats(range.value.from, range.value.to);
    promessasData.value = data;
  } catch {
    promessasError.value = 'Não foi possível carregar os dados de promessas.';
  } finally {
    promessasLoading.value = false;
  }
};

// ─── helpers ──────────────────────────────────────────────────────────────────

const fmtBRL = value =>
  Number(value || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

const TAB_LABELS = {
  inadimplencia: 'Inadimplência',
  atendimentos: 'Atendimentos',
  promessas: 'Promessas',
};

const setTab = tab => {
  activeTab.value = tab;
  if (tab === 'atendimentos' && !atendimentosData.value) fetchAtendimentos();
  if (tab === 'promessas' && !promessasData.value) fetchPromessas();
};

watch(
  () => range.value,
  () => {
    if (activeTab.value === 'atendimentos') fetchAtendimentos();
    if (activeTab.value === 'promessas') fetchPromessas();
  }
);

onMounted(fetchInadimplencia);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <!-- Header -->
    <header class="sticky top-0 z-10 bg-n-surface-1 border-b border-n-weak px-6 shrink-0">
      <div class="w-full max-w-5xl mx-auto">
        <div class="flex items-center justify-between w-full py-4 gap-3">
          <div class="min-w-0">
            <span class="text-xl font-medium text-n-slate-12 block leading-tight">
              Relatórios de Cobrança
            </span>
            <p class="text-sm text-n-slate-10 mt-0.5 hidden sm:block">
              Indicadores de inadimplência, atendimentos e promessas
            </p>
          </div>

          <button
            class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-n-weak text-sm font-medium text-n-slate-11 hover:bg-n-slate-3 transition-colors whitespace-nowrap"
            @click="router.back()"
          >
            <span class="i-lucide-arrow-left w-3.5 h-3.5" />
            Voltar
          </button>
        </div>
      </div>
    </header>

    <!-- Conteúdo -->
    <div class="flex-1 overflow-y-auto">
      <div class="w-full max-w-5xl mx-auto px-6 py-5 flex flex-col gap-5">

        <!-- Filtro de período + abas -->
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <!-- Abas -->
          <div class="flex items-center gap-1 border border-n-weak rounded-lg p-1 self-start">
            <button
              v-for="tab in TABS"
              :key="tab"
              class="px-3 py-1.5 rounded-md text-sm font-medium transition-colors"
              :class="
                activeTab === tab
                  ? 'bg-n-brand text-white'
                  : 'text-n-slate-11 hover:bg-n-slate-3'
              "
              @click="setTab(tab)"
            >
              {{ TAB_LABELS[tab] }}
            </button>
          </div>

          <!-- Período (apenas para Atendimentos e Promessas) -->
          <div
            v-if="activeTab !== 'inadimplencia'"
            role="group"
            aria-label="Período"
            class="flex items-center gap-1"
          >
            <button
              v-for="opt in PERIOD_OPTIONS"
              :key="opt"
              class="px-3 py-1.5 rounded-lg text-sm font-medium border transition-colors"
              :class="
                period === opt
                  ? 'bg-n-brand text-white border-n-brand'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-slate-3'
              "
              @click="period = opt"
            >
              {{ opt }}
            </button>
          </div>
        </div>

        <!-- ── TAB 1: Inadimplência ── -->
        <div v-if="activeTab === 'inadimplencia'" class="flex flex-col gap-5">
          <div v-if="inadimplenciaLoading" class="flex justify-center py-10">
            <Spinner />
          </div>

          <div
            v-else-if="inadimplenciaError"
            class="rounded-lg bg-n-ruby-3 text-n-ruby-11 px-4 py-3 text-sm"
          >
            {{ inadimplenciaError }}
          </div>

          <template v-else>
            <dl class="grid grid-cols-2 gap-3 m-0 sm:grid-cols-4">
              <ReportTile
                label="Clientes inadimplentes"
                :value="inadimplenciaKpis.total"
              />
              <ReportTile
                label="Valor total em aberto"
                :value="fmtBRL(inadimplenciaKpis.totalDebt)"
              />
              <ReportTile
                label="Ticket médio"
                :value="fmtBRL(inadimplenciaKpis.avgDebt)"
              />
              <ReportTile
                label="Em atraso +90 dias"
                :value="inadimplenciaKpis.high"
                :description="`${inadimplenciaKpis.total > 0 ? ((inadimplenciaKpis.high / inadimplenciaKpis.total) * 100).toFixed(0) : 0}% do total`"
              />
            </dl>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
              <div class="flex flex-col gap-2">
                <h3 class="m-0 text-sm font-medium text-n-slate-12">
                  Clientes por faixa de atraso
                </h3>
                <BarChart
                  :data="agingChartData"
                  :height="200"
                  aria-label="Clientes por faixa de atraso"
                />
              </div>

              <div class="flex flex-col gap-2">
                <h3 class="m-0 text-sm font-medium text-n-slate-12">
                  Clientes por faixa de dívida
                </h3>
                <BarChart
                  :data="debtChartData"
                  :height="200"
                  aria-label="Clientes por faixa de dívida"
                />
              </div>
            </div>
          </template>
        </div>

        <!-- ── TAB 2: Atendimentos ── -->
        <div v-if="activeTab === 'atendimentos'" class="flex flex-col gap-5">
          <div v-if="atendimentosLoading" class="flex justify-center py-10">
            <Spinner />
          </div>

          <div
            v-else-if="atendimentosError"
            class="rounded-lg bg-n-ruby-3 text-n-ruby-11 px-4 py-3 text-sm"
          >
            {{ atendimentosError }}
          </div>

          <template v-else-if="atendimentosData">
            <dl class="grid grid-cols-2 gap-3 m-0 sm:grid-cols-4">
              <ReportTile
                v-for="kpi in atendimentosKpis"
                :key="kpi.key"
                :label="kpi.label"
                :value="kpi.value"
              />
            </dl>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
              <div v-if="canalChartData" class="flex flex-col gap-2">
                <h3 class="m-0 text-sm font-medium text-n-slate-12">Por canal</h3>
                <BarChart
                  :data="canalChartData"
                  :height="200"
                  aria-label="Atendimentos por canal"
                />
              </div>

              <div v-if="resultadoChartData" class="flex flex-col gap-2">
                <h3 class="m-0 text-sm font-medium text-n-slate-12">Por resultado</h3>
                <BarChart
                  :data="resultadoChartData"
                  :height="200"
                  aria-label="Atendimentos por resultado"
                />
              </div>
            </div>

            <div v-if="atendDailyChartData" class="flex flex-col gap-2">
              <h3 class="m-0 text-sm font-medium text-n-slate-12">Evolução diária</h3>
              <BarChart
                :data="atendDailyChartData"
                :height="160"
                aria-label="Atendimentos por dia"
              />
            </div>

            <div v-if="atendimentosData.by_agent?.length" class="flex flex-col gap-2">
              <h3 class="m-0 text-sm font-medium text-n-slate-12">Por operador</h3>
              <div class="w-full overflow-x-auto">
                <BaseTable
                  :headers="['Operador', 'Atendimentos']"
                  :items="atendimentosData.by_agent"
                  no-data-message="Sem registros"
                >
                  <template #row="{ items }">
                    <BaseTableRow
                      v-for="(row, i) in items"
                      :key="i"
                      :item="row"
                    >
                      <BaseTableCell>
                        <span class="text-sm text-n-slate-12">{{ row.name }}</span>
                      </BaseTableCell>
                      <BaseTableCell>
                        <span class="text-sm tabular-nums text-n-slate-11">{{ row.count }}</span>
                      </BaseTableCell>
                    </BaseTableRow>
                  </template>
                </BaseTable>
              </div>
            </div>
          </template>
        </div>

        <!-- ── TAB 3: Promessas ── -->
        <div v-if="activeTab === 'promessas'" class="flex flex-col gap-5">
          <div v-if="promessasLoading" class="flex justify-center py-10">
            <Spinner />
          </div>

          <div
            v-else-if="promessasError"
            class="rounded-lg bg-n-ruby-3 text-n-ruby-11 px-4 py-3 text-sm"
          >
            {{ promessasError }}
          </div>

          <template v-else-if="promessasData">
            <dl class="grid grid-cols-2 gap-3 m-0 sm:grid-cols-4">
              <ReportTile
                v-for="kpi in promessasKpis"
                :key="kpi.key"
                :label="kpi.label"
                :value="kpi.value"
              />
            </dl>

            <div v-if="promDailyChartData" class="flex flex-col gap-2">
              <h3 class="m-0 text-sm font-medium text-n-slate-12">Promessas criadas por dia</h3>
              <BarChart
                :data="promDailyChartData"
                :height="160"
                aria-label="Promessas por dia"
              />
            </div>

            <div v-if="promessasData.by_agent?.length" class="flex flex-col gap-2">
              <h3 class="m-0 text-sm font-medium text-n-slate-12">Por operador</h3>
              <div class="w-full overflow-x-auto">
                <BaseTable
                  :headers="['Operador', 'Promessas', 'Valor total']"
                  :items="promessasData.by_agent"
                  no-data-message="Sem registros"
                >
                  <template #row="{ items }">
                    <BaseTableRow
                      v-for="(row, i) in items"
                      :key="i"
                      :item="row"
                    >
                      <BaseTableCell>
                        <span class="text-sm text-n-slate-12">{{ row.name }}</span>
                      </BaseTableCell>
                      <BaseTableCell>
                        <span class="text-sm tabular-nums text-n-slate-11">{{ row.count }}</span>
                      </BaseTableCell>
                      <BaseTableCell>
                        <span class="text-sm tabular-nums text-n-slate-11">{{ fmtBRL(row.amount) }}</span>
                      </BaseTableCell>
                    </BaseTableRow>
                  </template>
                </BaseTable>
              </div>
            </div>
          </template>
        </div>

      </div>
    </div>
  </section>
</template>
