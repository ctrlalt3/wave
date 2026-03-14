/**
 * <user-menu> Web Component — Wave Beta
 * Muestra botón Login (anónimo) o Avatar+Dropdown (autenticado).
 * Vanilla JS. escText() en todo contenido dinámico.
 */

function escText(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

class UserMenu extends HTMLElement {
  constructor() {
    super();
    this._open = false;
    this._user = null;
    this._onAuthChanged = this._onAuthChanged.bind(this);
    this._onDocClick = this._onDocClick.bind(this);
  }

  connectedCallback() {
    this._user = TokenManager.isAuthenticated() ? TokenManager.getCurrentUser() : null;
    this._render();
    document.addEventListener('wave:auth-changed', this._onAuthChanged);
  }

  disconnectedCallback() {
    document.removeEventListener('wave:auth-changed', this._onAuthChanged);
    document.removeEventListener('click', this._onDocClick);
  }

  _onAuthChanged(e) {
    this._user = e.detail.authenticated ? (e.detail.user || TokenManager.getCurrentUser()) : null;
    this._open = false;
    this._render();
  }

  _render() {
    const u = this._user;
    this.innerHTML = `
<style>
  .wum-wrap { position: relative; display: inline-flex; align-items: center; }
  .wum-login-btn {
    padding: 6px 14px; border: 1px solid var(--border-2, rgba(255,255,255,0.10));
    background: none; border-radius: 8px; cursor: pointer;
    color: var(--text-0, #fafafa); font-family: var(--font, sans-serif);
    font-size: 13px; font-weight: 500; transition: background 0.15s, border-color 0.15s;
    white-space: nowrap;
  }
  .wum-login-btn:hover { background: var(--surface-2, #232329); border-color: var(--accent, #ff6b35); }
  .wum-avatar-btn {
    display: flex; align-items: center; gap: 8px; padding: 4px 10px 4px 4px;
    background: var(--surface, #1c1c22); border: 1px solid var(--border, rgba(255,255,255,0.06));
    border-radius: 20px; cursor: pointer; transition: background 0.15s;
  }
  .wum-avatar-btn:hover { background: var(--surface-2, #232329); }
  .wum-circle {
    width: 28px; height: 28px; border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    font-size: 12px; font-weight: 700; color: #fff; flex-shrink: 0;
    text-transform: uppercase;
  }
  .wum-uname {
    font-size: 13px; font-weight: 500; color: var(--text-0, #fafafa);
    max-width: 100px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .wum-caret { font-size: 10px; color: var(--text-2, rgba(250,250,250,0.42)); }
  .wum-dropdown {
    position: absolute; top: calc(100% + 8px); right: 0;
    background: var(--surface, #1c1c22);
    border: 1px solid var(--border-2, rgba(255,255,255,0.10));
    border-radius: 10px; min-width: 200px; overflow: hidden;
    box-shadow: var(--shadow-lg, 0 20px 60px rgba(0,0,0,0.5));
    z-index: 8000;
    animation: wumDrop 0.15s ease;
    display: none;
  }
  .wum-dropdown.open { display: block; }
  @keyframes wumDrop { from { opacity:0; transform: translateY(-6px) } to { opacity:1; transform: translateY(0) } }
  .wum-info { padding: 12px 14px; border-bottom: 1px solid var(--border, rgba(255,255,255,0.06)); }
  .wum-info-name { font-size: 14px; font-weight: 600; color: var(--text-0, #fafafa); }
  .wum-info-email { font-size: 12px; color: var(--text-2, rgba(250,250,250,0.42)); margin-top: 2px; }
  .wum-item {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 14px; cursor: pointer;
    font-size: 13px; color: var(--text-1, rgba(250,250,250,0.7));
    transition: background 0.1s, color 0.1s;
    border: none; background: none; width: 100%; text-align: left;
    font-family: var(--font, sans-serif);
  }
  .wum-item:hover { background: var(--surface-2, #232329); color: var(--text-0, #fafafa); }
  .wum-divider { height: 1px; background: var(--border, rgba(255,255,255,0.06)); }
  .wum-item.danger { color: var(--error, #ef4444); }
  .wum-item.danger:hover { background: rgba(239,68,68,0.08); }
  @media (max-width: 480px) {
    .wum-uname { display: none; }
    .wum-dropdown { right: -4px; }
  }
</style>
<div class="wum-wrap">
  ${u ? `
  <button class="wum-avatar-btn" id="wum-trigger" aria-haspopup="true" aria-expanded="${this._open}" aria-label="Menú de usuario">
    <span class="wum-circle" style="background:${escText(u.avatar_color || '#6c5ce7')}">
      ${escText((u.username || u.display_name || 'U').charAt(0))}
    </span>
    <span class="wum-uname">${escText(u.username || u.display_name || '')}</span>
    <span class="wum-caret">▾</span>
  </button>
  <div class="wum-dropdown${this._open ? ' open' : ''}" id="wum-dropdown" role="menu">
    <div class="wum-info">
      <div class="wum-info-name">${escText(u.display_name || u.username || '')}</div>
      ${u.email ? `<div class="wum-info-email">${escText(u.email)}</div>` : ''}
    </div>
    <button class="wum-item" data-action="profile" role="menuitem">👤 Mi Perfil</button>
    <button class="wum-item" data-action="stats" role="menuitem">📊 Mis Stats</button>
    <button class="wum-item" data-action="history" role="menuitem">🕐 Historial</button>
    <div class="wum-divider"></div>
    <button class="wum-item danger" data-action="logout" role="menuitem">🚪 Logout</button>
  </div>` : `
  <button class="wum-login-btn" id="wum-login" aria-label="Iniciar sesión">Iniciar sesión</button>`}
</div>`;

    this._bindEvents();
  }

  _bindEvents() {
    const trigger = this.querySelector('#wum-trigger');
    const loginBtn = this.querySelector('#wum-login');
    if (trigger) {
      trigger.addEventListener('click', e => {
        e.stopPropagation();
        this._open = !this._open;
        this.querySelector('#wum-dropdown')?.classList.toggle('open', this._open);
        trigger.setAttribute('aria-expanded', String(this._open));
        if (this._open) document.addEventListener('click', this._onDocClick);
        else document.removeEventListener('click', this._onDocClick);
      });
    }
    if (loginBtn) {
      loginBtn.addEventListener('click', () => {
        document.dispatchEvent(new CustomEvent('wave:open-auth', { detail: { mode: 'login' } }));
      });
    }
    this.querySelectorAll('[data-action]').forEach(btn => {
      btn.addEventListener('click', () => this._handleAction(btn.dataset.action));
    });
  }

  _onDocClick(e) {
    if (!this.contains(e.target)) {
      this._open = false;
      this.querySelector('#wum-dropdown')?.classList.remove('open');
      document.removeEventListener('click', this._onDocClick);
    }
  }

  async _handleAction(action) {
    this._open = false;
    this.querySelector('#wum-dropdown')?.classList.remove('open');
    document.removeEventListener('click', this._onDocClick);
    if (action === 'logout') {
      try {
        await TokenManager.fetchWithAuth('/api/auth/logout', { method: 'POST' });
      } catch { /* best effort */ }
      TokenManager.clearToken();
      this._user = null;
      this._render();
      document.dispatchEvent(new CustomEvent('wave:auth-changed', { detail: { authenticated: false } }));
    } else if (action === 'profile' || action === 'stats') {
      document.dispatchEvent(new CustomEvent('wave:open-profile', { detail: { tab: action } }));
    } else if (action === 'history') {
      document.dispatchEvent(new CustomEvent('wave:open-profile', { detail: { tab: 'history' } }));
    }
  }
}

customElements.define('user-menu', UserMenu);
