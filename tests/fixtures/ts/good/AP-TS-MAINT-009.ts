// Good: targeted spy on a specific export — UC-4 (no AP-TS-MAINT-009 finding)

import * as auth from '../auth';

declare const fakeUser: { id: string; name: string };

vi.spyOn(auth, 'getUser').mockReturnValue(fakeUser);  // targets only one export

export {};
