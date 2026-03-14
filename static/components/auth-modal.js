/**
 * <auth-modal> Web Component — Wave Beta
 * Login / Register modal. Vanilla JS, no build tools.
 * Usa escText() para todo contenido dinámico.
 */

function escText(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

class AuthModal extends HTMLElement {
  constructor() {
    super();
    this._mode = 'login'; // 'login' | 'register'
    this._loading = false;
  }

  connectedCallback() {
    this._render();
    this._bindEvents();
  }

  open(mode = 'login') {
    this._mode = mode;
    this._render();
    this.querySelector('.wave-auth-backdrop').classList.add('visible');
    this.querySelector('.wave-auth-dialog').focus();
    this._trapFocus();
  }

  close() {
    const backdrop = this.querySelector('.wave-auth-backdrop');
    if (backdrop) backdrop.classList.remove('visible');
    this._clearError();
  }

  _render() {
    const isRegister = this._mode === 'register';
    this.innerHTML = `
<style>
  .wave-auth-backdrop {
    display: none;
    position: fixed; inset: 0; z-index: 9000;
    background: rgba(0,0,0,0.6);
    backdrop-filter: blur(4px);
    align-items: center; justify-content: center;
  }
  .wave-auth-backdrop.visible { display: flex; animation: wafadeIn 0.2s ease; }
  @keyframes wafadeIn { from { opacity:0 } to { opacity:1 } }
  .wave-auth-dialog {
    background: var(--surface, #1c1c22);
    border: 1px solid var(--border, rgba(255,255,255,0.06));
    border-radius: 12px;
    width: min(420px, 95vw);
    padding: 28px 24px 24px;
    position: relative;
    animation: waScaleIn 0.2s ease;
    outline: none;
  }
  @keyframes waScaleIn { from { opacity:0; transform: scale(0.95) } to { opacity:1; transform: scale(1) } }
  .wa-close {
    position: absolute; top: 14px; right: 14px;
    background: none; border: none; cursor: pointer;
    color: var(--text-2, rgba(250,250,250,0.42));
    font-size: 20px; line-height: 1; padding: 4px;
    transition: color 0.15s;
  }
  .wa-close:hover { color: var(--text-0, #fafafa); }
  .wa-tabs { display: flex; gap: 4px; margin-bottom: 24px; }
  .wa-tab {
    flex: 1; padding: 8px; background: none;
    border: 1px solid var(--border, rgba(255,255,255,0.06));
    border-radius: 8px; cursor: pointer;
    color: var(--text-2, rgba(250,250,250,0.42));
    font-family: var(--font, sans-serif); font-size: 14px;
    transition: all 0.15s;
  }
  .wa-tab.active {
    background: var(--accent, #ff6b35);
    border-color: var(--accent, #ff6b35);
    color: #fff;
  }
  .wa-field { margin-bottom: 16px; }
  .wa-label {
    display: block; font-size: 12px; font-weight: 500;
    color: var(--text-1, rgba(250,250,250,0.7));
    margin-bottom: 6px; letter-spacing: 0.03em;
  }
  .wa-input {
    width: 100%; padding: 10px 12px;
    background: var(--bg-2, #151518);
    border: 1px solid var(--border-2, rgba(255,255,255,0.10));
    border-radius: 8px; color: var(--text-0, #fafafa);
    font-family: var(--font, sans-serif); font-size: 14px;
    transition: border-color 0.15s; outline: none;
  }
  .wa-input:focus { border-color: var(--accent, #ff6b35); }
  .wa-input.invalid { border-color: var(--error, #ef4444); }
  .wa-error {
    font-size: 13px; color: var(--error, #ef4444);
    margin-bottom: 12px; min-height: 18px;
    display: none;
  }
  .wa-error.visible { display: block; }
  .wa-submit {
    width: 100%; padding: 12px;
    background: var(--accent, #ff6b35);
    border: none; border-radius: 8px;
    color: #fff; font-family: var(--font, sans-serif);
    font-size: 15px; font-weight: 600; cursor: pointer;
    transition: opacity 0.15s, transform 0.1s;
  }
  .wa-submit:hover:not(:disabled) { opacity: 0.9; }
  .wa-submit:active:not(:disabled) { transform: scale(0.98); }
  .wa-submit:disabled { opacity: 0.5; cursor: not-allowed; }
  .wa-hint { margin-top: 10px; font-size: 12px; color: var(--text-2, rgba(250,250,250,0.42)); text-align: center; }
  @media (max-width: 480px) {
    .wave-auth-dialog { padding: 20px 16px 18px; }
  }
</style>
<div class="wave-auth-backdrop" role="dialog" aria-modal="true" aria-label="Autenticación">
  <div class="wave-auth-dialog" tabindex="-1">
    <button class="wa-close" aria-label="Cerrar">✕</button>
    <div class="wa-tabs">
      <button class="wa-tab${!isRegister ? ' active' : ''}" data-mode="login">Iniciar sesión</button>
      <button class="wa-tab${isRegister ? ' active' : ''}" data-mode="register">Registrarse</button>
    </div>
    ${isRegister ? `
    <div class="wa-field">
      <label class="wa-label" for="wa-username">Nombre de usuario</label>
      <input class="wa-input" type="text" id="wa-username" name="username" autocomplete="username"
        placeholder="tulopetas" minlength="3" maxlength="32">
    </div>
    <div class="wa-field">
      <label class="wa-label" for="wa-email">Email</label>
      <input class="wa-input" type="email" id="wa-email" name="email" autocomplete="email" placeholder="tu@email.com">
    </div>` : `
    <div class="wa-field">
      <label class="wa-label" for="wa-identifier">Usuario o email</label>
      <input class="wa-input" type="text" id="wa-identifier" name="identifier" autocomplete="username"
        placeholder="usuario o email">
    </div>`}
    <div class="wa-field">
      <label class="wa-label" for="wa-password">Contraseña</label>
      <input class="wa-input" type="password" id="wa-password" name="password"
        autocomplete="${isRegister ? 'new-password' : 'current-password'}"
        placeholder="${isRegister ? 'mínimo 8 caracteres' : '••••••••'}">
    </div>
    <div class="wa-error" id="wa-error" role="alert" aria-live="polite"></div>
    <button class="wa-submit" id="wa-submit">
      ${isRegister ? 'Crear cuenta' : 'Entrar'}
    </button>
    <p class="wa-hint">Presiona Esc para cerrar</p>
  </div>
</div>`;
  }

  _bindEvents() {
    this.addEventListener('click', e => {
      if (e.target.classList.contains('wave-auth-backdrop') || e.target.classList.contains('wa-close')) {
        this.close();
      }
      if (e.target.classList.contains('wa-tab')) {
        this._mode = e.target.dataset.mode;
        this._render();
        this._bindEvents();
      }
      if (e.target.id === 'wa-submit') {
        this._submit();
      }
    });
    this.addEventListener('keydown', e => {
      if (e.key === 'Escape') this.close();
      if (e.key === 'Enter') this._submit();
    });
  }

  _trapFocus() {
    const dialog = this.querySelector('.wave-auth-dialog');
    const focusable = dialog.querySelectorAll('button, input, [tabindex]:not([tabindex="-1"])');
    const first = focusable[0], last = focusable[focusable.length - 1];
    dialog.addEventListener('keydown', e => {
      if (e.key !== 'Tab') return;
      if (e.shiftKey ? document.activeElement === first : document.activeElement === last) {
        e.preventDefault();
        (e.shiftKey ? last : first).focus();
      }
    });
    if (focusable.length) focusable[0].focus();
  }

  _showError(msg) {
    const el = this.querySelector('#wa-error');
    if (!el) return;
    el.textContent = escText(msg);
    el.classList.add('visible');
  }

  _clearError() {
    const el = this.querySelector('#wa-error');
    if (el) { el.textContent = ''; el.classList.remove('visible'); }
  }

  _setLoading(v) {
    const btn = this.querySelector('#wa-submit');
    if (!btn) return;
    btn.disabled = v;
    btn.textContent = v ? 'Cargando…' : (this._mode === 'register' ? 'Crear cuenta' : 'Entrar');
  }

  _validateRegister() {
    const username = (this.querySelector('#wa-username')?.value || '').trim();
    const email = (this.querySelector('#wa-email')?.value || '').trim();
    const password = (this.querySelector('#wa-password')?.value || '');
    if (!/^[a-zA-Z0-9_]{3,32}$/.test(username)) {
      this._showError('Usuario: 3-32 caracteres, solo letras, números y _');
      this.querySelector('#wa-username')?.classList.add('invalid');
      return null;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      this._showError('Email no válido');
      this.querySelector('#wa-email')?.classList.add('invalid');
      return null;
    }
    if (password.length < 8) {
      this._showError('La contraseña debe tener al menos 8 caracteres');
      this.querySelector('#wa-password')?.classList.add('invalid');
      return null;
    }
    return { username, email, password };
  }

  async _submit() {
    if (this._loading) return;
    this._clearError();
    this.querySelectorAll('.wa-input').forEach(i => i.classList.remove('invalid'));

    if (this._mode === 'register') {
      const data = this._validateRegister();
      if (!data) return;
      this._loading = true;
      this._setLoading(true);
      try {
        const res = await fetch('/api/auth/register', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(data)
        });
        const json = await res.json();
        if (!res.ok) {
          this._showError(json.error || 'Error al registrar');
          if (json.field === 'username') this.querySelector('#wa-username')?.classList.add('invalid');
        } else {
          TokenManager.setToken(json.token);
          TokenManager.setCurrentUser(json.user);
          document.dispatchEvent(new CustomEvent('wave:auth-changed', { detail: { authenticated: true, user: json.user } }));
          this.close();
        }
      } catch {
        this._showError('Error de conexión. Intenta de nuevo.');
      } finally {
        this._loading = false;
        this._setLoading(false);
      }
    } else {
      const identifier = (this.querySelector('#wa-identifier')?.value || '').trim();
      const password = this.querySelector('#wa-password')?.value || '';
      if (!identifier || !password) { this._showError('Completa todos los campos'); return; }
      this._loading = true;
      this._setLoading(true);
      try {
        const res = await fetch('/api/auth/login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ username_or_email: identifier, password })
        });
        const json = await res.json();
        if (!res.ok) {
          this._showError(json.error || 'Usuario o contraseña incorrectos');
        } else {
          TokenManager.setToken(json.token);
          TokenManager.setCurrentUser(json.user);
          document.dispatchEvent(new CustomEvent('wave:auth-changed', { detail: { authenticated: true, user: json.user } }));
          this.close();
        }
      } catch {
        this._showError('Error de conexión. Intenta de nuevo.');
      } finally {
        this._loading = false;
        this._setLoading(false);
      }
    }
  }
}

customElements.define('auth-modal', AuthModal);
