/* global axios */

import ApiClient from '../ApiClient';

class IxcAPI extends ApiClient {
  constructor() {
    super('integrations/ixc', { accountScoped: true });
  }

  getCustomer(contactId, inboxId) {
    return axios.get(`${this.url}/customer`, {
      params: { contact_id: contactId, inbox_id: inboxId },
    });
  }

  getOverdueCustomers(page = 1, perPage = 50) {
    return axios.get(`${this.url}/overdue_customers`, {
      params: { page, per_page: perPage },
    });
  }
}

export default new IxcAPI();
