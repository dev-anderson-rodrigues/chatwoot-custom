import { frontendURL } from '../../../helper/URLHelper';
import CobrancaIndex from './pages/CobrancaIndex.vue';
import RelatoriosCobranca from './pages/RelatoriosCobranca.vue';

const meta = { permissions: ['administrator', 'agent'] };

export const routes = [
  {
    path: frontendURL('accounts/:accountId/cobranca'),
    name: 'gestao_cobranca_index',
    component: CobrancaIndex,
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/cobranca/relatorios'),
    name: 'gestao_cobranca_relatorios',
    component: RelatoriosCobranca,
    meta,
  },
];
