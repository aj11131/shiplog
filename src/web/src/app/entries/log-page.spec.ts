import { HttpErrorResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';
import { EntriesService, LogEntry } from './entries.service';
import { AuthService } from '../core/auth.service';
import { fakeAuth, sampleEntry } from '../testing/fixtures';
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
      providers: [
        { provide: EntriesService, useValue: entriesService },
        { provide: AuthService, useValue: fakeAuth({ enabled: false }) },
      ],
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

  it('hides Delete on entries the caller may not delete', async () => {
    const { el } = await render([{ ...sampleEntry, canDelete: false }]);

    expect(el.querySelector('.entry .link')).toBeNull();
  });
});

describe('LogPage with sign-in enabled', () => {
  let entriesService: { list: ReturnType<typeof vi.fn>; create: ReturnType<typeof vi.fn> };
  let auth: ReturnType<typeof fakeAuth>;

  async function render() {
    const fixture = TestBed.createComponent(LogPage);
    await fixture.whenStable();
    return { fixture, el: fixture.nativeElement as HTMLElement };
  }

  beforeEach(() => {
    entriesService = { list: vi.fn().mockReturnValue(of([sampleEntry])), create: vi.fn() };
    auth = fakeAuth({ enabled: true, signedInAs: null });
    TestBed.configureTestingModule({
      imports: [LogPage],
      providers: [
        { provide: EntriesService, useValue: entriesService },
        { provide: AuthService, useValue: auth },
      ],
    });
  });

  it('asks anonymous visitors to sign in, but still shows the log', async () => {
    const { el } = await render();

    expect(el.querySelector('form')).toBeNull();
    expect(el.querySelector('.sign-in-prompt')?.textContent).toContain('Sign in to add entries');
    expect(el.querySelector('.entry')?.textContent).toContain('Land ho!');

    el.querySelector<HTMLButtonElement>('.sign-in-prompt button')!.click();
    expect(auth.signIn).toHaveBeenCalled();
  });

  it('lets signed-in users write without an author field', async () => {
    auth.signInAs('Alice');
    entriesService.create.mockReturnValue(of({ ...sampleEntry, id: 'new', author: 'Alice' }));
    const { fixture, el } = await render();

    expect(el.querySelector('input[formcontrolname=author]')).toBeNull();
    expect(el.textContent).toContain('Writing as Alice');

    const textarea = el.querySelector<HTMLTextAreaElement>('textarea')!;
    textarea.value = 'Signed and sealed';
    textarea.dispatchEvent(new Event('input'));
    el.querySelector<HTMLFormElement>('form')!.dispatchEvent(new Event('submit'));
    await fixture.whenStable();

    // No author is sent: the API takes it from the token.
    expect(entriesService.create).toHaveBeenCalledWith({ message: 'Signed and sealed' });
  });
});
