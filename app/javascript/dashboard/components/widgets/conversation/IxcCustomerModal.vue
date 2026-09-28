<script setup>
import { ref, computed, watch } from 'vue';
import IxcAPI from '../../../api/integrations/ixc';
import { useStore } from 'dashboard/composables/store';

const props = defineProps({
  show: { type: Boolean, default: false },
  customer: { type: Object, default: null },
  invoices: { type: Array, default: () => [] },
  contactId: { type: [Number, String], required: true },
  erpCustomerId: { type: [Number, String], required: true },
});

const emit = defineEmits(['close']);

const store = useStore();
const currentUserId = computed(() => store.getters['auth/getCurrentUser']?.id);

const activeTab = ref('faturas');
const promises = ref([]);
const attendances = ref([]);
const loadingPromises = ref(false);
const loadingAttendances = ref(false);
const showPromiseForm = ref(false);
const showAttendanceForm = ref(false);
const confirmDeleteId = ref(null);
const confirmDeleteType = ref(null);
const deleteError = ref('');

const promiseForm = ref({ promised_date: '', amount: '', observacao: '' });
const attendanceForm = ref({ canal: 'WhatsApp', resultado: 'Sem contato', descricao: '' });

const CANAIS = ['WhatsApp', 'Telefone', 'Email', 'Presencial', 'SMS'];
const RESULTADOS = ['Sem contato', 'Contatado', 'Acordo realizado', 'Recusou pagamento', 'Número errado'];

const customerName = computed(() => props.customer?.razao || props.customer?.nome || '—');
const customerCpf = computed(() => props.customer?.cnpj_cpf || '—');
const customerPhone = computed(() => props.customer?.telefone_celular || props.customer?.fone || '—');
const totalDebt = computed(() => {
  const sum = props.invoices.reduce((acc, i) => acc + parseFloat(i.valor || 0), 0);
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(sum);
});
const overdueInvoicesCount = computed(() => props.invoices.length);

const formatDate = dateStr => {
  if (!dateStr) return '—';
  if (dateStr.includes('T')) {
    const d = new Date(dateStr);
    return d.toLocaleDateString('pt-BR');
  }
  const [y, m, d] = dateStr.split('-');
  return `${d}/${m}/${y}`;
};

const formatCurrency = val => {
  if (!val && val !== 0) return '—';
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(val);
};

const loadPromises = async () => {
  if (!props.erpCustomerId) return;
  loadingPromises.value = true;
  try {
    const res = await IxcAPI.getPromises(props.contactId, props.erpCustomerId);
    promises.value = res.data;
  } finally {
    loadingPromises.value = false;
  }
};

const loadAttendances = async () => {
  if (!props.erpCustomerId) return;
  loadingAttendances.value = true;
  try {
    const res = await IxcAPI.getAttendances(props.contactId, props.erpCustomerId);
    attendances.value = res.data;
  } finally {
    loadingAttendances.value = false;
  }
};

const submitPromise = async () => {
  if (!promiseForm.value.promised_date) return;
  try {
    await IxcAPI.createPromise(
      props.contactId,
      props.erpCustomerId,
      promiseForm.value.promised_date,
      promiseForm.value.amount || null,
      promiseForm.value.observacao || null
    );
    promiseForm.value = { promised_date: '', amount: '', observacao: '' };
    showPromiseForm.value = false;
    await loadPromises();
  } catch (e) {
    // silent
  }
};

const submitAttendance = async () => {
  try {
    await IxcAPI.createAttendance(
      props.contactId,
      props.erpCustomerId,
      attendanceForm.value.canal,
      attendanceForm.value.resultado,
      attendanceForm.value.descricao
    );
    attendanceForm.value = { canal: 'WhatsApp', resultado: 'Sem contato', descricao: '' };
    showAttendanceForm.value = false;
    await loadAttendances();
  } catch (e) {
    // silent
  }
};

const askDelete = (type, id) => {
  confirmDeleteId.value = id;
  confirmDeleteType.value = type;
  deleteError.value = '';
};

const cancelDelete = () => {
  confirmDeleteId.value = null;
  confirmDeleteType.value = null;
  deleteError.value = '';
};

const confirmDelete = async () => {
  deleteError.value = '';
  try {
    if (confirmDeleteType.value === 'promise') {
      await IxcAPI.deletePromise(props.contactId, props.erpCustomerId, confirmDeleteId.value);
      await loadPromises();
    } else {
      await IxcAPI.deleteAttendance(props.contactId, props.erpCustomerId, confirmDeleteId.value);
      await loadAttendances();
    }
    cancelDelete();
  } catch (e) {
    deleteError.value = e.response?.data?.error || 'Erro ao excluir.';
  }
};

watch(() => props.show, show => {
  if (show) {
    activeTab.value = 'faturas';
    showPromiseForm.value = false;
    showAttendanceForm.value = false;
    confirmDeleteId.value = null;
    confirmDeleteType.value = null;
    deleteError.value = '';
    loadPromises();
    loadAttendances();
  }
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center"
      style="background: rgba(0,0,0,0.65)"
      @click.self="emit('close')"
    >
      <div
        class="relative w-full max-w-xl rounded-xl overflow-hidden shadow-2xl"
        style="background:#1c1c1e; color:#f0f0f0; max-height:90vh; display:flex; flex-direction:column"
      >
        <!-- Close button -->
        <button
          class="absolute top-3 right-4 text-gray-400 hover:text-white text-lg leading-none"
          @click="emit('close')"
        >
          ✕
        </button>

        <!-- Header -->
        <div class="px-5 pt-5 pb-3">
          <h2 class="text-base font-bold text-white tracking-wide mb-1">{{ customerName }}</h2>
          <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-gray-400">
            <span class="flex items-center gap-1">
              <span class="i-lucide-id-card" style="width:12px;height:12px" />
              {{ customerCpf }}
            </span>
            <span class="flex items-center gap-1">
              <span class="i-lucide-phone" style="width:12px;height:12px" />
              {{ customerPhone }}
            </span>
            <span class="flex items-center gap-1">
              <span class="i-lucide-circle-dollar-sign" style="width:12px;height:12px" />
              {{ totalDebt }}
            </span>
            <span class="flex items-center gap-1">
              <span class="i-lucide-file-text" style="width:12px;height:12px" />
              {{ overdueInvoicesCount }} fatura(s) em aberto
            </span>
          </div>

          <!-- Stats row -->
          <div class="flex items-center gap-4 mt-3">
            <button
              class="flex items-center gap-1.5 text-xs font-medium transition-colors"
              :class="activeTab === 'faturas' ? 'text-amber-400' : 'text-gray-400 hover:text-gray-200'"
              @click="activeTab = 'faturas'"
              style="background:none;border:none;padding:0;cursor:pointer"
            >
              <span class="i-lucide-file-text" style="width:12px;height:12px" />
              {{ overdueInvoicesCount }} fatura(s)
            </button>
            <button
              class="flex items-center gap-1.5 text-xs font-medium transition-colors"
              :class="activeTab === 'promessas' ? 'text-amber-400' : 'text-gray-400 hover:text-gray-200'"
              @click="activeTab = 'promessas'"
              style="background:none;border:none;padding:0;cursor:pointer"
            >
              <span class="i-lucide-heart" style="width:12px;height:12px" />
              {{ promises.length }} promessa(s)
            </button>
            <button
              class="flex items-center gap-1.5 text-xs font-medium transition-colors"
              :class="activeTab === 'atendimentos' ? 'text-amber-400' : 'text-gray-400 hover:text-gray-200'"
              @click="activeTab = 'atendimentos'"
              style="background:none;border:none;padding:0;cursor:pointer"
            >
              <span class="i-lucide-clipboard-list" style="width:12px;height:12px" />
              {{ attendances.length }} atendimento(s)
            </button>
          </div>
        </div>

        <!-- Divider -->
        <div style="height:1px;background:#2c2c2e;flex-shrink:0" />

        <!-- Tabs -->
        <div class="flex px-5" style="border-bottom:1px solid #2c2c2e;flex-shrink:0">
          <button
            v-for="tab in [{ key:'faturas',label:'Faturas' },{ key:'promessas',label:'Promessas' },{ key:'atendimentos',label:'Atendimentos' }]"
            :key="tab.key"
            class="text-sm py-3 px-1 mr-5 font-medium transition-colors"
            :class="activeTab === tab.key
              ? 'text-amber-400 border-b-2 border-amber-400'
              : 'text-gray-400 border-b-2 border-transparent hover:text-gray-200'"
            style="background:none;border:none;border-bottom-style:solid;cursor:pointer;margin-bottom:-1px"
            @click="activeTab = tab.key"
          >
            {{ tab.label }}
          </button>
        </div>

        <!-- Confirm delete overlay -->
        <div
          v-if="confirmDeleteId"
          class="absolute inset-0 z-10 flex items-center justify-center"
          style="background:rgba(0,0,0,0.7)"
        >
          <div class="rounded-xl p-5 w-72" style="background:#2c2c2e;border:1px solid #3a3a3c">
            <p class="text-sm text-white font-semibold mb-1">Confirmar exclusão</p>
            <p class="text-xs text-gray-400 mb-4">
              Este registro será removido e um log ficará registrado com seu nome e data.
            </p>
            <p v-if="deleteError" class="text-xs text-red-400 mb-3">{{ deleteError }}</p>
            <div class="flex justify-end gap-2">
              <button
                class="text-sm px-4 py-1.5 rounded-lg font-medium"
                style="background:none;border:1px solid #3a3a3c;color:#e0e0e0;cursor:pointer"
                @click="cancelDelete"
              >
                Cancelar
              </button>
              <button
                class="text-sm px-4 py-1.5 rounded-lg font-semibold"
                style="background:#b91c1c;color:#fff;border:none;cursor:pointer"
                @click="confirmDelete"
              >
                Excluir
              </button>
            </div>
          </div>
        </div>

        <!-- Tab content -->
        <div class="overflow-y-auto flex-1">

          <!-- Faturas -->
          <div v-if="activeTab === 'faturas'" class="px-5 pt-4 pb-5">
            <div v-if="invoices.length === 0" class="text-center text-gray-500 text-sm py-8">
              Nenhuma fatura em aberto.
            </div>
            <table v-else class="w-full text-sm">
              <thead>
                <tr style="border-bottom:1px solid #2c2c2e">
                  <th class="text-left text-xs font-semibold text-gray-500 pb-2 pr-3">CONTRATO</th>
                  <th class="text-left text-xs font-semibold text-gray-500 pb-2 pr-3">VENCIMENTO</th>
                  <th class="text-left text-xs font-semibold text-gray-500 pb-2 pr-3">VALOR</th>
                  <th class="text-left text-xs font-semibold text-gray-500 pb-2">STATUS</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="inv in invoices"
                  :key="inv.id"
                  style="border-bottom:1px solid #2c2c2e"
                >
                  <td class="py-2.5 pr-3 text-gray-300">{{ inv.id_contrato || '—' }}</td>
                  <td class="py-2.5 pr-3 text-gray-300">{{ formatDate(inv.data_vencimento) }}</td>
                  <td class="py-2.5 pr-3 text-gray-200 font-medium">{{ formatCurrency(inv.valor) }}</td>
                  <td class="py-2.5">
                    <span class="text-xs font-semibold px-2 py-0.5 rounded" style="background:#7f1d1d;color:#fca5a5">
                      A Receber
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <!-- Promessas -->
          <div v-else-if="activeTab === 'promessas'" class="px-5 pt-4 pb-5">
            <div class="flex items-center justify-between mb-4">
              <span class="text-sm font-semibold text-gray-200">Promessas de pagamento</span>
              <button
                v-if="!showPromiseForm"
                class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg transition-colors"
                style="border:1px solid #3a3a3c;color:#e0e0e0;background:none;cursor:pointer"
                @click="showPromiseForm = true"
              >
                <span class="i-lucide-plus" style="width:12px;height:12px" />
                Nova promessa
              </button>
            </div>

            <!-- Promise form -->
            <div
              v-if="showPromiseForm"
              class="rounded-xl p-4 mb-4"
              style="background:#2c2c2e;border:1px solid #3a3a3c"
            >
              <div class="mb-3">
                <label class="block text-xs font-semibold text-gray-400 mb-1.5 tracking-wide">DATA PROMETIDA</label>
                <input
                  v-model="promiseForm.promised_date"
                  type="date"
                  class="w-full rounded-lg px-3 py-2 text-sm"
                  style="background:#1c1c1e;border:1px solid #3a3a3c;color:#f0f0f0;outline:none"
                />
              </div>
              <div class="mb-3">
                <label class="block text-xs font-semibold text-gray-400 mb-1.5 tracking-wide">VALOR PROMETIDO (OPCIONAL)</label>
                <input
                  v-model="promiseForm.amount"
                  type="number"
                  step="0.01"
                  placeholder="R$ 0,00"
                  class="w-full rounded-lg px-3 py-2 text-sm"
                  style="background:#1c1c1e;border:1px solid #3a3a3c;color:#f0f0f0;outline:none"
                />
              </div>
              <div class="mb-4">
                <label class="block text-xs font-semibold text-gray-400 mb-1.5 tracking-wide">OBSERVAÇÃO (OPCIONAL)</label>
                <textarea
                  v-model="promiseForm.observacao"
                  rows="2"
                  placeholder="Observações sobre a promessa..."
                  class="w-full rounded-lg px-3 py-2 text-sm resize-none"
                  style="background:#1c1c1e;border:1px solid #3a3a3c;color:#f0f0f0;outline:none"
                />
              </div>
              <div class="flex justify-end gap-2">
                <button
                  class="text-sm px-4 py-1.5 rounded-lg font-medium"
                  style="background:none;border:1px solid #3a3a3c;color:#e0e0e0;cursor:pointer"
                  @click="showPromiseForm = false; promiseForm = { promised_date: '', amount: '', observacao: '' }"
                >
                  Cancelar
                </button>
                <button
                  class="text-sm px-4 py-1.5 rounded-lg font-semibold"
                  style="background:#d97706;color:#fff;border:none;cursor:pointer"
                  @click="submitPromise"
                >
                  Salvar
                </button>
              </div>
            </div>

            <div v-if="loadingPromises" class="text-center text-gray-500 text-sm py-6">Carregando...</div>
            <div v-else-if="promises.length === 0 && !showPromiseForm" class="text-center text-gray-500 text-sm py-6">
              Nenhuma promessa registrada.
            </div>
            <div v-else class="flex flex-col gap-2">
              <div
                v-for="p in promises"
                :key="p.id"
                class="rounded-lg px-3 py-2.5"
                style="background:#2c2c2e"
              >
                <div class="flex items-start justify-between gap-2">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="i-lucide-calendar text-amber-400 shrink-0" style="width:14px;height:14px" />
                    <span class="text-sm text-gray-200">{{ formatDate(p.promised_date) }}</span>
                    <span v-if="p.amount" class="text-sm font-semibold text-amber-400">{{ formatCurrency(p.amount) }}</span>
                  </div>
                  <button
                    class="shrink-0 text-gray-600 hover:text-red-400 transition-colors"
                    style="background:none;border:none;padding:2px;cursor:pointer"
                    title="Excluir"
                    @click="askDelete('promise', p.id)"
                  >
                    <span class="i-lucide-trash-2" style="width:13px;height:13px" />
                  </button>
                </div>
                <p v-if="p.observacao" class="text-xs text-gray-400 mt-1 ml-5">{{ p.observacao }}</p>
                <p class="text-xs text-gray-500 mt-1 ml-5">
                  <span class="i-lucide-user" style="width:11px;height:11px;display:inline-block;vertical-align:-2px;margin-right:3px" />
                  {{ p.created_by_name || 'Operador desconhecido' }} · {{ formatDate(p.created_at) }}
                </p>
              </div>
            </div>
          </div>

          <!-- Atendimentos -->
          <div v-else-if="activeTab === 'atendimentos'" class="px-5 pt-4 pb-5">
            <div class="flex items-center justify-between mb-4">
              <span class="text-sm font-semibold text-gray-200">Histórico de atendimentos</span>
              <button
                v-if="!showAttendanceForm"
                class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg transition-colors"
                style="border:1px solid #3a3a3c;color:#e0e0e0;background:none;cursor:pointer"
                @click="showAttendanceForm = true"
              >
                <span class="i-lucide-plus" style="width:12px;height:12px" />
                Novo atendimento
              </button>
            </div>

            <!-- Attendance form -->
            <div
              v-if="showAttendanceForm"
              class="rounded-xl p-4 mb-4"
              style="background:#2c2c2e;border:1px solid #3a3a3c"
            >
              <div class="mb-3">
                <label class="block text-xs font-semibold text-gray-400 mb-1.5 tracking-wide">CANAL</label>
                <select
                  v-model="attendanceForm.canal"
                  class="w-full rounded-lg px-3 py-2 text-sm"
                  style="background:#1c1c1e;border:1px solid #3a3a3c;color:#f0f0f0;outline:none"
                >
                  <option v-for="c in CANAIS" :key="c" :value="c">{{ c }}</option>
                </select>
              </div>
              <div class="mb-3">
                <label class="block text-xs font-semibold text-gray-400 mb-1.5 tracking-wide">RESULTADO</label>
                <select
                  v-model="attendanceForm.resultado"
                  class="w-full rounded-lg px-3 py-2 text-sm"
                  style="background:#1c1c1e;border:1px solid #3a3a3c;color:#f0f0f0;outline:none"
                >
                  <option v-for="r in RESULTADOS" :key="r" :value="r">{{ r }}</option>
                </select>
              </div>
              <div class="mb-4">
                <label class="block text-xs font-semibold text-gray-400 mb-1.5 tracking-wide">DESCRIÇÃO</label>
                <textarea
                  v-model="attendanceForm.descricao"
                  rows="3"
                  placeholder="Descreva o atendimento..."
                  class="w-full rounded-lg px-3 py-2 text-sm resize-none"
                  style="background:#1c1c1e;border:1px solid #3a3a3c;color:#f0f0f0;outline:none"
                />
              </div>
              <div class="flex justify-end gap-2">
                <button
                  class="text-sm px-4 py-1.5 rounded-lg font-medium"
                  style="background:none;border:1px solid #3a3a3c;color:#e0e0e0;cursor:pointer"
                  @click="showAttendanceForm = false; attendanceForm = { canal: 'WhatsApp', resultado: 'Sem contato', descricao: '' }"
                >
                  Cancelar
                </button>
                <button
                  class="text-sm px-4 py-1.5 rounded-lg font-semibold"
                  style="background:#d97706;color:#fff;border:none;cursor:pointer"
                  @click="submitAttendance"
                >
                  Salvar
                </button>
              </div>
            </div>

            <div v-if="loadingAttendances" class="text-center text-gray-500 text-sm py-6">Carregando...</div>
            <div v-else-if="attendances.length === 0 && !showAttendanceForm" class="text-center text-gray-500 text-sm py-6">
              Nenhum atendimento registrado.
            </div>
            <div v-else class="flex flex-col gap-2">
              <div
                v-for="a in attendances"
                :key="a.id"
                class="rounded-lg px-3 py-2.5"
                style="background:#2c2c2e"
              >
                <div class="flex items-start justify-between gap-2">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="text-xs font-semibold text-amber-400">{{ a.canal }}</span>
                    <span class="text-xs text-gray-500">·</span>
                    <span class="text-xs text-gray-400">{{ a.resultado }}</span>
                  </div>
                  <button
                    class="shrink-0 text-gray-600 hover:text-red-400 transition-colors"
                    style="background:none;border:none;padding:2px;cursor:pointer"
                    title="Excluir"
                    @click="askDelete('attendance', a.id)"
                  >
                    <span class="i-lucide-trash-2" style="width:13px;height:13px" />
                  </button>
                </div>
                <p v-if="a.descricao" class="text-sm text-gray-300 mt-1">{{ a.descricao }}</p>
                <p class="text-xs text-gray-500 mt-1">
                  <span class="i-lucide-user" style="width:11px;height:11px;display:inline-block;vertical-align:-2px;margin-right:3px" />
                  {{ a.created_by_name || 'Operador desconhecido' }} · {{ formatDate(a.created_at) }}
                </p>
              </div>
            </div>
          </div>

        </div>
      </div>
    </div>
  </Teleport>
</template>
