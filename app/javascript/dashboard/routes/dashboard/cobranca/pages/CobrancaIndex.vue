<script setup>
import { ref, computed, onMounted } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import IxcAPI from '../../../../api/integrations/ixc';

const loading = ref(false);
const error = ref('');
const records = ref([]);
const total = ref(0);
const page = ref(1);
const lastUpdate = ref(null);

const search = ref('');
const filterAtraso = ref('');
const filterDivida = ref('');

const ATRASO_RANGES = [
  { label: '1–30 dias', min: 1, max: 30 },
  { label: '31–60 dias', min: 31, max: 60 },
  { label: '61–90 dias', min: 61, max: 90 },
  { label: '+90 dias', min: 91, max: null },
  { label: '+180 dias', min: 181, max: null },
  { label: '+360 dias', min: 361, max: null },
  { label: '+720 dias', min: 721, max: null },
];

const DIVIDA_RANGES = [
  { label: 'Até R$ 200', min: 0, max: 200 },
  { label: 'R$ 200–500', min: 200, max: 500 },
  { label: 'R$ 500–1k', min: 500, max: 1000 },
  { label: 'R$ 1k+', min: 1000, max: null },
];

const filteredRecords = computed(() => {
  let list = records.value;

  if (search.value.trim()) {
    const q = search.value.toLowerCase();
    list = list.filter(r =>
      (r.name || '').toLowerCase().includes(q) ||
      (r.cpf_cnpj || '').replace(/\D/g, '').includes(q.replace(/\D/g, '')) ||
      (r.phone || '').replace(/\D/g, '').includes(q.replace(/\D/g, ''))
    );
  }

  if (filterAtraso.value) {
    const range = ATRASO_RANGES.find(r => r.label === filterAtraso.value);
    if (range) {
      list = list.filter(r =>
        r.max_overdue_days >= range.min &&
        (range.max === null || r.max_overdue_days <= range.max)
      );
    }
  }

  if (filterDivida.value) {
    const range = DIVIDA_RANGES.find(r => r.label === filterDivida.value);
    if (range) {
      list = list.filter(r =>
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

const formatCurrency = v =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

const formatDate = d => {
  if (!d) return '—';
  const [y, m, day] = d.split('-');
  return `${day}/${m}/${y}`;
};

const formatTime = d => {
  if (!d) return '—';
  return d.toLocaleString('pt-BR');
};

const toggleAtraso = value => {
  filterAtraso.value = filterAtraso.value === value ? '' : value;
};

const toggleDivida = value => {
  filterDivida.value = filterDivida.value === value ? '' : value;
};

const fetchData = async () => {
  loading.value = true;
  error.value = '';
  try {
    const res = await IxcAPI.getOverdueCustomers(1, 200);
    records.value = res.data.records || [];
    total.value = res.data.total || 0;
    lastUpdate.value = new Date();
  } catch (e) {
    error.value = e.response?.data?.error || 'Erro ao carregar dados do IXC';
  } finally {
    loading.value = false;
  }
};

onMounted(fetchData);
</script>

<template>
  <div class="flex flex-col h-full bg-n-background overflow-hidden">
    <!-- Header -->
    <div class="px-6 pt-6 pb-4 border-b border-n-weak shrink-0">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold text-n-slate-12">Gestão de Cobrança</h1>
          <p class="text-n-slate-10 text-sm mt-0.5">
            Acompanhe a base validada no ERP, identifique quem está em atraso e avance com a cobrança.
          </p>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <div v-if="lastUpdate" class="text-right mr-2">
            <p class="text-xs text-n-slate-10">Última atualização</p>
            <p class="text-xs font-semibold text-n-slate-12">{{ formatTime(lastUpdate) }}</p>
          </div>
          <button
            class="flex items-center gap-1.5 px-3 py-2 rounded-lg border border-n-weak text-xs font-medium text-n-slate-11 hover:bg-n-slate-3 transition-colors disabled:opacity-50"
            :disabled="loading"
            @click="fetchData"
          >
            <span class="i-lucide-refresh-cw w-3.5 h-3.5" :class="{ 'animate-spin': loading }" />
            Atualizar ERP
          </button>
        </div>
      </div>

      <!-- Stats row -->
      <div class="grid grid-cols-4 gap-3 mt-4">
        <div class="bg-n-slate-2 rounded-lg px-4 py-3">
          <div class="flex items-center gap-2 mb-1">
            <span class="i-lucide-users w-3.5 h-3.5 text-n-slate-10" />
            <span class="text-xs text-n-slate-10 uppercase tracking-wide">Clientes Vencidos</span>
          </div>
          <p class="text-2xl font-bold text-n-ruby-11">{{ filteredRecords.length }}</p>
        </div>
        <div class="bg-n-slate-2 rounded-lg px-4 py-3">
          <div class="flex items-center gap-2 mb-1">
            <span class="i-lucide-circle-dollar-sign w-3.5 h-3.5 text-n-slate-10" />
            <span class="text-xs text-n-slate-10 uppercase tracking-wide">Dívida Total</span>
          </div>
          <p class="text-2xl font-bold text-n-ruby-11">{{ formatCurrency(totalDebt) }}</p>
        </div>
        <div class="bg-n-slate-2 rounded-lg px-4 py-3">
          <div class="flex items-center gap-2 mb-1">
            <span class="i-lucide-database w-3.5 h-3.5 text-n-slate-10" />
            <span class="text-xs text-n-slate-10 uppercase tracking-wide">Fonte dos Dados</span>
          </div>
          <p class="text-sm font-semibold text-n-teal-11">Base IXC sincronizada</p>
        </div>
        <div class="bg-n-slate-2 rounded-lg px-4 py-3">
          <div class="flex items-center gap-2 mb-1">
            <span class="i-lucide-search w-3.5 h-3.5 text-n-slate-10" />
            <span class="text-xs text-n-slate-10 uppercase tracking-wide">Nesta Página</span>
          </div>
          <p class="text-2xl font-bold text-n-slate-12">{{ filteredRecords.length }}</p>
        </div>
      </div>
    </div>

    <!-- Filters -->
    <div class="px-6 py-3 border-b border-n-weak bg-n-slate-1 shrink-0">
      <!-- Search -->
      <div class="relative mb-3">
        <span class="i-lucide-search absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-n-slate-10" />
        <input
          v-model="search"
          type="text"
          placeholder="Buscar por nome, CPF/CNPJ ou telefone"
          class="w-full pl-9 pr-4 py-2 rounded-lg border border-n-weak bg-n-background text-sm text-n-slate-12 placeholder-n-slate-10 focus:outline-none focus:ring-1 focus:ring-n-brand"
        />
      </div>

      <!-- Atraso chips -->
      <div class="flex items-center gap-2 flex-wrap mb-2">
        <span class="text-xs text-n-slate-10 w-12 shrink-0">Atraso</span>
        <button
          v-for="range in ATRASO_RANGES"
          :key="range.label"
          class="px-2.5 py-1 rounded-full text-xs border transition-colors"
          :class="filterAtraso === range.label
            ? 'bg-n-brand text-white border-n-brand'
            : 'border-n-weak text-n-slate-11 hover:bg-n-slate-3'"
          @click="toggleAtraso(range.label)"
        >
          {{ range.label }}
        </button>
      </div>

      <!-- Dívida chips -->
      <div class="flex items-center gap-2 flex-wrap">
        <span class="text-xs text-n-slate-10 w-12 shrink-0">Dívida</span>
        <button
          v-for="range in DIVIDA_RANGES"
          :key="range.label"
          class="px-2.5 py-1 rounded-full text-xs border transition-colors"
          :class="filterDivida === range.label
            ? 'bg-n-brand text-white border-n-brand'
            : 'border-n-weak text-n-slate-11 hover:bg-n-slate-3'"
          @click="toggleDivida(range.label)"
        >
          {{ range.label }}
        </button>
      </div>
    </div>

    <!-- Content -->
    <div class="flex-1 overflow-y-auto px-6 py-4">
      <!-- Loading -->
      <div v-if="loading" class="flex justify-center items-center py-16">
        <Spinner size="32" class="text-n-brand" />
      </div>

      <!-- Error -->
      <div v-else-if="error" class="flex flex-col items-center justify-center py-16 gap-3">
        <span class="i-lucide-wifi-off w-10 h-10 text-n-slate-9" />
        <p class="text-n-ruby-11 text-sm font-medium">{{ error }}</p>
        <button
          class="px-4 py-2 rounded-lg border border-n-weak text-xs font-medium text-n-slate-11 hover:bg-n-slate-3"
          @click="fetchData"
        >
          Tentar novamente
        </button>
      </div>

      <!-- Empty -->
      <div v-else-if="!filteredRecords.length" class="flex flex-col items-center justify-center py-16 gap-2">
        <span class="i-lucide-check-circle w-10 h-10 text-n-teal-9" />
        <p class="text-n-slate-11 text-sm">Nenhum cliente em atraso encontrado</p>
      </div>

      <!-- Cards grid -->
      <div v-else class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-3">
        <div
          v-for="r in filteredRecords"
          :key="r.customer_id"
          class="bg-n-slate-2 border border-n-weak rounded-xl p-4 flex flex-col gap-3"
        >
          <!-- Card header -->
          <div class="flex items-start justify-between gap-2">
            <p class="font-bold text-n-slate-12 text-sm leading-tight">{{ r.name }}</p>
            <span class="shrink-0 rounded-full bg-n-ruby-9 text-white text-xs font-semibold px-2 py-0.5 whitespace-nowrap">
              {{ r.max_overdue_days }}d Vencido
            </span>
          </div>

          <!-- Info grid -->
          <div class="grid grid-cols-2 gap-x-3 gap-y-1.5">
            <div class="flex items-center gap-1.5">
              <span class="i-lucide-phone w-3.5 h-3.5 text-n-ruby-9 shrink-0" />
              <span class="text-xs text-n-slate-11 truncate">{{ r.phone || '—' }}</span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="i-lucide-id-card w-3.5 h-3.5 text-n-slate-10 shrink-0" />
              <span class="text-xs text-n-slate-11 truncate">{{ r.cpf_cnpj || '—' }}</span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="i-lucide-file-text w-3.5 h-3.5 text-n-slate-10 shrink-0" />
              <span class="text-xs text-n-slate-11">{{ r.open_invoices_count }} fatura{{ r.open_invoices_count !== 1 ? 's' : '' }}</span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="i-lucide-circle-dollar-sign w-3.5 h-3.5 text-n-ruby-9 shrink-0" />
              <span class="text-xs font-semibold text-n-ruby-11">{{ formatCurrency(r.total_debt) }}</span>
            </div>
            <div class="flex items-center gap-1.5 col-span-2">
              <span class="i-lucide-calendar w-3.5 h-3.5 text-n-slate-10 shrink-0" />
              <span class="text-xs text-n-slate-11">Venc. {{ formatDate(r.oldest_due_date) }}</span>
            </div>
          </div>

          <!-- Actions -->
          <div class="flex gap-2 pt-1 border-t border-n-weak">
            <button class="flex-1 flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-lg border border-n-weak text-xs font-medium text-n-slate-11 hover:bg-n-slate-3 transition-colors">
              <span class="i-lucide-eye w-3 h-3" />
              Ver detalhes
            </button>
            <button class="flex-1 flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-lg bg-n-brand text-white text-xs font-semibold hover:bg-n-brand/90 transition-colors">
              <span class="i-lucide-send w-3 h-3" />
              Disparar
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
