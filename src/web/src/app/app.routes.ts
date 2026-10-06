import { Routes } from '@angular/router';

export const routes: Routes = [
  {
    path: '',
    title: 'Shiplog',
    loadComponent: () => import('./entries/log-page').then((m) => m.LogPage),
  },
  {
    path: 'diagnostics',
    title: 'Shiplog · Diagnostics',
    loadComponent: () => import('./diagnostics/diagnostics-page').then((m) => m.DiagnosticsPage),
  },
  { path: '**', redirectTo: '' },
];
