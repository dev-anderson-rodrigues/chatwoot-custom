<script setup>
import { ref, computed, watch } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import IxcAPI from '../../../api/integrations/ixc';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import IxcCustomerModal from './IxcCustomerModal.vue';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
  inboxId: { type: Number, default: undefined },
  contactEmail: { type: String, default: '' },
  contactPhone: { type: String, default: '' },
});

const { t } = useI18n();
const store = useStore();

const ixcApiUrl = computed(() => {
  const ixc = store.getters['integrations/getIntegration']('ixc');
  return ixc?.hooks?.[0]?.settings?.api_url || '';
});

const showModal = ref(false);

const openCustomerDetail = () => {
  if (!customer.value?.id) return;
  showModal.value = true;
};

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
    <div v-if="state === 'loading'">
      <div class="h-px bg-n-weak mx-4 mb-3" />
      <div class="flex justify-center items-center py-4">
        <Spinner size="20" class="text-n-brand" />
      </div>
    </div>

    <!-- Error -->
    <div v-else-if="state === 'error'">
      <div class="h-px bg-n-weak mx-4 mb-3" />
      <div class="px-4 py-2">
        <p class="text-n-ruby-11 text-xs mb-1">{{ errorMsg }}</p>
        <button class="text-xs text-n-brand hover:underline" @click="fetchCustomer">
          {{ $t('CONVERSATION_SIDEBAR.IXC.RETRY') }}
        </button>
      </div>
    </div>

    <!-- Not found -->
    <div v-else-if="state === 'not_found'">
      <div class="h-px bg-n-weak mx-4 mb-3" />
      <div class="px-4 py-2">
        <p class="text-n-slate-11 text-xs mb-1">{{ $t('CONVERSATION_SIDEBAR.IXC.NOT_FOUND') }}</p>
        <button class="text-xs text-n-brand hover:underline" @click="fetchCustomer">
          {{ $t('CONVERSATION_SIDEBAR.IXC.RETRY') }}
        </button>
      </div>
    </div>

    <!-- Ambiguous -->
    <div v-else-if="state === 'ambiguous'">
      <div class="h-px bg-n-weak mx-4 mb-3" />
      <div class="px-4 py-2">
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
    </div>

    <!-- Linked — inline style replacing ContactInfo rows -->
    <div v-else-if="state === 'linked'">
      <!-- Divider -->
      <div class="h-px bg-n-weak mx-4 mb-3" />

      <!-- Status badge row -->
      <div class="px-4 mb-2 flex items-center gap-2">
        <span
          v-if="maxOverdueDays > 0"
          class="rounded-full bg-n-ruby-9 text-white text-xs font-semibold px-2.5 py-0.5 whitespace-nowrap"
        >
          {{ maxOverdueDays }} Dias Vencidos
        </span>
        <span
          v-else
          class="rounded-full bg-n-teal-9 text-white text-xs font-semibold px-2.5 py-0.5"
        >
          Em dia
        </span>
        <span v-if="customer?.id" class="text-xs text-n-slate-10">Cód. {{ customer.id }}</span>
      </div>

      <!-- Info rows (estilo ContactInfoRow) -->
      <div class="flex flex-col gap-1 px-4 pb-1">
        <!-- Telefone IXC -->
        <div class="flex items-center gap-2 text-n-slate-11 h-5 ltr:-ml-1 rtl:-mr-1">
          <span class="i-lucide-phone shrink-0 ltr:ml-1 rtl:mr-1 text-n-ruby-9" style="width:14px;height:14px" />
          <span class="overflow-hidden text-sm whitespace-nowrap text-ellipsis">
            {{ customer?.telefone_celular || customer?.fone || contactPhone || '—' }}
          </span>
        </div>
        <!-- CPF/CNPJ -->
        <div class="flex items-center gap-2 text-n-slate-11 h-5 ltr:-ml-1 rtl:-mr-1">
          <span class="i-lucide-id-card shrink-0 ltr:ml-1 rtl:mr-1" style="width:14px;height:14px" />
          <span class="overflow-hidden text-sm whitespace-nowrap text-ellipsis">{{ customer?.cnpj_cpf || '—' }}</span>
        </div>
        <!-- Email -->
        <div v-if="contactEmail" class="flex items-center gap-2 text-n-slate-11 h-5 ltr:-ml-1 rtl:-mr-1">
          <span class="i-lucide-mail shrink-0 ltr:ml-1 rtl:mr-1" style="width:14px;height:14px" />
          <span class="overflow-hidden text-sm whitespace-nowrap text-ellipsis">{{ contactEmail }}</span>
        </div>
        <!-- Faturas em aberto -->
        <div class="flex items-center gap-2 h-5 ltr:-ml-1 rtl:-mr-1">
          <span class="i-lucide-file-text shrink-0 ltr:ml-1 rtl:mr-1 text-n-ruby-9" style="width:14px;height:14px" />
          <span class="text-sm text-n-slate-11">{{ openInvoicesCount }} faturas em aberto</span>
          <span v-if="maxOverdueDays > 0" class="text-xs text-n-slate-10 ml-1">· venc. {{ oldestDueDate }}</span>
        </div>
        <!-- Dívida total -->
        <div class="flex items-center gap-2 h-5 ltr:-ml-1 rtl:-mr-1">
          <span class="i-lucide-circle-dollar-sign shrink-0 ltr:ml-1 rtl:mr-1 text-n-slate-9" style="width:14px;height:14px" />
          <span class="text-sm font-semibold text-n-ruby-11">{{ totalDebt }}</span>
        </div>
        <!-- Contrato -->
        <div v-if="firstContract" class="flex items-center gap-2 text-n-slate-11 h-5 ltr:-ml-1 rtl:-mr-1">
          <span class="i-lucide-wifi shrink-0 ltr:ml-1 rtl:mr-1 text-n-teal-9" style="width:14px;height:14px" />
          <span class="text-sm whitespace-nowrap text-ellipsis">Contrato {{ firstContract.id }}</span>
        </div>
      </div>

      <!-- Footer cobranças/promessa -->
      <div class="flex items-center gap-4 mx-4 mt-2 mb-3 pt-2 border-t border-n-weak">
        <div class="flex items-center gap-1.5">
          <span class="i-lucide-send text-n-slate-10 shrink-0" style="width:12px;height:12px" />
          <span class="text-xs text-n-slate-10">Sem cobranças</span>
        </div>
        <div class="flex items-center gap-1.5">
          <span class="i-lucide-heart text-n-slate-10 shrink-0" style="width:12px;height:12px" />
          <span class="text-xs text-n-slate-10">Sem promessa</span>
        </div>
      </div>

      <!-- Botões de ação -->
      <div class="flex gap-2 px-4 pb-4">
        <button
          class="flex-1 flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-lg border border-n-weak text-xs font-medium text-n-slate-11 hover:bg-n-slate-3 transition-colors"
          @click="openCustomerDetail"
        >
          <span class="i-lucide-external-link" style="width:12px;height:12px" />
          Ver detalhes
        </button>
        <ComposeConversation :contact-id="String(contactId)">
          <template #trigger>
            <button
              class="flex-1 flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-lg bg-n-amber-9 text-n-slate-1 text-xs font-semibold transition-colors hover:opacity-90"
            >
              <span class="i-lucide-send" style="width:12px;height:12px" />
              Disparar
            </button>
          </template>
        </ComposeConversation>
      </div>
    </div>

    <!-- Idle -->
    <div v-else>
      <div class="h-px bg-n-weak mx-4 mb-3" />
      <div class="px-4 py-2 text-center">
        <button class="text-xs text-n-brand hover:underline" @click="fetchCustomer">
          {{ $t('CONVERSATION_SIDEBAR.IXC.LOAD') }}
        </button>
      </div>
    </div>
  </div>

  <IxcCustomerModal
    :show="showModal"
    :customer="customer"
    :invoices="invoices"
    :contact-id="contactId"
    :erp-customer-id="customer?.id || ''"
    @close="showModal = false"
  />
</template>
