import { hasAnUpdateAvailable } from '../versionCheckHelper';

// [FORK] Aviso de atualização desativado — sempre retorna false.
describe('#hasAnUpdateAvailable', () => {
  it('always returns false regardless of versions', () => {
    expect(hasAnUpdateAvailable('1.1.0', '1.0.0')).toBe(false);
    expect(hasAnUpdateAvailable('0.1.0', '1.0.0')).toBe(false);
    expect(hasAnUpdateAvailable('invalid', '1.0.0')).toBe(false);
    expect(hasAnUpdateAvailable(null, '1.0.0')).toBe(false);
  });
});
