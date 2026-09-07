// ================================================================
//  mm-adminpakke V2 — ITEM-MODUL
//  Grid, kategorier (config-drevet, ingen hardcoded prefix-gæt),
//  søgning/tabs, favoritter, seneste, missing-images manager.
// ================================================================
'use strict';

const Items = (() => {
    let allItems = [];
    let favorites = new Set();
    let recentItems = [];
    let activeTab = 'all';
    let activeCategory = null;
    let searchQuery = '';

    const MAX_RECENT = 20;
    const LS_FAVS = 'mmadmin_favs';
    const LS_RECENT = 'mmadmin_recent';

    // ── INIT ────────────────────────────────────────────────────
    function init() {
        loadLocalStorage();
        AddModal.init();
        Pagination.init(renderPage);
        bindSearch();
        bindTabs();
        bindMissingModal();

        document.addEventListener('basketChanged', () => Basket.updateCount());
        document.addEventListener('missingImageAdded', updateMissingTabCount);
    }

    function loadLocalStorage() {
        try {
            const fav = localStorage.getItem(LS_FAVS);
            const rec = localStorage.getItem(LS_RECENT);
            if (fav) favorites = new Set(JSON.parse(fav));
            if (rec) recentItems = JSON.parse(rec).slice(0, MAX_RECENT);
        } catch (_) { /* localStorage kan være utilgængelig - fortsæt uden */ }
    }

    function saveFavorites() { try { localStorage.setItem(LS_FAVS, JSON.stringify([...favorites])); } catch (_) {} }
    function saveRecent() { try { localStorage.setItem(LS_RECENT, JSON.stringify(recentItems)); } catch (_) {} }

    // ── SÆT ITEMS (ved 'open') ─────────────────────────────────
    function setItems(items) {
        allItems = items || [];
        document.getElementById('headerItemCount').textContent = `${allItems.length.toLocaleString('da-DK')} items`;
        buildCategoryBar();
        Pagination.reset();
        applyFilters();
    }

    function getCategoryInfo(catId) {
        if (catId === window.AdminState.weaponsCategory.id) return window.AdminState.weaponsCategory;
        if (catId === window.AdminState.uncategorized.id) return window.AdminState.uncategorized;
        return window.AdminState.categories.find(c => c.id === catId) || window.AdminState.uncategorized;
    }
    function getCategoryLabel(catId) { return getCategoryInfo(catId).label; }

    // ── KATEGORI BAR ────────────────────────────────────────────
    function buildCategoryBar() {
        const bar = document.getElementById('categoryBar');
        bar.innerHTML = '';

        const counts = {};
        allItems.forEach(i => { counts[i.category] = (counts[i.category] || 0) + 1; });

        const allCats = [window.AdminState.weaponsCategory, ...window.AdminState.categories, window.AdminState.uncategorized];
        const used = allCats.filter(c => (counts[c.id] || 0) > 0);

        document.querySelector('.category-bar-wrap').style.display = used.length ? 'flex' : 'none';

        used.forEach(cat => {
            const btn = document.createElement('button');
            btn.className = 'cat-btn';
            btn.dataset.cat = cat.id;
            btn.innerHTML = `<span>${cat.icon}</span><span>${cat.label}</span><span class="cat-btn-count">${counts[cat.id] || 0}</span>`;
            btn.addEventListener('click', () => toggleCategory(cat.id, btn));
            bar.appendChild(btn);
        });

        checkCatScroll();
    }

    function toggleCategory(catId, btn) {
        if (activeCategory === catId) {
            activeCategory = null;
            document.querySelectorAll('.cat-btn').forEach(b => b.classList.remove('active'));
        } else {
            activeCategory = catId;
            document.querySelectorAll('.cat-btn').forEach(b => b.classList.toggle('active', b === btn));
        }
        Pagination.reset();
        applyFilters();
    }

    function checkCatScroll() {
        const bar = document.getElementById('categoryBar');
        const rBtn = document.getElementById('catScrollRight');
        const lBtn = document.getElementById('catScrollLeft');
        if (bar.scrollWidth > bar.clientWidth) {
            rBtn.classList.remove('hidden');
            bar.addEventListener('scroll', () => {
                lBtn.classList.toggle('hidden', bar.scrollLeft <= 4);
                rBtn.classList.toggle('hidden', bar.scrollLeft + bar.clientWidth >= bar.scrollWidth - 4);
            });
            lBtn.addEventListener('click', () => bar.scrollBy({ left: -200, behavior: 'smooth' }));
            rBtn.addEventListener('click', () => bar.scrollBy({ left: 200, behavior: 'smooth' }));
        } else {
            rBtn.classList.add('hidden');
            lBtn.classList.add('hidden');
        }
    }

    // ── SØGNING + TABS ──────────────────────────────────────────
    function bindSearch() {
        const input = document.getElementById('searchInput');
        const clearBtn = document.getElementById('clearSearch');
        let debounceTimer;

        input.addEventListener('input', () => {
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(() => {
                searchQuery = input.value.trim().toLowerCase();
                clearBtn.classList.toggle('hidden', !searchQuery);
                Pagination.reset();
                applyFilters();
            }, 80);
        });

        clearBtn.addEventListener('click', () => {
            input.value = '';
            searchQuery = '';
            clearBtn.classList.add('hidden');
            input.focus();
            applyFilters();
        });

        document.addEventListener('keydown', (e) => {
            if ((e.key === '/' ) && document.activeElement !== input && !isAnyModalOpen()) {
                e.preventDefault();
                input.focus();
            }
        });
    }

    function bindTabs() {
        document.querySelectorAll('.tab-btn').forEach(tab => {
            tab.addEventListener('click', () => {
                document.querySelectorAll('.tab-btn').forEach(t => t.classList.remove('active'));
                tab.classList.add('active');
                activeTab = tab.dataset.tab;
                Pagination.reset();
                applyFilters();
            });
        });
    }

    function isAnyModalOpen() {
        return !document.getElementById('addModal').classList.contains('hidden')
            || !document.getElementById('missingModal').classList.contains('hidden')
            || !document.getElementById('profileModal').classList.contains('hidden');
    }

    // ── FILTRERING ──────────────────────────────────────────────
    function getFilteredItems() {
        let list = allItems;

        if (activeTab === 'items') {
            list = list.filter(i => !i.isWeapon);
        } else if (activeTab === 'weapons') {
            list = list.filter(i => i.isWeapon);
        } else if (activeTab === 'favorites') {
            list = list.filter(i => favorites.has(i.name));
        } else if (activeTab === 'recent') {
            const order = new Map(recentItems.map((n, idx) => [n, idx]));
            return list.filter(i => order.has(i.name)).sort((a, b) => order.get(a.name) - order.get(b.name));
        } else if (activeTab === 'missing') {
            const missing = ImageResolver.getMissingSet();
            list = list.filter(i => missing.has(i.name));
        } else if (activeTab === 'blacklisted') {
            list = list.filter(i => window.AdminState.blacklist.has(i.name));
        }

        if (activeCategory) {
            list = list.filter(i => i.category === activeCategory);
        }

        if (searchQuery) {
            list = list.filter(i =>
                i.name.toLowerCase().includes(searchQuery) ||
                (i.label || '').toLowerCase().includes(searchQuery) ||
                (i.description || '').toLowerCase().includes(searchQuery)
            );
        }

        return list;
    }

    function applyFilters() {
        const filtered = getFilteredItems();
        Pagination.update(filtered.length);
        renderPage();
    }

    // ── RENDER ──────────────────────────────────────────────────
    function renderPage() {
        const grid = document.getElementById('itemsGrid');
        const filtered = getFilteredItems();
        const page = Pagination.getSlice(filtered);

        if (filtered.length === 0) {
            grid.innerHTML = `
                <div class="empty-grid-state">
                    <div class="empty-grid-icon">🔍</div>
                    <div>Ingen items fundet</div>
                    <div class="empty-grid-sub">Prøv at ændre din søgning eller dit filter.</div>
                </div>`;
            return;
        }

        const frag = document.createDocumentFragment();
        page.forEach((item, i) => frag.appendChild(buildItemCard(item, i)));
        grid.innerHTML = '';
        grid.appendChild(frag);
    }

    function buildItemCard(item, animIdx) {
        const isBlacklisted = window.AdminState.blacklist.has(item.name);
        const isFav = favorites.has(item.name);
        const inBasket = Basket.has(item.name);
        const catLabel = getCategoryLabel(item.category);

        const card = document.createElement('div');
        card.className = `item-card${isBlacklisted ? ' blacklisted' : ''}${inBasket ? ' in-basket' : ''}`;
        card.dataset.name = item.name;
        card.style.animationDelay = `${Math.min(animIdx * 10, 160)}ms`;

        card.innerHTML = `
            <div class="item-img-wrap">
                <img class="item-img" alt="${item.label || item.name}"/>
                <div class="item-img-missing hidden">
                    <div class="item-img-missing-icon">📦</div>
                    <div class="item-img-missing-badge">MANGLER</div>
                </div>
                <button class="item-fav-btn${isFav ? ' faved' : ''}" data-name="${item.name}" data-tooltip="${isFav ? 'Fjern favorit' : 'Tilføj favorit'}">★</button>
            </div>
            <div class="item-name">${item.label || item.name}</div>
            <div class="item-label">${item.name}</div>
            <div class="item-cat-badge${item.isWeapon ? ' cat-weapon' : ''}">${catLabel}</div>
            ${isBlacklisted ? `<div class="item-blacklist-overlay"><div class="item-blacklist-x">❌</div><div>SORTLISTET</div></div>` : ''}
        `;

        const imgEl = card.querySelector('.item-img');
        const missingEl = card.querySelector('.item-img-missing');
        lazyLoadImage(imgEl, missingEl, item);

        if (!isBlacklisted) {
            card.addEventListener('click', (e) => {
                if (e.target.closest('.item-fav-btn')) return;
                AddModal.open(item);
            });
        }

        card.querySelector('.item-fav-btn').addEventListener('click', (e) => {
            e.stopPropagation();
            toggleFavorite(item.name, e.currentTarget);
        });

        card.addEventListener('mouseenter', (e) => showPreview(item, e));
        card.addEventListener('mouseleave', hidePreview);
        card.addEventListener('mousemove', movePreview);

        return card;
    }

    function lazyLoadImage(imgEl, missingEl, item) {
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    ImageResolver.applyTo(imgEl, item, (ok) => {
                        if (!ok) {
                            imgEl.style.display = 'none';
                            missingEl.classList.remove('hidden');
                        }
                    });
                    observer.disconnect();
                }
            });
        }, { rootMargin: '80px' });
        observer.observe(imgEl);
    }

    // ── FAVORITTER / SENESTE ────────────────────────────────────
    function toggleFavorite(name, btn) {
        if (favorites.has(name)) {
            favorites.delete(name);
            btn.classList.remove('faved');
            btn.dataset.tooltip = 'Tilføj favorit';
            Toast.show('Fjernet fra favoritter', 'info');
        } else {
            favorites.add(name);
            btn.classList.add('faved');
            btn.dataset.tooltip = 'Fjern favorit';
            Toast.show('Tilføjet til favoritter ★', 'success');
        }
        saveFavorites();
        if (activeTab === 'favorites') applyFilters();
    }

    function trackRecent(name) {
        recentItems = [name, ...recentItems.filter(n => n !== name)].slice(0, MAX_RECENT);
        saveRecent();
    }

    // ── PREVIEW TOOLTIP ─────────────────────────────────────────
    let previewEl;
    function showPreview(item, ev) {
        if (!previewEl) previewEl = document.getElementById('itemPreview');
        const isBlacklisted = window.AdminState.blacklist.has(item.name);

        const img = document.getElementById('previewImg');
        img.classList.remove('loaded');
        ImageResolver.applyTo(img, item);

        document.getElementById('previewName').textContent = item.label || item.name;
        document.getElementById('previewLabel').textContent = item.name;
        document.getElementById('previewCat').textContent = `${getCategoryInfo(item.category).icon} ${getCategoryLabel(item.category)}`;
        document.getElementById('previewWeight').textContent = item.weight ? `${(item.weight / 1000).toFixed(2)} kg` : '';
        document.getElementById('previewDesc').textContent = item.description || '';
        document.getElementById('previewBlacklistBadge').classList.toggle('hidden', !isBlacklisted);
        document.getElementById('previewBlacklistMsg').classList.toggle('hidden', !isBlacklisted);

        previewEl.classList.remove('hidden');
        positionPreview(ev);
    }
    function hidePreview() { if (previewEl) previewEl.classList.add('hidden'); }
    function movePreview(ev) { positionPreview(ev); }
    function positionPreview(ev) {
        if (!previewEl || previewEl.classList.contains('hidden')) return;
        const x = ev.clientX + 16, y = ev.clientY + 16;
        const r = previewEl.getBoundingClientRect();
        previewEl.style.left = (x + r.width > window.innerWidth - 10 ? ev.clientX - r.width - 10 : x) + 'px';
        previewEl.style.top = (y + r.height > window.innerHeight - 10 ? ev.clientY - r.height - 10 : y) + 'px';
    }

    // ── MISSING IMAGES MANAGER ──────────────────────────────────
    function updateMissingTabCount() {
        const size = ImageResolver.getMissingSet().size;
        const badge = document.getElementById('missingTabCount');
        badge.textContent = size;
        badge.classList.toggle('hidden', size === 0);
        if (activeTab === 'missing') applyFilters();
    }

    function bindMissingModal() {
        document.getElementById('missingBtn').addEventListener('click', openMissingModal);
        document.getElementById('missingModalClose').addEventListener('click', closeMissingModal);
        document.getElementById('missingModal').addEventListener('click', (e) => {
            if (e.target === document.getElementById('missingModal')) closeMissingModal();
        });
    }

    function openMissingModal() {
        if (!window.AdminState.missingImageManagerEnabled) return;

        const missing = ImageResolver.getMissingSet();
        const tbody = document.getElementById('missingTableBody');
        tbody.innerHTML = '';

        document.getElementById('missingStatTotal').textContent = allItems.length.toLocaleString('da-DK');
        document.getElementById('missingStatBad').textContent = missing.size.toLocaleString('da-DK');
        document.getElementById('missingStatOk').textContent = (allItems.length - missing.size).toLocaleString('da-DK');

        const sorted = [...allItems].sort((a, b) => {
            const aM = missing.has(a.name) ? 0 : 1;
            const bM = missing.has(b.name) ? 0 : 1;
            if (aM !== bM) return aM - bM;
            return a.label.localeCompare(b.label);
        });

        const frag = document.createDocumentFragment();
        sorted.forEach(item => {
            const isMissing = missing.has(item.name);
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${item.name}</td>
                <td>${item.label}</td>
                <td style="color:var(--text-muted);font-family:'JetBrains Mono',monospace;font-size:9.5px;">${item.image}</td>
                <td><span class="missing-status ${isMissing ? 'bad' : 'ok'}">${isMissing ? 'MANGLER' : 'OK'}</span></td>`;
            frag.appendChild(tr);
        });
        tbody.appendChild(frag);

        document.getElementById('missingModal').classList.remove('hidden');
    }

    function closeMissingModal() {
        document.getElementById('missingModal').classList.add('hidden');
    }

    return { init, setItems, getCategoryLabel, trackRecent };
})();
window.Items = Items;
