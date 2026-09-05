import {
  interpolateDashboardAppUrl,
  interpolateDashboardAppConfig,
} from '../dashboardAppHelper';

const context = {
  accountId: 7,
  user: {
    id: 42,
    email: 'ana@exemplo.com',
    name: 'Ana Souza',
    access_token: 'tok_abc123',
  },
};

describe('interpolateDashboardAppUrl', () => {
  it('replaces every supported variable', () => {
    const url = interpolateDashboardAppUrl(
      'https://erp.exemplo.com/p?c={account_id}&u={user_id}&e={user_email}&n={user_name}&t={user_token}',
      context
    );

    expect(url).toBe(
      'https://erp.exemplo.com/p?c=7&u=42&e=ana%40exemplo.com&n=Ana%20Souza&t=tok_abc123'
    );
  });

  it('leaves an unknown placeholder alone', () => {
    expect(
      interpolateDashboardAppUrl('https://e.com/{conversation_id}', context)
    ).toBe('https://e.com/{conversation_id}');
  });

  it('escapes a value that would rewrite the query string', () => {
    const url = interpolateDashboardAppUrl('https://e.com/?n={user_name}', {
      ...context,
      user: { ...context.user, name: 'Ana&admin=1' },
    });

    expect(url).toBe('https://e.com/?n=Ana%26admin%3D1');
  });

  it('does not substitute inside a value that looks like a variable', () => {
    const url = interpolateDashboardAppUrl('https://e.com/?n={user_name}', {
      ...context,
      user: { ...context.user, name: '{user_token}' },
    });

    // Um replace encadeado, como o da fonte, faria o token do proprio agente
    // entrar numa URL que so pedia o nome. O token so vai quando o admin pede.
    expect(url).toBe('https://e.com/?n=%7Buser_token%7D');
    expect(url).not.toContain('tok_abc123');
  });

  it('sends an empty value instead of the string "undefined"', () => {
    const url = interpolateDashboardAppUrl('https://e.com/?t={user_token}', {
      accountId: 7,
      user: { id: 42 },
    });

    expect(url).toBe('https://e.com/?t=');
  });

  it('returns falsy urls untouched', () => {
    expect(interpolateDashboardAppUrl('', context)).toBe('');
    expect(interpolateDashboardAppUrl(undefined, context)).toBe(undefined);
  });
});

describe('interpolateDashboardAppConfig', () => {
  it('resolves the url of every frame', () => {
    const config = interpolateDashboardAppConfig(
      [
        { type: 'frame', url: 'https://e.com/?c={account_id}' },
        { type: 'frame', url: 'https://e.com/?u={user_id}' },
      ],
      context
    );

    expect(config.map(item => item.url)).toEqual([
      'https://e.com/?c=7',
      'https://e.com/?u=42',
    ]);
  });

  it('keeps an item without url as it is', () => {
    const item = { type: 'frame' };

    expect(interpolateDashboardAppConfig([item], context)).toEqual([item]);
  });

  it('survives an empty config', () => {
    expect(interpolateDashboardAppConfig(undefined, context)).toEqual([]);
  });
});
