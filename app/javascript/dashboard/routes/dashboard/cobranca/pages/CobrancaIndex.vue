<script setup>
import { ref, computed, onMounted } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import IxcAPI from '../../../../api/integrations/ixc';

const loading = ref(false);
const error = ref('');
const records = ref([]);
const lastUpdate = ref(null);

const search = ref('');
const filterAtraso = ref('');
const filterDivida = ref('');

const ATRASO_RANGES = [
  { label: '1–30d', min: 1, max: 30 },
  { label: '31–60d', min: 31, max: 60 },
  { label: '61–90d', min: 61, max: 90 },
  { label: '+90d', min: 91, max: null },
  { label: '+180d', min: 181, max: null },
  { label: '+360d', min: 361, max: null },
];

const DIVIDA_RANGES = [
  { label: 'até R$200', min: 0, max: 200 },
  { label: 'R$200–500', min: 200, max: 500 },
  { label: 'R$500–1k', min: 500, max: 1000 },
  { label: 'R$1k+', min: 1000, max: null },
];

const filteredRecords = computed(() => {
  let list = records.value;

  if (search.value.trim()) {
    const q = search.value.toLowerCase();
    list = list.filter(
      r =>
        (r.name || '').toLowerCase().includes(q) ||
        (r.cpf_cnpj || '').replace(/\D/g, '').includes(q.replace(/\D/g, '')) ||
        (r.phone || '').replace(/\D/g, '').includes(q.replace(/\D/g, ''))
    );
  }

  if (filterAtraso.value) {
    const range = ATRASO_RANGES.find(r => r.label === filterAtraso.value);
    if (range) {
      list = list.filter(
        r =>
          r.max_overdue_days >= range.min &&
          (range.max === null || r.max_overdue_days <= range.max)
      );
    }
  }

  if (filterDivida.value) {
    const range = DIVIDA_RANGES.find(r => r.label === filterDivida.value);
    if (range) {
      list = list.filter(
        r =>
          r.total_debt >= range.min &&
          (range.max === null || r.total_debt < range.max)
      );
    }
  }

  return list;
});

const totalDebt = computed(() =>
  filteredRecords.value.reduce((s, r) => s + r.total_debt, 0)
);

const hasActiveFilters = computed(
  () => !!filterAtraso.value || !!filterDivida.value || !!search.value.trim()
);

const formatCurrency = v =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

const formatDate = d => {
  if (!d) return '—';
  const [y, m, day] = d.split('-');
  return `${day}/${m}/${y}`;
};

const formatTime = d => {
  if (!d) return null;
  return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
};

const toggleAtraso = value => {
  filterAtraso.value = filterAtraso.value === value ? '' : value;
};

const toggleDivida = value => {
  filterDivida.value = filterDivida.value === value ? '' : value;
};

const clearFilters = () => {
  filterAtraso.value = '';
  filterDivida.value = '';
  search.value = '';
};

const fetchData = async () => {
  loading.value = true;
  error.value = '';
  try {
    const res = await IxcAPI.getOverdueCustomers(1, 200);
    records.value = res.data.records || [];
    lastUpdate.value = new Date();
  } catch (e) {
    error.value = e.response?.data?.error || 'Erro ao carregar dados do IXC.';
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <!-- Sticky header -->
    <header class="sticky top-0 z-10 bg-n-surface-1 border-b border-n-weak px-6 shrink-0">
      <div class="w-full max-w-5xl mx-auto">
        <div class="flex items-start sm:items-center justify-between w-full py-4 gap-3 flex-col sm:flex-row">
          <div class="min-w-0">
            <span class="text-xl font-medium text-n-slate-12 block leading-tight">
              Gestão de Cobrança
            </span>
            <p class="text-sm text-n-slate-10 mt-0.5 hidden sm:block">
              Clientes em atraso sincronizados da base IXC
            </p>
          </div>

          <div class="flex items-center gap-3 shrink-0 self-start sm:self-auto">
            <span v-if="lastUpdate" class="text-xs text-n-slate-10 hidden md:block text-right">
              Atualizado {{ formatTime(lastUpdate) }}
            </span>
            <button
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-n-weak text-sm font-medium text-n-slate-11 hover:bg-n-slate-3 transition-colors disabled:opacity-40 whitespace-nowrap"
              :disabled="loading"
              @click="fetchData"
            >
              <span
                class="i-lucide-refresh-cw w-3.5 h-3.5"
                :class="{ 'animate-spin': loading }"
              />
              Atualizar
            </button>
          </div>
        </div>
      </div>
    </header>

    <!-- Scrollable content -->
    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full max-w-5xl mx-auto py-5 flex flex-col gap-5">

        <!-- Stats row -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
          <div class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-4">
            <div class="flex items-center gap-1.5 mb-2">
              <span class="i-lucide-users w-3.5 h-3.5 text-n-slate-10" />
              <span class="text-xs text-n-slate-10 font-medium uppercase tracking-wider">Vencidos</span>
            </div>
            <p class="text-2xl font-semibold text-n-ruby-11 leading-none">{{ filteredRecords.length }}</p>
            <p class="text-xs text-n-slate-10 mt-1">clientes</p>
          </div>

          <div class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-4">
            <div class="flex items-center gap-1.5 mb-2">
              <span class="i-lucide-circle-dollar-sign w-3.5 h-3.5 text-n-slate-10" />
              <span class="text-xs text-n-slate-10 font-medium uppercase tracking-wider">Dívida total</span>
            </div>
            <p class="text-2xl font-semibold text-n-ruby-11 leading-none tabular-nums">
              {{ formatCurrency(totalDebt) }}
            </p>
            <p class="text-xs text-n-slate-10 mt-1">em aberto</p>
          </div>

          <div class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-4">
            <div class="flex items-center gap-1.5 mb-2">
              <span class="i-lucide-database w-3.5 h-3.5 text-n-slate-10" />
              <span class="text-xs text-n-slate-10 font-medium uppercase tracking-wider">Fonte</span>
            </div>
            <p class="text-sm font-medium text-n-teal-11 leading-snug">Base IXC</p>
            <p class="text-xs text-n-slate-10 mt-1">sincronizada</p>
          </div>

          <div class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-4">
            <div class="flex items-center gap-1.5 mb-2">
              <span class="i-lucide-filter w-3.5 h-3.5 text-n-slate-10" />
              <span class="text-xs text-n-slate-10 font-medium uppercase tracking-wider">Filtrados</span>
            </div>
            <p class="text-2xl font-semibold text-n-slate-12 leading-none">
              {{ hasActiveFilters ? filteredRecords.length : records.length }}
            </p>
            <p class="text-xs text-n-slate-10 mt-1">de {{ records.length }}</p>
          </div>
        </div>

        <!-- Search + Filters -->
        <div class="flex flex-col gap-3">
          <!-- Search row -->
          <div class="flex items-center gap-2">
            <label class="flex items-center gap-2 flex-1 h-9 px-3 rounded-lg border border-n-weak bg-n-background focus-within:border-n-brand transition-colors cursor-text">
              <span class="i-lucide-search w-4 h-4 text-n-slate-10 shrink-0" />
              <input
                v-model="search"
                type="search"
                placeholder="Buscar por nome, CPF/CNPJ ou telefone…"
                class="flex-1 min-w-0 bg-transparent text-sm text-n-slate-12 placeholder-n-slate-10 focus:outline-none"
              />
            </label>
            <button
              v-if="hasActiveFilters"
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-slate-3 transition-colors whitespace-nowrap"
              @click="clearFilters"
            >
              <span class="i-lucide-x w-3.5 h-3.5" />
              Limpar
            </button>
          </div>

          <!-- Filter chips row -->
          <div class="flex flex-col gap-2">
            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-xs font-medium text-n-slate-10 w-10 shrink-0">Atraso</span>
              <button
                v-for="range in ATRASO_RANGES"
                :key="range.label"
                class="px-2.5 py-1 rounded-full text-xs font-medium border transition-colors"
                :class="
                  filterAtraso === range.label
                    ? 'bg-n-brand text-white border-n-brand'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-slate-3 bg-transparent'
                "
                @click="toggleAtraso(range.label)"
              >
                {{ range.label }}
              </button>
            </div>

            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-xs font-medium text-n-slate-10 w-10 shrink-0">Dívida</span>
              <button
                v-for="range in DIVIDA_RANGES"
                :key="range.label"
                class="px-2.5 py-1 rounded-full text-xs font-medium border transition-colors"
                :class="
                  filterDivida === range.label
                    ? 'bg-n-brand text-white border-n-brand'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-slate-3 bg-transparent'
                "
                @click="toggleDivida(range.label)"
              >
                {{ range.label }}
              </button>
            </div>
          </div>
        </div>

        <!-- Content area -->
        <div>
          <!-- Loading -->
          <div v-if="loading" class="flex justify-center items-center py-20">
            <Spinner :size="32" class="text-n-brand" />
          </div>

          <!-- Error -->
          <div
            v-else-if="error"
            class="flex flex-col items-center justify-center py-20 gap-3 text-center"
          >
            <span class="i-lucide-wifi-off w-10 h-10 text-n-slate-9" />
            <p class="text-base font-medium text-n-slate-12">Erro ao carregar dados</p>
            <p class="text-sm text-n-slate-10 max-w-xs">{{ error }}</p>
            <button
              class="mt-2 flex items-center gap-1.5 px-4 py-2 rounded-lg border border-n-weak text-sm font-medium text-n-slate-11 hover:bg-n-slate-3 transition-colors"
              @click="fetchData"
            >
              <span class="i-lucide-refresh-cw w-3.5 h-3.5" />
              Tentar novamente
            </button>
          </div>

          <!-- Empty -->
          <div
            v-else-if="!filteredRecords.length"
            class="flex flex-col items-center justify-center py-20 gap-2 text-center"
          >
            <span class="i-lucide-check-circle w-10 h-10 text-n-teal-9" />
            <p class="text-base text-n-slate-11">
              {{ hasActiveFilters ? 'Nenhum cliente encontrado com esses filtros.' : 'Nenhum cliente em atraso.' }}
            </p>
            <button
              v-if="hasActiveFilters"
              class="text-sm text-n-brand hover:underline mt-1"
              @click="clearFilters"
            >
              Limpar filtros
            </button>
          </div>

          <!-- Cards grid -->
          <div
            v-else
            class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-3"
          >
            <div
              v-for="r in filteredRecords"
              :key="r.customer_id"
              class="flex flex-col gap-0 outline outline-1 outline-n-container -outline-offset-1 rounded-xl bg-n-solid-2 overflow-hidden"
            >
              <!-- Card header -->
              <div class="flex items-start justify-between gap-2 px-4 pt-4 pb-3">
                <div class="min-w-0">
                  <p class="font-semibold text-n-slate-12 text-sm leading-snug truncate">
                    {{ r.name }}
                  </p>
                  <p class="text-xs text-n-slate-10 mt-0.5 truncate">{{ r.cpf_cnpj || '—' }}</p>
                </div>
                <span
                  class="shrink-0 rounded-full text-xs font-semibold px-2.5 py-0.5 tabular-nums whitespace-nowrap"
                  :class="
                    r.max_overdue_days >= 90
                      ? 'bg-n-ruby-9 text-white'
                      : r.max_overdue_days >= 30
                        ? 'bg-n-amber-9 text-white'
                        : 'bg-n-yellow-9 text-n-slate-12'
                  "
                >
                  {{ r.max_overdue_days }}d
                </span>
              </div>

              <!-- Divider -->
              <div class="h-px bg-n-weak mx-4" />

              <!-- Info grid -->
              <div class="grid grid-cols-2 gap-x-3 gap-y-2 px-4 py-3">
                <div class="flex items-center gap-1.5 min-w-0">
                  <span class="i-lucide-phone w-3.5 h-3.5 text-n-slate-9 shrink-0" />
                  <span class="text-xs text-n-slate-11 truncate">{{ r.phone || '—' }}</span>
                </div>
                <div class="flex items-center gap-1.5 min-w-0">
                  <span class="i-lucide-file-text w-3.5 h-3.5 text-n-slate-9 shrink-0" />
                  <span class="text-xs text-n-slate-11">
                    {{ r.open_invoices_count }}
                    {{ r.open_invoices_count === 1 ? 'fatura' : 'faturas' }}
                  </span>
                </div>
                <div class="flex items-center gap-1.5 col-span-2 min-w-0">
                  <span class="i-lucide-circle-dollar-sign w-3.5 h-3.5 text-n-ruby-9 shrink-0" />
                  <span class="text-xs font-semibold text-n-ruby-11 tabular-nums">
                    {{ formatCurrency(r.total_debt) }}
                  </span>
                  <span class="text-xs text-n-slate-10 ml-auto shrink-0">
                    venc. {{ formatDate(r.oldest_due_date) }}
                  </span>
                </div>
              </div>

              <!-- Actions -->
              <div class="flex gap-2 px-4 pb-4">
                <button
                  class="flex-1 flex items-center justify-center gap-1.5 h-8 rounded-lg border border-n-weak text-xs font-medium text-n-slate-11 hover:bg-n-slate-3 transition-colors"
                >
                  <span class="i-lucide-eye w-3.5 h-3.5" />
                  Detalhes
                </button>
                <button
                  class="flex-1 flex items-center justify-center gap-1.5 h-8 rounded-lg bg-n-brand text-white text-xs font-semibold hover:bg-n-brand/90 transition-colors"
                >
                  <span class="i-lucide-send w-3.5 h-3.5" />
                  Disparar
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>
  </section>
</template>
