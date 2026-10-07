import { DatePipe } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { APP_CONFIG } from '../core/app-config';
import { ServedByStore } from '../core/served-by';

export interface Diagnostics {
  cloud: string;
  region: string;
  cluster: string;
  node: string;
  pod: string;
  version: string;
  environment: string;
  databaseProvider: string;
  databaseReachable: boolean;
  serverTimeUtc: string;
}

/** What the API sees in the caller's token (GET /api/me). */
export interface Me {
  authEnabled: boolean;
  isAuthenticated: boolean;
  name: string | null;
  objectId: string | null;
  roles: string[];
  scopes: string[];
  isAdmin: boolean;
  canWrite: boolean;
}

@Component({
  selector: 'app-diagnostics-page',
  imports: [DatePipe],
  templateUrl: './diagnostics-page.html',
  styleUrl: './diagnostics-page.scss',
})
export class DiagnosticsPage implements OnInit {
  private readonly http = inject(HttpClient);
  private readonly config = inject(APP_CONFIG);

  protected readonly servedBy = inject(ServedByStore);
  protected readonly telemetryEnabled = !!this.config.appInsightsConnectionString;
  protected readonly environment = this.config.environment;

  protected readonly diagnostics = signal<Diagnostics | null>(null);
  protected readonly me = signal<Me | null>(null);
  protected readonly error = signal<string | null>(null);

  ngOnInit(): void {
    this.refresh();
  }

  refresh(): void {
    this.http.get<Diagnostics>(`${this.config.apiBaseUrl}/api/diagnostics`).subscribe({
      next: (d) => {
        this.diagnostics.set(d);
        this.error.set(null);
      },
      error: () => this.error.set('Could not reach the API.'),
    });
    this.http.get<Me>(`${this.config.apiBaseUrl}/api/me`).subscribe({
      next: (me) => this.me.set(me),
      error: () => this.me.set(null),
    });
  }

  /** Fires a burst of requests so you can watch them spread across API pods. */
  burst(count = 20): void {
    for (let i = 0; i < count; i++) {
      this.http
        .get(`${this.config.apiBaseUrl}/api/diagnostics`)
        .subscribe({ error: () => undefined });
    }
  }
}
