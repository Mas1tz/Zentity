/* ============================================================
   kc_mdt · js/dispatch.js
   Dispatch call list + interactive map (§22-§27).

   Depends on api.js globals ($ / el / api / toast / escapeHtml /
   fmtDate / confirmModal) loaded before this file. Exposes a single
   `Dispatch` object that app.js drives from switchTab()/message
   handlers — mirrors how the rest of the app is organised, just kept
   in its own file since it's a genuinely new, self-contained feature.
   ============================================================ */

'use strict';

const Dispatch = (function () {
    let cfg = null;              // Config.Dispatch (from getStaticConfig)
    let calls = [];              // active (non-resolved) dispatches
    let selectedId = null;
    let mapMode = 'auto';        // 'day' | 'night' | 'auto'
    let view = { x: 0, y: 0, scale: 1 };
    let dragging = null;
    let initialized = false;

    const MAP_BASE_WIDTH = 1100; // px — the "1x zoom" render width of the map image
    const MIN_SCALE = 0.4, MAX_SCALE = 4;

    function worldToPercent(x, y) {
        const b = cfg.MapBounds;
        const px = ((x - b.minX) / (b.maxX - b.minX)) * 100;
        // Y: north (max world Y) is the TOP of the image (0%), south is 100%.
        const py = (1 - (y - b.minY) / (b.maxY - b.minY)) * 100;
        return { left: Math.min(100, Math.max(0, px)), top: Math.min(100, Math.max(0, py)) };
    }

    // ── MAP MODE (day/night/auto) ──────────────────────────────
    async function resolveAutoMode() {
        try {
            const res = await api('getGameClock');
            const hour = (res && typeof res.hour === 'number') ? res.hour : 12;
            return (hour >= 6 && hour < 19) ? 'day' : 'night';
        } catch { return 'day'; }
    }
    async function applyMapMode() {
        const effective = mapMode === 'auto' ? await resolveAutoMode() : mapMode;
        const img = $('#map-image');
        if (img) img.src = effective === 'night' ? cfg.MapNight : cfg.MapDay;
        $$('.map-mode-btn').forEach(b => b.classList.toggle('active', b.dataset.mode === mapMode));
    }

    // ── PAN / ZOOM ──────────────────────────────────────────────
    function applyTransform() {
        const canvas = $('#map-canvas');
        if (canvas) canvas.style.transform = `translate(${view.x}px, ${view.y}px) scale(${view.scale})`;
    }
    function resetView() {
        const viewport = $('#map-viewport');
        if (!viewport) return;
        view = { x: (viewport.clientWidth - MAP_BASE_WIDTH) / 2, y: 20, scale: 0.6 };
        applyTransform();
    }
    function zoomBy(factor, center) {
        const viewport = $('#map-viewport');
        const rect = viewport.getBoundingClientRect();
        const cx = center ? center.x - rect.left : rect.width / 2;
        const cy = center ? center.y - rect.top : rect.height / 2;

        const newScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, view.scale * factor));
        const ratio = newScale / view.scale;
        view.x = cx - (cx - view.x) * ratio;
        view.y = cy - (cy - view.y) * ratio;
        view.scale = newScale;
        applyTransform();
    }
    function bindMapControls() {
        const viewport = $('#map-viewport');
        if (!viewport) return;

        viewport.addEventListener('mousedown', e => {
            dragging = { startX: e.clientX, startY: e.clientY, origX: view.x, origY: view.y };
        });
        window.addEventListener('mousemove', e => {
            if (!dragging) return;
            view.x = dragging.origX + (e.clientX - dragging.startX);
            view.y = dragging.origY + (e.clientY - dragging.startY);
            applyTransform();
        });
        window.addEventListener('mouseup', () => { dragging = null; });

        viewport.addEventListener('wheel', e => {
            e.preventDefault();
            zoomBy(e.deltaY < 0 ? 1.15 : 1 / 1.15, { x: e.clientX, y: e.clientY });
        }, { passive: false });

        $('#map-zoom-in').addEventListener('click', () => zoomBy(1.25));
        $('#map-zoom-out').addEventListener('click', () => zoomBy(1 / 1.25));
        $('#map-reset').addEventListener('click', resetView);

        $$('.map-mode-btn').forEach(b => b.addEventListener('click', () => {
            mapMode = b.dataset.mode;
            applyMapMode();
        }));
    }
    function centerOn(x, y) {
        const viewport = $('#map-viewport');
        if (!viewport) return;
        const pos = worldToPercent(x, y);
        const px = (pos.left / 100) * MAP_BASE_WIDTH;
        const py = (pos.top / 100) * (MAP_BASE_WIDTH * 1.2); // approx image ratio (3000/2500)
        view.x = viewport.clientWidth / 2 - px * view.scale;
        view.y = viewport.clientHeight / 2 - py * view.scale;
        applyTransform();
    }

    // ── RENDER: CALL LIST ──────────────────────────────────────
    function priorityInfo(p) {
        return (cfg.Priorities && cfg.Priorities[p]) || { label: '—', color: '#6b7280' };
    }
    function renderCallList() {
        const list = $('#call-list');
        const count = $('#call-count');
        if (!list) return;
        count.textContent = calls.length;

        if (!calls.length) {
            list.innerHTML = '<div class="empty-state"><div class="empty-icon">📡</div><p>Ingen opkald</p><p class="empty-sub">Nye opkald dukker automatisk op her.</p></div>';
            return;
        }

        list.innerHTML = '';
        // Nyeste øverst, ligesom reference-værktøjet (Opkaldsliste).
        const sorted = [...calls].sort((a, b) => (b.id || 0) - (a.id || 0));
        for (const c of sorted) {
            const units = safeUnits(c.units);
            const taken = units.length > 0 || c.status === 'active';
            const card = el('div', {
                className: `call-card prio-${c.priority} ${String(c.id) === String(selectedId) ? 'selected' : ''}`,
                onclick: () => selectCall(c.id),
            });
            card.innerHTML = `
                <div class="cc-top"><span class="cc-code">${escapeHtml(c.code || 'UKENDT')}</span><span class="cc-time">${fmtDate(c.created_at)}</span></div>
                <div class="cc-desc">${escapeHtml(c.description || '')}</div>
                <div class="cc-bottom">
                    <span>${escapeHtml(c.location || '—')}</span>
                    <span class="cc-units">${units.length ? units.map(u => `<span class="cc-unit-chip">${escapeHtml(u.unit || u.name || '?')}</span>`).join('') : (taken ? '<span class="pill pill-danger">Taget</span>' : '<span class="pill pill-success">Ledig</span>')}</span>
                </div>`;
            list.appendChild(card);
        }
    }
    function safeUnits(raw) {
        if (Array.isArray(raw)) return raw;
        if (typeof raw === 'string') { try { const p = JSON.parse(raw); return Array.isArray(p) ? p : []; } catch { return []; } }
        return [];
    }

    // ── RENDER: MARKERS ─────────────────────────────────────────
    function renderMarkers() {
        const wrap = $('#map-markers');
        if (!wrap) return;
        wrap.innerHTML = '';
        for (const c of calls) {
            if (c.coords_x == null || c.coords_y == null) continue;
            const pos = worldToPercent(c.coords_x, c.coords_y);
            const units = safeUnits(c.units);
            const taken = units.length > 0 || c.status === 'active';
            const marker = el('div', {
                className: `map-marker ${!taken ? 'pulse' : ''}`,
                style: `left:${pos.left}%; top:${pos.top}%;`,
                onclick: (e) => { e.stopPropagation(); selectCall(c.id, true); },
            });
            marker.innerHTML = `<img src="${taken ? cfg.MarkerTaken : cfg.MarkerAvailable}" alt="">`;
            wrap.appendChild(marker);
        }
        renderPopup();
    }

    function renderPopup() {
        $$('.call-popup').forEach(p => p.remove());
        if (!selectedId) return;
        const c = calls.find(x => String(x.id) === String(selectedId));
        if (!c || c.coords_x == null) return;

        const pos = worldToPercent(c.coords_x, c.coords_y);
        const units = safeUnits(c.units);
        const iAmOn = units.some(u => u.identifier === (window.state && state.user && state.user.identifier));
        const prio = priorityInfo(c.priority);

        const popup = el('div', { className: 'call-popup', style: `left:${pos.left}%; top:${pos.top}%;` });
        popup.innerHTML = `
            <div class="call-popup-title">${escapeHtml(c.code || 'UKENDT')} <span class="pill pill-neutral" style="color:${prio.color};">${prio.label}</span></div>
            <div class="call-popup-desc">${escapeHtml(c.description || '')}<br><span class="muted">${escapeHtml(c.location || '')}</span></div>
            <div class="call-popup-actions">
                ${iAmOn
                    ? '<button class="btn btn-secondary" id="pop-drop">Gå af opkald</button>'
                    : '<button class="btn btn-primary" id="pop-take">Tag opkald</button>'}
                <button class="btn btn-success" id="pop-resolve">Afslut</button>
            </div>`;
        $('#map-canvas').appendChild(popup);

        const takeBtn = $('#pop-take'), dropBtn = $('#pop-drop');
        if (takeBtn) takeBtn.addEventListener('click', () => takeCall(c.id));
        if (dropBtn) dropBtn.addEventListener('click', () => dropCall(c.id));
        $('#pop-resolve').addEventListener('click', () => resolveCall(c.id));
    }

    function selectCall(id, fromMarker) {
        selectedId = (String(selectedId) === String(id)) ? null : id;
        renderCallList();
        renderPopup();
        const c = calls.find(x => String(x.id) === String(selectedId));
        if (c && c.coords_x != null && !fromMarker) centerOn(c.coords_x, c.coords_y);
    }

    async function takeCall(id) {
        await api('takeDispatch', { id });
        toast('Du tog opkaldet.', 'success');
    }
    async function dropCall(id) {
        await api('dropDispatch', { id });
        toast('Du forlod opkaldet.', 'inform');
    }
    async function resolveCall(id) {
        const ok = await confirmModal('Afslut opkald', 'Marker dette opkald som afsluttet? Det fjernes fra listen for alle betjente.', { confirmLabel: 'Afslut', danger: false });
        if (!ok) return;
        await api('resolveDispatch', { id });
        toast('Opkald afsluttet.', 'success');
    }

    // ── NEW CALL MODAL ──────────────────────────────────────────
    function openNewCallModal() {
        const codeOpts = (cfg.Codes || []).map(c => `<option value="${escapeHtml(c)}">${escapeHtml(c)}</option>`).join('');
        const prioOpts = Object.entries(cfg.Priorities || {}).map(([k, v]) => `<option value="${k}" ${k === '2' ? 'selected' : ''}>${escapeHtml(v.label)}</option>`).join('');
        openModal(`
            <div class="modal-header"><h3>📡 Nyt opkald</h3></div>
            <div class="modal-body">
                <div class="new-call-form">
                    <div class="form-group full"><label>Type</label><select id="nd-code">${codeOpts}</select></div>
                    <div class="form-group full"><label>Beskrivelse</label><textarea id="nd-desc" rows="3" maxlength="1500"></textarea></div>
                    <div class="form-group"><label>Lokation (fritekst)</label><input type="text" id="nd-loc" maxlength="255" placeholder="fx Strøget 12"></div>
                    <div class="form-group"><label>Prioritet</label><select id="nd-prio">${prioOpts}</select></div>
                </div>
                <p class="caption mt-2">Din nuværende position bruges automatisk som kortmarkør.</p>
            </div>
            <div class="modal-footer">
                <button class="btn btn-ghost" onclick="closeModal()">Annullér</button>
                <button class="btn btn-primary" id="nd-save">Send opkald</button>
            </div>
        `, { size: 'md' });
        $('#nd-save').addEventListener('click', async () => {
            const description = $('#nd-desc').value.trim();
            if (!description) { toast('Angiv en beskrivelse', 'error'); return; }
            await api('createDispatch', {
                code: $('#nd-code').value,
                description,
                location: $('#nd-loc').value.trim(),
                priority: parseInt($('#nd-prio').value, 10),
            });
            closeModal();
        });
    }

    // ── PUBLIC ────────────────────────────────────────────────────
    async function init(staticConfig) {
        cfg = staticConfig.dispatch;
        if (!cfg) return;

        if (!initialized) {
            initialized = true;
            bindMapControls();
            $('#new-call-btn').addEventListener('click', openNewCallModal);
            $('#map-viewport').addEventListener('click', () => { selectedId = null; renderPopup(); renderCallList(); });
        }

        resetView();
        await applyMapMode();
        await load();
    }

    async function load() {
        calls = await api('getDispatches') || [];
        renderCallList();
        renderMarkers();
    }

    function handleNew(data) {
        calls.push(data);
        renderCallList();
        renderMarkers();
    }
    function handleResolved(data) {
        calls = calls.filter(c => String(c.id) !== String(data.id));
        if (String(selectedId) === String(data.id)) selectedId = null;
        renderCallList();
        renderMarkers();
    }
    function handleUpdated(data) {
        const c = calls.find(x => String(x.id) === String(data.id));
        if (c) {
            if (data.units) c.units = data.units;
            if (data.status) c.status = data.status;
        }
        renderCallList();
        renderMarkers();
    }

    return { init, load, handleNew, handleResolved, handleUpdated };
})();
