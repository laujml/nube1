// Utilidades compartidas: sesion (localStorage) y wrapper de fetch contra la
// API de CloudShop. Sin build step: se carga como <script> plano en cada
// pagina, junto con config.js.

const AUTH = {
  getAccessToken: () => localStorage.getItem("cs_access_token"),
  getRefreshToken: () => localStorage.getItem("cs_refresh_token"),
  getRole: () => localStorage.getItem("cs_role"),
  getEmail: () => localStorage.getItem("cs_email"),
  getUserId: () => localStorage.getItem("cs_user_id"),

  save(session) {
    localStorage.setItem("cs_access_token", session.access_token);
    localStorage.setItem("cs_refresh_token", session.refresh_token);
    localStorage.setItem("cs_role", session.role);
    localStorage.setItem("cs_user_id", session.user_id);
    if (session.email) localStorage.setItem("cs_email", session.email);
  },

  clear() {
    ["cs_access_token", "cs_refresh_token", "cs_role", "cs_user_id", "cs_email"]
      .forEach((k) => localStorage.removeItem(k));
  },

  isLoggedIn() {
    return Boolean(this.getAccessToken());
  },
};

function requireAuth() {
  if (!AUTH.isLoggedIn()) {
    window.location.href = "index.html";
  }
}

function requireRole(allowedRoles) {
  requireAuth();
  if (!allowedRoles.includes(AUTH.getRole())) {
    alert("No tienes permiso para ver esta pagina.");
    window.location.href = "shop.html";
  }
}

function logout() {
  AUTH.clear();
  window.location.href = "index.html";
}

// Llama a la API. Si el access token expiro (401) intenta refrescar una vez
// con el refresh token antes de mandar al login.
async function apiFetch(path, options = {}) {
  const cfg = window.CLOUDSHOP_CONFIG;
  const headers = Object.assign(
    { "Content-Type": "application/json" },
    options.headers || {}
  );
  if (cfg.API_KEY) headers["x-api-key"] = cfg.API_KEY;
  const token = AUTH.getAccessToken();
  if (token) headers["Authorization"] = `Bearer ${token}`;

  const doFetch = () =>
    fetch(`${cfg.API_BASE_URL}${path}`, { ...options, headers });

  let resp = await doFetch();

  if (resp.status === 401 && AUTH.getRefreshToken()) {
    const refreshed = await _tryRefresh();
    if (refreshed) {
      headers["Authorization"] = `Bearer ${AUTH.getAccessToken()}`;
      resp = await fetch(`${cfg.API_BASE_URL}${path}`, { ...options, headers });
    }
  }

  const data = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    const error = new Error(data.error || `Error ${resp.status}`);
    error.status = resp.status;
    throw error;
  }
  return data;
}

async function _tryRefresh() {
  try {
    const cfg = window.CLOUDSHOP_CONFIG;
    const resp = await fetch(`${cfg.API_BASE_URL}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: AUTH.getRefreshToken() }),
    });
    if (!resp.ok) return false;
    const data = await resp.json();
    localStorage.setItem("cs_access_token", data.access_token);
    localStorage.setItem("cs_refresh_token", data.refresh_token);
    return true;
  } catch (e) {
    return false;
  }
}

function money(amount) {
  return `$${Number(amount).toFixed(2)}`;
}

function showError(elementId, message) {
  const el = document.getElementById(elementId);
  if (el) {
    el.textContent = message;
    el.style.display = "block";
  }
}
