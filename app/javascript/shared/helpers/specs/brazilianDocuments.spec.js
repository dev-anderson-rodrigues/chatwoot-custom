import {
  isValidCPF,
  isValidCNPJ,
  formatCPF,
  formatCNPJ,
  DOCUMENT_HANDLERS,
} from '../brazilianDocuments';

describe('isValidCPF', () => {
  it.each(['529.982.247-25', '52998224725', '111.444.777-35'])(
    'accepts %s',
    value => {
      expect(isValidCPF(value)).toBe(true);
    }
  );

  it('accepts a CPF whose check digit is zero', () => {
    // 000.000.001-91 exercita o ramo "resto < 2 vira zero"
    expect(isValidCPF('00000000191')).toBe(true);
  });

  it('rejects a number with the right length but a wrong check digit', () => {
    expect(isValidCPF('52998224724')).toBe(false);
    expect(isValidCPF('12345678901')).toBe(false);
  });

  it.each([
    '00000000000',
    '11111111111',
    '99999999999',
    '123.456.789-09'.replace(/\D/g, '').replace(/./g, '7'),
  ])('rejects the repeated sequence %s', value => {
    expect(isValidCPF(value)).toBe(false);
  });

  it.each(['5299822472', '529982247251', '', '   ', 'abc'])(
    'rejects %s for having the wrong number of digits',
    value => {
      expect(isValidCPF(value)).toBe(false);
    }
  );

  it('does not blow up on null or undefined', () => {
    expect(isValidCPF(null)).toBe(false);
    expect(isValidCPF(undefined)).toBe(false);
  });

  it('ignores anything that is not a digit', () => {
    expect(isValidCPF('529 982 247 25')).toBe(true);
    expect(isValidCPF('CPF: 529.982.247-25')).toBe(true);
  });
});

describe('isValidCNPJ', () => {
  it.each(['11.222.333/0001-81', '11222333000181'])('accepts %s', value => {
    expect(isValidCNPJ(value)).toBe(true);
  });

  it('rejects a number with the right length but a wrong check digit', () => {
    expect(isValidCNPJ('11222333000182')).toBe(false);
    expect(isValidCNPJ('12345678901234')).toBe(false);
  });

  it.each(['00000000000000', '11111111111111'])(
    'rejects the repeated sequence %s',
    value => {
      expect(isValidCNPJ(value)).toBe(false);
    }
  );

  it.each(['1122233300018', '112223330001811', '', 'abc'])(
    'rejects %s for having the wrong number of digits',
    value => {
      expect(isValidCNPJ(value)).toBe(false);
    }
  );

  it('does not blow up on null or undefined', () => {
    expect(isValidCNPJ(null)).toBe(false);
    expect(isValidCNPJ(undefined)).toBe(false);
  });

  it('does not accept a valid CPF as a CNPJ', () => {
    expect(isValidCNPJ('52998224725')).toBe(false);
  });
});

describe('formatCPF', () => {
  it.each([
    ['5', '5'],
    ['529', '529'],
    ['5299', '529.9'],
    ['529982', '529.982'],
    ['5299822', '529.982.2'],
    ['529982247', '529.982.247'],
    ['5299822472', '529.982.247-2'],
    ['52998224725', '529.982.247-25'],
  ])('formats %s progressively as %s', (input, expected) => {
    expect(formatCPF(input)).toBe(expected);
  });

  it('drops anything past 11 digits', () => {
    expect(formatCPF('529982247259999')).toBe('529.982.247-25');
  });

  it('reformats a value that already has a mask', () => {
    expect(formatCPF('529.982.247-25')).toBe('529.982.247-25');
  });

  it('returns an empty string for empty input', () => {
    expect(formatCPF('')).toBe('');
    expect(formatCPF(null)).toBe('');
  });
});

describe('formatCNPJ', () => {
  it.each([
    ['11', '11'],
    ['112', '11.2'],
    ['11222', '11.222'],
    ['112223', '11.222.3'],
    ['11222333', '11.222.333'],
    ['112223330', '11.222.333/0'],
    ['112223330001', '11.222.333/0001'],
    ['1122233300018', '11.222.333/0001-8'],
    ['11222333000181', '11.222.333/0001-81'],
  ])('formats %s progressively as %s', (input, expected) => {
    expect(formatCNPJ(input)).toBe(expected);
  });

  it('drops anything past 14 digits', () => {
    expect(formatCNPJ('112223330001819999')).toBe('11.222.333/0001-81');
  });

  it('returns an empty string for empty input', () => {
    expect(formatCNPJ('')).toBe('');
    expect(formatCNPJ(null)).toBe('');
  });
});

describe('DOCUMENT_HANDLERS', () => {
  it('maps the macro input field type to its validator and mask', () => {
    expect(DOCUMENT_HANDLERS.cpf.isValid('529.982.247-25')).toBe(true);
    expect(DOCUMENT_HANDLERS.cpf.format('52998224725')).toBe('529.982.247-25');
    expect(DOCUMENT_HANDLERS.cnpj.isValid('11222333000181')).toBe(true);
    expect(DOCUMENT_HANDLERS.cnpj.format('11222333000181')).toBe(
      '11.222.333/0001-81'
    );
  });

  it('has no handler for the other field types', () => {
    expect(DOCUMENT_HANDLERS.text).toBeUndefined();
    expect(DOCUMENT_HANDLERS.phone).toBeUndefined();
  });
});
