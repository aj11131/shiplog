import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { App } from './app';
import { APP_CONFIG, defaultConfig } from './core/app-config';
import { ServedByStore } from './core/served-by';

describe('App', () => {
  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [App],
      providers: [
        provideRouter([]),
        { provide: APP_CONFIG, useValue: { ...defaultConfig, environment: 'aks-dev' } },
      ],
    });
  });

  it('shows the brand, environment and navigation', async () => {
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;

    expect(el.querySelector('h1')?.textContent).toBe('Shiplog');
    expect(el.querySelector('header .chip')?.textContent?.trim()).toBe('aks-dev');
    expect([...el.querySelectorAll('nav a')].map((a) => a.textContent)).toEqual([
      'Log',
      'Diagnostics',
    ]);
  });

  it('shows the last pod that served a request', async () => {
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const servedBy = () =>
      (fixture.nativeElement as HTMLElement).querySelector('[data-testid=served-by]')?.textContent;

    expect(servedBy()).toBe('—');

    TestBed.inject(ServedByStore).record('shiplog-api-abc');
    await fixture.whenStable();

    expect(servedBy()).toBe('shiplog-api-abc');
  });
});
