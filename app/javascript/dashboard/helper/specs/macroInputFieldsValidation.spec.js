import { validateMacroInputFields } from '../validations';

const field = (overrides = {}) => ({
  key: 'cpf',
  label: 'CPF',
  type: 'cpf',
  ...overrides,
});

describe('validateMacroInputFields', () => {
  it('returns no errors for an empty or missing list', () => {
    expect(validateMacroInputFields([])).toEqual({});
    expect(validateMacroInputFields(undefined)).toEqual({});
    expect(validateMacroInputFields(null)).toEqual({});
  });

  it('accepts a well formed field', () => {
    expect(validateMacroInputFields([field()])).toEqual({});
  });

  describe('key', () => {
    it('requires a key', () => {
      expect(validateMacroInputFields([field({ key: '  ' })])).toEqual({
        input_field_0: { key: 'KEY_REQUIRED' },
      });
    });

    it.each([
      ['CPF Cliente', 'espaços e maiúsculas'],
      ['1cpf', 'começando com dígito'],
      ['cpf-cliente', 'hífen'],
      ['cpf.cliente', 'ponto'],
    ])('rejects %s (%s)', key => {
      expect(validateMacroInputFields([field({ key })])).toEqual({
        input_field_0: { key: 'KEY_INVALID' },
      });
    });

    it.each(['cpf', 'nome_completo', 'campo2', 'a'])('accepts %s', key => {
      expect(validateMacroInputFields([field({ key })])).toEqual({});
    });

    it('flags only the second occurrence of a duplicated key', () => {
      const errors = validateMacroInputFields([
        field({ key: 'cpf' }),
        field({ key: 'cpf' }),
      ]);

      expect(errors.input_field_0).toBeUndefined();
      expect(errors.input_field_1).toEqual({ key: 'KEY_DUPLICATED' });
    });

    it('does not accuse a field of duplicating itself', () => {
      expect(validateMacroInputFields([field({ key: 'cpf' })])).toEqual({});
    });
  });

  describe('label', () => {
    it('requires a label', () => {
      expect(validateMacroInputFields([field({ label: '' })])).toEqual({
        input_field_0: { label: 'LABEL_REQUIRED' },
      });
    });

    it('rejects a whitespace-only label', () => {
      expect(validateMacroInputFields([field({ label: '   ' })])).toEqual({
        input_field_0: { label: 'LABEL_REQUIRED' },
      });
    });
  });

  describe('select', () => {
    it('requires at least one option', () => {
      expect(
        validateMacroInputFields([field({ type: 'select', options: [] })])
      ).toEqual({ input_field_0: { options: 'OPTIONS_REQUIRED' } });
    });

    it('accepts a select with options', () => {
      const options = [{ value: '1', label: 'Um' }];
      expect(
        validateMacroInputFields([field({ type: 'select', options })])
      ).toEqual({});
    });
  });

  describe('lookup', () => {
    const lookup = (overrides = {}) =>
      field({
        type: 'lookup',
        lookup_url: 'https://api.example.com/x',
        depends_on: ['cpf'],
        ...overrides,
      });

    it('accepts a well formed lookup', () => {
      expect(validateMacroInputFields([lookup()])).toEqual({});
    });

    it('requires a lookup_url', () => {
      expect(validateMacroInputFields([lookup({ lookup_url: '' })])).toEqual({
        input_field_0: { lookup_url: 'LOOKUP_URL_REQUIRED' },
      });
    });

    // eslint-disable-next-line no-script-url
    it.each(['ftp://x.com', 'javascript:alert(1)', 'nao-e-url'])(
      'rejects %s as lookup_url',
      lookup_url => {
        expect(validateMacroInputFields([lookup({ lookup_url })])).toEqual({
          input_field_0: { lookup_url: 'LOOKUP_URL_INVALID' },
        });
      }
    );

    it('requires at least one dependency', () => {
      expect(validateMacroInputFields([lookup({ depends_on: [] })])).toEqual({
        input_field_0: { depends_on: 'DEPENDS_ON_REQUIRED' },
      });
    });

    it('reports url and dependency problems together', () => {
      expect(
        validateMacroInputFields([lookup({ lookup_url: '', depends_on: [] })])
      ).toEqual({
        input_field_0: {
          lookup_url: 'LOOKUP_URL_REQUIRED',
          depends_on: 'DEPENDS_ON_REQUIRED',
        },
      });
    });
  });

  it('indexes errors by position and skips valid fields', () => {
    const errors = validateMacroInputFields([
      field({ key: 'ok' }),
      field({ key: '' }),
      field({ key: 'tambem_ok' }),
      field({ key: 'x', label: '' }),
    ]);

    expect(Object.keys(errors)).toEqual(['input_field_1', 'input_field_3']);
  });
});
