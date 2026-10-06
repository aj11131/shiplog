import { bootstrapApplication } from '@angular/platform-browser';
import { App } from './app/app';
import { createAppConfig } from './app/app.config';
import { loadConfig } from './app/core/app-config';

// Load runtime settings (/config.json) before Angular starts so every service can inject them.
loadConfig()
  .then((config) => bootstrapApplication(App, createAppConfig(config)))
  .catch((err) => console.error(err));
