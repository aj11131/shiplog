import { bootstrapApplication } from '@angular/platform-browser';
import { App } from './app/app';
import { createAppConfig } from './app/app.config';
import { loadConfig } from './app/core/app-config';
import { REDIRECT_PATH } from './app/core/auth.service';

if (window.location.pathname === REDIRECT_PATH) {
  // MSAL v5 "redirect bridge": Entra returns here after sign-in. This page doesn't start
  // Angular. It stashes the response and sends the browser back to the page that started
  // sign-in, where AuthService.init() completes it. It's bundled with the app (same origin)
  // because it handles authorization codes.
  import('@azure/msal-browser/redirect-bridge')
    .then((bridge) => bridge.broadcastResponseToMainFrame())
    .catch((err) => console.error('Sign-in redirect failed', err));
} else {
  // Load runtime settings (/config.json) before Angular starts so every service can inject them.
  loadConfig()
    .then((config) => bootstrapApplication(App, createAppConfig(config)))
    .catch((err) => console.error(err));
}
