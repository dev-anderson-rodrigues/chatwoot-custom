import {
  CONVERSATION_PERMISSIONS,
  ROLES,
} from 'dashboard/constants/permissions';
import { frontendURL } from '../../../helper/URLHelper';
import DashboardAppPage from './pages/DashboardAppPage.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/apps/:appId'),
    name: 'dashboard_app_page',
    component: DashboardAppPage,
    props: route => ({ appId: route.params.appId }),
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
  },
];
