import { frontendURL } from '../../../helper/URLHelper';
import CobrancaIndex from './pages/CobrancaIndex.vue';

const meta = { permissions: ['administrator', 'agent'] };

export const routes = [
  {
    path: frontendURL('accounts/:accountId/cobranca'),
    name: 'gestao_cobranca_index',
    component: CobrancaIndex,
    meta,
  },
];
