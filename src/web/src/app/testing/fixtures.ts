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
};
