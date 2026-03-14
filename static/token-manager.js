/**
 * TokenManager — Wave Beta
 * Singleton para gestión de JWT: almacenamiento, refresh auto, fetch interceptado.
 * No hardcoded tokens. Sin dependencias externas.
 */
const TokenManager = (() => {
  const STORAGE_KEY = 'wave_token';
  const USER_KEY = 'wave_user';

  function getToken() {
    return localStorage.getItem(STORAGE_KEY);
  }

  function setToken(jwt) {
    localStorage.setItem(STORAGE_KEY, jwt);
  }

  function clearToken() {
    localStorage.removeItem(STORAGE_KEY);
    localStorage.removeItem(USER_KEY);
  }

  function isAuthenticated() {
    const t = getToken();
    if (!t) return false;
    try {
      const payload = JSON.parse(atob(t.split('.')[1]));
      return payload.exp * 1000 > Date.now();
    } catch {
      return false;
    }
  }

  function getCurrentUser() {
    try {
      return JSON.parse(localStorage.getItem(USER_KEY));
    } catch {
      return null;
    }
  }

  function setCurrentUser(user) {
    localStorage.setItem(USER_KEY, JSON.stringify(user));
  }

  async function fetchWithAuth(url, opts = {}) {
    const token = getToken();
    const headers = { ...(opts.headers || {}) };
    if (token) headers['Authorization'] = 'Bearer ' + token;
    const res = await fetch(url, { ...opts, headers });
    if (res.status === 401) {
      clearToken();
      document.dispatchEvent(new CustomEvent('wave:auth-changed', { detail: { authenticated: false } }));
    }
    return res;
  }

  async function refreshIfNeeded() {
    const t = getToken();
    if (!t) return;
    try {
      const payload = JSON.parse(atob(t.split('.')[1]));
      const msLeft = payload.exp * 1000 - Date.now();
      if (msLeft < 24 * 60 * 60 * 1000) {
        const res = await fetchWithAuth('/api/auth/refresh', { method: 'POST' });
        if (res.ok) {
          const d = await res.json();
          if (d.token) setToken(d.token);
        }
      }
    } catch { /* ignore */ }
  }

  async function init() {
    if (!isAuthenticated()) {
      clearToken();
      return;
    }
    await refreshIfNeeded();
    try {
      const res = await fetchWithAuth('/api/auth/me');
      if (res.ok) {
        const user = await res.json();
        setCurrentUser(user);
        document.dispatchEvent(new CustomEvent('wave:auth-changed', { detail: { authenticated: true, user } }));
      }
    } catch { /* offline */ }
  }

  return { getToken, setToken, clearToken, isAuthenticated, getCurrentUser, setCurrentUser, fetchWithAuth, init };
})();

// Auto-init on load
document.addEventListener('DOMContentLoaded', () => TokenManager.init());
