// ============================================================
//  Masitz-AgriHub | web/js/app.js
//  NUI state machine. Denne fil tager INGEN sikkerhedsbeslutninger —
//  den viser hvad Lua/serveren svarer, og sender kun ønsker videre.
//  Rolle/adgang vist her er ALTID hvad server/access.lua returnerede
//  ved login, aldrig noget denne fil selv erklærer.
// ============================================================

(function () {
    'use strict';

    const resourceName = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'Masitz-AgriHub';

    function nuiFetch(name, data) {
        return fetch(`https://${resourceName}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).then((r) => r.json()).catch(() => ({ success: false, msg: 'Ingen forbindelse.' }));
    }

    const el = (id) => document.getElementById(id);
    const money = (n) => `${Math.floor(n || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')} kr.`;

    const state = {
        role: null,
        cart: {}, // { shopId: qty }
        shopItems: [],
        farmers: [],
        taskTypes: {},
    };

    // ───────── OPEN / CLOSE ─────────
    window.addEventListener('message', (event) => {
        const msg = event.data || {};
        if (msg.action === 'open') {
            openApp(msg.focusTab);
        } else if (msg.action === 'close') {
            closeApp();
        }
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') closeApp();
    });

    function openApp(focusTab) {
        el('app').classList.remove('hidden');
        if (state.role) {
            showDashboard();
            if (focusTab && focusTab.tab) switchTab(focusTab.tab, focusTab.farmerId);
        } else {
            showScreen('screen-login');
        }
    }

    function closeApp() {
        el('app').classList.add('hidden');
        nuiFetch('close', {});
    }

    function showScreen(id) {
        document.querySelectorAll('.screen').forEach((s) => s.classList.add('hidden'));
        el(id).classList.remove('hidden');
    }

    // ───────── LOGIN ─────────
    el('btn-login').addEventListener('click', async () => {
        el('btn-login').disabled = true;
        el('login-error').classList.add('hidden');
        const result = await nuiFetch('login', {});
        el('btn-login').disabled = false;

        if (result && result.success) {
            state.role = result.role;
            await preloadStaticData();
            showDashboard();
        } else {
            el('login-error').textContent = (result && result.reason) || 'Login mislykkedes.';
            el('login-error').classList.remove('hidden');
        }
    });

    el('btn-logout').addEventListener('click', async () => {
        await nuiFetch('logout', {});
        state.role = null;
        closeApp();
        showScreen('screen-login');
    });

    el('btn-close').addEventListener('click', closeApp);

    async function preloadStaticData() {
        state.shopItems = await nuiFetch('shopCatalog', {}) || [];
        state.farmers = await nuiFetch('farmerList', {}) || [];
        state.taskTypes = await nuiFetch('taskTypes', {}) || {};
    }

    function showDashboard() {
        showScreen('screen-dashboard');
        el('user-role').textContent = state.role === 'SUPER_ADMIN' ? 'SUPER ADMIN' : 'BRUGER';
        el('nav-admin').classList.toggle('hidden', state.role !== 'SUPER_ADMIN');
        refreshTasks();
    }

    // ───────── TAB NAVIGATION ─────────
    document.querySelectorAll('.nav-item').forEach((btn) => {
        btn.addEventListener('click', () => switchTab(btn.dataset.tab));
    });

    function switchTab(tab, farmerId) {
        document.querySelectorAll('.nav-item').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
        document.querySelectorAll('.panel').forEach((p) => p.classList.remove('active'));
        el(`panel-${tab}`).classList.add('active');

        if (tab === 'tasks') refreshTasks(farmerId);
        else if (tab === 'rentals') refreshRentals(farmerId);
        else if (tab === 'overview') refreshOverview();
        else if (tab === 'shop') refreshShop();
        else if (tab === 'contracts') refreshContracts();
        else if (tab === 'admin') refreshAdmin();
    }

    // ───────── MODAL HELPER ─────────
    function openModal(title, fieldsHtml, onSubmit) {
        const root = el('modal-root');
        root.innerHTML = `
            <div class="modal-box">
                <h3>${title}</h3>
                <div class="modal-body">${fieldsHtml}</div>
                <div class="modal-actions">
                    <button class="btn btn-ghost" id="modal-cancel">Annullér</button>
                    <button class="btn btn-primary" id="modal-confirm">Bekræft</button>
                </div>
            </div>`;
        root.classList.remove('hidden');

        el('modal-cancel').onclick = () => root.classList.add('hidden');
        el('modal-confirm').onclick = () => {
            onSubmit();
            root.classList.add('hidden');
        };
    }

    function closeModal() { el('modal-root').classList.add('hidden'); }

    // ───────── OPGAVER ─────────
    el('btn-tasks-refresh').addEventListener('click', () => refreshTasks());

    async function refreshTasks(focusFarmerId) {
        const result = await nuiFetch('tasksList', {});
        const available = (result && result.available) || [];
        const active = (result && result.active) || [];

        const availBox = el('tasks-available');
        availBox.innerHTML = '';
        const filtered = focusFarmerId ? available.filter((t) => taskFarmerId(t) === focusFarmerId) : available;

        if (filtered.length === 0) {
            availBox.innerHTML = '<div class="card-empty">Ingen ledige opgaver lige nu.</div>';
        }
        filtered.forEach((t) => {
            const typeInfo = state.taskTypes[t.type] || { label: t.type, icon: '📦' };
            const card = document.createElement('div');
            card.className = 'card';
            card.innerHTML = `
                <div class="card-title">${typeInfo.icon || ''} ${typeInfo.label}</div>
                <div class="card-row"><span>Belønning</span><span>${money(t.reward)}</span></div>
                <div class="card-actions"><button class="btn btn-primary btn-sm btn-claim">Tag opgave</button></div>`;
            card.querySelector('.btn-claim').addEventListener('click', async () => {
                const res = await nuiFetch('tasksClaim', { taskId: t.task_id });
                if (!(res && res.success)) alert((res && res.msg) || 'Kunne ikke tage opgaven.');
            });
            availBox.appendChild(card);
        });

        const activeBox = el('tasks-active');
        activeBox.innerHTML = '';
        if (active.length === 0) {
            activeBox.innerHTML = '<div class="card-empty">Du har ingen aktive opgaver.</div>';
        }
        active.forEach((t) => {
            const typeInfo = state.taskTypes[t.type] || { label: t.type, icon: '📦' };
            const card = document.createElement('div');
            card.className = 'card';
            card.innerHTML = `
                <div class="card-title">${typeInfo.icon || ''} ${typeInfo.label}</div>
                <span class="card-badge success">AKTIV</span>
                <div class="card-row"><span>Belønning</span><span>${money(t.reward)}</span></div>`;
            activeBox.appendChild(card);
        });
    }

    function taskFarmerId(task) {
        try {
            const data = JSON.parse(task.data);
            return data.meta && (data.meta.farmerId || (data.stops && data.stops[0] && data.stops[0].meta && data.stops[0].meta.farmerId));
        } catch (e) { return null; }
    }

    // ───────── UDLEJNING ─────────
    el('btn-rentals-refresh').addEventListener('click', () => refreshRentals());

    async function refreshRentals(focusFarmerId) {
        const catalog = await nuiFetch('rentalCatalog', {});
        const machines = (catalog && catalog.machines) || [];
        const rules = (catalog && catalog.rules) || { minDurationHours: 6, maxDurationHours: 336, defaultDurationHours: 72 };

        let list = machines;
        if (focusFarmerId) {
            const farmer = state.farmers.find((f) => f.id === focusFarmerId);
            if (farmer) list = machines.filter((m) => farmer.machines.includes(m.machine));
        }

        const box = el('rentals-catalog');
        box.innerHTML = '';
        if (list.length === 0) {
            box.innerHTML = '<div class="card-empty">Ingen maskiner tilgængelige lige nu.</div>';
        }
        list.forEach((m) => {
            const card = document.createElement('div');
            card.className = 'card';
            card.innerHTML = `
                <div class="card-title">🚜 ${m.label}</div>
                <div class="card-row"><span>Depositum</span><span>${money(m.deposit)}</span></div>
                <div class="card-row"><span>Leje</span><span>${money(m.rent)}</span></div>
                <div class="card-actions"><button class="btn btn-primary btn-sm btn-rent">Lej</button></div>`;
            card.querySelector('.btn-rent').addEventListener('click', () => {
                openModal(`Lej ${m.label}`, `
                    <div class="modal-field">
                        <label>Betalingsmetode</label>
                        <select class="input" id="modal-payment">
                            <option value="bank">Bank</option>
                            <option value="cash">Kontant</option>
                        </select>
                    </div>
                    <div class="modal-field">
                        <label>Varighed (timer, ${rules.minDurationHours}-${rules.maxDurationHours})</label>
                        <input type="number" class="input" id="modal-duration" value="${rules.defaultDurationHours}" min="${rules.minDurationHours}" max="${rules.maxDurationHours}">
                    </div>
                `, async () => {
                    const paymentMethod = el('modal-payment').value;
                    const durationHours = parseInt(el('modal-duration').value, 10);
                    const res = await nuiFetch('rentalNpcCreate', { machine: m.machine, paymentMethod, durationHours });
                    if (!(res && res.success)) alert((res && res.msg) || 'Kunne ikke oprette lejeaftale.');
                });
            });
            box.appendChild(card);
        });
    }

    // ───────── OVERSIGT ─────────
    async function refreshOverview() {
        const [tasks, rentals] = await Promise.all([nuiFetch('tasksList', {}), nuiFetch('rentalList', {})]);
        const activeTasks = (tasks && tasks.active) || [];
        const availableTasks = (tasks && tasks.available) || [];
        const asRenter = (rentals && rentals.asRenter) || [];
        const activeRentals = asRenter.filter((c) => c.status === 'active');

        el('overview-stats').innerHTML = `
            <div class="stat-box"><div class="stat-value">${activeTasks.length}</div><div class="stat-label">Aktive opgaver</div></div>
            <div class="stat-box"><div class="stat-value">${availableTasks.length}</div><div class="stat-label">Ledige opgaver</div></div>
            <div class="stat-box"><div class="stat-value">${activeRentals.length}</div><div class="stat-label">Aktive lejemål</div></div>`;

        const table = el('overview-rentals');
        if (asRenter.length === 0) {
            table.innerHTML = '<tr><td class="card-empty">Ingen lejemål endnu.</td></tr>';
            return;
        }
        table.innerHTML = `
            <tr><th>Kontrakt</th><th>Maskine</th><th>Plade</th><th>Status</th><th>Udløber</th></tr>
            ${asRenter.map((c) => `
                <tr>
                    <td>${c.contract_id}</td>
                    <td>${c.vehicle_model}</td>
                    <td>${c.vehicle_plate || '—'}</td>
                    <td>${statusBadge(c.status)}</td>
                    <td>${c.expires_at || '—'}</td>
                </tr>`).join('')}`;
    }

    function statusBadge(status) {
        const map = { active: 'success', pending: 'warning', expired: 'danger', cancelled: 'danger', completed: '' };
        return `<span class="card-badge ${map[status] || ''}">${status.toUpperCase()}</span>`;
    }

    // ───────── INDKØB ─────────
    async function refreshShop() {
        state.cart = {};
        updateCartSummary();
        const box = el('shop-items');
        box.innerHTML = '';
        state.shopItems.forEach((item) => {
            const card = document.createElement('div');
            card.className = 'card';
            card.innerHTML = `
                <div class="card-title">${item.label}</div>
                <div class="card-row"><span>Pris/stk</span><span>${money(item.price)}</span></div>
                <div class="qty-stepper">
                    <button class="qty-minus">−</button>
                    <span class="qty-val">0</span>
                    <button class="qty-plus">+</button>
                </div>`;
            const qtyEl = card.querySelector('.qty-val');
            card.querySelector('.qty-minus').addEventListener('click', () => {
                const qty = Math.max(0, (state.cart[item.id] || 0) - 1);
                setCartQty(item, qty, qtyEl);
            });
            card.querySelector('.qty-plus').addEventListener('click', () => {
                const qty = Math.min(item.maxCart, (state.cart[item.id] || 0) + 1);
                setCartQty(item, qty, qtyEl);
            });
            box.appendChild(card);
        });
    }

    function setCartQty(item, qty, qtyEl) {
        if (qty <= 0) delete state.cart[item.id];
        else state.cart[item.id] = qty;
        qtyEl.textContent = qty;
        updateCartSummary();
    }

    function updateCartSummary() {
        let total = 0;
        for (const id in state.cart) {
            const item = state.shopItems.find((i) => i.id === id);
            if (item) total += item.price * state.cart[id];
        }
        el('cart-summary').textContent = `Kurv: ${money(total)}`;
    }

    el('btn-shop-purchase').addEventListener('click', async () => {
        const cart = Object.keys(state.cart).map((id) => ({ id, qty: state.cart[id] }));
        if (cart.length === 0) { alert('Din kurv er tom.'); return; }
        const paymentMethod = el('shop-payment').value;
        const res = await nuiFetch('shopPurchase', { cart, paymentMethod });
        if (res && res.success) {
            alert(`Køb gennemført — ${money(res.total)} betalt.`);
            refreshShop();
        } else {
            alert((res && res.msg) || 'Købet mislykkedes.');
        }
    });

    // ───────── KONTRAKTER ─────────
    el('btn-contracts-refresh').addEventListener('click', () => refreshContracts());

    async function refreshContracts() {
        const rentals = await nuiFetch('rentalList', {});
        const asRenter = (rentals && rentals.asRenter) || [];
        const asOwner = (rentals && rentals.asOwner) || [];

        const incoming = asRenter.filter((c) => c.status === 'pending');
        const activeAsRenter = asRenter.filter((c) => c.status === 'active');

        // Indkommende tilbud (skal godkendes/signeres af mig som lejer)
        const incomingBox = el('contracts-incoming');
        incomingBox.innerHTML = incoming.length === 0 ? '<div class="card-empty">Ingen indkommende tilbud.</div>' : '';
        incoming.forEach((c) => {
            const card = document.createElement('div');
            card.className = 'card';
            const needsApproval = c.renter_approved === 0;
            card.innerHTML = `
                <div class="card-title">📄 ${c.contract_id}</div>
                <div class="card-sub">${c.vehicle_model} — ${money(c.deposit)} depositum + ${money(c.rent)} leje</div>
                <div class="card-actions"></div>`;
            const actions = card.querySelector('.card-actions');
            if (needsApproval) {
                const acceptBtn = document.createElement('button');
                acceptBtn.className = 'btn btn-primary btn-sm';
                acceptBtn.textContent = 'Godkend';
                acceptBtn.onclick = async () => { await nuiFetch('rentalRespondSublet', { contractId: c.contract_id, accept: true }); refreshContracts(); };
                const declineBtn = document.createElement('button');
                declineBtn.className = 'btn btn-danger btn-sm';
                declineBtn.textContent = 'Afvis';
                declineBtn.onclick = async () => { await nuiFetch('rentalRespondSublet', { contractId: c.contract_id, accept: false }); refreshContracts(); };
                actions.append(acceptBtn, declineBtn);
            } else {
                const signBtn = document.createElement('button');
                signBtn.className = 'btn btn-primary btn-sm';
                signBtn.textContent = 'Signér';
                signBtn.onclick = async () => {
                    const res = await nuiFetch('rentalSignContract', { contractId: c.contract_id });
                    if (!(res && res.success)) alert((res && res.msg) || 'Kunne ikke signere.');
                    refreshContracts();
                };
                actions.appendChild(signBtn);
            }
            incomingBox.appendChild(card);
        });

        // Mine kontrakter som lejer (kan tilbyde videre / se status)
        const renterBox = el('contracts-renter');
        renterBox.innerHTML = activeAsRenter.length === 0 ? '<div class="card-empty">Ingen aktive lejemål.</div>' : '';
        activeAsRenter.forEach((c) => {
            const card = document.createElement('div');
            card.className = 'card';
            card.innerHTML = `
                <div class="card-title">🚜 ${c.vehicle_model}</div>
                <div class="card-sub">${c.contract_id} — ${c.vehicle_plate || '—'}</div>
                ${statusBadge(c.status)}
                <div class="card-actions"></div>`;
            const actions = card.querySelector('.card-actions');

            const subletBtn = document.createElement('button');
            subletBtn.className = 'btn btn-secondary btn-sm';
            subletBtn.textContent = 'Fremlej';
            subletBtn.onclick = () => openSubletModal(c.contract_id);
            actions.appendChild(subletBtn);

            const extendBtn = document.createElement('button');
            extendBtn.className = 'btn btn-secondary btn-sm';
            extendBtn.textContent = 'Forlæng';
            extendBtn.onclick = () => openExtendModal(c.contract_id);
            actions.appendChild(extendBtn);

            renterBox.appendChild(card);
        });

        // Mine kontrakter som udlejer (pending fremlejetilbud jeg selv har sendt)
        const ownerBox = el('contracts-owner');
        const pendingOwner = asOwner.filter((c) => c.status === 'pending');
        ownerBox.innerHTML = pendingOwner.length === 0 ? '<div class="card-empty">Ingen udestående fremlejetilbud.</div>' : '';
        pendingOwner.forEach((c) => {
            const card = document.createElement('div');
            card.className = 'card';
            card.innerHTML = `
                <div class="card-title">📄 ${c.contract_id}</div>
                <div class="card-sub">${c.vehicle_model} — afventer modpart</div>
                <div class="card-actions"></div>`;
            const cancelBtn = document.createElement('button');
            cancelBtn.className = 'btn btn-danger btn-sm';
            cancelBtn.textContent = 'Annullér';
            cancelBtn.onclick = async () => { await nuiFetch('rentalCancelSublet', { contractId: c.contract_id }); refreshContracts(); };
            card.querySelector('.card-actions').appendChild(cancelBtn);
            ownerBox.appendChild(card);
        });
    }

    function openSubletModal(sourceContractId) {
        openModal('Fremlej kontrakt', `
            <div class="modal-field">
                <label>Søg spiller (navn eller server-ID)</label>
                <input type="text" class="input" id="modal-lookup">
                <div id="modal-lookup-results" style="margin-top:8px;"></div>
            </div>
        `, () => {});

        let selected = null;
        const input = el('modal-lookup');
        const results = el('modal-lookup-results');
        const confirmBtn = el('modal-confirm');
        confirmBtn.disabled = true;

        input.addEventListener('input', async () => {
            const query = input.value.trim();
            if (query.length < 2) { results.innerHTML = ''; return; }
            const players = await nuiFetch('rentalLookupPlayer', { query });
            results.innerHTML = '';
            (players || []).forEach((p) => {
                const row = document.createElement('div');
                row.className = 'card';
                row.style.padding = '8px 10px';
                row.style.cursor = 'pointer';
                row.textContent = `${p.name} (ID ${p.serverId})`;
                row.addEventListener('click', () => {
                    selected = p;
                    confirmBtn.disabled = false;
                    Array.from(results.children).forEach((c) => (c.style.borderColor = 'var(--border)'));
                    row.style.borderColor = 'var(--accent)';
                });
                results.appendChild(row);
            });
        });

        confirmBtn.onclick = async () => {
            if (!selected) return;
            closeModal();
            const res = await nuiFetch('rentalOfferSublet', { sourceContractId, targetServerId: selected.serverId, targetName: selected.name });
            if (!(res && res.success)) alert((res && res.msg) || 'Kunne ikke sende tilbud.');
            refreshContracts();
        };
    }

    function openExtendModal(contractId) {
        openModal('Forlæng lejeaftale', `
            <div class="modal-field">
                <label>Ekstra timer</label>
                <input type="number" class="input" id="modal-extra-hours" value="24" min="1">
            </div>
        `, async () => {
            const extraHours = parseInt(el('modal-extra-hours').value, 10);
            const res = await nuiFetch('rentalExtend', { contractId, extraHours });
            if (res && res.success) alert(`Forlænget med ${res.extraHours} timer for ${money(res.cost)}.`);
            else alert((res && res.msg) || 'Kunne ikke forlænge.');
            refreshContracts();
        });
    }

    // ───────── ADMIN ─────────
    el('admin-search-btn').addEventListener('click', async () => {
        const query = el('admin-search-input').value.trim();
        const results = await nuiFetch('adminSearchPlayer', { query });
        const table = el('admin-search-results');
        if (!results || results.length === 0) {
            table.innerHTML = '<tr><td class="card-empty">Ingen resultater.</td></tr>';
            return;
        }
        table.innerHTML = `
            <tr><th>ID</th><th>Navn</th><th>Discord</th><th></th></tr>
            ${results.map((p) => `
                <tr>
                    <td>${p.serverId}</td><td>${p.name}</td><td>${p.discordId || '—'}</td>
                    <td><button class="btn btn-primary btn-sm" data-grant="${p.serverId}">Giv adgang</button></td>
                </tr>`).join('')}`;
        table.querySelectorAll('[data-grant]').forEach((btn) => {
            btn.addEventListener('click', async () => {
                const res = await nuiFetch('adminGrantAccess', { targetId: btn.dataset.grant });
                if (res && res.success) { alert(`Adgang givet til ${res.name}.`); refreshAdmin(); }
                else alert((res && res.msg) || 'Kunne ikke give adgang.');
            });
        });
    });

    async function refreshAdmin() {
        const status = await nuiFetch('adminSystemStatus', {});
        el('admin-status').innerHTML = `
            <div class="stat-box"><div class="stat-value">${status.activeUsers ?? 0}</div><div class="stat-label">Brugere med adgang</div></div>
            <div class="stat-box"><div class="stat-value">${status.activeTasks ?? 0}</div><div class="stat-label">Aktive opgaver</div></div>
            <div class="stat-box"><div class="stat-value">${status.activeContracts ?? 0}</div><div class="stat-label">Aktive kontrakter</div></div>
            <div class="stat-box"><div class="stat-value">${status.onlinePlayers ?? 0}</div><div class="stat-label">Spillere online</div></div>`;

        const users = await nuiFetch('adminListUsers', {});
        const userTable = el('admin-user-list');
        userTable.innerHTML = `
            <tr><th>Bruger</th><th>Discord</th><th>Status</th><th>Givet af</th><th></th></tr>
            ${(users || []).map((u) => `
                <tr>
                    <td>${u.player_name}</td><td>${u.discord_id || '—'}</td>
                    <td>${statusBadge(u.status === 'active' ? 'active' : 'expired')}</td>
                    <td>${u.granted_by}</td>
                    <td>${u.status === 'active' ? `<button class="btn btn-danger btn-sm" data-revoke="${u.identifier}">Fjern</button>` : ''}</td>
                </tr>`).join('')}`;
        userTable.querySelectorAll('[data-revoke]').forEach((btn) => {
            btn.addEventListener('click', async () => {
                const res = await nuiFetch('adminRevokeAccess', { identifier: btn.dataset.revoke });
                if (res && res.success) refreshAdmin();
                else alert((res && res.msg) || 'Kunne ikke fjerne adgang.');
            });
        });

        const logs = await nuiFetch('adminGetLogs', { filter: '' });
        const logTable = el('admin-logs');
        logTable.innerHTML = `
            <tr><th>Handling</th><th>Spiller</th><th>Tidspunkt</th></tr>
            ${(logs || []).slice(0, 50).map((l) => `
                <tr><td>${l.action}</td><td>${l.player_name}</td><td>${l.created_at}</td></tr>`).join('')}`;
    }

    // Klar til at modtage NUI-beskeder
    nuiFetch('ready', {});
})();
