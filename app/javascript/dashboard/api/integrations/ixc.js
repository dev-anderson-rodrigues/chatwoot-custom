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

  getCustomerDetails(erpCustomerId) {
    return axios.get(`${this.url}/customer_details`, {
      params: { erp_customer_id: erpCustomerId },
    });
  }

  getPromises(contactId, erpCustomerId) {
    return axios.get(`${this.url}/promises`, {
      params: { contact_id: contactId, erp_customer_id: erpCustomerId },
    });
  }

  createPromise(contactId, erpCustomerId, promisedDate, amount, observacao) {
    return axios.post(`${this.url}/create_promise`, {
      contact_id: contactId,
      erp_customer_id: erpCustomerId,
      promised_date: promisedDate,
      amount: amount || null,
      observacao: observacao || null,
    });
  }

  deletePromise(contactId, erpCustomerId, id) {
    return axios.delete(`${this.url}/promises/${id}`, {
      params: { contact_id: contactId, erp_customer_id: erpCustomerId },
    });
  }

  getAttendances(contactId, erpCustomerId) {
    return axios.get(`${this.url}/attendances`, {
      params: { contact_id: contactId, erp_customer_id: erpCustomerId },
    });
  }

  createAttendance(contactId, erpCustomerId, canal, resultado, descricao) {
    return axios.post(`${this.url}/create_attendance`, {
      contact_id: contactId,
      erp_customer_id: erpCustomerId,
      canal,
      resultado,
      descricao,
    });
  }

  deleteAttendance(contactId, erpCustomerId, id) {
    return axios.delete(`${this.url}/attendances/${id}`, {
      params: { contact_id: contactId, erp_customer_id: erpCustomerId },
    });
  }

  getAttendanceStats(from, to) {
    return axios.get(`${this.url}/attendance_stats`, { params: { from, to } });
  }

  getPromiseStats(from, to) {
    return axios.get(`${this.url}/promise_stats`, { params: { from, to } });
  }
}

export default new IxcAPI();
