import { accountSchema, type Account } from './schema';

// ruleid: slopguard.ts.double-cast
export function loadAccount(input: unknown): Account {
  const account = accountSchema.parse(input);
  const generic: Record<string, unknown> = account;
  return generic as unknown as Account;
}

// ruleid: slopguard.ts.double-cast
export function readToken(res: Response): { token: string } {
  return (res.body as unknown) as { token: string };
}

// ruleid: slopguard.ts.double-cast
export function angleBracket(raw: object): Account {
  return <Account>(<unknown>raw);
}
