const app = document.getElementById('app');
const roleBadge = document.getElementById('roleBadge');
const closeBtn = document.getElementById('closeBtn');

const trustValueEl = document.getElementById('trustValue');
const trustBarFillEl = document.getElementById('trustBarFill');
const trustHintEl = document.getElementById('trustHint');
const statAssignedEl = document.getElementById('statAssigned');
const statCompletedEl = document.getElementById('statCompleted');
const statActiveEl = document.getElementById('statActive');
const statRemovedEl = document.getElementById('statRemoved');
const statusTextEl = document.getElementById('statusText');
const historyListEl = document.getElementById('historyList');
const toastStackEl = document.getElementById('toastStack');
const viewTitleEl = document.getElementById('viewTitle');
const viewSubtitleEl = document.getElementById('viewSubtitle');

const ROLE_LABELS = { player: 'Spiller', staff: 'Staff', owner: 'Owner' };
const VIEW_META = {
    overview: ['Oversigt', 'Dit personlige overblik'],
    history: ['Historik', 'Alle ændringer i din tjeneste over tid'],
    players: ['Spillere', 'Søg eller vælg blandt spillere der er online'],
    stats: ['Statistik', 'Globale tal for hele systemet'],
    settings: ['Indstillinger', 'Justér trust factor, tidsreduktion og anti-escape'],
    tasks: ['Opgavetyper', 'Slå enkelte opgavetyper til/fra'],
    audit: ['Audit log', 'Komplet historik over alle staff/owner-handlinger'],
};

// Ren, indbygget default-avatar (ingen broken images, ingen ekstern fil).
const DEFAULT_AVATAR = 'data:image/svg+xml;utf8,' + encodeURIComponent(`
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">
    <rect width="40" height="40" rx="20" fill="#262a35"/>
    <circle cx="20" cy="16" r="7" fill="#454b5c"/>
    <path d="M6 36c0-8 6.3-14 14-14s14 6 14 14" fill="#454b5c"/>
</svg>`);

let historyLoaded = false;
let currentRole = 'player';
let inService = false;

function resolveResourceName() {
    // Native funktion, injiceret af CEF i spillet. Findes ikke hvis man
    // åbner html/index.html direkte i en almindelig browser til test.
    return (typeof window.GetParentResourceName === 'function')
        ? window.GetParentResourceName()
        : 'Masitz-samfundstjeneste';
}

async function nuiFetch(endpoint, body = {}) {
    try {
        const resp = await fetch(`https://${resolveResourceName()}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
        return await resp.json();
    } catch (e) {
        // Sker typisk kun ved test uden for spillet — fejl skal aldrig
        // vælte resten af UI'et.
        console.error('nuiFetch fejlede:', endpoint, e);
        return null;
    }
}

function withDefaultAvatar(url) {
    return url && url.trim() !== '' ? url : DEFAULT_AVATAR;
}

// ------------------------------------------------------------
// TOASTS
// ------------------------------------------------------------
function showToast(message, kind = 'info') {
    const toast = document.createElement('div');
    toast.className = `toast toast-${kind}`;
    toast.textContent = message;
    toastStackEl.appendChild(toast);

    requestAnimationFrame(() => toast.classList.add('toast-in'));

    setTimeout(() => {
        toast.classList.remove('toast-in');
        setTimeout(() => toast.remove(), 220);
    }, 3200);
}

// ------------------------------------------------------------
// CONFIRM MODAL
// ------------------------------------------------------------
const confirmBackdrop = document.getElementById('confirmBackdrop');
const confirmTitleEl = document.getElementById('confirmTitle');
const confirmMessageEl = document.getElementById('confirmMessage');
const confirmOkBtn = document.getElementById('confirmOkBtn');
const confirmCancelBtn = document.getElementById('confirmCancelBtn');

function confirmAction(title, message) {
    confirmTitleEl.textContent = title;
    confirmMessageEl.textContent = message;
    confirmBackdrop.classList.remove('hidden');

    return new Promise((resolve) => {
        const cleanup = (result) => {
            confirmBackdrop.classList.add('hidden');
            confirmOkBtn.removeEventListener('click', onOk);
            confirmCancelBtn.removeEventListener('click', onCancel);
            resolve(result);
        };
        const onOk = () => cleanup(true);
        const onCancel = () => cleanup(false);

        confirmOkBtn.addEventListener('click', onOk);
        confirmCancelBtn.addEventListener('click', onCancel);
    });
}

confirmBackdrop.addEventListener('click', (e) => {
    if (e.target === confirmBackdrop) confirmBackdrop.classList.add('hidden');
});

// ------------------------------------------------------------
// TRUST FACTOR — FARVEGRADIENT (matcher Utils.GetTrustColor i Lua 1:1)
// ------------------------------------------------------------
const COLOR_GREEN = [53, 214, 138];
const COLOR_YELLOW = [255, 214, 10];
const COLOR_ORANGE = [255, 145, 0];
const COLOR_RED = [255, 92, 108];

function lerpColor(a, b, t) {
    return [
        Math.floor(a[0] + (b[0] - a[0]) * t),
        Math.floor(a[1] + (b[1] - a[1]) * t),
        Math.floor(a[2] + (b[2] - a[2]) * t),
    ];
}

function toHex([r, g, b]) {
    return `#${[r, g, b].map((v) => v.toString(16).padStart(2, '0')).join('')}`;
}

function getTrustColor(percent) {
    percent = Math.max(0, Math.min(100, percent));

    if (percent >= 90) return toHex(COLOR_GREEN);
    if (percent >= 80) return toHex(lerpColor(COLOR_GREEN, COLOR_YELLOW, (90 - percent) / 10));
    if (percent >= 70) return toHex(COLOR_ORANGE);
    if (percent >= 60) return toHex(lerpColor(COLOR_ORANGE, COLOR_RED, (70 - percent) / 10));
    return toHex(COLOR_RED);
}

function getTrustHint(percent) {
    if (percent >= 90) return 'Din tillid er i god stand.';
    if (percent >= 70) return 'Din tillid er faldet en smule.';
    if (percent >= 60) return 'Din tillid er markant lav.';
    return 'Din tillid er kritisk lav.';
}

// ------------------------------------------------------------
// ANIMEREDE TÆLLERE
// ------------------------------------------------------------
function animateCount(el, target, duration = 600) {
    const start = Number(el.textContent) || 0;
    const startTime = performance.now();

    function tick(now) {
        const progress = Math.min(1, (now - startTime) / duration);
        const eased = 1 - Math.pow(1 - progress, 3);
        el.textContent = Math.round(start + (target - start) * eased);

        if (progress < 1) requestAnimationFrame(tick);
    }

    requestAnimationFrame(tick);
}

function formatDate(rawDate) {
    if (!rawDate) return '';

    let parsed;
    if (rawDate instanceof Date) {
        parsed = rawDate;
    } else if (typeof rawDate === 'string') {
        // MySQL DATETIME kommer normalt som "YYYY-MM-DD HH:MM:SS"
        parsed = new Date(rawDate.replace(' ', 'T'));
    } else {
        parsed = new Date(rawDate);
    }

    if (isNaN(parsed.getTime())) return String(rawDate);

    const dd = String(parsed.getDate()).padStart(2, '0');
    const mm = String(parsed.getMonth() + 1).padStart(2, '0');
    const yyyy = parsed.getFullYear();
    return `${dd}/${mm}/${yyyy}`;
}

// ------------------------------------------------------------
// SIDEBAR / VIEW SWITCHING
// ------------------------------------------------------------
const viewLoaders = {
    history: loadHistoryIfNeeded,
    players: loadOnlinePlayersIfNeeded,
    stats: () => loadOwnerPanel('stats'),
    settings: () => loadOwnerPanel('settings'),
    tasks: () => loadOwnerPanel('tasks'),
    audit: () => loadOwnerPanel('audit', true),
};

document.querySelectorAll('.nav-item').forEach((navBtn) => {
    navBtn.addEventListener('click', () => {
        const view = navBtn.dataset.view;

        document.querySelectorAll('.nav-item').forEach((b) => b.classList.remove('active'));
        document.querySelectorAll('.view').forEach((v) => v.classList.remove('active'));

        navBtn.classList.add('active');
        document.getElementById(`view-${view}`).classList.add('active');

        const meta = VIEW_META[view];
        if (meta) {
            viewTitleEl.textContent = meta[0];
            viewSubtitleEl.textContent = meta[1];
        }

        if (viewLoaders[view]) viewLoaders[view]();
    });
});

// ------------------------------------------------------------
// OVERSIGT / PLAYER RENDER
// ------------------------------------------------------------
function renderPlayer(player) {
    const trust = Math.max(0, Math.min(100, Number(player.trust_factor) || 0));
    const color = getTrustColor(trust);

    trustValueEl.textContent = `${Math.round(trust)}%`;
    trustValueEl.style.color = color;
    trustHintEl.textContent = getTrustHint(trust);

    requestAnimationFrame(() => {
        trustBarFillEl.style.width = `${trust}%`;
        trustBarFillEl.style.color = color;
        trustBarFillEl.style.backgroundColor = color;
    });

    animateCount(statAssignedEl, Number(player.total_assigned) || 0);
    animateCount(statCompletedEl, Number(player.total_completed) || 0);
    animateCount(statActiveEl, Number(player.active_tasks) || 0);
    animateCount(statRemovedEl, Number(player.total_removed_manual) || 0);

    if (player.inService !== undefined) inService = !!player.inService;

    const activeTasks = Number(player.active_tasks) || 0;
    if (inService) {
        statusTextEl.textContent = `Du er i tjeneste — ${activeTasks} aktive opgaver tilbage.`;
    } else if (activeTasks > 0) {
        statusTextEl.textContent = `Du har ${activeTasks} aktive opgaver. Du bliver sendt ud automatisk.`;
    } else {
        statusTextEl.textContent = 'Du har ingen aktive opgaver lige nu.';
    }
}

// ------------------------------------------------------------
// HISTORIK
// ------------------------------------------------------------
function renderHistory(rows) {
    historyListEl.innerHTML = '';

    if (!rows || rows.length === 0) {
        historyListEl.innerHTML = '<p class="history-empty">Der er ingen historik at vise endnu.</p>';
        return;
    }

    rows.forEach((row, index) => {
        const isPositive = row.amount > 0;
        const item = document.createElement('div');
        item.className = 'history-item';
        item.style.animationDelay = `${Math.min(index, 12) * 0.02}s`;

        item.innerHTML = `
            <div class="history-item-left">
                <span class="history-reason">${row.reason}</span>
                <span class="history-date">${formatDate(row.created_at)}${row.actor_name ? ' · ' + row.actor_name : ''}</span>
            </div>
            <span class="history-amount ${isPositive ? 'positive' : 'negative'}">${isPositive ? '+' : ''}${row.amount} opgaver</span>
        `;

        historyListEl.appendChild(item);
    });
}

async function loadHistoryIfNeeded() {
    if (historyLoaded) return;
    historyLoaded = true;

    const rows = await nuiFetch('getHistory');
    renderHistory(rows);
}

// ------------------------------------------------------------
// SPILLERE (staff + owner) — søgning OG online-liste
// ------------------------------------------------------------
const staffSearchInput = document.getElementById('staffSearchInput');
const staffSearchBtn = document.getElementById('staffSearchBtn');
const playersListEl = document.getElementById('playersList');
const playersListTitleEl = document.getElementById('playersListTitle');
const staffProfileEl = document.getElementById('staffProfile');
const profileEmptyStateEl = document.getElementById('profileEmptyState');
const refreshOnlineBtn = document.getElementById('refreshOnlineBtn');
const onlineCountBadge = document.getElementById('onlineCountBadge');

let onlinePlayersLoaded = false;
let selectedIdentifier = null;

function trustBadgeHtml(trust) {
    const color = getTrustColor(trust);
    return `<span class="trust-badge" style="color:${color}; border-color:${color}">${Math.round(trust)}%</span>`;
}

function renderPlayerRows(container, profiles, emptyMessage) {
    container.innerHTML = '';

    if (!profiles || profiles.length === 0) {
        container.innerHTML = `<p class="search-empty">${emptyMessage}</p>`;
        return;
    }

    profiles.forEach((profile, index) => {
        const row = document.createElement('button');
        row.type = 'button';
        row.className = 'player-row';
        row.style.animationDelay = `${Math.min(index, 14) * 0.02}s`;
        if (profile.identifier === selectedIdentifier) row.classList.add('selected');

        const online = !!profile.source;
        row.innerHTML = `
            <img class="player-avatar-sm" src="${withDefaultAvatar(profile.steam_avatar || profile.discord_avatar)}" onerror="this.src='${DEFAULT_AVATAR}'" />
            <div class="player-row-info">
                <span class="player-row-name">${profile.name}</span>
                <span class="player-row-sub">${online ? 'Online · ID ' + profile.source : 'Offline'}</span>
            </div>
            ${online ? '<span class="online-dot" title="Online"></span>' : ''}
            ${trustBadgeHtml(profile.trust_factor)}
        `;
        row.addEventListener('click', () => {
            selectedIdentifier = profile.identifier;
            container.querySelectorAll('.player-row').forEach((r) => r.classList.remove('selected'));
            row.classList.add('selected');
            renderStaffProfile(profile);
        });
        container.appendChild(row);
    });
}

async function loadOnlinePlayersIfNeeded() {
    if (onlinePlayersLoaded) return;
    await refreshOnlinePlayers();
}

async function refreshOnlinePlayers() {
    refreshOnlineBtn.classList.add('spinning');
    playersListTitleEl.textContent = 'Online spillere';

    const profiles = await nuiFetch('staffGetOnlinePlayers');
    onlinePlayersLoaded = true;

    onlineCountBadge.textContent = profiles ? profiles.length : 0;
    onlineCountBadge.classList.toggle('hidden', !profiles || profiles.length === 0);

    renderPlayerRows(playersListEl, profiles, 'Ingen spillere er online lige nu.');
    setTimeout(() => refreshOnlineBtn.classList.remove('spinning'), 400);
}

function renderStaffProfile(profile) {
    profileEmptyStateEl.classList.add('hidden');
    staffProfileEl.classList.remove('hidden');
    staffProfileEl.dataset.identifier = profile.identifier;

    staffProfileEl.innerHTML = `
        <div class="profile-header">
            <img class="profile-avatar" src="${withDefaultAvatar(profile.steam_avatar || profile.discord_avatar)}" onerror="this.src='${DEFAULT_AVATAR}'" />
            <div>
                <h3>${profile.name}</h3>
                <span class="profile-sub">${profile.source ? 'Online · ID ' + profile.source : 'Offline'}</span>
            </div>
            ${trustBadgeHtml(profile.trust_factor)}
        </div>

        <div class="profile-stats">
            <div class="profile-stat"><span>${profile.active_tasks}</span><label>Aktive</label></div>
            <div class="profile-stat"><span>${profile.total_assigned}</span><label>Tildelte</label></div>
            <div class="profile-stat"><span>${profile.total_completed}</span><label>Gennemført</label></div>
        </div>

        <div class="profile-actions">
            <div class="action-row">
                <input type="number" min="1" class="text-input input-sm" id="giveAmount" placeholder="Antal" />
                <input type="text" class="text-input" id="giveReason" placeholder="Årsag" />
                <button class="btn btn-primary" id="giveBtn" type="button">Giv</button>
            </div>
            <div class="action-row">
                <input type="number" min="1" class="text-input input-sm" id="removeAmount" placeholder="Antal" />
                <button class="btn btn-secondary" id="removeBtn" type="button">Fjern</button>
                <input type="number" min="0" class="text-input input-sm" id="setAmount" placeholder="Sæt til" />
                <button class="btn btn-secondary" id="setBtn" type="button">Sæt</button>
            </div>
            <div class="action-row">
                <button class="btn btn-danger" id="releaseBtn" type="button">Løslad spiller</button>
            </div>
        </div>
    `;

    document.getElementById('giveBtn').addEventListener('click', () => runStaffAction('staffGiveService', {
        identifier: profile.identifier,
        amount: Number(document.getElementById('giveAmount').value),
        reason: document.getElementById('giveReason').value || 'Tildelt af Staff',
    }));

    document.getElementById('removeBtn').addEventListener('click', () => runStaffAction('staffRemoveTasks', {
        identifier: profile.identifier,
        amount: Number(document.getElementById('removeAmount').value),
    }));

    document.getElementById('setBtn').addEventListener('click', () => runStaffAction('staffSetTasks', {
        identifier: profile.identifier,
        amount: Number(document.getElementById('setAmount').value),
    }));

    document.getElementById('releaseBtn').addEventListener('click', async () => {
        const ok = await confirmAction('Løslad spiller?', `${profile.name} mister alle resterende opgaver med det samme. Dette kan ikke fortrydes.`);
        if (ok) runStaffAction('staffRelease', { identifier: profile.identifier });
    });
}

async function runStaffAction(endpoint, payload) {
    const result = await nuiFetch(endpoint, payload);
    if (result && result.ok) {
        showToast('Handling gennemført.', 'success');
        if (result.profile) renderStaffProfile(result.profile);
        refreshOnlinePlayers();
    } else {
        showToast((result && result.error) || 'Handlingen fejlede.', 'error');
    }
}

staffSearchBtn.addEventListener('click', async () => {
    const query = staffSearchInput.value.trim();
    if (query.length < 2) {
        onlinePlayersLoaded = false;
        loadOnlinePlayersIfNeeded();
        return;
    }
    playersListTitleEl.textContent = `Søgeresultater for "${query}"`;
    const results = await nuiFetch('staffSearch', { query });
    renderPlayerRows(playersListEl, results, 'Ingen spillere fundet.');
});

staffSearchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') staffSearchBtn.click();
});

staffSearchInput.addEventListener('input', () => {
    if (staffSearchInput.value.trim() === '') {
        onlinePlayersLoaded = false;
        loadOnlinePlayersIfNeeded();
    }
});

refreshOnlineBtn.addEventListener('click', () => {
    onlinePlayersLoaded = false;
    refreshOnlinePlayers();
});

// ------------------------------------------------------------
// OWNER
// ------------------------------------------------------------
const ownerStatsGrid = document.getElementById('ownerStatsGrid');
const ownerSettingsList = document.getElementById('ownerSettingsList');
const ownerTaskList = document.getElementById('ownerTaskList');
const ownerAuditList = document.getElementById('ownerAuditList');

const SETTING_LABELS = {
    trustFactorMode: { label: 'Trust factor-metode', type: 'select', options: [['per_task', 'Pr. opgave'], ['per_x_tasks', 'X opgaver = X%']] },
    trustFactorPerTaskLoss: { label: 'Tab pr. opgave (%)', type: 'number' },
    trustFactorPerXTasksTasks: { label: 'Antal opgaver pr. blok', type: 'number' },
    trustFactorPerXTasksLoss: { label: 'Tab pr. blok (%)', type: 'number' },
    trustFactorRecoveryEnabled: { label: 'Recovery aktiveret', type: 'bool' },
    trustFactorRecoveryMinutes: { label: 'Aktive minutter for +recovery', type: 'number' },
    trustFactorRecoveryAmount: { label: 'Recovery-mængde (%)', type: 'number' },
    trustFactorAfkTimeout: { label: 'AFK-timeout (sekunder)', type: 'number' },
    timeReductionEnabled: { label: 'Automatisk reduktion aktiveret', type: 'bool' },
    timeReductionInterval: { label: 'Interval (sekunder)', type: 'number' },
    timeReductionAmount: { label: 'Opgaver fjernet pr. interval', type: 'number' },
    antiEscapeEnabled: { label: 'Anti-escape aktiveret', type: 'bool' },
    antiEscapePauseDuration: { label: 'Escape-pause (sekunder)', type: 'number' },
};

let ownerPanelLoaded = { stats: false, settings: false, tasks: false, audit: false };
let auditOffset = 0;

function renderOwnerStats(stats) {
    ownerStatsGrid.innerHTML = '';
    if (!stats) {
        ownerStatsGrid.innerHTML = '<p class="search-empty">Kunne ikke hente statistik.</p>';
        return;
    }

    const entries = [
        ['Total spillere', stats.totalPlayers],
        ['Aktive nu', stats.activePlayers],
        ['Total tildelte', stats.totalAssigned],
        ['Total gennemført', stats.totalCompleted],
        ['Auto-fjernet', stats.autoRemoved],
        ['Manuelt fjernet', stats.manualRemoved],
        ['Gns. trust factor', `${stats.avgTrust}%`],
        ['Laveste trust factor', `${stats.minTrust}%`],
        ['Højeste trust factor', `${stats.maxTrust}%`],
    ];

    entries.forEach(([label, value], index) => {
        const card = document.createElement('div');
        card.className = 'card stat-card';
        card.style.animationDelay = `${index * 0.03}s`;
        card.innerHTML = `<span class="stat-value">${value}</span><span class="stat-label">${label}</span>`;
        ownerStatsGrid.appendChild(card);
    });
}

function renderOwnerSettings(settings) {
    ownerSettingsList.innerHTML = '';
    if (!settings) {
        ownerSettingsList.innerHTML = '<p class="search-empty">Kunne ikke hente indstillinger.</p>';
        return;
    }

    Object.entries(SETTING_LABELS).forEach(([key, meta]) => {
        const value = settings[key];
        const row = document.createElement('div');
        row.className = 'setting-row';

        let inputHtml = '';
        if (meta.type === 'select') {
            inputHtml = `<select class="select-input" data-key="${key}">${meta.options.map(([v, l]) => `<option value="${v}" ${v === value ? 'selected' : ''}>${l}</option>`).join('')}</select>`;
        } else if (meta.type === 'bool') {
            inputHtml = `<input type="checkbox" class="checkbox-input" data-key="${key}" ${value ? 'checked' : ''} />`;
        } else {
            inputHtml = `<input type="number" step="0.1" class="text-input input-sm" data-key="${key}" value="${value}" />`;
        }

        row.innerHTML = `<label>${meta.label}</label>${inputHtml}`;
        ownerSettingsList.appendChild(row);
    });

    ownerSettingsList.querySelectorAll('[data-key]').forEach((el) => {
        el.addEventListener('change', async () => {
            const key = el.dataset.key;
            const meta = SETTING_LABELS[key];
            let value = meta.type === 'bool' ? el.checked : (meta.type === 'select' ? el.value : Number(el.value));

            const result = await nuiFetch('ownerUpdateSetting', { key, value });
            showToast(result && result.ok ? 'Indstilling opdateret.' : ((result && result.error) || 'Kunne ikke opdatere.'), result && result.ok ? 'success' : 'error');
        });
    });
}

function renderOwnerTasks(tasks) {
    ownerTaskList.innerHTML = '';
    if (!tasks || tasks.length === 0) {
        ownerTaskList.innerHTML = '<p class="search-empty">Ingen opgavetyper fundet i config.</p>';
        return;
    }

    tasks.forEach((task) => {
        const row = document.createElement('div');
        row.className = 'setting-row';
        row.innerHTML = `
            <label>${task.label}</label>
            <input type="checkbox" class="checkbox-input" data-task="${task.key}" ${task.enabled ? 'checked' : ''} />
        `;
        ownerTaskList.appendChild(row);
    });

    ownerTaskList.querySelectorAll('[data-task]').forEach((el) => {
        el.addEventListener('change', async () => {
            const result = await nuiFetch('ownerToggleTask', { taskKey: el.dataset.task, enabled: el.checked });
            showToast(result && result.ok ? 'Opgavetype opdateret.' : ((result && result.error) || 'Fejlede.'), result && result.ok ? 'success' : 'error');
        });
    });
}

function renderAuditEntry(row) {
    const item = document.createElement('div');
    item.className = 'audit-item';
    let details = '';
    try { details = row.details ? JSON.stringify(JSON.parse(row.details)) : ''; } catch (e) { details = row.details || ''; }

    item.innerHTML = `
        <div class="audit-item-top">
            <span class="audit-action">${row.action}</span>
            <span class="audit-date">${formatDate(row.created_at)}</span>
        </div>
        <div class="audit-item-body">
            <span>${row.actor_name || 'System'}${row.target_name ? ' → ' + row.target_name : ''}</span>
            <span class="audit-details">${details}</span>
        </div>
    `;
    return item;
}

async function loadOwnerAudit(reset) {
    if (reset) {
        auditOffset = 0;
        ownerAuditList.innerHTML = '';
    }

    const rows = await nuiFetch('ownerGetAuditLog', { offset: auditOffset });

    if (!rows || rows.length === 0) {
        if (auditOffset === 0) ownerAuditList.innerHTML = '<p class="search-empty">Ingen log-poster endnu.</p>';
        return;
    }

    rows.forEach((row) => ownerAuditList.appendChild(renderAuditEntry(row)));
    auditOffset += rows.length;

    const more = document.createElement('button');
    more.className = 'btn btn-secondary btn-load-more';
    more.type = 'button';
    more.textContent = 'Indlæs flere';
    more.addEventListener('click', () => {
        more.remove();
        loadOwnerAudit(false);
    });
    ownerAuditList.appendChild(more);
}

async function loadOwnerPanel(panel, isAudit = false) {
    if (ownerPanelLoaded[panel]) return;
    ownerPanelLoaded[panel] = true;

    if (panel === 'stats') renderOwnerStats(await nuiFetch('ownerGetStatistics'));
    else if (panel === 'settings') renderOwnerSettings(await nuiFetch('ownerGetSettings'));
    else if (panel === 'tasks') renderOwnerTasks(await nuiFetch('ownerGetTasks'));
    else if (isAudit) loadOwnerAudit(true);
}

// ------------------------------------------------------------
// CLOSE
// ------------------------------------------------------------
function closeDashboard() {
    app.classList.add('hidden');
    nuiFetch('close');
}

closeBtn.addEventListener('click', closeDashboard);

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !app.classList.contains('hidden')) {
        closeDashboard();
    }
});

// ------------------------------------------------------------
// MESSAGES FRA CLIENT LUA
// ------------------------------------------------------------
window.addEventListener('message', (event) => {
    const data = event.data;

    if (data.action === 'open') {
        currentRole = data.role;
        inService = !!data.inService;

        roleBadge.textContent = ROLE_LABELS[data.role] || 'Spiller';

        document.querySelector('.nav-group-staff').classList.toggle('hidden', !(data.role === 'staff' || data.role === 'owner'));
        document.querySelector('.nav-group-owner').classList.toggle('hidden', data.role !== 'owner');

        renderPlayer(data.player);

        historyLoaded = false;
        onlinePlayersLoaded = false;
        selectedIdentifier = null;
        ownerPanelLoaded = { stats: false, settings: false, tasks: false, audit: false };

        // Reset til Oversigt hver gang dashboardet åbnes.
        document.querySelectorAll('.nav-item').forEach((b) => b.classList.remove('active'));
        document.querySelectorAll('.view').forEach((v) => v.classList.remove('active'));
        document.querySelector('.nav-item[data-view="overview"]').classList.add('active');
        document.getElementById('view-overview').classList.add('active');
        viewTitleEl.textContent = VIEW_META.overview[0];
        viewSubtitleEl.textContent = VIEW_META.overview[1];

        profileEmptyStateEl.classList.remove('hidden');
        staffProfileEl.classList.add('hidden');

        app.classList.remove('hidden');
    }

    if (data.action === 'playerUpdate') {
        renderPlayer(data.player);
    }

    if (data.action === 'close') {
        app.classList.add('hidden');
    }
});
