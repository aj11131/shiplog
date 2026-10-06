import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { APP_CONFIG, defaultConfig } from '../core/app-config';
import { SERVED_BY_HEADER, servedByInterceptor } from '../core/served-by';
import { Diagnostics, DiagnosticsPage } from './diagnostics-page';

const diagnostics: Diagnostics = {
  cloud: 'eks',
  region: 'us-east-1',
  cluster: 'shiplog-dev',
  node: 'ip-10-0-1-23',
  pod: 'shiplog-api-xyz',
  version: '1.2.3',
  environment: 'Production',
  databaseProvider: 'Postgres',
  databaseReachable: true,
  serverTimeUtc: '2026-01-01T12:00:00Z',
};

describe('DiagnosticsPage', () => {
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [DiagnosticsPage],
      providers: [
        provideHttpClient(withInterceptors([servedByInterceptor])),
        provideHttpClientTesting(),
        { provide: APP_CONFIG, useValue: defaultConfig },
      ],
    });
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('shows where the API is running and records the serving pod', async () => {
    const fixture = TestBed.createComponent(DiagnosticsPage);
    await fixture.whenStable();

    httpMock
      .expectOne('/api/diagnostics')
      .flush(diagnostics, { headers: { [SERVED_BY_HEADER]: 'shiplog-api-xyz' } });
    await fixture.whenStable();

    const text = (fixture.nativeElement as HTMLElement).textContent;
    expect(text).toContain('eks');
    expect(text).toContain('ip-10-0-1-23');
    expect(text).toContain('Postgres');
    expect(text).toContain('reachable');
    expect(text).toContain('disabled (no connection string)');
    const rows = (fixture.nativeElement as HTMLElement).querySelectorAll('tbody tr');
    expect(rows.length).toBe(1);
    expect(rows[0].textContent).toContain('shiplog-api-xyz');
  });

  it('sends a burst of requests', async () => {
    const fixture = TestBed.createComponent(DiagnosticsPage);
    await fixture.whenStable();
    httpMock.expectOne('/api/diagnostics').flush(diagnostics);

    fixture.componentInstance.burst(5);

    const requests = httpMock.match('/api/diagnostics');
    expect(requests.length).toBe(5);
    requests.forEach((r) => r.flush(diagnostics));
  });

  it('shows an error when the API cannot be reached', async () => {
    const fixture = TestBed.createComponent(DiagnosticsPage);
    await fixture.whenStable();

    httpMock.expectOne('/api/diagnostics').flush(null, { status: 503, statusText: 'Unavailable' });
    await fixture.whenStable();

    expect(
      (fixture.nativeElement as HTMLElement).querySelector('[role=alert]')?.textContent,
    ).toContain('Could not reach the API');
  });
});
