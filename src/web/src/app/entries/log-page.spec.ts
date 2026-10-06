import { HttpErrorResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';
import { EntriesService, LogEntry } from './entries.service';
import { sampleEntry } from '../testing/fixtures';
import { LogPage } from './log-page';

describe('LogPage', () => {
  let entriesService: {
    list: ReturnType<typeof vi.fn>;
    create: ReturnType<typeof vi.fn>;
    delete: ReturnType<typeof vi.fn>;
  };

  async function render(initial: LogEntry[] = [sampleEntry]) {
    entriesService.list.mockReturnValue(of(initial));
    const fixture = TestBed.createComponent(LogPage);
    await fixture.whenStable();
    return { fixture, el: fixture.nativeElement as HTMLElement };
  }

  function type(el: HTMLElement, selector: string, value: string) {
    const input = el.querySelector<HTMLInputElement | HTMLTextAreaElement>(selector)!;
    input.value = value;
    input.dispatchEvent(new Event('input'));
  }

  beforeEach(() => {
    entriesService = { list: vi.fn(), create: vi.fn(), delete: vi.fn() };
    TestBed.configureTestingModule({
      imports: [LogPage],
      providers: [{ provide: EntriesService, useValue: entriesService }],
    });
  });

  it('shows entries with their cloud/pod stamp', async () => {
    const { el } = await render();

    const entry = el.querySelector('.entry')!;
    expect(entry.textContent).toContain('Land ho!');
    expect(entry.textContent).toContain('Captain');
    expect(entry.textContent).toContain('aks');
    expect(entry.textContent).toContain('pod shiplog-api-abc');
  });

  it('shows an empty state', async () => {
    const { el } = await render([]);

    expect(el.textContent).toContain('The log is empty');
  });

  it('does not submit an invalid form', async () => {
    const { fixture, el } = await render();

    el.querySelector<HTMLFormElement>('form')!.dispatchEvent(new Event('submit'));
    await fixture.whenStable();

    expect(entriesService.create).not.toHaveBeenCalled();
    expect(el.querySelectorAll('.field-error').length).toBe(2);
  });

  it('submits a new entry, prepends it and clears the message', async () => {
    const created: LogEntry = { ...sampleEntry, id: 'new', message: 'Storm ahead' };
    entriesService.create.mockReturnValue(of(created));
    const { fixture, el } = await render();

    type(el, 'input', 'Captain');
    type(el, 'textarea', 'Storm ahead');
    el.querySelector<HTMLFormElement>('form')!.dispatchEvent(new Event('submit'));
    await fixture.whenStable();

    expect(entriesService.create).toHaveBeenCalledWith({
      author: 'Captain',
      message: 'Storm ahead',
    });
    const messages = [...el.querySelectorAll('.entry .message')].map((m) => m.textContent?.trim());
    expect(messages).toEqual(['Storm ahead', 'Land ho!']);
    expect(el.querySelector<HTMLTextAreaElement>('textarea')!.value).toBe('');
    expect(el.querySelector<HTMLInputElement>('input')!.value).toBe('Captain');
  });

  it('removes a deleted entry', async () => {
    entriesService.delete.mockReturnValue(of(undefined));
    const { fixture, el } = await render();

    el.querySelector<HTMLButtonElement>('.entry .link')!.click();
    await fixture.whenStable();

    expect(entriesService.delete).toHaveBeenCalledWith(sampleEntry.id);
    expect(el.querySelector('.entry')).toBeNull();
  });

  it('shows a friendly error when the API is unreachable', async () => {
    entriesService.list.mockReturnValue(throwError(() => new HttpErrorResponse({ status: 0 })));
    const fixture = TestBed.createComponent(LogPage);
    await fixture.whenStable();

    expect(
      (fixture.nativeElement as HTMLElement).querySelector('[role=alert]')?.textContent,
    ).toContain('the API is unreachable');
  });
});
