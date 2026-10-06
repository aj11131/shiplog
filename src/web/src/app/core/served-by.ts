import { HttpInterceptorFn } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { tap } from 'rxjs';

export const SERVED_BY_HEADER = 'X-Served-By';

/**
 * Remembers which API pods have answered this browser.
 *
 * With several API replicas behind a Kubernetes Service you should see requests
 * spread across pods. Scale the deployment or delete a pod and watch this change.
 */
@Injectable({ providedIn: 'root' })
export class ServedByStore {
  private readonly counts = signal<ReadonlyMap<string, number>>(new Map());

  readonly lastPod = signal<string | null>(null);
  readonly pods = computed(() =>
    [...this.counts().entries()]
      .map(([pod, requests]) => ({ pod, requests }))
      .sort((a, b) => b.requests - a.requests),
  );

  record(pod: string): void {
    this.lastPod.set(pod);
    this.counts.update((current) => new Map(current).set(pod, (current.get(pod) ?? 0) + 1));
  }

  reset(): void {
    this.lastPod.set(null);
    this.counts.set(new Map());
  }
}

/** Reads the X-Served-By header from every API response. */
export const servedByInterceptor: HttpInterceptorFn = (req, next) => {
  const store = inject(ServedByStore);
  return next(req).pipe(
    tap({
      next: (event) => {
        if ('headers' in event) {
          const pod = event.headers.get(SERVED_BY_HEADER);
          if (pod) store.record(pod);
        }
      },
      error: (error: { headers?: { get(name: string): string | null } }) => {
        const pod = error.headers?.get(SERVED_BY_HEADER);
        if (pod) store.record(pod);
      },
    }),
  );
};
