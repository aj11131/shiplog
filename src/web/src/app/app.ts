import { Component, inject } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { APP_CONFIG } from './core/app-config';
import { AuthService } from './core/auth.service';
import { ServedByStore } from './core/served-by';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  protected readonly environment = inject(APP_CONFIG).environment;
  protected readonly lastPod = inject(ServedByStore).lastPod;
  protected readonly auth = inject(AuthService);
}
