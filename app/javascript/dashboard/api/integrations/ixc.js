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
}

export default new IxcAPI();
