import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { SERVED_BY_HEADER, ServedByStore, servedByInterceptor } from './served-by';

describe('servedByInterceptor', () => {
  let http: HttpClient;
  let httpMock: HttpTestingController;
  let store: ServedByStore;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([servedByInterceptor])),
        provideHttpClientTesting(),
      ],
    });
    http = TestBed.inject(HttpClient);
    httpMock = TestBed.inject(HttpTestingController);
    store = TestBed.inject(ServedByStore);
  });

  afterEach(() => httpMock.verify());

  it('records the pod from successful responses and counts per pod', () => {
    for (const pod of ['api-a', 'api-b', 'api-a']) {
      http.get('/api/diagnostics').subscribe();
      httpMock.expectOne('/api/diagnostics').flush({}, { headers: { [SERVED_BY_HEADER]: pod } });
    }

    expect(store.lastPod()).toBe('api-a');
    expect(store.pods()).toEqual([
      { pod: 'api-a', requests: 2 },
      { pod: 'api-b', requests: 1 },
    ]);
  });

  it('records the pod from error responses too', () => {
    http.get('/api/entries/x').subscribe({ error: () => undefined });
    httpMock.expectOne('/api/entries/x').flush(null, {
      status: 404,
      statusText: 'Not Found',
      headers: { [SERVED_BY_HEADER]: 'api-c' },
    });

    expect(store.lastPod()).toBe('api-c');
  });

  it('ignores responses without the header', () => {
    http.get('/somewhere-else').subscribe();
    httpMock.expectOne('/somewhere-else').flush({});

    expect(store.lastPod()).toBeNull();
    expect(store.pods()).toEqual([]);
  });
});
