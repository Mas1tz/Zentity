/* ============================================================
   kc_mdt · script.js · Premium Police MDT UI logic
   ============================================================ */

'use strict';

// ─── STATE ───────────────────────────────────────────────────
const state = {
    isOpen: false,
    isLoggedIn: false,
    user: null,                  // { username, name, rank, grade, badge, mustChangePw, accountId }
    currentTab: 'dashboard',
    previousTab: 'dashboard',    // så "Opret sigtelse" kan navigere tilbage til hvor vi kom fra
    currentPerson: null,         // citizenid
    currentVehiclePlate: null,
    currentCaseId: null,
    staticConfig: null,
    dutyStartTs: null,
    dutyBaseSec: 0,
    chargesCache: null,
    lawsCache: null,
    radioCache: null,
    lawsView: 'laws',            // 'laws' | 'radio' (§5/§6 — Lovbog)
    onlinePlayersCache: null,
    quickSearchTimer: null,
    personSearchTimer: null,
    arrestForm: null,            // aktiv "Opret sigtelse"-tilstand, se createArrestFormState()
};

// Auto-detekter resource navn — FiveM giver os GetParentResourceName().
// Fallback til hostname hvis ikke tilgængelig (under web-debug).
const RESOURCE = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName()
    : (window.location.hostname || 'kc_mdt');

// ─── API BRIDGE ──────────────────────────────────────────────
async function api(route, body = {}) {
    try {
        const res = await fetch(`https://${RESOURCE}/${route}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body),
        });
        const text = await res.text();
        if (!text || text.length === 0) return {};
        try { return JSON.parse(text); } catch { return {}; }
    } catch (e) {
        console.error('[kc_mdt] api error:', route, e);
        return null;
    }
}

// ─── OPACITY-SYSTEM (§1, §2) ─────────────────────────────────
const OPACITY_STORAGE_KEY = 'kcmdt_opacity';
let opacityCfg = { defaultOpacity: 1, minOpacity: 0.10, hoverOpacity: 0.50 };
let opacitySaved = 1;      // brugerens valgte "base"-opacity (fra slider)
let opacityHovering = false;

function getSavedOpacity() {
    const raw = parseFloat(localStorage.getItem(OPACITY_STORAGE_KEY));
    if (!isNaN(raw) && raw >= (opacityCfg.minOpacity || 0.1) && raw <= 1) return raw;
    return opacityCfg.defaultOpacity ?? 1;
}
function setAppOpacity(value) {
    document.documentElement.style.setProperty('--app-opacity', value);
}
function applyOpacityState() {
    setAppOpacity(opacityHovering ? (opacityCfg.hoverOpacity ?? 0.5) : opacitySaved);
}
function initOpacitySystem(uiCfg) {
    if (uiCfg) opacityCfg = { ...opacityCfg, ...uiCfg };
    opacitySaved = getSavedOpacity();
    applyOpacityState();

    const slider = $('#opacity-slider');
    const valueLabel = $('#opacity-value');
    if (slider) {
        slider.min = Math.round((opacityCfg.minOpacity ?? 0.1) * 100);
        slider.value = Math.round(opacitySaved * 100);
        if (valueLabel) valueLabel.textContent = `${slider.value}%`;
        slider.addEventListener('input', () => {
            opacitySaved = parseInt(slider.value, 10) / 100;
            if (valueLabel) valueLabel.textContent = `${slider.value}%`;
            localStorage.setItem(OPACITY_STORAGE_KEY, String(opacitySaved));
            if (!opacityHovering) applyOpacityState();
        });
    }

    const zone = $('#opacity-hover-zone');
    if (zone) {
        zone.addEventListener('mouseenter', () => { opacityHovering = true; applyOpacityState(); });
        zone.addEventListener('mouseleave', () => { opacityHovering = false; applyOpacityState(); });
    }
}

// ─── FARVETEMA FRA CONFIG (§41) ───────────────────────────────
function applyTheme(uiCfg) {
    const t = uiCfg && uiCfg.Theme;
    if (!t) return;
    const root = document.documentElement.style;
    const map = {
        bgPrimary: '--bg-base', bgSecondary: '--bg-panel', bgCard: '--bg-card',
        bgHover: '--bg-elev', accentBlue: '--accent', accentBlueHov: '--accent-hover',
        textPrimary: '--text', textSecondary: '--text-mid', textMuted: '--text-dim',
        borderColor: '--border',
    };
    for (const [key, cssVar] of Object.entries(map)) {
        if (t[key]) root.setProperty(cssVar, t[key]);
    }
}

// ─── NAVIGATION — bygges dynamisk ud fra Config.Menus (§3, §4) ─
const NAV_ICONS = {
    home: '🏠', users: '👤', car: '🚗', alert: '🚨', file: '📁',
    shield: '🚓', radio: '📡', book: '📚', gavel: '⚖️', key: '🛡️', settings: '⚙️',
};
function renderSidenav(menus) {
    const nav = $('#sidenav');
    if (!nav || !Array.isArray(menus)) return;
    nav.innerHTML = '';

    let lastGroupEnd = null; // simple grouping: divider before dispatch og før accounts
    const dividerBefore = new Set(['dispatch', 'accounts']);

    menus.forEach(m => {
        if (m.enabled === false) return;

        if (dividerBefore.has(m.id)) {
            nav.appendChild(el('div', { className: 'nav-divider' }));
        }

        const isDev = !!m.development;
        const badge = isDev
            ? el('span', { className: 'ni-dev-tag' }, 'Under udvikling')
            : el('span', { className: 'ni-badge', id: `badge-${m.id}` });

        const btn = el('button', {
            className: 'navitem' + (isDev ? ' navitem-dev' : '') + (m.id === 'accounts' ? ' boss-only hidden' : ''),
            'data-tab': m.id,
        },
            el('span', { className: 'ni-icon' }, NAV_ICONS[m.icon] || '•'),
            el('span', {}, m.label),
            badge,
        );

        if (isDev) {
            btn.addEventListener('click', () => toast(`${m.label} er under udvikling.`, 'warning'));
        } else {
            btn.addEventListener('click', () => switchTab(m.id));
        }
        nav.appendChild(btn);
    });
}

// ─── DOM HELPERS ─────────────────────────────────────────────
const $  = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
function el(tag, attrs = {}, ...children) {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
        if (k === 'className') node.className = v;
        else if (k === 'onclick') node.addEventListener('click', v);
        else if (k.startsWith('data-')) node.setAttribute(k, v);
        else if (v != null) node[k] = v;
    }
    for (const c of children) {
        if (c == null) continue;
        node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return node;
}
function escapeHtml(s) {
    if (s == null) return '';
    return String(s).replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
}
function fmtDate(d) {
    if (!d) return '—';
    try {
        const dt = new Date(d.replace(' ', 'T'));
        if (isNaN(dt)) return d;
        return dt.toLocaleString('da-DK', { year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit' });
    } catch { return d; }
}
function fmtDuration(sec) {
    sec = Math.max(0, parseInt(sec) || 0);
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    return `${h}:${String(m).padStart(2,'0')}`;
}

// ─── TOAST ───────────────────────────────────────────────────
function toast(msg, type = 'inform', duration = 3500) {
    const c = $('#toast-container');
    const t = el('div', { className: `toast ${type}` });
    t.innerHTML = escapeHtml(msg);
    c.appendChild(t);
    setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 300); }, duration);
}

// ─── MODAL HELPER ────────────────────────────────────────────
function openModal(html) {
    const host = $('#modal-host');
    const content = $('#modal-content');
    content.innerHTML = html;
    host.classList.remove('hidden');
}
function closeModal() {
    $('#modal-host').classList.add('hidden');
    $('#modal-content').innerHTML = '';
}
// ─── IMAGE PASTE / CLIENT-SIDE KOMPRIMERING (CTRL+V) — §12, §18 ─
// Skalerer billedet ned til Config.Images.maxDimensionPx og genkoder det
// som JPEG ved Config.Images.jpegQuality, så vi aldrig gemmer unødvendigt
// store billeder i databasen (§12).
function compressImageBlob(blob, maxDim, quality) {
    return new Promise((resolve, reject) => {
        const img = new Image();
        const url = URL.createObjectURL(blob);
        img.onload = () => {
            URL.revokeObjectURL(url);
            let { width, height } = img;
            if (width > maxDim || height > maxDim) {
                const scale = maxDim / Math.max(width, height);
                width = Math.max(1, Math.round(width * scale));
                height = Math.max(1, Math.round(height * scale));
            }
            const canvas = document.createElement('canvas');
            canvas.width = width; canvas.height = height;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(img, 0, 0, width, height);
            resolve(canvas.toDataURL('image/jpeg', quality));
        };
        img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('image load failed')); };
        img.src = url;
    });
}

// Binder CTRL+V på et dropzone-element. `onAdd(dataUrl)` kaldes med det
// færdigkomprimerede billede — kalderen har selv ansvar for at håndhæve
// et evt. maxCount, da det varierer pr. brugssted (efterlysning: 1, sigtelse: flere).
function bindImagePaste(zoneEl, onAdd) {
    if (!zoneEl) return;
    zoneEl.addEventListener('click', () => zoneEl.focus());
    zoneEl.addEventListener('focus', () => zoneEl.classList.add('dz-active'));
    zoneEl.addEventListener('blur', () => zoneEl.classList.remove('dz-active'));
    zoneEl.addEventListener('paste', async e => {
        const items = (e.clipboardData && e.clipboardData.items) || [];
        for (const item of items) {
            if (item.type && item.type.startsWith('image/')) {
                e.preventDefault();
                const blob = item.getAsFile();
                if (!blob) continue;
                const imgCfg = (state.staticConfig && state.staticConfig.images) || {};
                try {
                    const dataUrl = await compressImageBlob(blob, imgCfg.maxDimensionPx || 640, imgCfg.jpegQuality || 0.72);
                    onAdd(dataUrl);
                } catch {
                    toast('Kunne ikke indsætte billedet.', 'error');
                }
                break;
            }
        }
    });
}

// Render en simpel thumbnail-liste med fjern-knapper. `onRemove(index)`
// kaldes når en enkelt thumbnail fjernes.
function renderImageThumbs(containerEl, images, onRemove) {
    if (!containerEl) return;
    containerEl.innerHTML = '';
    (images || []).forEach((src, i) => {
        const thumb = el('div', { className: 'image-thumb' });
        thumb.innerHTML = `<img src="${escapeHtml(src)}">`;
        const rm = el('button', { type: 'button', onclick: () => onRemove(i) }, '✕');
        thumb.appendChild(rm);
        containerEl.appendChild(thumb);
    });
}

$('#modal-host').addEventListener('click', e => { if (e.target.id === 'modal-host') closeModal(); });
document.addEventListener('keydown', e => {
    if (e.key !== 'Escape') return;
    // 1) Hvis et modal er åbent — luk modal først
    if (!$('#modal-host').classList.contains('hidden')) { closeModal(); return; }
    if (!$('#pwchange-modal').classList.contains('hidden')) { return; } // forceret skift — kan ikke escapes
    // 2) Ellers — luk hele MDT'en (fra både login og hovedapp)
    if (state.isOpen) api('close');
});

// ─── CLOCK ───────────────────────────────────────────────────
setInterval(() => {
    const t = $('#topbar-time'), d = $('#topbar-date');
    if (!t || !d) return;
    const now = new Date();
    t.textContent = now.toLocaleTimeString('da-DK', { hour:'2-digit', minute:'2-digit' });
    d.textContent = now.toLocaleDateString('da-DK', { weekday:'short', day:'2-digit', month:'short' });
}, 1000);

// ─── DUTY TIMER ──────────────────────────────────────────────
setInterval(() => {
    if (!state.isLoggedIn || !state.dutyStartTs) return;
    const live = Math.floor((Date.now() - state.dutyStartTs) / 1000);
    const total = state.dutyBaseSec + live;
    const dt = $('#duty-time'); if (dt) dt.textContent = fmtDuration(total);
}, 1000);

// =============================================================
//  WINDOW MESSAGE HANDLER
// =============================================================
window.addEventListener('message', e => {
    const m = e.data; if (!m || !m.action) return;
    switch (m.action) {
        case 'open':
            state.isOpen = true;
            document.body.style.background = 'transparent';
            if (state.isLoggedIn) showApp(); else showLogin();
            break;
        case 'close':
            state.isOpen = false;
            $('#app').classList.add('hidden');
            $('#login-screen').classList.add('hidden');
            $('#modal-host').classList.add('hidden');
            $('#pwchange-modal').classList.add('hidden');
            break;
        case 'notify':
            toast(m.data.msg, m.data.type);
            break;
        case 'forceLogout':
            doLogout(m.data && m.data.reason);
            break;
        case 'warrantAlert':
            if (state.currentTab === 'warrants') loadWarrants();
            if (state.currentTab === 'dashboard') loadDashboard();
            if (!m.data.removed) toast(`🚨 Ny efterlysning: ${m.data.reason || ''}`, 'error', 6000);
            break;
        case 'newDispatch':
            // Dispatch-panelet er under udvikling (§9) og har ingen aktiv liste
            // at genindlæse — dashboardets stats/liste opdateres stadig.
            if (state.currentTab === 'dashboard') loadDashboard();
            toast(`📡 ${m.data.code || 'Dispatch'}: ${m.data.description || ''}`, 'warning', 6000);
            break;
        case 'dispatchResolved':
            if (state.currentTab === 'dashboard') loadDashboard();
            break;
        case 'updatePatrolList':
            if (state.currentTab === 'patrol') renderPatrolGrid(m.data);
            if (state.currentTab === 'dashboard') {
                const list = $('#dash-patrol');
                if (list) renderDashPatrol(m.data);
            }
            break;
        case 'panicAlert':
            toast(`⚠️ PANIC: ${m.data.officer} (${m.data.unit || '-'})`, 'error', 12000);
            break;
        case 'caseCreated':
            if (state.currentTab === 'cases') loadCases();
            if (state.currentTab === 'dashboard') loadDashboard();
            break;
        case 'newAccountCreated':
            if (state.currentTab === 'accounts') loadAccounts();
            toast(`✅ Ny konto: ${m.data.username} (${m.data.targetName}) af ${m.data.createdBy}`, 'success', 5000);
            break;
    }
});

// =============================================================
//  LOGIN
// =============================================================
function showLogin() {
    $('#app').classList.add('hidden');
    $('#login-screen').classList.remove('hidden');
    $('#login-error').classList.add('hidden');
    $('#login-username').value = '';
    $('#login-password').value = '';
    setTimeout(() => $('#login-username').focus(), 100);
}
function showApp() {
    $('#login-screen').classList.add('hidden');
    $('#app').classList.remove('hidden');
    applyUserToUI();
    switchTab('dashboard');
}

function applyUserToUI() {
    if (!state.user) return;
    $('#officer-name').textContent = state.user.username || '—';
    $('#officer-rank').textContent = state.user.rank || 'Officer';
    $('#set-username').textContent = state.user.username || '—';
    $('#set-rank').textContent = state.user.rank || '—';
    $('#set-badge').textContent = state.user.badge || '—';
    $('#set-grade').textContent = state.user.grade ?? '—';

    // Boss panel adgang
    const isBoss = (state.user.liveGrade ?? state.user.grade ?? 0) >= 10;
    $$('.boss-only').forEach(b => b.classList.toggle('hidden', !isBoss));
}

$('#toggle-password').addEventListener('click', () => {
    const inp = $('#login-password');
    inp.type = inp.type === 'password' ? 'text' : 'password';
});
$('#login-password').addEventListener('keydown', e => { if (e.key === 'Enter') $('#login-btn').click(); });
$('#login-username').addEventListener('keydown', e => { if (e.key === 'Enter') $('#login-password').focus(); });

$('#login-btn').addEventListener('click', async () => {
    const username = $('#login-username').value.trim().toLowerCase();
    const password = $('#login-password').value;
    if (!username || !password) {
        showLoginError('Indtast brugernavn og adgangskode.'); return;
    }
    const btn = $('#login-btn');
    btn.disabled = true;
    btn.querySelector('.btn-label').classList.add('hidden');
    btn.querySelector('.btn-spinner').classList.remove('hidden');

    const res = await api('login', { username, password });

    btn.disabled = false;
    btn.querySelector('.btn-label').classList.remove('hidden');
    btn.querySelector('.btn-spinner').classList.add('hidden');

    if (!res || !res.ok) {
        showLoginError((res && res.error) || 'Netværksfejl.');
        return;
    }

    state.isLoggedIn = true;
    state.user = res;
    state.dutyStartTs = Date.now();

    // Hent static config + duty time
    state.staticConfig = await api('getStaticConfig');
    applyTheme(state.staticConfig && state.staticConfig.ui);
    renderSidenav(state.staticConfig && state.staticConfig.menus);
    initOpacitySystem(state.staticConfig && state.staticConfig.ui);
    const dt = await api('getDutyTime');
    state.dutyBaseSec = parseInt(dt && dt.seconds) || 0;

    if (res.mustChangePw) {
        showForcedPasswordChange();
    } else {
        showApp();
    }
});

function showLoginError(msg) {
    const el = $('#login-error');
    el.textContent = msg;
    el.classList.remove('hidden');
}

// ─── FORCED PASSWORD CHANGE ──────────────────────────────────
function showForcedPasswordChange() {
    $('#pwchange-modal').classList.remove('hidden');
    $('#pw-old').value = '';
    $('#pw-new').value = '';
    $('#pw-new2').value = '';
    $('#pw-error').classList.add('hidden');
    setTimeout(() => $('#pw-old').focus(), 100);
}
$('#pw-save').addEventListener('click', async () => {
    const oldPw = $('#pw-old').value;
    const newPw = $('#pw-new').value;
    const newPw2 = $('#pw-new2').value;
    const err = $('#pw-error');
    err.classList.add('hidden');
    if (!oldPw || !newPw || !newPw2) { err.textContent = 'Udfyld alle felter.'; err.classList.remove('hidden'); return; }
    if (newPw !== newPw2) { err.textContent = 'De nye adgangskoder matcher ikke.'; err.classList.remove('hidden'); return; }
    if (newPw.length < 4) { err.textContent = 'Min. 4 tegn.'; err.classList.remove('hidden'); return; }

    const res = await api('changePassword', { oldPw, newPw });
    if (!res || !res.ok) {
        err.textContent = (res && res.error) || 'Fejl.'; err.classList.remove('hidden'); return;
    }
    $('#pwchange-modal').classList.add('hidden');
    toast('Adgangskode opdateret.', 'success');
    if (state.user) state.user.mustChangePw = false;
    showApp();
});

// ─── LOGOUT / CLOSE ──────────────────────────────────────────
$('#logout-btn').addEventListener('click', () => doLogout('Logget ud.'));
$('#close-btn').addEventListener('click', () => api('close'));

function doLogout(reason) {
    api('logout');
    state.isLoggedIn = false;
    state.user = null;
    state.dutyStartTs = null;
    state.dutyBaseSec = 0;
    showLogin();
    if (reason) toast(reason, 'warning');
}

// =============================================================
//  NAVIGATION
// =============================================================
// Nav-knapperne bygges dynamisk i renderSidenav() (se ovenfor) ud fra
// Config.Menus, med click-listeners tilknyttet direkte pr. knap.

function switchTab(name) {
    if (state.currentTab !== 'arrest-form') state.previousTab = state.currentTab;
    state.currentTab = name;
    $$('.navitem').forEach(b => b.classList.toggle('active', b.dataset.tab === name));
    $$('.panel').forEach(p => p.classList.toggle('hidden', p.dataset.panel !== name));

    switch (name) {
        case 'dashboard': loadDashboard(); break;
        case 'persons':   focusEl('#persons-search'); loadOnlinePersons(); break;
        case 'vehicles':  focusEl('#vehicle-plate'); break;
        case 'cases':     loadCases(); break;
        case 'warrants':  loadWarrants(); break;
        case 'patrol':    loadPatrolPanel(); break;
        case 'charges':   loadCharges(); break;
        case 'laws':      loadLaws(); break;
        case 'accounts':  loadAccounts(); break;
    }
}
function focusEl(sel) { const e = $(sel); if (e) setTimeout(() => e.focus(), 50); }

// =============================================================
//  DASHBOARD
// =============================================================
async function loadDashboard() {
    const data = await api('getDashboard');
    if (!data) return;

    // Defensiv adgang — hvis serveren returnerer tomt/ufuldstændigt
    // (fx pga. en fejlet query) så vis 0/tomme i stedet for at crashe.
    const stats = data.stats || {};
    $('#stat-warrants').textContent   = stats.activeWarrants   ?? 0;
    $('#stat-cases').textContent      = stats.openCases        ?? 0;
    $('#stat-arrests').textContent    = stats.todayArrests     ?? 0;
    $('#stat-dispatches').textContent = stats.activeDispatches ?? 0;
    $('#stat-online').textContent     = stats.onlineOfficers   ?? 0;

    // Sidebar badges (kun hvis menuen er aktiv/synlig i navigationen)
    const bw = $('#badge-warrants');
    const bd = $('#badge-dispatch');
    if (bw) bw.textContent = stats.activeWarrants   ? stats.activeWarrants   : '';
    if (bd) bd.textContent = stats.activeDispatches ? stats.activeDispatches : '';

    // Lists — alle defaulter til tom array
    renderDashList('#dash-warrants',  data.recentWarrants || [], w => ({
        title: `${w.firstname || '?'} ${w.lastname || ''}`,
        meta:  fmtDate(w.created_at),
        sub:   w.reason,
        cls:   'danger',
    }));
    renderDashList('#dash-dispatches', data.activeDispatches || [], d => ({
        title: `${d.code} · ${d.description}`,
        meta:  d.location || fmtDate(d.created_at),
        cls:   d.priority === 3 ? 'danger' : d.priority === 2 ? 'warning' : '',
    }));
    renderDashList('#dash-cases', data.recentCases || [], c => ({
        title: `${c.case_number} · ${c.title}`,
        meta:  `${c.status} · ${fmtDate(c.created_at)}`,
        cls:   c.status === 'closed' ? 'success' : '',
    }));
    renderDashList('#dash-arrests', data.recentArrests || [], a => ({
        title: `${a.firstname || '?'} ${a.lastname || ''}`,
        meta:  `${a.officer_name} · ${fmtDate(a.created_at)}`,
        sub:   `${a.total_fine || 0} kr · ${a.total_jail || 0} md`,
        cls:   'warning',
    }));
    renderDashList('#dash-topofficers', data.topOfficers || [], o => ({
        title: `${o.rank || ''} ${o.username || ''}`,
        meta:  fmtDuration(o.total_sec),
        cls:   'purple',
    }));
    renderDashPatrol(data.patrolList || []);
}
function renderDashList(sel, items, mapper) {
    const c = $(sel); c.innerHTML = '';
    if (!items || !items.length) { c.innerHTML = '<div class="dash-empty">Ingen data</div>'; return; }
    for (const item of items) {
        const m = mapper(item);
        const row = el('div', { className: `dash-row ${m.cls || ''}` });
        const left = el('div', { className: 'row-title' });
        left.innerHTML = `<div>${escapeHtml(m.title)}</div>${m.sub ? `<div style="font-size:11px;color:var(--text-dim);margin-top:2px;">${escapeHtml(m.sub)}</div>` : ''}`;
        row.appendChild(left);
        row.appendChild(el('div', { className: 'row-meta' }, m.meta || ''));
        c.appendChild(row);
    }
}
function renderDashPatrol(list) {
    const c = $('#dash-patrol'); if (!c) return;
    c.innerHTML = '';
    if (!list || !list.length) { c.innerHTML = '<div class="dash-empty">Ingen enheder</div>'; return; }
    for (const p of list) {
        const cls = p.status === 4 ? 'danger' : p.status === 3 ? 'warning' : p.status === 2 ? '' : 'success';
        const row = el('div', { className: `dash-row ${cls}` });
        row.innerHTML = `<div class="row-title">${escapeHtml(p.name)} <span style="font-size:11px;color:var(--text-dim);">${escapeHtml(p.unit || '-')}</span></div>
                         <div class="row-meta">${statusLabel(p.status)}</div>`;
        c.appendChild(row);
    }
}
function statusLabel(s) {
    return ({1:'I tjeneste', 2:'Ude af tjeneste', 3:'Optaget', 4:'Nødsituation'})[s] || '—';
}
$('#refresh-dashboard').addEventListener('click', loadDashboard);

// =============================================================
//  PERSONS
// =============================================================
$('#persons-search').addEventListener('input', e => {
    clearTimeout(state.personSearchTimer);
    const q = e.target.value.trim();
    if (q.length < 2) { loadOnlinePersons(); return; }
    state.personSearchTimer = setTimeout(async () => {
        const list = await api('searchCitizens', { query: q }) || [];
        $('#persons-results-header').classList.add('hidden');
        renderPersonsResults(list);
    }, 250);
});

// Online-liste (§10) — vises som standard når Personregister åbnes / søgefeltet er tomt.
async function loadOnlinePersons() {
    if (($('#persons-search').value || '').trim().length >= 2) return; // en søgning er allerede i gang
    const list = await api('getOnlinePlayers') || [];
    state.onlinePlayersCache = list;
    const header = $('#persons-results-header');
    header.innerHTML = `<span class="status-dot online"></span><span>ONLINE (${list.length})</span>`;
    header.classList.remove('hidden');
    renderPersonsResults(list, true);
}

function renderPersonsResults(list, isOnlineList) {
    const c = $('#persons-results'); c.innerHTML = '';
    if (!list.length) {
        c.innerHTML = `<div class="empty-state"><p class="muted">${isOnlineList ? 'Ingen spillere online' : 'Ingen resultater'}</p></div>`;
        return;
    }
    for (const p of list) {
        const row = el('div', { className: 'result-item', onclick: () => openPerson(p.citizenid) });
        const riskCol = state.staticConfig && state.staticConfig.riskLevels[p.risk_level || 0] || { label:'Ingen', color:'#6b7280' };
        row.innerHTML = `
            <div class="ri-title">${escapeHtml(p.firstname || '')} ${escapeHtml(p.lastname || '')}</div>
            <div class="ri-meta">
                ${isOnlineList
                    ? `<span class="ri-job">${escapeHtml(p.jobLabel || p.job || '—')}</span>`
                    : `<span>🆔 ${escapeHtml(p.citizenid || '').slice(-8)}</span>`}
                ${p.warrant_count > 0 ? `<span style="color:var(--danger);">🚨 ${p.warrant_count}</span>` : ''}
                <span style="color:${riskCol.color};">● ${riskCol.label}</span>
            </div>`;
        c.appendChild(row);
    }
}
async function openPerson(cid) {
    state.currentPerson = cid;
    $$('#persons-results .result-item').forEach(r => r.classList.remove('selected'));
    const data = await api('getCitizenFull', { citizenid: cid });
    renderPersonDetail(data);
}
function renderPersonDetail(d) {
    const c = $('#person-detail'); c.innerHTML = '';
    if (!d || !d.user) { c.innerHTML = '<div class="empty-state"><p class="muted">Kunne ikke hente data</p></div>'; return; }
    const u = d.user, m = d.mdt || {};
    const risk = state.staticConfig && state.staticConfig.riskLevels[m.risk_level || 0] || { label:'Ingen', color:'#6b7280' };
    const mugshot = m.mugshot_url
        ? `style="background-image:url('${escapeHtml(m.mugshot_url)}');"`
        : '';

    c.innerHTML = `
        <div class="person-head">
            <div class="person-mugshot" ${mugshot}>${!m.mugshot_url ? '👤' : ''}</div>
            <div class="person-info" style="flex:1;">
                <h2>${escapeHtml(u.firstname || '')} ${escapeHtml(u.lastname || '')}</h2>
                <div class="kv"><span>CPR:</span><strong>${escapeHtml(u.dateofbirth || '—')}</strong></div>
                <div class="kv"><span>Telefon:</span><strong>${escapeHtml(u.phone_number || '—')}</strong></div>
                <div class="kv"><span>Job:</span><strong>${escapeHtml(u.job || '—')}</strong></div>
                <div class="kv"><span>Køn:</span><strong>${escapeHtml(u.sex || '—')}</strong></div>
                <span class="risk-badge" style="background:${risk.color};color:white;">⚠ ${risk.label}</span>
            </div>
            <div style="display:flex;flex-direction:column;gap:6px;">
                <button class="btn btn-secondary" id="pd-edit">✎ Profil</button>
                <button class="btn btn-danger" id="pd-arrest">⚖️ Opret sigtelse</button>
                <button class="btn btn-secondary" id="pd-warrant">🚨 Efterlys</button>
            </div>
        </div>

        <div class="person-tabs">
            <button class="person-tab active" data-ptab="journals">Journaler (${d.journals.length})</button>
            <button class="person-tab" data-ptab="warrants">Efterlysninger (${d.warrants.length})</button>
            <button class="person-tab" data-ptab="arrests">Sigtelser (${d.arrests.length})</button>
            <button class="person-tab" data-ptab="evidence">Beviser (${d.evidence.length})</button>
        </div>

        <div class="person-tab-content active" data-pcontent="journals">
            <div style="margin-bottom:10px;"><button class="btn btn-primary" id="pd-add-journal">+ Tilføj journal</button></div>
            ${d.journals.map(j => `
                <div class="entry-card">
                    <div class="entry-head">
                        <div class="entry-title">${escapeHtml(j.title)}</div>
                        <div class="entry-meta">${escapeHtml(j.author_name)} · ${fmtDate(j.created_at)}</div>
                    </div>
                    <div class="entry-body">${escapeHtml(j.body)}</div>
                </div>
            `).join('') || '<div class="empty-state"><p class="muted">Ingen journaler</p></div>'}
        </div>

        <div class="person-tab-content" data-pcontent="warrants">
            ${d.warrants.map(w => `
                <div class="entry-card ${w.active ? 'danger' : ''}">
                    <div class="entry-head">
                        <div class="entry-title">${w.active ? '🚨 AKTIV' : 'Annulleret'}</div>
                        <div class="entry-meta">${escapeHtml(w.issued_by)} · ${fmtDate(w.created_at)}</div>
                    </div>
                    ${w.image ? `<img src="${escapeHtml(w.image)}" style="max-width:140px;border-radius:6px;margin-bottom:8px;display:block;">` : ''}
                    <div class="entry-body">${escapeHtml(w.reason)}</div>
                    ${w.active ? `<button class="btn btn-secondary" style="margin-top:8px;" data-warrant-to-arrest="${w.id}">⚖️ Opret sigtelse inkl. efterlysning</button>` : ''}
                </div>
            `).join('') || '<div class="empty-state"><p class="muted">Ingen efterlysninger</p></div>'}
        </div>

        <div class="person-tab-content" data-pcontent="arrests">
            ${d.arrests.map(a => {
                let charges = [], officers = [], images = [], seized = [];
                try { charges = JSON.parse(a.charges || '[]'); } catch {}
                try { officers = JSON.parse(a.officers || '[]'); } catch {}
                try { images = JSON.parse(a.images || '[]'); } catch {}
                try { seized = JSON.parse(a.seized_items || '[]'); } catch {}
                return `
                <div class="entry-card warning">
                    <div class="entry-head">
                        <div class="entry-title">${a.total_fine || 0} kr · ${a.total_jail || 0} md</div>
                        <div class="entry-meta">${escapeHtml(a.officer_name)} · ${fmtDate(a.created_at)}</div>
                    </div>
                    ${charges.length ? `<div class="entry-body">${charges.map(escapeHtml).join(', ')}</div>` : ''}
                    ${a.notes ? `<div class="entry-body" style="margin-top:6px;">${escapeHtml(a.notes)}</div>` : ''}
                    ${officers.length ? `<div class="entry-meta" style="margin-top:8px;">👮 ${officers.map(o => escapeHtml(o.name)).join(', ')}</div>` : ''}
                    ${seized.length ? `<div class="entry-meta" style="margin-top:4px;">🎒 ${seized.map(s => `${escapeHtml(s.item)} (${s.qty})`).join(', ')}</div>` : ''}
                    ${images.length ? `<div style="display:flex;gap:6px;margin-top:8px;">${images.map(img => `<img src="${escapeHtml(img)}" style="width:56px;height:56px;object-fit:cover;border-radius:6px;">`).join('')}</div>` : ''}
                </div>
            `;}).join('') || '<div class="empty-state"><p class="muted">Ingen sigtelser</p></div>'}
        </div>

        <div class="person-tab-content" data-pcontent="evidence">
            ${d.evidence.map(ev => `
                <div class="entry-card">
                    <div class="entry-head">
                        <div class="entry-title">${escapeHtml(ev.label)}</div>
                        <div class="entry-meta">${escapeHtml(ev.added_by)} · ${fmtDate(ev.created_at)}</div>
                    </div>
                    <div class="entry-body">${escapeHtml(ev.value || '')}</div>
                </div>
            `).join('') || '<div class="empty-state"><p class="muted">Ingen beviser</p></div>'}
        </div>
    `;

    $$('#person-detail .person-tab').forEach(t => t.addEventListener('click', () => {
        $$('#person-detail .person-tab').forEach(x => x.classList.toggle('active', x === t));
        $$('#person-detail .person-tab-content').forEach(c2 => c2.classList.toggle('active', c2.dataset.pcontent === t.dataset.ptab));
    }));

    $('#pd-edit').addEventListener('click', () => openEditCitizenModal(d));
    $('#pd-arrest').addEventListener('click', () => openArrestForm(u));
    $('#pd-warrant').addEventListener('click', () => openWarrantModal(u));
    const aj = $('#pd-add-journal'); if (aj) aj.addEventListener('click', () => openJournalModal(u));
    $$('#person-detail [data-warrant-to-arrest]').forEach(btn => {
        btn.addEventListener('click', () => {
            const warrant = d.warrants.find(w => String(w.id) === btn.dataset.warrantToArrest);
            openArrestForm(u, warrant);
        });
    });
}

function openEditCitizenModal(d) {
    const m = d.mdt || {};
    const rlOpts = Object.entries(state.staticConfig.riskLevels)
        .map(([k,v]) => `<option value="${k}" ${parseInt(k) === (m.risk_level||0) ? 'selected' : ''}>${v.label}</option>`).join('');
    openModal(`
        <div class="modal-header"><h3>Redigér profil</h3></div>
        <div class="modal-body">
            <div class="form-group"><label>Trusselsniveau</label><select id="m-risk">${rlOpts}</select></div>
            <div class="form-group"><label>Mugshot URL</label><input type="text" id="m-mug" value="${escapeHtml(m.mugshot_url||'')}"></div>
            <div class="form-group"><label>Noter</label><textarea id="m-notes" rows="4">${escapeHtml(m.notes||'')}</textarea></div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal()">Annullér</button>
            <button class="btn btn-primary" id="m-save">Gem</button>
        </div>
    `);
    $('#m-save').addEventListener('click', async () => {
        await api('updateCitizen', {
            citizenid: state.currentPerson,
            risk_level: parseInt($('#m-risk').value),
            mugshot_url: $('#m-mug').value,
            notes: $('#m-notes').value,
        });
        closeModal();
        setTimeout(() => openPerson(state.currentPerson), 300);
    });
}
window.closeModal = closeModal;

function openJournalModal(u) {
    openModal(`
        <div class="modal-header"><h3>Ny journal — ${escapeHtml(u.firstname||'')} ${escapeHtml(u.lastname||'')}</h3></div>
        <div class="modal-body">
            <div class="form-group"><label>Titel</label><input type="text" id="j-title" maxlength="255"></div>
            <div class="form-group"><label>Indhold</label><textarea id="j-body" rows="8" maxlength="8000"></textarea></div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal()">Annullér</button>
            <button class="btn btn-primary" id="j-save">Gem</button>
        </div>
    `);
    $('#j-save').addEventListener('click', async () => {
        const title = $('#j-title').value.trim(), body = $('#j-body').value.trim();
        if (!title || !body) { toast('Udfyld både titel og indhold', 'error'); return; }
        await api('addJournal', { citizenid: state.currentPerson, title, body });
        closeModal();
        setTimeout(() => openPerson(state.currentPerson), 300);
    });
}

function openWarrantModal(u) {
    const rlOpts = Object.entries(state.staticConfig.riskLevels)
        .map(([k,v]) => `<option value="${k}">${v.label}</option>`).join('');
    let warrantImage = null;
    openModal(`
        <div class="modal-header"><h3>🚨 Ny efterlysning — ${escapeHtml(u.firstname||'')} ${escapeHtml(u.lastname||'')}</h3></div>
        <div class="modal-body">
            <div class="form-group"><label>Grund</label><textarea id="w-reason" rows="3" maxlength="1000"></textarea></div>
            <div class="form-group"><label>Klip / billede</label>
                <div class="image-dropzone" id="w-dropzone" tabindex="0">
                    <div class="image-dropzone-hint">
                        <span class="image-dropzone-icon">🖼</span>
                        <span>Klik her og indsæt billede med <strong>CTRL + V</strong></span>
                    </div>
                    <div class="image-thumbs" id="w-thumbs"></div>
                </div>
            </div>
            <div class="form-group"><label>Risikoniveau</label><select id="w-risk">${rlOpts}</select></div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal()">Annullér</button>
            <button class="btn btn-danger" id="w-save">Udsted efterlysning</button>
        </div>
    `);
    bindImagePaste($('#w-dropzone'), dataUrl => {
        warrantImage = dataUrl;
        renderImageThumbs($('#w-thumbs'), [warrantImage], () => { warrantImage = null; });
    });
    $('#w-save').addEventListener('click', async () => {
        const reason = $('#w-reason').value.trim();
        if (!reason) { toast('Angiv grund', 'error'); return; }
        await api('addWarrant', { citizenid: state.currentPerson, reason, risk_level: parseInt($('#w-risk').value), image: warrantImage });
        closeModal();
        setTimeout(() => openPerson(state.currentPerson), 300);
    });
}

// =============================================================
//  VEHICLES
// =============================================================
$('#vehicle-search-btn').addEventListener('click', searchVehicle);
$('#vehicle-plate').addEventListener('keydown', e => { if (e.key === 'Enter') searchVehicle(); });

async function searchVehicle() {
    const plate = $('#vehicle-plate').value.trim().toUpperCase();
    if (!plate) return;
    const r = await api('searchVehicle', { plate });
    renderVehicleResult(r);
}
function renderVehicleResult(r) {
    const c = $('#vehicle-result');
    if (!r || !r.found) {
        c.innerHTML = '<div class="empty-state"><div class="empty-icon">🚗</div><p class="muted">Ingen registreret køretøj fundet</p></div>';
        return;
    }
    state.currentVehiclePlate = r.plate;
    const f = r.flags || {};
    const stops = (r.stops || []).map(s => `
        <div class="entry-card">
            <div class="entry-head"><div class="entry-title">${escapeHtml(s.officer_name)}</div><div class="entry-meta">${fmtDate(s.created_at)}</div></div>
            <div class="entry-body">${escapeHtml(s.notes || '—')}</div>
        </div>`).join('') || '<div class="empty-state"><p class="muted">Ingen registrerede standsninger</p></div>';
    c.innerHTML = `
        <div class="vehicle-card">
            <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:20px;">
                <div>
                    <div class="plate-display">${escapeHtml(r.plate)}</div>
                    <div style="margin-top:14px;">
                        <div class="kv"><span>Ejer:</span><strong>${escapeHtml(r.owner)}</strong></div>
                        <div class="kv"><span>Model:</span><strong>${escapeHtml(r.modelName || r.props && r.props.model || '—')}</strong></div>
                        <div class="kv"><span>Status:</span><strong>${r.stored ? 'I garage' : 'På vej'}</strong></div>
                    </div>
                </div>
                <button class="btn btn-secondary" id="v-stop">+ Standsning</button>
            </div>

            <h3 style="font-size:13px;margin-top:18px;text-transform:uppercase;color:var(--text-mid);letter-spacing:.5px;">Markeringer</h3>
            <div class="vehicle-grid">
                ${flagBtn('stolen', '🚨 Efterlyst', f.stolen)}
                ${flagBtn('seized', '🔒 Beslaglagt', f.seized)}
                ${flagBtn('bolo',   '👁 BOLO',       f.bolo)}
                ${flagBtn('tracker','📡 Tracker',    f.tracker, true)}
                ${flagBtn('insurance','✓ Forsikring',f.insurance, true)}
            </div>

            <div class="form-group" style="margin-top:14px;"><label>Noter på køretøj</label>
                <textarea id="v-notes" rows="2">${escapeHtml(f.notes || '')}</textarea>
            </div>
            <button class="btn btn-primary" id="v-save">Gem markeringer</button>

            <h3 style="font-size:13px;margin-top:24px;text-transform:uppercase;color:var(--text-mid);letter-spacing:.5px;">Standsninger (seneste 20)</h3>
            <div style="margin-top:10px;">${stops}</div>
        </div>
    `;
    $$('#vehicle-result .vehicle-flag').forEach(b => b.addEventListener('click', () => {
        const ok = b.dataset.success === '1';
        b.classList.toggle(ok ? 'on' : 'on');
    }));
    $('#v-save').addEventListener('click', async () => {
        const flags = {};
        $$('#vehicle-result .vehicle-flag').forEach(b => {
            flags[b.dataset.flag] = b.classList.contains('on');
        });
        flags.notes = $('#v-notes').value;
        await api('updateVehicleRecord', { plate: r.plate, flags });
        setTimeout(searchVehicle, 200);
    });
    $('#v-stop').addEventListener('click', () => openTrafficStopModal(r.plate));
}
function flagBtn(key, label, on, isSuccess) {
    return `<div class="vehicle-flag ${on ? 'on' : ''} ${isSuccess ? 'success' : ''}" data-flag="${key}" ${isSuccess ? 'data-success="1"' : ''}>
        <span>${label}</span>
        <span class="flag-toggle"></span>
    </div>`;
}
function openTrafficStopModal(plate) {
    openModal(`
        <div class="modal-header"><h3>+ Ny standsning — ${escapeHtml(plate)}</h3></div>
        <div class="modal-body"><div class="form-group"><label>Noter</label><textarea id="ts-notes" rows="4" maxlength="1000"></textarea></div></div>
        <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal()">Annullér</button>
            <button class="btn btn-primary" id="ts-save">Registrér</button>
        </div>
    `);
    $('#ts-save').addEventListener('click', async () => {
        await api('addTrafficStop', { plate, notes: $('#ts-notes').value });
        closeModal();
        setTimeout(searchVehicle, 200);
    });
}

// =============================================================
//  CASES
// =============================================================
$('#case-filter').addEventListener('change', loadCases);
$('#case-search').addEventListener('input', () => {
    clearTimeout(state._caseT);
    state._caseT = setTimeout(loadCases, 300);
});
$('#new-case-btn').addEventListener('click', openNewCaseModal);

async function loadCases() {
    const list = await api('getCases', {
        status: $('#case-filter').value,
        query:  $('#case-search').value.trim(),
    }) || [];
    const c = $('#cases-list'); c.innerHTML = '';
    if (!list.length) { c.innerHTML = '<div class="empty-state"><p class="muted">Ingen sager fundet</p></div>'; return; }
    for (const cs of list) {
        const card = el('div', { className: 'case-card', onclick: () => openCase(cs.id) });
        card.innerHTML = `
            <div class="case-num">${escapeHtml(cs.case_number)}</div>
            <div class="case-info">
                <div class="case-title">${escapeHtml(cs.title)}</div>
                <div class="case-meta"><span>👤 ${escapeHtml(cs.created_by)}</span><span>${fmtDate(cs.created_at)}</span></div>
            </div>
            <span class="case-status ${cs.status}">${cs.status}</span>`;
        c.appendChild(card);
    }
}
async function openCase(id) {
    state.currentCaseId = id;
    const cs = await api('getCase', { id });
    if (!cs) return;
    const statusOpts = ['open','investigating','closed','archived'].map(s =>
        `<option value="${s}" ${s===cs.status?'selected':''}>${s}</option>`).join('');
    openModal(`
        <div class="modal-header"><h3>${escapeHtml(cs.case_number)} · ${escapeHtml(cs.title)}</h3></div>
        <div class="modal-body" style="max-height:70vh;">
            <div class="form-group"><label>Status</label><select id="c-status">${statusOpts}</select></div>
            <div class="form-group"><label>Beskrivelse</label><textarea id="c-desc" rows="4">${escapeHtml(cs.description||'')}</textarea></div>
            <h3 style="font-size:13px;margin:10px 0;text-transform:uppercase;color:var(--text-mid);">Kommentarer</h3>
            <div id="c-comments">${cs.comments.map(co => `
                <div class="entry-card">
                    <div class="entry-head"><div class="entry-title">${escapeHtml(co.author_name)}</div><div class="entry-meta">${fmtDate(co.created_at)}</div></div>
                    <div class="entry-body">${escapeHtml(co.body)}</div>
                </div>`).join('') || '<div class="muted">Ingen kommentarer</div>'}</div>
            <div style="display:flex;gap:6px;margin-top:8px;">
                <input type="text" id="c-newcomment" placeholder="Tilføj kommentar..." style="flex:1;">
                <button class="btn btn-primary" id="c-addcomment">Send</button>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal()">Luk</button>
            <button class="btn btn-primary" id="c-save">Gem ændringer</button>
        </div>
    `);
    $('#c-save').addEventListener('click', async () => {
        await api('updateCase', {
            id, status: $('#c-status').value,
            description: $('#c-desc').value,
            priority: cs.priority, title: cs.title,
        });
        closeModal();
        loadCases();
    });
    $('#c-addcomment').addEventListener('click', async () => {
        const body = $('#c-newcomment').value.trim(); if (!body) return;
        await api('addCaseComment', { case_id: id, body });
        $('#c-newcomment').value = '';
        setTimeout(() => openCase(id), 200);
    });
}
function openNewCaseModal() {
    openModal(`
        <div class="modal-header"><h3>+ Ny sag</h3></div>
        <div class="modal-body">
            <div class="form-group"><label>Titel</label><input type="text" id="nc-title" maxlength="255"></div>
            <div class="form-group"><label>Beskrivelse</label><textarea id="nc-desc" rows="6"></textarea></div>
            <div class="form-group"><label>Prioritet</label>
                <select id="nc-prio"><option value="1">Lav</option><option value="2" selected>Normal</option><option value="3">Høj</option></select>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal()">Annullér</button>
            <button class="btn btn-primary" id="nc-save">Opret</button>
        </div>
    `);
    $('#nc-save').addEventListener('click', async () => {
        const title = $('#nc-title').value.trim(); if (!title) { toast('Titel kræves', 'error'); return; }
        await api('createCase', { title, description: $('#nc-desc').value, priority: parseInt($('#nc-prio').value) });
        closeModal();
        loadCases();
    });
}

// =============================================================
//  WARRANTS
// =============================================================
async function loadWarrants() {
    const list = await api('getWarrants') || [];
    const c = $('#warrants-grid'); c.innerHTML = '';
    if (!list.length) { c.innerHTML = '<div class="empty-state"><div class="empty-icon">✅</div><p class="muted">Ingen aktive efterlysninger</p></div>'; return; }
    for (const w of list) {
        const risk = state.staticConfig && state.staticConfig.riskLevels[w.risk_level || 1] || { label:'?', color:'#ef4444' };
        const card = el('div', { className: 'warrant-card' });
        card.innerHTML = `
            <div class="wc-name">${escapeHtml(w.firstname||'?')} ${escapeHtml(w.lastname||'')}</div>
            <div style="color:${risk.color};font-size:11px;font-weight:600;text-transform:uppercase;margin-bottom:6px;">● ${risk.label}</div>
            <div class="wc-reason">${escapeHtml(w.reason)}</div>
            <div class="wc-meta">
                <span>${escapeHtml(w.issued_by)}</span>
                <span>${fmtDate(w.created_at)}</span>
            </div>
            <div class="wc-actions">
                <button class="btn btn-secondary" data-act="view">Profil</button>
                <button class="btn btn-secondary" data-act="toarrest">⚖️ Opret sigtelse</button>
                <button class="btn btn-danger" data-act="remove">Fjern</button>
            </div>`;
        card.querySelector('[data-act="view"]').addEventListener('click', () => {
            switchTab('persons');
            setTimeout(() => openPerson(w.citizenid), 100);
        });
        card.querySelector('[data-act="toarrest"]').addEventListener('click', async () => {
            const data = await api('getCitizenFull', { citizenid: w.citizenid });
            if (!data || !data.user) { toast('Kunne ikke hente borgerdata.', 'error'); return; }
            openArrestForm(data.user, w);
        });
        card.querySelector('[data-act="remove"]').addEventListener('click', async () => {
            await api('removeWarrant', { citizenid: w.citizenid });
            setTimeout(loadWarrants, 200);
        });
        c.appendChild(card);
    }
}
$('#warrants-refresh').addEventListener('click', loadWarrants);

// =============================================================
//  OPRET SIGTELSE — fuld side, ikke en modal (§15-§21)
// =============================================================
function showPanel(name) {
    $$('.panel').forEach(p => p.classList.toggle('hidden', p.dataset.panel !== name));
}

let arrestDraftTimer = null;

async function openArrestForm(u, warrant) {
    if (!u || !u.identifier) { toast('Kunne ikke åbne sigtelse — mangler borgerdata.', 'error'); return; }

    state.previousTab = (state.currentTab !== 'arrest-form') ? state.currentTab : state.previousTab;
    state.currentTab = 'arrest-form';
    showPanel('arrest-form');
    clearTimeout(arrestDraftTimer);

    state.arrestForm = {
        citizenid: u.identifier,
        officers: [],
        images: [],
        seized: [],
        notes: '',
        charges: [],
        warrant_id: warrant ? warrant.id : null,
    };

    renderArrestPersonHead(u);
    $('#af-officers').innerHTML = '';
    $('#af-officer-search').value = '';
    $('#af-officer-results').classList.add('hidden');
    $('#af-notes').value = '';
    $('#af-seized').innerHTML = '';
    $('#af-thumbs').innerHTML = '';
    $('#af-draft-banner').classList.add('hidden');

    renderSeizedCategories();
    if (!state.chargesCache) state.chargesCache = await api('getCharges') || [];
    renderArrestCharges();

    // Prefill fra en aktiv efterlysning (§13), hvis vi kommer derfra.
    if (warrant) {
        state.arrestForm.notes = `Sigtelse baseret på efterlysning:\n${warrant.reason || ''}\n\n`;
        $('#af-notes').value = state.arrestForm.notes;
        if (warrant.image) {
            state.arrestForm.images.push(warrant.image);
            renderArrestThumbs();
        }
    }

    // Kladde (§21) — indlæses sidst, så den kan overskrive warrant-prefillet
    // ovenfor (en gemt kladde er nyere/vigtigere arbejde end en frisk prefill).
    const draft = await api('getArrestDraft', { citizenid: u.identifier });
    if (draft && draft.payload) {
        applyDraftToForm(draft.payload, draft.updated_at);
    }
}

function closeArrestForm() {
    clearTimeout(arrestDraftTimer);
    const cid = state.arrestForm && state.arrestForm.citizenid;
    state.arrestForm = null;
    switchTab(state.previousTab || 'persons');
    if (state.currentTab === 'persons' && cid) {
        setTimeout(() => openPerson(cid), 100);
    }
}
$('#af-cancel').addEventListener('click', closeArrestForm);
$('#af-cancel-2').addEventListener('click', closeArrestForm);

// #af-dropzone er et statisk element i index.html (kun vist/skjult, aldrig
// genskabt) — bindes derfor ÉN gang her, ikke inde i openArrestForm(), for
// ikke at hobe identiske paste-listeners op hver gang formularen åbnes (§43).
// Handleren læser state.arrestForm dynamisk, så den altid rammer den
// aktuelt åbne sigtelse.
bindImagePaste($('#af-dropzone'), dataUrl => {
    if (!state.arrestForm) return;
    const maxImgs = (state.staticConfig && state.staticConfig.images && state.staticConfig.images.maxPerEntry) || 4;
    if (state.arrestForm.images.length >= maxImgs) { toast(`Maks ${maxImgs} billeder.`, 'warning'); return; }
    state.arrestForm.images.push(dataUrl);
    renderArrestThumbs();
    scheduleArrestDraftSave();
});

function renderArrestPersonHead(u) {
    $('#af-person-head').innerHTML = `
        <div class="person-mugshot">👤</div>
        <div class="person-info" style="flex:1;">
            <h2>${escapeHtml(u.firstname || '')} ${escapeHtml(u.lastname || '')}</h2>
            <div class="kv"><span>CPR:</span><strong>${escapeHtml(u.dateofbirth || '—')}</strong></div>
            <div class="kv"><span>Telefon:</span><strong>${escapeHtml(u.phone_number || '—')}</strong></div>
            <div class="kv"><span>Job:</span><strong>${escapeHtml(u.job || '—')}</strong></div>
            <div class="kv"><span>Køn:</span><strong>${escapeHtml(u.sex || '—')}</strong></div>
        </div>`;
}

// ─── Deltagende betjente (§16) ─────────────────────────────────
$('#af-officer-search').addEventListener('input', async e => {
    const q = e.target.value.trim().toLowerCase();
    const box = $('#af-officer-results');
    if (!q) { box.classList.add('hidden'); return; }
    if (!state.onlinePlayersCache) state.onlinePlayersCache = await api('getOnlinePlayers') || [];
    const matches = state.onlinePlayersCache.filter(p =>
        `${p.firstname || ''} ${p.lastname || ''}`.toLowerCase().includes(q) &&
        !state.arrestForm.officers.some(o => o.identifier === p.citizenid)
    ).slice(0, 8);
    box.innerHTML = '';
    if (!matches.length) { box.innerHTML = '<div class="dash-empty">Ingen match</div>'; box.classList.remove('hidden'); return; }
    for (const p of matches) {
        const row = el('div', { className: 'result-item', onclick: () => addArrestOfficer(p) });
        row.innerHTML = `<div class="ri-title">${escapeHtml(p.firstname || '')} ${escapeHtml(p.lastname || '')}</div>
                         <div class="ri-meta"><span class="ri-job">${escapeHtml(p.jobLabel || p.job || '')}</span></div>`;
        box.appendChild(row);
    }
    box.classList.remove('hidden');
});
document.addEventListener('click', e => {
    if (!e.target.closest('.officer-search-wrap')) {
        const box = $('#af-officer-results');
        if (box) box.classList.add('hidden');
    }
});
function addArrestOfficer(p) {
    state.arrestForm.officers.push({ identifier: p.citizenid, name: `${p.firstname || ''} ${p.lastname || ''}`.trim() || 'Ukendt' });
    renderArrestOfficers();
    $('#af-officer-search').value = '';
    $('#af-officer-results').classList.add('hidden');
    scheduleArrestDraftSave();
}
function renderArrestOfficers() {
    const c = $('#af-officers'); c.innerHTML = '';
    state.arrestForm.officers.forEach((o, i) => {
        const chip = el('div', { className: 'officer-chip' });
        chip.innerHTML = `<span>${escapeHtml(o.name)}</span>`;
        const rm = el('button', { type: 'button', onclick: () => { state.arrestForm.officers.splice(i, 1); renderArrestOfficers(); scheduleArrestDraftSave(); } }, '✕');
        chip.appendChild(rm);
        c.appendChild(chip);
    });
}

// ─── Bødeskema (§17 → sigtelser) ───────────────────────────────
function renderArrestCharges() {
    const charges = state.chargesCache || [];
    const grouped = {};
    charges.forEach(c => { (grouped[c.category] = grouped[c.category] || []).push(c); });
    const html = Object.entries(grouped).map(([cat, list]) => `
        <div style="margin-bottom:10px;">
            <strong style="color:var(--accent);font-size:12px;">${escapeHtml(cat)}</strong>
            ${list.map(c => `
                <label style="display:flex;align-items:center;gap:8px;padding:5px 4px;font-size:12.5px;">
                    <input type="checkbox" data-fine="${c.fine}" data-jail="${c.jail}" value="${escapeHtml(c.label)}" ${state.arrestForm.charges.includes(c.label) ? 'checked' : ''}>
                    <span style="flex:1;">${escapeHtml(c.label)}</span>
                    <span style="color:var(--gold);font-family:'JetBrains Mono',monospace;">${c.fine} kr</span>
                    <span style="color:var(--danger);font-family:'JetBrains Mono',monospace;">${c.jail} md</span>
                </label>
            `).join('')}
        </div>
    `).join('');
    $('#af-charges').innerHTML = html || '<div class="muted">Intet bødeskema fundet.</div>';
    recalcArrestTotals();
    $$('#af-charges input').forEach(cb => cb.addEventListener('change', () => {
        state.arrestForm.charges = $$('#af-charges input:checked').map(x => x.value);
        recalcArrestTotals();
        scheduleArrestDraftSave();
    }));
}
function recalcArrestTotals() {
    let f = 0, j = 0;
    $$('#af-charges input:checked').forEach(cb => { f += parseInt(cb.dataset.fine) || 0; j += parseInt(cb.dataset.jail) || 0; });
    $('#af-tfine').textContent = f;
    $('#af-tjail').textContent = j;
}

// ─── Hændelsesforløb ────────────────────────────────────────────
$('#af-notes').addEventListener('input', () => {
    state.arrestForm.notes = $('#af-notes').value;
    scheduleArrestDraftSave();
});

// ─── Beslaglagte genstande (§19) ────────────────────────────────
function renderSeizedCategories() {
    const cats = (state.staticConfig && state.staticConfig.seizedCategories) || [];
    $('#af-seized-cat').innerHTML = cats.map(c => `<option value="${escapeHtml(c)}">${escapeHtml(c)}</option>`).join('');
}
function renderArrestSeized() {
    const c = $('#af-seized'); c.innerHTML = '';
    state.arrestForm.seized.forEach((s, i) => {
        const row = el('div', { className: 'seized-row' });
        row.innerHTML = `<span class="sr-cat">${escapeHtml(s.category)}</span><span class="sr-item">${escapeHtml(s.item)}</span><span class="sr-qty">×${s.qty}</span>`;
        const rm = el('button', { type: 'button', onclick: () => { state.arrestForm.seized.splice(i, 1); renderArrestSeized(); scheduleArrestDraftSave(); } }, '✕');
        row.appendChild(rm);
        c.appendChild(row);
    });
}
$('#af-seized-add-btn').addEventListener('click', () => {
    const cat = $('#af-seized-cat').value;
    const item = $('#af-seized-item').value.trim();
    const qty = Math.max(1, parseInt($('#af-seized-qty').value) || 1);
    if (!item) { toast('Angiv en genstand', 'error'); return; }
    state.arrestForm.seized.push({ category: cat, item, qty });
    $('#af-seized-item').value = '';
    $('#af-seized-qty').value = '1';
    renderArrestSeized();
    scheduleArrestDraftSave();
});

// ─── Klip / billeder (§18) ───────────────────────────────────────
function renderArrestThumbs() {
    renderImageThumbs($('#af-thumbs'), state.arrestForm.images, i => {
        state.arrestForm.images.splice(i, 1);
        renderArrestThumbs();
        scheduleArrestDraftSave();
    });
}

// ─── Autosave / kladde (§21) ─────────────────────────────────────
function scheduleArrestDraftSave() {
    if (!state.arrestForm) return;
    clearTimeout(arrestDraftTimer);
    arrestDraftTimer = setTimeout(saveArrestDraftNow, 1500);
}
async function saveArrestDraftNow() {
    if (!state.arrestForm) return;
    const payload = {
        notes: state.arrestForm.notes,
        charges: state.arrestForm.charges,
        officers: state.arrestForm.officers,
        images: state.arrestForm.images,
        seized_items: state.arrestForm.seized,
        warrant_id: state.arrestForm.warrant_id,
    };
    await api('saveArrestDraft', { citizenid: state.arrestForm.citizenid, payload });
    showDraftBanner(`💾 Kladde gemt kl. ${new Date().toLocaleTimeString('da-DK', { hour: '2-digit', minute: '2-digit' })}`);
}
function applyDraftToForm(payload, updatedAt) {
    state.arrestForm.notes    = payload.notes || '';
    state.arrestForm.officers = Array.isArray(payload.officers) ? payload.officers : [];
    state.arrestForm.images   = Array.isArray(payload.images) ? payload.images : [];
    state.arrestForm.seized   = Array.isArray(payload.seized_items) ? payload.seized_items : [];
    state.arrestForm.charges  = Array.isArray(payload.charges) ? payload.charges : [];
    if (payload.warrant_id) state.arrestForm.warrant_id = payload.warrant_id;

    $('#af-notes').value = state.arrestForm.notes;
    renderArrestOfficers();
    renderArrestThumbs();
    renderArrestSeized();
    renderArrestCharges();

    showDraftBanner(`📝 Kladde indlæst — sidst gemt ${escapeHtml(fmtDate(updatedAt))}`);
}
function showDraftBanner(msg) {
    const banner = $('#af-draft-banner');
    banner.innerHTML = `<span>${msg}</span><button class="btn btn-ghost" id="af-draft-delete">🗑 Slet kladde</button>`;
    banner.classList.remove('hidden');
    $('#af-draft-delete').addEventListener('click', async () => {
        if (!state.arrestForm) return;
        clearTimeout(arrestDraftTimer);
        await api('deleteArrestDraft', { citizenid: state.arrestForm.citizenid });
        banner.classList.add('hidden');
        toast('Kladde slettet.', 'success');
    });
}

// ─── Opret / Annullér (§20) ──────────────────────────────────────
$('#af-submit').addEventListener('click', async () => {
    if (!state.arrestForm) return;
    const notes = $('#af-notes').value.trim();
    if (!notes) { toast('Beskriv hændelsesforløbet', 'error'); return; }
    if (!state.arrestForm.charges.length) { toast('Vælg mindst én sigtelse fra bødeskemaet', 'error'); return; }

    const fine = parseInt($('#af-tfine').textContent) || 0;
    const jail = parseInt($('#af-tjail').textContent) || 0;
    const cid  = state.arrestForm.citizenid;

    await api('createArrest', {
        citizenid:    cid,
        charges:      state.arrestForm.charges,
        total_fine:   fine,
        total_jail:   jail,
        notes,
        officers:     state.arrestForm.officers,
        images:       state.arrestForm.images,
        seized_items: state.arrestForm.seized,
        warrant_id:   state.arrestForm.warrant_id,
    });

    clearTimeout(arrestDraftTimer);
    toast('Sigtelse oprettet.', 'success');
    state.arrestForm = null;
    switchTab('persons');
    setTimeout(() => openPerson(cid), 150);
});

// =============================================================
//  DISPATCH — under udvikling (§9), se cl_nui.lua for detaljer.
// =============================================================

// =============================================================
//  PATROL
// =============================================================
async function loadPatrolPanel() {
    if (state.staticConfig && state.staticConfig.units) {
        renderUnitGrid(state.staticConfig.units);
    }
    const list = await api('getPatrolUnits') || [];
    renderPatrolGrid(list);
    refreshDutyTime();
}
function renderUnitGrid(units) {
    const c = $('#unit-grid'); c.innerHTML = '';
    for (const u of units) {
        const b = el('button', { className: 'unit-btn', onclick: () => selectUnit(u.call) });
        b.innerHTML = `<strong>${escapeHtml(u.call)}</strong><span>${escapeHtml(u.label)}</span>`;
        c.appendChild(b);
    }
}
async function selectUnit(call) {
    await api('joinUnit', { unit_call: call });
    $$('.unit-btn').forEach(b => b.classList.toggle('active', b.querySelector('strong').textContent === call));
    $('#unit-display').textContent = call;
}
$$('.status-pill').forEach(p => p.addEventListener('click', async () => {
    const s = parseInt(p.dataset.status);
    if (s === 4 && !confirm('Aktivér PANIC? Dette alarmerer alle betjente.')) return;
    $$('.status-pill').forEach(x => x.classList.remove('active'));
    p.classList.add('active');
    await api('setUnitStatus', { status: s });
}));
// Flådestyring (§22) — grupperer betjente der reelt sidder i samme
// køretøj (vehicleNetId sat af cl_polititablet.lua), i stedet for bare
// at liste hver betjent for sig.
function renderPatrolGrid(list) {
    const c = $('#patrol-grid'); if (!c) return;
    c.innerHTML = '';
    if (!list || !list.length) { c.innerHTML = '<div class="empty-state"><p class="muted">Ingen aktive enheder</p></div>'; return; }

    const groups = new Map(); // vehicleNetId -> medlemmer
    const solo = [];
    for (const p of list) {
        if (p.vehicleNetId) {
            if (!groups.has(p.vehicleNetId)) groups.set(p.vehicleNetId, []);
            groups.get(p.vehicleNetId).push(p);
        } else {
            solo.push(p);
        }
    }

    const memberRow = p => `
        <div class="fleet-member s${p.status || 1}">
            <span class="fm-role">${p.seatRole === 'driver' ? 'Fører' : p.seatRole === 'passenger' ? 'Passager' : ''}</span>
            <span class="fm-name">${escapeHtml(p.name)}${p.unit ? ` · ${escapeHtml(p.unit)}` : ''}</span>
            <span class="fm-status">${statusLabel(p.status)}</span>
        </div>`;

    for (const members of groups.values()) {
        members.sort((a, b) => (a.seatRole === 'driver' ? 0 : 1) - (b.seatRole === 'driver' ? 0 : 1));
        const card = el('div', { className: 'fleet-card' });
        card.innerHTML = `
            <div class="fc-vehicle"><span class="fc-icon">🚓</span>${escapeHtml(members[0].vehicleLabel || 'Køretøj')}</div>
            <div class="fc-members">${members.map(memberRow).join('')}</div>`;
        c.appendChild(card);
    }
    for (const p of solo) {
        const card = el('div', { className: 'fleet-card solo' });
        card.innerHTML = `
            <div class="fc-vehicle"><span class="fc-icon">👮</span>${escapeHtml(p.name)}</div>
            <div class="fc-members">
                <div class="fleet-member s${p.status || 1}">
                    <span class="fm-name">${escapeHtml(p.unit || 'Ingen enhed')}</span>
                    <span class="fm-status">${statusLabel(p.status)}</span>
                </div>
            </div>`;
        c.appendChild(card);
    }
}
async function refreshDutyTime() {
    const dt = await api('getDutyTime');
    state.dutyBaseSec = parseInt(dt && dt.seconds) || 0;
    state.dutyStartTs = Date.now();
}

// =============================================================
//  CHARGES & LAWS
// =============================================================
async function loadCharges() {
    if (!state.chargesCache) state.chargesCache = await api('getCharges') || [];
    renderCharges($('#charges-search').value.trim().toLowerCase());
}
$('#charges-search').addEventListener('input', () => renderCharges($('#charges-search').value.trim().toLowerCase()));
function renderCharges(filter) {
    const c = $('#charges-grid'); c.innerHTML = '';
    const list = (state.chargesCache || []).filter(x =>
        !filter || x.label.toLowerCase().includes(filter) || x.category.toLowerCase().includes(filter));
    if (!list.length) { c.innerHTML = '<div class="empty-state"><p class="muted">Ingen bøder fundet</p></div>'; return; }
    for (const ch of list) {
        const div = el('div', { className: 'charge-card' });
        div.innerHTML = `
            <div class="charge-cat">${escapeHtml(ch.category)}</div>
            <div class="charge-label">${escapeHtml(ch.label)}</div>
            <div class="charge-vals">
                <span class="v-fine">${ch.fine} kr</span>
                <span class="v-jail">${ch.jail} md</span>
            </div>
            ${ch.law_ref ? `<div class="charge-ref">${escapeHtml(ch.law_ref)}</div>` : ''}`;
        c.appendChild(div);
    }
}

async function loadLaws(query) {
    const list = await api('getLaws', { query: query || '' }) || [];
    state.lawsCache = list;
    renderLaws(list);
}
$('#laws-search').addEventListener('input', () => {
    clearTimeout(state._lawsT);
    const q = $('#laws-search').value.trim();
    state._lawsT = setTimeout(() => {
        if (state.lawsView === 'radio') renderRadioCodes(q);
        else loadLaws(q);
    }, 300);
});
function renderLaws(list) {
    const c = $('#laws-list'); c.innerHTML = '';
    if (!list.length) { c.innerHTML = '<div class="empty-state"><p class="muted">Ingen resultater</p></div>'; return; }
    for (const l of list) {
        const div = el('div', { className: 'law-card' });
        div.innerHTML = `
            <div class="law-head">
                <span class="law-para">${escapeHtml(l.paragraph)}</span>
                <span class="law-title">${escapeHtml(l.title)}</span>
                <span class="law-book">${escapeHtml(l.book)}</span>
            </div>
            <div class="law-text">${escapeHtml(l.text)}</div>`;
        c.appendChild(div);
    }
}

// ─── RADIOMELDINGER (§6) — vises som en fane inde i Lovbogen ───
function renderRadioCodes(query) {
    const c = $('#radio-list'); c.innerHTML = '';
    let list = (state.staticConfig && state.staticConfig.radioCodes) || [];
    if (query) {
        const q = query.toLowerCase();
        list = list.filter(r => r.code.toLowerCase().includes(q) || r.desc.toLowerCase().includes(q));
    }
    if (!list.length) { c.innerHTML = '<div class="empty-state"><p class="muted">Ingen resultater</p></div>'; return; }
    for (const r of list) {
        const div = el('div', { className: 'law-card' });
        div.innerHTML = `
            <div class="law-head"><span class="law-title">${escapeHtml(r.code)}</span></div>
            <div class="law-text">${escapeHtml(r.desc)}</div>`;
        c.appendChild(div);
    }
}
$$('#laws-view-toggle .view-toggle-btn').forEach(btn => btn.addEventListener('click', () => {
    $$('#laws-view-toggle .view-toggle-btn').forEach(b => b.classList.toggle('active', b === btn));
    state.lawsView = btn.dataset.lawview;
    const q = $('#laws-search').value.trim();
    if (state.lawsView === 'radio') {
        $('#laws-list').classList.add('hidden');
        $('#radio-list').classList.remove('hidden');
        renderRadioCodes(q);
    } else {
        $('#radio-list').classList.add('hidden');
        $('#laws-list').classList.remove('hidden');
        loadLaws(q);
    }
}));

// =============================================================
//  ACCOUNTS (boss panel)
// =============================================================
async function loadAccounts() {
    const list = await api('getRecentAccounts') || [];
    const tb = $('#accounts-tbody'); tb.innerHTML = '';
    if (!list.length) { tb.innerHTML = '<tr><td colspan="9"><div class="empty-state"><p class="muted">Ingen konti endnu — brug /registermdt</p></div></td></tr>'; return; }
    for (const a of list) {
        const tr = el('tr');
        tr.innerHTML = `
            <td><code>${escapeHtml(a.username)}</code></td>
            <td>${escapeHtml(a.rank || '—')}</td>
            <td>${a.grade ?? 0}</td>
            <td>${escapeHtml(a.badge_number || '—')}</td>
            <td><span class="acct-status ${a.status}">${a.status}</span></td>
            <td>${escapeHtml(a.created_by_name || '—')}</td>
            <td>${fmtDate(a.created_at)}</td>
            <td>${a.last_login ? fmtDate(a.last_login) : '<span class="muted">aldrig</span>'}</td>
            <td>
                <button class="acct-btn" data-act="reset">Reset pw</button>
                <button class="acct-btn" data-act="suspend">${a.status==='suspended'?'Aktivér':'Suspendér'}</button>
                <button class="acct-btn danger" data-act="ban">${a.status==='banned'?'Aktivér':'Ban'}</button>
            </td>`;
        tr.querySelector('[data-act="reset"]').addEventListener('click', () => openResetPwModal(a.username));
        tr.querySelector('[data-act="suspend"]').addEventListener('click', async () => {
            const newSt = a.status === 'suspended' ? 'active' : 'suspended';
            const r = await api('setAccountStatus', { username: a.username, status: newSt });
            if (r && r.ok) { toast('Status opdateret', 'success'); loadAccounts(); }
        });
        tr.querySelector('[data-act="ban"]').addEventListener('click', async () => {
            const newSt = a.status === 'banned' ? 'active' : 'banned';
            if (newSt === 'banned' && !confirm('Bekræft ban af '+a.username+'?')) return;
            const r = await api('setAccountStatus', { username: a.username, status: newSt });
            if (r && r.ok) { toast('Status opdateret', 'success'); loadAccounts(); }
        });
        tb.appendChild(tr);
    }
}
$('#accounts-refresh').addEventListener('click', loadAccounts);
function openResetPwModal(username) {
    openModal(`
        <div class="modal-header"><h3>🔑 Reset adgangskode — ${escapeHtml(username)}</h3></div>
        <div class="modal-body">
            <p class="muted">Spilleren bliver tvunget til at vælge en ny adgangskode ved næste login.</p>
            <div class="form-group"><label>Ny midlertidig adgangskode</label><input type="text" id="rp-new" value="1234"></div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal()">Annullér</button>
            <button class="btn btn-primary" id="rp-save">Bekræft reset</button>
        </div>
    `);
    $('#rp-save').addEventListener('click', async () => {
        const r = await api('resetPassword', { username, newPw: $('#rp-new').value });
        if (r && r.ok) { toast('Adgangskode nulstillet', 'success'); closeModal(); loadAccounts(); }
        else { toast((r && r.error) || 'Fejl', 'error'); }
    });
}

// ─── SETTINGS · Change password ──────────────────────────────
$('#open-pwchange').addEventListener('click', () => {
    openModal(`
        <div class="modal-header"><h3>🔐 Skift adgangskode</h3></div>
        <div class="modal-body">
            <div class="form-group"><label>Nuværende</label><input type="password" id="cp-old" maxlength="64"></div>
            <div class="form-group"><label>Ny</label><input type="password" id="cp-new" maxlength="64"></div>
            <div class="form-group"><label>Gentag</label><input type="password" id="cp-new2" maxlength="64"></div>
            <div id="cp-error" class="login-error hidden"></div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-ghost" onclick="closeModal()">Annullér</button>
            <button class="btn btn-primary" id="cp-save">Gem</button>
        </div>
    `);
    $('#cp-save').addEventListener('click', async () => {
        const o = $('#cp-old').value, n = $('#cp-new').value, n2 = $('#cp-new2').value;
        const err = $('#cp-error'); err.classList.add('hidden');
        if (!o || !n || !n2) { err.textContent='Udfyld alle felter'; err.classList.remove('hidden'); return; }
        if (n !== n2) { err.textContent='Ny adgangskode matcher ikke'; err.classList.remove('hidden'); return; }
        const r = await api('changePassword', { oldPw: o, newPw: n });
        if (!r || !r.ok) { err.textContent=(r && r.error)||'Fejl'; err.classList.remove('hidden'); return; }
        closeModal();
        toast('Adgangskode opdateret', 'success');
    });
});

// ─── QUICK SEARCH (top bar) ──────────────────────────────────
$('#quick-search').addEventListener('input', e => {
    clearTimeout(state.quickSearchTimer);
    const q = e.target.value.trim();
    const box = $('#quick-search-results');
    if (q.length < 2) { box.classList.add('hidden'); return; }
    state.quickSearchTimer = setTimeout(async () => {
        const list = await api('searchCitizens', { query: q }) || [];
        box.innerHTML = '';
        if (!list.length) { box.innerHTML = '<div class="dash-empty">Ingen resultater</div>'; box.classList.remove('hidden'); return; }
        for (const p of list.slice(0, 6)) {
            const row = el('div', { className: 'result-item', onclick: () => {
                box.classList.add('hidden');
                $('#quick-search').value = '';
                switchTab('persons');
                setTimeout(() => openPerson(p.citizenid), 100);
            }});
            row.innerHTML = `<div class="ri-title">${escapeHtml(p.firstname||'')} ${escapeHtml(p.lastname||'')}</div>
                             <div class="ri-meta">${p.warrant_count > 0 ? `<span style="color:var(--danger);">🚨 ${p.warrant_count}</span>` : ''}<span>${escapeHtml((p.citizenid||'').slice(-8))}</span></div>`;
            box.appendChild(row);
        }
        box.classList.remove('hidden');
    }, 250);
});
document.addEventListener('click', e => {
    if (!e.target.closest('.quick-search')) $('#quick-search-results').classList.add('hidden');
});

// =============================================================
//  INIT
// =============================================================
window.addEventListener('DOMContentLoaded', () => {
    // Body starter usynlig (NUI fader baggrund)
    document.body.style.background = 'transparent';
});