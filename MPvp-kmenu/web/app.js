// ============================================================
//  MPvp-kmenu | web/app.js
//  NUI state machine for the MPvp Weapon Hub. No security decisions
//  are made here — every give-request is re-validated server-side;
//  this file only displays what the server responds with.
// ============================================================

(function () {
    'use strict';

    const resourceName = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'MPvp-kmenu';

    function nuiFetch(name, data) {
        return fetch(`https://${resourceName}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    const el = (id) => document.getElementById(id);

    // ───────── ICONS (inline SVG, no external assets/fonts) ─────────
    const ICONS = {
        grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
        search: '<circle cx="10.5" cy="10.5" r="6.5"/><line x1="20" y1="20" x2="15.4" y2="15.4"/>',
        close: '<line x1="5" y1="5" x2="19" y2="19"/><line x1="19" y1="5" x2="5" y2="19"/>',
        back: '<polyline points="14 6 8 12 14 18"/>',
        pistol: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2.4" fill="currentColor" stroke="none"/>',
        smg: '<line x1="7" y1="5" x2="7" y2="19"/><line x1="12" y1="5" x2="12" y2="19"/><line x1="17" y1="5" x2="17" y2="19"/>',
        rifle: '<polyline points="6 15 12 7 18 15"/><line x1="12" y1="7" x2="12" y2="19"/>',
        shotgun: '<line x1="12" y1="20" x2="12" y2="12"/><line x1="12" y1="12" x2="5" y2="4"/><line x1="12" y1="12" x2="12" y2="3"/><line x1="12" y1="12" x2="19" y2="4"/>',
        attachment: '<rect x="4" y="4" width="16" height="16" rx="2"/><line x1="12" y1="8" x2="12" y2="16"/><line x1="8" y1="12" x2="16" y2="12"/>',
        gear: '<polygon points="12 3 19 7.5 19 16.5 12 21 5 16.5 5 7.5"/><circle cx="12" cy="12" r="3"/>',
        box: '<rect x="4" y="7" width="16" height="13" rx="1.5"/><polyline points="4 7 12 3 20 7"/><line x1="12" y1="12" x2="12" y2="20"/>',
        check: '<polyline points="5 13 10 18 19 7"/>',
        warning: '<polygon points="12 3 22 20 2 20"/><line x1="12" y1="9" x2="12" y2="14"/><circle cx="12" cy="17" r="0.6" fill="currentColor" stroke="none"/>',
    };

    function iconSvg(name, strokeWidth) {
        const body = ICONS[name] || ICONS.box;
        return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${strokeWidth || 1.6}" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
    }

    function renderIcons(root) {
        (root || document).querySelectorAll('[data-icon]').forEach((node) => {
            node.innerHTML = iconSvg(node.dataset.icon);
        });
    }

    // ───────── STATE ─────────
    const state = {
        categories: [],
        weapons: {},
        allEntries: [], // flattened, normalized: { key, type, label, category, categoryLabel, image, maxAmount }
        imagePath: '',
        maxItemAmount: 20,
        view: 'dashboard',
        activeCategory: null,
        activeEntry: null,
        quantity: 1,
        returnTo: { view: 'dashboard' }, // hvor "Tilbage" fra detail-viewet skal gå hen
    };

    // ───────── TOAST ─────────
    function toast(title, message, type) {
        type = type || 'info';
        const stack = el('toast-stack');
        if (!stack) return;

        const iconName = type === 'success' ? 'check' : type === 'error' ? 'close' : 'warning';
        const node = document.createElement('div');
        node.className = `toast toast-${type}`;
        node.innerHTML = `
            <span class="toast-icon">${iconSvg(iconName, 2)}</span>
            <div class="toast-body">
                <div class="toast-title"></div>
                <div class="toast-msg"></div>
            </div>`;
        node.querySelector('.toast-title').textContent = title;
        node.querySelector('.toast-msg').textContent = message;
        stack.appendChild(node);

        requestAnimationFrame(() => node.classList.add('toast-in'));
        setTimeout(() => {
            node.classList.remove('toast-in');
            node.classList.add('toast-out');
            setTimeout(() => node.remove(), 250);
        }, 4000);
    }

    // ───────── OPEN / CLOSE ─────────
    window.addEventListener('message', (event) => {
        const msg = event.data || {};
        if (msg.action === 'open') {
            openApp(msg.payload);
        } else if (msg.action === 'close') {
            closeApp();
        } else if (msg.action === 'result') {
            handleResult(msg.result);
        }
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') closeApp();
    });

    function openApp(payload) {
        if (payload) loadPayload(payload);
        el('app').classList.remove('hidden');
        showDashboard();
    }

    function closeApp() {
        el('app').classList.add('hidden');
        nuiFetch('close', {});
    }

    el('btn-close').addEventListener('click', closeApp);

    function loadPayload(payload) {
        state.categories = payload.categories || [];
        state.weapons = payload.weapons || {};
        state.imagePath = payload.imagePath || '';
        state.maxItemAmount = payload.maxItemAmount || 20;

        const categoryLabel = {};
        state.categories.forEach((c) => { categoryLabel[c.key] = c.label; });

        const flattened = [];
        Object.keys(state.weapons).forEach((categoryKey) => {
            (state.weapons[categoryKey] || []).forEach((entry) => {
                const isWeapon = !!entry.weapon;
                const key = isWeapon ? entry.weapon : entry.item;
                flattened.push({
                    key,
                    type: isWeapon ? 'weapon' : 'item',
                    label: entry.label,
                    category: categoryKey,
                    categoryLabel: categoryLabel[categoryKey] || categoryKey,
                    // Brug et eksplicit config-billede hvis der er sat ét
                    // (fx ox_inventory's rigtige attachment/ammo-billeder),
                    // ellers gæt ud fra item-/våben-navnet som normalt.
                    image: entry.image || `${key}.png`,
                    maxAmount: entry.maxAmount || state.maxItemAmount,
                });
            });
        });
        state.allEntries = flattened;

        buildSidebarNav();
    }

    // ───────── SIDEBAR NAV ─────────
    function buildSidebarNav() {
        const nav = el('nav-list');
        // Ryd alt undtagen "Oversigt", som allerede ligger statisk i HTML'en.
        Array.from(nav.querySelectorAll('.nav-item[data-category]:not([data-category=""])')).forEach((n) => n.remove());
        Array.from(nav.querySelectorAll('.nav-separator')).forEach((n) => n.remove());

        const sep = document.createElement('div');
        sep.className = 'nav-separator';
        nav.appendChild(sep);

        state.categories.forEach((cat) => {
            const btn = document.createElement('button');
            btn.className = 'nav-item';
            btn.dataset.view = 'category';
            btn.dataset.category = cat.key;
            btn.innerHTML = `<span class="nav-icon" data-icon="${cat.icon}"></span><span></span>`;
            btn.querySelector('span:last-child').textContent = cat.label;
            btn.addEventListener('click', () => showCategory(cat.key));
            nav.appendChild(btn);
        });

        nav.querySelector('[data-view="dashboard"]').onclick = () => showDashboard();
        renderIcons(nav);
    }

    function setActiveNav(categoryKey) {
        document.querySelectorAll('.nav-item').forEach((n) => {
            n.classList.toggle('active', (n.dataset.category || '') === (categoryKey || ''));
        });
    }

    // ───────── VIEW HELPERS ─────────
    function setTopbar(heading, sub) {
        el('topbar-heading').textContent = heading;
        el('topbar-sub').textContent = sub;
    }

    function renderView(html) {
        const area = el('view-area');
        area.innerHTML = `<div class="view active">${html}</div>`;
        renderIcons(area);
        return area.querySelector('.view');
    }

    function categoryCount(categoryKey) {
        return (state.weapons[categoryKey] || []).length;
    }

    // ───────── DASHBOARD ─────────
    function showDashboard() {
        state.view = 'dashboard';
        state.activeCategory = null;
        state.returnTo = { view: 'dashboard' };
        setActiveNav(null);
        document.querySelector('.nav-item[data-view="dashboard"]').classList.add('active');
        setTopbar('Weapon Hub', 'Vælg en kategori for at komme i gang');

        const cardsHtml = state.categories.map((cat) => `
            <div class="category-card" data-category="${cat.key}">
                <div class="category-icon" data-icon="${cat.icon}"></div>
                <div class="category-name"></div>
                <div class="category-count">${categoryCount(cat.key)} TILGÆNGELIGE</div>
            </div>`).join('');

        const view = renderView(`<div class="category-grid">${cardsHtml}</div>`);
        view.querySelectorAll('.category-card').forEach((card, i) => {
            card.querySelector('.category-name').textContent = state.categories[i].label;
            card.addEventListener('click', () => showCategory(state.categories[i].key));
        });
    }

    // ───────── KATEGORI (weapon/item liste) ─────────
    function showCategory(categoryKey) {
        state.view = 'category';
        state.activeCategory = categoryKey;
        state.returnTo = { view: 'category', category: categoryKey };
        setActiveNav(categoryKey);

        const cat = state.categories.find((c) => c.key === categoryKey);
        const entries = state.allEntries.filter((e) => e.category === categoryKey);
        setTopbar(cat ? cat.label : categoryKey, `${entries.length} tilgængelige`);

        renderView(buildCardGrid(entries));
        bindCardClicks();
    }

    // ───────── SØGNING ─────────
    // Instant — datasættet er lille (håndfuld dusin items), så filtrering
    // sker synkront pr. tastetryk uden nogen kunstig debounce/delay.
    el('search-input').addEventListener('input', (e) => {
        showSearch(e.target.value.trim());
    });

    function showSearch(query) {
        if (query.length === 0) {
            if (state.view === 'search') showDashboard();
            return;
        }

        state.view = 'search';
        state.returnTo = { view: 'search', query };
        setActiveNav(null);
        const q = query.toLowerCase();
        const results = state.allEntries.filter((e) =>
            e.label.toLowerCase().includes(q) ||
            e.key.toLowerCase().includes(q) ||
            e.categoryLabel.toLowerCase().includes(q)
        );

        setTopbar('Søgeresultater', `${results.length} resultater for "${query}"`);
        renderView(buildCardGrid(results, true));
        bindCardClicks();
    }

    function buildCardGrid(entries, showCategoryTag) {
        if (entries.length === 0) {
            return '<div class="card-empty">Ingen items er tilgængelige i denne kategori.</div>';
        }
        return `<div class="card-grid">${entries.map((e) => `
            <div class="item-card" data-key="${e.key}" data-category="${e.category}">
                <div class="item-thumb">
                    <img src="${state.imagePath}${e.image}" alt="" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                    <div class="fallback-icon" data-icon="box" style="display:none;"></div>
                </div>
                <div class="item-body">
                    <div class="item-label">${e.label}${showCategoryTag ? ` <span style="color:var(--text-muted);font-weight:400;">· ${e.categoryLabel}</span>` : ''}</div>
                    <div class="item-code">${e.key}</div>
                </div>
            </div>`).join('')}</div>`;
    }

    function bindCardClicks() {
        document.querySelectorAll('.item-card').forEach((card) => {
            card.addEventListener('click', () => {
                const entry = state.allEntries.find((e) => e.key === card.dataset.key && e.category === card.dataset.category);
                if (entry) showDetail(entry);
            });
        });
        renderIcons(el('view-area'));
    }

    // ───────── DETAIL / GIV ─────────
    function showDetail(entry) {
        state.view = 'detail';
        state.activeEntry = entry;
        state.quantity = 1;
        setTopbar(entry.categoryLabel, 'Detaljer');

        const isItem = entry.type === 'item';
        const view = renderView(`
            <div class="detail-wrap">
                <button class="detail-back" id="detail-back"><span data-icon="back"></span> Tilbage</button>
                <div class="detail-thumb">
                    <img src="${state.imagePath}${entry.image}" alt="" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                    <div class="fallback-icon" data-icon="box" style="display:none;"></div>
                </div>
                <div class="detail-category">${entry.categoryLabel}</div>
                <div class="detail-label">${entry.label}</div>
                <div class="detail-code">${entry.key}</div>
                ${isItem ? `
                    <div class="quantity-row">
                        <button class="qty-btn" id="qty-minus">−</button>
                        <span class="qty-value" id="qty-value">1</span>
                        <button class="qty-btn" id="qty-plus">+</button>
                    </div>` : ''}
                <button class="btn-give" id="btn-give">${isItem ? 'Giv item' : 'Giv våben'}</button>
            </div>`);

        view.querySelector('#detail-back').addEventListener('click', () => {
            const back = state.returnTo || { view: 'dashboard' };
            if (back.view === 'category') showCategory(back.category);
            else if (back.view === 'search') showSearch(back.query);
            else showDashboard();
        });

        if (isItem) {
            const qtyValue = view.querySelector('#qty-value');
            view.querySelector('#qty-minus').addEventListener('click', () => {
                state.quantity = Math.max(1, state.quantity - 1);
                qtyValue.textContent = state.quantity;
            });
            view.querySelector('#qty-plus').addEventListener('click', () => {
                state.quantity = Math.min(entry.maxAmount, state.quantity + 1);
                qtyValue.textContent = state.quantity;
            });
        }

        view.querySelector('#btn-give').addEventListener('click', (e) => {
            const btn = e.currentTarget;
            btn.disabled = true;
            if (isItem) {
                nuiFetch('giveItem', { key: entry.key, amount: state.quantity });
            } else {
                nuiFetch('giveWeapon', { key: entry.key });
            }
            setTimeout(() => { btn.disabled = false; }, 400);
        });
    }

    // ───────── SERVER-RESULTAT (toast) ─────────
    function handleResult(result) {
        if (!result) return;
        toast(result.title || (result.success ? 'Succes' : 'Fejl'), result.message || '', result.success ? 'success' : 'error');
    }

    renderIcons(document);
})();
