import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { from, switchMap } from 'rxjs';
import { APP_CONFIG } from './app-config';
import { AuthService } from './auth.service';

/**
 * Adds "Authorization: Bearer <access token>" to calls to OUR API only.
 *
 * Scoping matters: attaching the token to every request would hand it to any third-party
 * endpoint the app talks to (e.g. telemetry), and anyone holding it can act as the user.
 */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  const apiPrefix = `${inject(APP_CONFIG).apiBaseUrl}/api/`;

  if (!auth.signedIn() || !req.url.startsWith(apiPrefix)) {
    return next(req);
  }

  return from(auth.getAccessToken()).pipe(
    switchMap((token) =>
      next(token ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } }) : req),
    ),
  );
};
