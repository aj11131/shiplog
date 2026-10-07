import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { NonNullableFormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { AuthService } from '../core/auth.service';
import { AUTHOR_MAX_LENGTH, EntriesService, LogEntry, MESSAGE_MAX_LENGTH } from './entries.service';

@Component({
  selector: 'app-log-page',
  imports: [ReactiveFormsModule, DatePipe],
  templateUrl: './log-page.html',
  styleUrl: './log-page.scss',
})
export class LogPage implements OnInit {
  private readonly entriesService = inject(EntriesService);
  protected readonly auth = inject(AuthService);

  protected readonly authorMax = AUTHOR_MAX_LENGTH;
  protected readonly messageMax = MESSAGE_MAX_LENGTH;

  protected readonly entries = signal<LogEntry[]>([]);
  protected readonly loading = signal(true);
  protected readonly saving = signal(false);
  protected readonly error = signal<string | null>(null);

  protected readonly form = inject(NonNullableFormBuilder).group({
    // With sign-in enabled the author comes from the token, so the field is disabled
    // (a disabled control is skipped by validation and by form.value).
    author: [
      { value: '', disabled: this.auth.enabled },
      [Validators.required, Validators.maxLength(AUTHOR_MAX_LENGTH)],
    ],
    message: ['', [Validators.required, Validators.maxLength(MESSAGE_MAX_LENGTH)]],
  });

  ngOnInit(): void {
    this.refresh();
  }

  refresh(): void {
    this.loading.set(true);
    this.entriesService.list().subscribe({
      next: (entries) => {
        this.entries.set(entries);
        this.error.set(null);
        this.loading.set(false);
      },
      error: (err: unknown) => {
        this.error.set(describeError('load the log', err));
        this.loading.set(false);
      },
    });
  }

  submit(): void {
    if (this.form.invalid || this.saving()) {
      this.form.markAllAsTouched();
      return;
    }

    this.saving.set(true);
    this.entriesService.create(this.form.value as { author?: string; message: string }).subscribe({
      next: (entry) => {
        this.entries.update((current) => [entry, ...current]);
        // Keep the author so posting several entries is quick.
        this.form.controls.message.reset();
        this.error.set(null);
        this.saving.set(false);
      },
      error: (err: unknown) => {
        this.error.set(describeError('save the entry', err));
        this.saving.set(false);
      },
    });
  }

  remove(entry: LogEntry): void {
    this.entriesService.delete(entry.id).subscribe({
      next: () => this.entries.update((current) => current.filter((e) => e.id !== entry.id)),
      error: (err: unknown) => this.error.set(describeError('delete the entry', err)),
    });
  }
}

function describeError(action: string, err: unknown): string {
  if (err instanceof HttpErrorResponse) {
    if (err.status === 0) return `Could not ${action}: the API is unreachable.`;
    if (err.status === 401) return `Could not ${action}: please sign in first.`;
    if (err.status === 403) return `Could not ${action}: you don't have permission.`;
    const detail = (err.error as { title?: string } | null)?.title ?? err.statusText;
    return `Could not ${action}: ${err.status} ${detail}`;
  }
  return `Could not ${action}.`;
}
