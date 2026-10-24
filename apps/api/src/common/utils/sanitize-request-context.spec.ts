import { isSecretKey, sanitizeRequestContext, MAX_CONTEXT_JSON_LENGTH } from './sanitize-request-context';

describe('isSecretKey', () => {
  it.each(['code', 'pin', 'password', 'token', 'otp', 'authorization', 'aadhaar', 'current_code', 'new_code', 'newCode', 'access_token', 'refresh-token', 'verificationToken', 'Password'])(
    'treats %s as secret',
    (key) => expect(isSecretKey(key)).toBe(true),
  );

  it.each(['phone', 'full_name', 'medical_conditions', 'shipping_area', 'spinal_care', 'hospital', 'description', 'type_of_nurse', 'codes_of_conduct_url_x'.replace('codes', 'rules')])(
    'does not treat %s as secret (no substring false positives)',
    (key) => expect(isSecretKey(key)).toBe(false),
  );
});

describe('sanitizeRequestContext', () => {
  it('keeps the real business data an admin needs (phone, names, fields)', () => {
    const ctx = sanitizeRequestContext({
      body: { phone: '+919876543210', full_name: 'Asha Rao', care_receiver: { age: 74, gender: 'female' } },
      params: { id: 'abc' },
      query: { page: '2' },
    });
    expect(ctx).toEqual({
      body: { phone: '+919876543210', full_name: 'Asha Rao', care_receiver: { age: 74, gender: 'female' } },
      params: { id: 'abc' },
      query: { page: '2' },
    });
  });

  it('never stores PINs, passwords, tokens or OTPs — at any depth', () => {
    const ctx = sanitizeRequestContext({
      body: {
        phone: '+919876543210',
        code: '1234',
        password: 'hunter2',
        nested: { refresh_token: 'rt', deeper: { otp: '999999', ok: 'fine' } },
        list: [{ current_code: '1111', keep: 1 }],
      },
    });
    const json = JSON.stringify(ctx);
    expect(json).not.toContain('1234');
    expect(json).not.toContain('hunter2');
    expect(json).not.toContain('"rt"');
    expect(json).not.toContain('999999');
    expect(json).not.toContain('1111');
    expect(ctx).toMatchObject({
      body: {
        phone: '+919876543210',
        code: '[redacted]',
        password: '[redacted]',
        nested: { refresh_token: '[redacted]', deeper: { otp: '[redacted]', ok: 'fine' } },
        list: [{ current_code: '[redacted]', keep: 1 }],
      },
    });
  });

  it('truncates long strings, big arrays, too many keys and deep nesting', () => {
    const ctx = sanitizeRequestContext({
      body: {
        long: 'x'.repeat(1000),
        arr: Array.from({ length: 50 }, (_, i) => i),
        deep: { a: { b: { c: { d: { e: 1 } } } } },
        ...Object.fromEntries(Array.from({ length: 60 }, (_, i) => [`k${i}`, i])),
      },
    }) as any;
    expect(ctx.body.long.length).toBeLessThan(400);
    expect(ctx.body.long).toContain('[+700 chars]');
    expect(ctx.body.arr).toHaveLength(21);
    expect(ctx.body.arr[20]).toBe('[+30 more]');
    expect(JSON.stringify(ctx.body.deep)).toContain('[truncated]');
    expect(ctx.body['[truncated]']).toMatch(/more keys/);
  });

  it('returns null when there is nothing to store', () => {
    expect(sanitizeRequestContext({})).toBeNull();
    expect(sanitizeRequestContext({ body: {}, query: {}, params: {} })).toBeNull();
    expect(sanitizeRequestContext({ body: undefined })).toBeNull();
  });

  it('degrades to a small preview when the whole context is still too large', () => {
    const wide = Object.fromEntries(Array.from({ length: 40 }, (_, i) => [`field_${i}`, 'y'.repeat(290)]));
    const ctx = sanitizeRequestContext({ body: wide }) as any;
    expect(JSON.stringify(wide).length).toBeGreaterThan(MAX_CONTEXT_JSON_LENGTH);
    expect(ctx.truncated).toBe(true);
    expect(JSON.stringify(ctx).length).toBeLessThan(2500);
  });

  it('does not choke on binary bodies or odd values', () => {
    const ctx = sanitizeRequestContext({ body: { file: Buffer.from('abc'), fn: () => 1 } }) as any;
    expect(ctx.body.file).toBe('[binary]');
    expect(ctx.body.fn).toBe('[unsupported]');
  });
});
