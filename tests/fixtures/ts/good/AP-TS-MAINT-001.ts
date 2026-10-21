import { accountSchema, tokenSchema, type Account, type TokenEnvelope } from './schema';

// ok: slopguard.ts.double-cast — the schema already returns Account; the value is
// parsed at the boundary and never widened and re-asserted.
export function loadAccount(raw: string): Account {
  return accountSchema.parse(raw);
}

// ok: slopguard.ts.double-cast — same for the token envelope: one parse, typed end to end.
export function readToken(res: Response): TokenEnvelope {
  return tokenSchema.parse(res.body);
}