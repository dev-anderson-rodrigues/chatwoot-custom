<script setup>
import { ref, watch } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import IxcAPI from '../../../api/integrations/ixc';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const { t } = useI18n();

const state = ref('idle'); // idle | loading | linked | ambiguous | not_found | error
const customer = ref(null);
const invoices = ref([]);
const contracts = ref([]);
const candidates = ref([]);
const errorMsg = ref('');

const statusLabel = status => {
  const map = { A: t('CONVERSATION_SIDEBAR.IXC.INVOICE_STATUS.OPEN'), B: t('CONVERSATION_SIDEBAR.IXC.INVOICE_STATUS.PAID'), C: t('CONVERSATION_SIDEBAR.IXC.INVOICE_STATUS.CANCELLED') };
  return map[status] || status;
};

const contractStatusLabel = status => {
  const map = { A: t('CONVERSATION_SIDEBAR.IXC.CONTRACT_STATUS.ACTIVE'), I: t('CONVERSATION_SIDEBAR.IXC.CONTRACT_STATUS.INACTIVE'), C: t('CONVERSATION_SIDEBAR.IXC.CONTRACT_STATUS.CANCELLED') };
  return map[status] || status;
};

const formatDate = dateStr => {
  if (!dateStr) return '';
  const [y, m, d] = dateStr.split('-');
  return `${d}/${m}/${y}`;
};

const formatCurrency = value => {
  const num = parseFloat(value);
  if (isNaN(num)) return value;
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(num);
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
  <div class="px-4 py-2 text-n-slate-12 text-sm">
    <!-- Loading -->
    <div v-if="state === 'loading'" class="flex justify-center items-center p-4">
      <Spinner size="24" class="text-n-brand" />
    </div>

    <!-- Error -->
    <div v-else-if="state === 'error'" class="text-center text-n-ruby-12 text-xs py-2">
      {{ errorMsg }}
    </div>

    <!-- Not found -->
    <div v-else-if="state === 'not_found'" class="text-center py-3">
      <p class="text-n-slate-11 text-xs mb-2">
        {{ $t('CONVERSATION_SIDEBAR.IXC.NOT_FOUND') }}
      </p>
      <button
        class="text-xs text-n-brand hover:underline"
        @click="fetchCustomer"
      >
        {{ $t('CONVERSATION_SIDEBAR.IXC.RETRY') }}
      </button>
    </div>

    <!-- Ambiguous - multiple candidates -->
    <div v-else-if="state === 'ambiguous'" class="py-2">
      <p class="text-n-slate-11 text-xs mb-2">
        {{ $t('CONVERSATION_SIDEBAR.IXC.AMBIGUOUS') }}
      </p>
      <div
        v-for="c in candidates"
        :key="c.id"
        class="border border-n-weak rounded-md px-3 py-2 mb-2 text-xs"
      >
        <p class="font-medium">{{ c.razao || c.nome }}</p>
        <p class="text-n-slate-11">{{ c.cnpj_cpf }}</p>
      </div>
    </div>

    <!-- Linked -->
    <div v-else-if="state === 'linked'">
      <!-- Customer info -->
      <div class="mb-3">
        <p class="font-semibold text-n-slate-12 truncate">{{ customer?.razao || customer?.nome }}</p>
        <p v-if="customer?.cnpj_cpf" class="text-n-slate-11 text-xs">{{ customer.cnpj_cpf }}</p>
        <p v-if="customer?.email" class="text-n-slate-11 text-xs truncate">{{ customer.email }}</p>
      </div>

      <!-- Invoices -->
      <div class="mb-3">
        <p class="text-n-slate-11 text-xs font-medium uppercase tracking-wide mb-1">
          {{ $t('CONVERSATION_SIDEBAR.IXC.INVOICES') }}
          <span class="ml-1 font-normal">({{ invoices.length }})</span>
        </p>
        <div v-if="!invoices.length" class="text-n-slate-11 text-xs">
          {{ $t('CONVERSATION_SIDEBAR.IXC.NO_INVOICES') }}
        </div>
        <div
          v-for="inv in invoices"
          :key="inv.id"
          class="border border-n-weak rounded-md px-3 py-2 mb-1.5"
        >
          <div class="flex items-center justify-between">
            <span class="font-medium">{{ formatCurrency(inv.valor) }}</span>
            <span
              class="text-xs px-1.5 py-0.5 rounded"
              :class="inv.status === 'A' ? 'bg-n-ruby-3 text-n-ruby-11' : 'bg-n-teal-3 text-n-teal-11'"
            >{{ statusLabel(inv.status) }}</span>
          </div>
          <div class="flex items-center justify-between mt-0.5">
            <span class="text-n-slate-11 text-xs">{{ $t('CONVERSATION_SIDEBAR.IXC.DUE') }}: {{ formatDate(inv.data_vencimento) }}</span>
            <span v-if="parseInt(inv.atraso) > 0" class="text-n-ruby-11 text-xs font-medium">
              {{ inv.atraso }}d {{ $t('CONVERSATION_SIDEBAR.IXC.LATE') }}
            </span>
          </div>
        </div>
      </div>

      <!-- Contracts -->
      <div>
        <p class="text-n-slate-11 text-xs font-medium uppercase tracking-wide mb-1">
          {{ $t('CONVERSATION_SIDEBAR.IXC.CONTRACTS') }}
          <span class="ml-1 font-normal">({{ contracts.length }})</span>
        </p>
        <div v-if="!contracts.length" class="text-n-slate-11 text-xs">
          {{ $t('CONVERSATION_SIDEBAR.IXC.NO_CONTRACTS') }}
        </div>
        <div
          v-for="ct in contracts"
          :key="ct.id"
          class="border border-n-weak rounded-md px-3 py-2 mb-1.5"
        >
          <div class="flex items-center justify-between">
            <span class="font-medium text-xs truncate pr-2">{{ ct.descricao || ct.id }}</span>
            <span
              class="text-xs px-1.5 py-0.5 rounded shrink-0"
              :class="ct.status === 'A' ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-slate-3 text-n-slate-11'"
            >{{ contractStatusLabel(ct.status) }}</span>
          </div>
          <p v-if="ct.velocidade" class="text-n-slate-11 text-xs mt-0.5">{{ ct.velocidade }}</p>
        </div>
      </div>

      <!-- Refresh link -->
      <button
        class="mt-2 text-xs text-n-slate-10 hover:text-n-brand w-full text-center"
        @click="fetchCustomer"
      >
        {{ $t('CONVERSATION_SIDEBAR.IXC.REFRESH') }}
      </button>
    </div>

    <!-- Idle fallback -->
    <div v-else class="text-center py-3">
      <button class="text-xs text-n-brand hover:underline" @click="fetchCustomer">
        {{ $t('CONVERSATION_SIDEBAR.IXC.LOAD') }}
      </button>
    </div>
  </div>
</template>
