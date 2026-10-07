import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { APP_CONFIG } from '../core/app-config';

export interface LogEntry {
  id: string;
  author: string;
  message: string;
  createdAtUtc: string;
  cloud: string;
  region: string;
  cluster: string;
  node: string;
  pod: string;
  /** Computed by the API for the caller: author or Shiplog.Admin (always true with auth disabled). */
  canDelete: boolean;
}

export interface CreateEntryRequest {
  /** Only used with auth disabled; otherwise the API takes the author from the token. */
  author?: string;
  message: string;
}

// Mirrors the API's limits (LogEntry.AuthorMaxLength / MessageMaxLength).
export const AUTHOR_MAX_LENGTH = 60;
export const MESSAGE_MAX_LENGTH = 280;

@Injectable({ providedIn: 'root' })
export class EntriesService {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = `${inject(APP_CONFIG).apiBaseUrl}/api/entries`;

  list(limit = 50): Observable<LogEntry[]> {
    return this.http.get<LogEntry[]>(this.baseUrl, { params: { limit } });
  }

  create(request: CreateEntryRequest): Observable<LogEntry> {
    return this.http.post<LogEntry>(this.baseUrl, request);
  }

  delete(id: string): Observable<void> {
    return this.http.delete<void>(`${this.baseUrl}/${encodeURIComponent(id)}`);
  }
}
