<script setup>
import { ref, computed, watch } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import IxcAPI from '../../../api/integrations/ixc';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
  inboxId: { type: Number, default: undefined },
  contactEmail: { type: String, default: '' },
});

const { t } = useI18n();

const state = ref('idle');
const customer = ref(null);
const invoices = ref([]);
const contracts = ref([]);
const candidates = ref([]);
const errorMsg = ref('');

const maxOverdueDays = computed(() => {
  const days = invoices.value.map(i => parseInt(i.atraso) || 0);
  return days.length ? Math.max(...days) : 0;
});

const totalDebt = computed(() => {
  const sum = invoices.value.reduce((acc, i) => acc + parseFloat(i.valor || 0), 0);
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(sum);
});

const openInvoicesCount = computed(() => invoices.value.length);

const firstContract = computed(() => contracts.value.find(c => c.status === 'A') || contracts.value[0]);

const oldestDueDate = computed(() => {
  const dates = invoices.value.map(i => i.data_vencimento).filter(Boolean).sort();
  return dates[0] ? formatDate(dates[0]) : '—';
});

const formatDate = dateStr => {
  if (!dateStr) return '—';
  const [y, m, d] = dateStr.split('-');
  return `${d}/${m}/${y}`;
};

const fetchCustomer = async () => {
  state.value = 'loading';
  errorMsg.value = '';
  try {
    const response = await IxcAPI.getCustomer(props.contactId, props.inboxId);
    const data = response.data;
    if (data.status === 'linked') {
      customer.value = data.customer;
      invoices.value = data.invoices || [];
      contracts.value = data.contracts || [];
      state.value = 'linked';
    } else if (data.status === 'ambiguous') {
      candidates.value = data.candidates || [];
      state.value = 'ambiguous';
    } else {
      state.value = 'not_found';
    }
  } catch (e) {
    errorMsg.value = e.response?.data?.error || t('CONVERSATION_SIDEBAR.IXC.ERROR');
    state.value = 'error';
  }
};

watch(() => props.contactId, fetchCustomer, { immediate: true });
</script>

<template>
  <div class="text-n-slate-12 text-sm">
    <!-- Loading -->
    <div v-if="state === 'loading'" class="flex justify-center items-center py-6">
      <Spinner size="24" class="text-n-brand" />
    </div>

    <!-- Error -->
    <div v-else-if="state === 'error'" class="px-4 py-3">
      <p class="text-n-ruby-11 text-xs text-center mb-2">{{ errorMsg }}</p>
      <button class="w-full text-xs text-n-slate-11 hover:text-n-brand text-center" @click="fetchCustomer">
        {{ $t('CONVERSATION_SIDEBAR.IXC.RETRY') }}
      </button>
    </div>

    <!-- Not found -->
    <div v-else-if="state === 'not_found'" class="px-4 py-3 text-center">
      <p class="text-n-slate-11 text-xs mb-2">{{ $t('CONVERSATION_SIDEBAR.IXC.NOT_FOUND') }}</p>
      <button class="text-xs text-n-brand hover:underline" @click="fetchCustomer">
        {{ $t('CONVERSATION_SIDEBAR.IXC.RETRY') }}
      </button>
    </div>

    <!-- Ambiguous -->
    <div v-else-if="state === 'ambiguous'" class="px-4 py-3">
      <p class="text-n-slate-11 text-xs mb-2">{{ $t('CONVERSATION_SIDEBAR.IXC.AMBIGUOUS') }}</p>
      <div
        v-for="c in candidates"
        :key="c.id"
        class="border border-n-weak rounded-lg px-3 py-2 mb-2 text-xs"
      >
        <p class="font-semibold">{{ c.razao || c.nome }}</p>
        <p class="text-n-slate-11">{{ c.cnpj_cpf }}</p>
      </div>
    </div>

    <!-- Linked — card style matching reference -->
    <div v-else-if="state === 'linked'" class="px-3 py-3">
      <div class="rounded-xl bg-n-slate-2 outline outline-1 outline-n-container -outline-offset-1 p-4">
        <!-- Header: name + overdue badge -->
        <div class="flex items-start justify-between gap-2 mb-3">
          <p class="font-bold text-n-slate-12 text-sm uppercase leading-tight flex-1 min-w-0">
            {{ customer?.razao || customer?.nome }}
          </p>
          <span
            v-if="maxOverdueDays > 0"
            class="shrink-0 rounded-full bg-n-ruby-9 text-white text-xs font-semibold px-2.5 py-0.5 whitespace-nowrap"
          >
            {{ maxOverdueDays }} Dias Vencidos
          </span>
          <span
            v-else
            class="shrink-0 rounded-full bg-n-teal-9 text-white text-xs font-semibold px-2.5 py-0.5"
          >
            Em dia
          </span>
        </div>

        <!-- Info grid 2 columns -->
        <div class="grid grid-cols-2 gap-x-3 gap-y-2 mb-3">
          <!-- Phone -->
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="i-lucide-phone text-n-ruby-9 shrink-0 w-3.5 h-3.5" />
            <span class="text-xs text-n-slate-12 truncate">{{ customer?.telefone_celular || customer?.fone || '—' }}</span>
          </div>
          <!-- CPF/CNPJ -->
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="i-lucide-id-card text-n-slate-9 shrink-0 w-3.5 h-3.5" />
            <span class="text-xs text-n-slate-11 truncate">{{ customer?.cnpj_cpf || '—' }}</span>
          </div>
          <!-- Faturas em aberto -->
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="i-lucide-file-text text-n-ruby-9 shrink-0 w-3.5 h-3.5" />
            <span class="text-xs text-n-slate-11">{{ openInvoicesCount }} faturas em aberto</span>
          </div>
          <!-- Contract -->
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="i-lucide-wifi text-n-teal-9 shrink-0 w-3.5 h-3.5" />
            <span class="text-xs text-n-slate-11 truncate">
              {{ firstContract ? `Contrato ${firstContract.id}` : '—' }}
            </span>
          </div>
          <!-- Total debt -->
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="i-lucide-circle-dollar-sign text-n-teal-9 shrink-0 w-3.5 h-3.5" />
            <span class="text-xs font-semibold text-n-ruby-11">{{ totalDebt }}</span>
          </div>
          <!-- Oldest due date -->
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="i-lucide-calendar text-n-slate-9 shrink-0 w-3.5 h-3.5" />
            <span class="text-xs text-n-slate-11">{{ oldestDueDate }}</span>
          </div>
          <!-- Email -->
          <div v-if="contactEmail" class="flex items-center gap-1.5 min-w-0 col-span-2">
            <span class="i-lucide-mail text-n-slate-9 shrink-0 w-3.5 h-3.5" />
            <span class="text-xs text-n-slate-11 truncate">{{ contactEmail }}</span>
          </div>
          <!-- ID do cadastro IXC -->
          <div v-if="customer?.id" class="flex items-center gap-1.5 min-w-0">
            <span class="i-lucide-hash text-n-slate-9 shrink-0 w-3.5 h-3.5" />
            <span class="text-xs text-n-slate-11">Cód. {{ customer.id }}</span>
          </div>
        </div>

        <!-- Footer: cobranças + promessa -->
        <div class="flex items-center gap-4 mb-3 pb-3 border-b border-n-weak">
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="i-lucide-send w-3.5 h-3.5 shrink-0 text-n-slate-10" />
            <span class="text-xs text-n-slate-10">Sem cobranças enviadas</span>
          </div>
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="i-lucide-heart w-3.5 h-3.5 shrink-0 text-n-slate-10" />
            <span class="text-xs text-n-slate-10 whitespace-nowrap">Sem promessa</span>
          </div>
        </div>

        <!-- Action buttons -->
        <div class="flex gap-2">
          <button
            class="flex-1 flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-lg border border-n-weak text-xs font-medium text-n-slate-11 hover:bg-n-slate-3 transition-colors"
          >
            <span class="i-lucide-external-link w-3 h-3" />
            Ver detalhes
          </button>
          <button
            class="flex-1 flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-lg bg-amber-500 hover:bg-amber-600 text-white text-xs font-semibold transition-colors"
          >
            <span class="i-lucide-send w-3 h-3" />
            Disparar
          </button>
        </div>
      </div>
    </div>

    <!-- Idle -->
    <div v-else class="px-4 py-3 text-center">
      <button class="text-xs text-n-brand hover:underline" @click="fetchCustomer">
        {{ $t('CONVERSATION_SIDEBAR.IXC.LOAD') }}
      </button>
    </div>
  </div>
</template>
