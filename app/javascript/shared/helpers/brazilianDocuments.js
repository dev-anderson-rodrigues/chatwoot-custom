/**
 * [FORK] Validação e máscara de CPF e CNPJ.
 *
 * Arquivo próprio, e não uma adição ao shared/helpers/Validators.js, para não
 * criar superfície de conflito num arquivo do upstream.
 *
 * Confere o dígito verificador, não só a quantidade de dígitos. A diferença
 * importa: o agente digita esses números lendo do cliente por telefone, e
 * "12345678901" tem 11 dígitos sem ser um CPF. Errar aqui vira macro executada
 * com documento inválido.
 */

const onlyDigits = value => String(value ?? '').replace(/\D/g, '');

/**
 * Sequência de dígitos repetidos (00000000000, 11111111111...) passa na conta
 * do dígito verificador, mas não é documento. Precisa ser barrada à parte.
 */
const isRepeatedSequence = digits => /^(\d)\1+$/.test(digits);

/**
 * Dígito verificador no padrão da Receita: soma ponderada, módulo 11, e resto
 * menor que 2 vira zero.
 *
 * @param {string} digits
 * @param {number[]} weights
 * @returns {number}
 */
const checkDigit = (digits, weights) => {
  const sum = weights.reduce(
    (total, weight, index) => total + Number(digits[index]) * weight,
    0
  );
  const remainder = sum % 11;

  return remainder < 2 ? 0 : 11 - remainder;
};

const CPF_FIRST_WEIGHTS = [10, 9, 8, 7, 6, 5, 4, 3, 2];
const CPF_SECOND_WEIGHTS = [11, 10, 9, 8, 7, 6, 5, 4, 3, 2];
const CNPJ_FIRST_WEIGHTS = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
const CNPJ_SECOND_WEIGHTS = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

/**
 * @param {string} value - com ou sem máscara
 * @returns {boolean}
 */
export const isValidCPF = value => {
  const digits = onlyDigits(value);

  if (digits.length !== 11 || isRepeatedSequence(digits)) return false;

  return (
    checkDigit(digits, CPF_FIRST_WEIGHTS) === Number(digits[9]) &&
    checkDigit(digits, CPF_SECOND_WEIGHTS) === Number(digits[10])
  );
};

/**
 * @param {string} value - com ou sem máscara
 * @returns {boolean}
 */
export const isValidCNPJ = value => {
  const digits = onlyDigits(value);

  if (digits.length !== 14 || isRepeatedSequence(digits)) return false;

  return (
    checkDigit(digits, CNPJ_FIRST_WEIGHTS) === Number(digits[12]) &&
    checkDigit(digits, CNPJ_SECOND_WEIGHTS) === Number(digits[13])
  );
};

/**
 * Máscara progressiva: formata o que já foi digitado sem exigir o documento
 * completo, para o campo não brigar com quem ainda está digitando.
 *
 * @param {string} value
 * @returns {string} ex.: 529.982.247-25
 */
export const formatCPF = value => {
  const digits = onlyDigits(value).slice(0, 11);

  return digits
    .replace(/^(\d{3})(\d)/, '$1.$2')
    .replace(/^(\d{3})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/^(\d{3})\.(\d{3})\.(\d{3})(\d)/, '$1.$2.$3-$4');
};

/**
 * @param {string} value
 * @returns {string} ex.: 11.222.333/0001-81
 */
export const formatCNPJ = value => {
  const digits = onlyDigits(value).slice(0, 14);

  return digits
    .replace(/^(\d{2})(\d)/, '$1.$2')
    .replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/^(\d{2})\.(\d{3})\.(\d{3})(\d)/, '$1.$2.$3/$4')
    .replace(/^(\d{2})\.(\d{3})\.(\d{3})\/(\d{4})(\d)/, '$1.$2.$3/$4-$5');
};

/**
 * Escolhe validador e máscara pelo tipo do input_field da macro.
 * Tipo desconhecido não valida nada — quem decide o conjunto de tipos é o
 * backend (Macro::INPUT_FIELD_TYPES).
 */
export const DOCUMENT_HANDLERS = {
  cpf: { isValid: isValidCPF, format: formatCPF },
  cnpj: { isValid: isValidCNPJ, format: formatCNPJ },
};
