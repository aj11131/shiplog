import { computed, signal } from '@angular/core';
import { LogEntry } from '../entries/entries.service';

export const sampleEntry: LogEntry = {
  id: '0199b1c2-0000-7000-8000-000000000001',
  author: 'Captain',
  message: 'Land ho!',
  createdAtUtc: '2026-01-01T12:00:00Z',
  cloud: 'aks',
  region: 'eastus2',
  cluster: 'shiplog-dev',
  node: 'aks-system-0',
  pod: 'shiplog-api-abc',
  canDelete: true,
};

/** An AuthService stand-in for component tests. */
export function fakeAuth(options: { enabled: boolean; signedInAs?: string | null }) {
  const name = signal<string | null>(options.signedInAs ?? null);
  return {
    enabled: options.enabled,
    signedIn: computed(() => name() !== null),
    userName: name,
    error: signal<string | null>(null),
    signIn: vi.fn().mockResolvedValue(undefined),
    signOut: vi.fn().mockResolvedValue(undefined),
    getAccessToken: vi.fn().mockResolvedValue(options.signedInAs ? 'test-token' : null),
    signInAs: (who: string | null) => name.set(who),
  };
}
