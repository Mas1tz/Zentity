/* ============================================================
   kc_mdt · js/api.js
   NUI fetch bridge + DOM helpers + toast + modal system.
   Loaded first — app.js and dispatch.js both depend on these globals.
   ============================================================ */

'use strict';

const RESOURCE = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName()
    : (window.location.hostname || 'kc_mdt');

// ─── API BRIDGE ────────────────────────────────────────────────
// Every RegisterNUICallback in cl_nui.lua calls cb(...) synchronously
// with a real payload (never leaves the promise hanging), so a
// network-level failure here (res.ok false, JSON parse failure, or the
// fetch itself throwing) is the one genuine "something is wrong with
// the UI" case — surfaced through the central error toast.
async function api(route, body = {}) {
    try {
        const res = await fetch(`https://${RESOURCE}/${route}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body),
        });
        const text = await res.text();
        if (!text || text.length === 0) return {};
        try { return JSON.parse(text); }
        catch { console.error('[kc_mdt] invalid JSON from', route, text); return {}; }
    } catch (e) {
        console.error('[kc_mdt] api error:', route, e);
        toast('Kunne ikke kontakte MDT-serveren. Prøv igen.', 'error');
        return null;
    }
}

// ─── DOM HELPERS ───────────────────────────────────────────────
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
        const dt = new Date(String(d).replace(' ', 'T'));
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
function fmtClockNow() {
    return new Date().toLocaleTimeString('da-DK', { hour: '2-digit', minute: '2-digit' });
}
function debounce(fn, ms) {
    let t = null;
    return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

// ─── TOAST (§41) ───────────────────────────────────────────────
const TOAST_ICONS = { success: '✓', error: '!', warning: '⚠', inform: 'ℹ' };
function toast(msg, type = 'inform', duration = 3500) {
    const c = $('#toast-container');
    if (!c) return;
    const t = el('div', { className: `toast ${type}` });
    t.innerHTML = `<span>${TOAST_ICONS[type] || 'ℹ'}</span><span>${escapeHtml(msg)}</span>`;
    c.appendChild(t);
    setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 250); }, duration);
}

// ─── MODAL SYSTEM (§33) ────────────────────────────────────────
// Central modal host: animation + ESC + backdrop-click + focus + cleanup
// are all handled once, here, instead of per call-site.
let modalCloseHandler = null;
function openModal(html, opts = {}) {
    const host = $('#modal-host');
    const content = $('#modal-content');
    content.className = 'modal' + (opts.size === 'lg' ? ' modal-lg' : opts.size === 'md' ? ' modal-md' : '');
    content.innerHTML = html;
    host.classList.remove('hidden');
    modalCloseHandler = opts.onClose || null;

    const firstInput = content.querySelector('input, textarea, select, button');
    if (firstInput) setTimeout(() => firstInput.focus(), 60);
}
function closeModal() {
    const host = $('#modal-host');
    if (host.classList.contains('hidden')) return;
    host.classList.add('hidden');
    $('#modal-content').innerHTML = '';
    if (modalCloseHandler) { const fn = modalCloseHandler; modalCloseHandler = null; fn(); }
}
window.closeModal = closeModal; // used by inline onclick="closeModal()" in modal bodies

// Confirmation modal helper — used everywhere a destructive action needs
// a "are you sure" step (delete warrant, ban account, resolve call, ...).
function confirmModal(title, message, opts = {}) {
    return new Promise(resolve => {
        openModal(`
            <div class="modal-header"><h3>${escapeHtml(title)}</h3></div>
            <div class="modal-body"><p class="muted">${escapeHtml(message)}</p></div>
            <div class="modal-footer">
                <button class="btn btn-ghost" id="cm-cancel">${escapeHtml(opts.cancelLabel || 'Annullér')}</button>
                <button class="btn ${opts.danger === false ? 'btn-primary' : 'btn-danger'}" id="cm-confirm">${escapeHtml(opts.confirmLabel || 'Bekræft')}</button>
            </div>
        `, { size: 'md', onClose: () => resolve(false) });
        $('#cm-cancel').addEventListener('click', () => { modalCloseHandler = null; closeModal(); resolve(false); });
        $('#cm-confirm').addEventListener('click', () => { modalCloseHandler = null; closeModal(); resolve(true); });
    });
}

$('#modal-host').addEventListener('click', e => { if (e.target.id === 'modal-host') closeModal(); });

// ─── IMAGE PASTE / CLIENT-SIDE KOMPRIMERING (CTRL+V) — §20 ──────
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
function bindImagePaste(zoneEl, onAdd) {
    if (!zoneEl) return;
    zoneEl.addEventListener('click', () => zoneEl.focus());
    zoneEl.addEventListener('focus', () => zoneEl.classList.add('dz-active'));
    zoneEl.addEventListener('blur', () => zoneEl.classList.remove('dz-active'));
    zoneEl.addEventListener('paste', async e => {
        const items = (e.clipboardData && e.clipboardData.items) || [];
        let handled = false;
        for (const item of items) {
            if (item.type && item.type.startsWith('image/')) {
                e.preventDefault();
                handled = true;
                const blob = item.getAsFile();
                if (!blob) continue;
                const imgCfg = (window.state && state.staticConfig && state.staticConfig.images) || {};
                try {
                    const dataUrl = await compressImageBlob(blob, imgCfg.maxDimensionPx || 640, imgCfg.jpegQuality || 0.72);
                    onAdd(dataUrl);
                } catch {
                    toast('Kunne ikke indsætte billedet — prøv et andet billede.', 'error');
                }
                break;
            }
        }
        if (!handled) toast('Udklipsholderen indeholder ikke et billede.', 'warning');
    });
}
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

// ─── COPY TO CLIPBOARD ─────────────────────────────────────────
async function copyText(text) {
    try {
        await navigator.clipboard.writeText(text);
        return true;
    } catch {
        // Fallback for contexts where the async Clipboard API is blocked.
        try {
            const ta = document.createElement('textarea');
            ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
            document.body.appendChild(ta); ta.select();
            document.execCommand('copy');
            document.body.removeChild(ta);
            return true;
        } catch { return false; }
    }
}
