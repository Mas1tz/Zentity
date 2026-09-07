// ================================================================
//  mm-adminpakke V2 — DELTE UI-KOMPONENTER
//  Toast, billed-opløsning, kurv, "tilføj item"-modal, pagination.
// ================================================================
'use strict';

// Delt state sat af app.js ved 'open' - læses af alle moduler.
window.AdminState = {
    maxItemAmount: 5000,
    itemsPerPage: 40,
    imageBasePath: '',
    categories: [],
    uncategorized: { id: 'ukategoriseret', label: 'Ukategoriseret', icon: '❔' },
    weaponsCategory: { id: 'vaaben', label: 'Våben', icon: '🔫' },
    blacklist: new Set(),
    debug: false,
};

function debugLog(...args) {
    if (window.AdminState.debug) console.log('[mm-adminpakke]', ...args);
}

// ── TOAST ────────────────────────────────────────────────────────
const Toast = (() => {
    function show(msg, type = 'info') {
        const c = document.getElementById('toastContainer');
        const t = document.createElement('div');
        t.className = `toast ${type}`;
        const icons = { success: '✓', error: '✗', warning: '⚠', info: 'ℹ' };
        const colors = { success: 'var(--success)', error: 'var(--danger)', warning: 'var(--warn)', info: 'var(--accent)' };
        t.innerHTML = `<span class="toast-icon" style="color:${colors[type] || colors.info}">${icons[type] || icons.info}</span><span>${msg}</span>`;
        c.appendChild(t);
        setTimeout(() => { t.classList.add('removing'); setTimeout(() => t.remove(), 200); }, 3200);
    }
    return { show };
})();

// ── BILLED-OPLØSNING ─────────────────────────────────────────────
// Én korrekt sti (Config.ImageBasePath + item.image, eller den manuelle
// override/navn-fallback som serveren allerede har udregnet) - ingen
// gætte-kæde af flere mulige mapper. Fejler den, vises en neutral
// placeholder og debug-info logges KUN hvis Config.Debug = true.
const ImageResolver = (() => {
    const missingItems = new Set();
    const cache = new Map();

    const PLACEHOLDER_SVG = `data:image/svg+xml,${encodeURIComponent(
        `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
            <rect width="64" height="64" rx="8" fill="#333333"/>
            <text x="32" y="30" text-anchor="middle" font-size="20">📦</text>
            <text x="32" y="46" text-anchor="middle" fill="#707070" font-size="8" font-family="system-ui" font-weight="700">MANGLER</text>
        </svg>`
    )}`;

    function buildUrl(filename) {
        if (!filename) return null;
        if (filename.startsWith('nui://') || filename.startsWith('http')) return filename;
        const base = (window.AdminState.imageBasePath || '').replace(/\/+$/, '');
        return `${base}/${filename.replace(/^\/+/, '')}`;
    }

    function urlFor(item) {
        return buildUrl(item.image) || PLACEHOLDER_SVG;
    }

    function applyTo(imgEl, item, onResult) {
        const url = urlFor(item);
        if (url === PLACEHOLDER_SVG) {
            imgEl.src = PLACEHOLDER_SVG;
            markMissing(item.name);
            if (onResult) onResult(false);
            return;
        }

        if (cache.has(url)) {
            const ok = cache.get(url);
            imgEl.src = ok ? url : PLACEHOLDER_SVG;
            imgEl.classList.add('loaded');
            if (!ok) markMissing(item.name);
            if (onResult) onResult(ok);
            return;
        }

        const tester = new Image();
        tester.onload = () => {
            cache.set(url, true);
            imgEl.src = url;
            imgEl.classList.add('loaded');
            if (onResult) onResult(true);
        };
        tester.onerror = () => {
            cache.set(url, false);
            imgEl.src = PLACEHOLDER_SVG;
            imgEl.classList.add('loaded');
            markMissing(item.name);
            if (window.AdminState.debug) {
                console.warn(`[mm-adminpakke] Billede ikke fundet for "${item.name}": ${url}`);
            }
            if (onResult) onResult(false);
        };
        tester.src = url;
    }

    function markMissing(name) {
        if (!missingItems.has(name)) {
            missingItems.add(name);
            document.dispatchEvent(new CustomEvent('missingImageAdded', { detail: { name } }));
        }
    }

    function isMissing(name) { return missingItems.has(name); }
    function getMissingSet() { return missingItems; }
    function getUrlForDisplay(item) { return urlFor(item); }

    return { applyTo, isMissing, getMissingSet, urlFor: getUrlForDisplay, PLACEHOLDER_SVG };
})();
window.ImageResolver = ImageResolver;

// ── NUI FETCH ────────────────────────────────────────────────────
function nuiFetch(action, data = {}) {
    const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'mm-adminpakke';
    return fetch(`https://${resource}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
    }).then(r => r.json()).catch(() => ({}));
}
window.nuiFetch = nuiFetch;

// ── KURV ─────────────────────────────────────────────────────────
const Basket = (() => {
    const items = new Map();
    const MAX_ITEMS = 50;

    let listEl, countEl, sendBtn;

    function init() {
        listEl = document.getElementById('basketList');
        countEl = document.getElementById('basketCount');
        sendBtn = document.getElementById('sendBtn');
        document.getElementById('clearBasketBtn').addEventListener('click', clear);
    }

    function maxAmount() { return window.AdminState.maxItemAmount; }

    function add(item, amount) {
        amount = Math.max(1, Math.min(maxAmount(), parseInt(amount) || 1));

        if (!items.has(item.name)) {
            if (items.size >= MAX_ITEMS) {
                Toast.show(`Kurven er fuld (max ${MAX_ITEMS} varetyper)`, 'warning');
                return false;
            }
            items.set(item.name, { name: item.name, label: item.label || item.name, image: item.image || '', amount });
        } else {
            const entry = items.get(item.name);
            entry.amount = Math.min(maxAmount(), entry.amount + amount);
        }

        render();
        fireChange();
        return true;
    }

    function remove(name) {
        items.delete(name);
        render();
        updateCardState(name, false);
        fireChange();
    }

    function setAmount(name, amount) {
        amount = parseInt(amount);
        if (isNaN(amount) || amount < 1) { remove(name); return; }
        amount = Math.min(maxAmount(), amount);
        if (items.has(name)) items.get(name).amount = amount;
        updateCount();
        fireChange();
    }

    function clear() {
        const names = [...items.keys()];
        items.clear();
        render();
        names.forEach(n => updateCardState(n, false));
        fireChange();
    }

    function render() {
        updateCount();

        if (items.size === 0) {
            listEl.innerHTML = '<div class="empty-state">Kurven er tom</div>';
            return;
        }

        listEl.innerHTML = '';
        items.forEach(entry => {
            const row = document.createElement('div');
            row.className = 'basket-item';
            row.dataset.name = entry.name;

            const img = document.createElement('img');
            img.className = 'basket-item-img';
            img.alt = entry.label;
            img.src = ImageResolver.urlFor(entry);

            row.appendChild(img);
            row.insertAdjacentHTML('beforeend', `
                <div class="basket-item-info">
                    <div class="basket-item-name">${entry.label}</div>
                    <div class="basket-item-sub">${entry.name}</div>
                </div>
                <div class="basket-item-controls">
                    <input type="number" class="basket-amount-input" value="${entry.amount}" min="1" max="${maxAmount()}" data-name="${entry.name}"/>
                    <button class="basket-remove-btn" data-name="${entry.name}" title="Fjern">
                        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                    </button>
                </div>`);

            listEl.appendChild(row);
        });

        listEl.querySelectorAll('.basket-remove-btn').forEach(btn => {
            btn.addEventListener('click', () => remove(btn.dataset.name));
        });
        listEl.querySelectorAll('.basket-amount-input').forEach(input => {
            input.addEventListener('change', () => setAmount(input.dataset.name, input.value));
            input.addEventListener('blur', () => setAmount(input.dataset.name, input.value));
        });
    }

    function updateCount() {
        countEl.textContent = items.size;
        sendBtn.disabled = items.size === 0 || !window.AdminSelectedPlayer;
    }

    function updateCardState(name, inBasket) {
        const card = document.querySelector(`.item-card[data-name="${CSS.escape(name)}"]`);
        if (card) card.classList.toggle('in-basket', inBasket);
    }

    function fireChange() {
        document.dispatchEvent(new CustomEvent('basketChanged'));
    }

    function getPayload() {
        return [...items.values()].map(e => ({ name: e.name, amount: e.amount }));
    }

    function has(name) { return items.has(name); }
    function size() { return items.size; }

    return { init, add, remove, clear, getPayload, has, size, updateCount };
})();
window.Basket = Basket;

// ── "TILFØJ ITEM" MODAL ──────────────────────────────────────────
const AddModal = (() => {
    let currentItem = null;

    function init() {
        bindAmountControls();
        document.getElementById('modalClose').addEventListener('click', close);
        document.getElementById('modalCancel').addEventListener('click', close);
        document.getElementById('addModal').addEventListener('click', (e) => {
            if (e.target === document.getElementById('addModal')) close();
        });
    }

    function open(item) {
        currentItem = item;
        const input = document.getElementById('amountInput');
        input.max = window.AdminState.maxItemAmount;

        document.getElementById('modalName').textContent = item.label || item.name;
        document.getElementById('modalLabel').textContent = item.name;
        document.getElementById('modalCat').textContent = Items.getCategoryLabel(item.category);

        const img = document.getElementById('modalImg');
        img.classList.remove('loaded');
        ImageResolver.applyTo(img, item);

        input.value = 1;
        document.getElementById('addModal').classList.remove('hidden');
        setTimeout(() => input.select(), 40);
    }

    function close() {
        document.getElementById('addModal').classList.add('hidden');
        currentItem = null;
    }

    function bindAmountControls() {
        const maxAmount = () => window.AdminState.maxItemAmount;

        document.querySelectorAll('.amount-btn').forEach(btn => {
            let holdTimer, holdInterval;
            const trigger = () => {
                const input = document.getElementById('amountInput');
                const by = parseInt(btn.dataset.by) || 1;
                let val = parseInt(input.value) || 1;
                val = btn.dataset.action === 'increase' ? val + by : val - by;
                input.value = Math.max(1, Math.min(maxAmount(), val));
            };
            btn.addEventListener('click', trigger);
            btn.addEventListener('mousedown', () => { holdTimer = setTimeout(() => { holdInterval = setInterval(trigger, 70); }, 380); });
            ['mouseup', 'mouseleave'].forEach(ev => btn.addEventListener(ev, () => { clearTimeout(holdTimer); clearInterval(holdInterval); }));
        });

        document.querySelectorAll('.preset-btn:not(.max-btn)').forEach(btn => {
            btn.addEventListener('click', () => {
                document.getElementById('amountInput').value = Math.min(maxAmount(), parseInt(btn.dataset.val));
            });
        });
        document.getElementById('maxBtn').addEventListener('click', () => {
            document.getElementById('amountInput').value = maxAmount();
        });

        document.getElementById('modalAdd').addEventListener('click', () => {
            if (!currentItem) return;
            const item = currentItem;
            const amount = Math.max(1, Math.min(maxAmount(), parseInt(document.getElementById('amountInput').value) || 1));
            if (Basket.add(item, amount)) {
                Items.trackRecent(item.name);
                const card = document.querySelector(`.item-card[data-name="${CSS.escape(item.name)}"]`);
                if (card) card.classList.add('in-basket');
                close();
                Toast.show(`${item.label || item.name} × ${amount.toLocaleString('da-DK')} tilføjet`, 'success');
            }
        });
    }

    return { init, open, close };
})();
window.AddModal = AddModal;

// ── PAGINATION ───────────────────────────────────────────────────
const Pagination = (() => {
    let currentPage = 1;
    let totalPages = 1;
    let onPageChange = null;

    function itemsPerPage() { return window.AdminState.itemsPerPage || 40; }

    function init(onChange) {
        onPageChange = onChange;
        document.getElementById('prevPage').addEventListener('click', () => { if (currentPage > 1) { currentPage--; render(); onChange(); } });
        document.getElementById('nextPage').addEventListener('click', () => { if (currentPage < totalPages) { currentPage++; render(); onChange(); } });
    }

    function update(totalItems) {
        totalPages = Math.max(1, Math.ceil(totalItems / itemsPerPage()));
        if (currentPage > totalPages) currentPage = 1;
        render();
    }

    function reset() { currentPage = 1; render(); }

    function getSlice(arr) {
        const start = (currentPage - 1) * itemsPerPage();
        return arr.slice(start, start + itemsPerPage());
    }

    function getPageNumbers(current, total) {
        if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
        if (current <= 4) return [1, 2, 3, 4, 5, '...', total];
        if (current >= total - 3) return [1, '...', total - 4, total - 3, total - 2, total - 1, total];
        return [1, '...', current - 1, current, current + 1, '...', total];
    }

    function render() {
        const prevBtn = document.getElementById('prevPage');
        const nextBtn = document.getElementById('nextPage');
        const numbersEl = document.getElementById('pageNumbers');
        const infoEl = document.getElementById('pageInfo');

        prevBtn.disabled = currentPage <= 1;
        nextBtn.disabled = currentPage >= totalPages;

        numbersEl.innerHTML = '';
        getPageNumbers(currentPage, totalPages).forEach(p => {
            if (p === '...') {
                const span = document.createElement('span');
                span.textContent = '…';
                span.style.cssText = 'color:var(--text-muted);padding:0 3px;display:flex;align-items:center;font-size:11px;';
                numbersEl.appendChild(span);
                return;
            }
            const btn = document.createElement('button');
            btn.className = 'page-number' + (p === currentPage ? ' active' : '');
            btn.textContent = p;
            btn.addEventListener('click', () => { currentPage = p; render(); if (onPageChange) onPageChange(); });
            numbersEl.appendChild(btn);
        });

        infoEl.textContent = totalPages > 1 ? `Side ${currentPage}/${totalPages}` : '';
        document.getElementById('pagination').style.visibility = totalPages <= 1 ? 'hidden' : 'visible';
    }

    return { init, update, reset, getSlice };
})();
window.Pagination = Pagination;
