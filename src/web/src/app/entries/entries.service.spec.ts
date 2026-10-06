import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { APP_CONFIG, defaultConfig } from '../core/app-config';
import { sampleEntry } from '../testing/fixtures';
import { EntriesService, LogEntry } from './entries.service';

describe('EntriesService', () => {
  let service: EntriesService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: APP_CONFIG, useValue: { ...defaultConfig, apiBaseUrl: 'https://api.test' } },
      ],
    });
    service = TestBed.inject(EntriesService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('lists entries with a limit, using the configured base URL', () => {
    let result: LogEntry[] | undefined;
    service.list(10).subscribe((entries) => (result = entries));

    const req = httpMock.expectOne('https://api.test/api/entries?limit=10');
    expect(req.request.method).toBe('GET');
    req.flush([sampleEntry]);

    expect(result).toEqual([sampleEntry]);
  });

  it('creates an entry', () => {
    service.create({ author: 'Captain', message: 'Land ho!' }).subscribe();

    const req = httpMock.expectOne('https://api.test/api/entries');
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({ author: 'Captain', message: 'Land ho!' });
    req.flush(sampleEntry);
  });

  it('deletes an entry by id', () => {
    service.delete(sampleEntry.id).subscribe();

    const req = httpMock.expectOne(`https://api.test/api/entries/${sampleEntry.id}`);
    expect(req.request.method).toBe('DELETE');
    req.flush(null, { status: 204, statusText: 'No Content' });
  });
});
