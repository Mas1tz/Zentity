// ================================================================
//  mm-adminpakke V2 — APP ORKESTRERING
//  NUI-besked-håndtering, tema-anvendelse, globale bindings.
// ================================================================
'use strict';

const App = (() => {
    let isOpen = false;

    function init() {
        Players.init();
        Items.init();
        Basket.init();

        window.addEventListener('message', onNUIMessage);
        document.addEventListener('keydown', onKeyDown);
        bindEvents();
    }

    // ── TEMA ────────────────────────────────────────────────────
    function applyTheme(theme) {
        if (!theme) return;
        const root = document.documentElement;
        if (theme.Background) root.style.setProperty('--panel', theme.Background);
        if (theme.Accent) {
            root.style.setProperty('--accent', theme.Accent);
            const rgb = hexToRgb(theme.Accent);
            if (rgb) root.style.setProperty('--accent-rgb', `${rgb.r}, ${rgb.g}, ${rgb.b}`);
        }
    }

    function hexToRgb(hex) {
        const m = hex.replace('#', '').match(/^([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
        if (!m) return null;
        return { r: parseInt(m[1], 16), g: parseInt(m[2], 16), b: parseInt(m[3], 16) };
    }

    // ── NUI EVENTS ──────────────────────────────────────────────
    function onNUIMessage(ev) {
        const msg = ev.data || {};
        switch (msg.action) {
            case 'open':          onOpen(msg); break;
            case 'playersUpdate': Players.setPlayers(msg.players || []); break;
            case 'basketSent':    onBasketSent(msg.success, msg.error); break;
            case 'escape':        onEscape(); break;
            case 'forceClose':    onForceClose(); break;
        }
    }

    function onOpen(data) {
        if (isOpen) return;
        isOpen = true;

        window.AdminState.maxItemAmount = data.maxItemAmount || 5000;
        window.AdminState.itemsPerPage = data.itemsPerPage || 40;
        window.AdminState.imageBasePath = (data.imageBasePath || '').replace(/\/+$/, '');
        window.AdminState.categories = data.categories || [];
        window.AdminState.uncategorized = data.uncategorized || window.AdminState.uncategorized;
        window.AdminState.weaponsCategory = data.weaponsCategory || window.AdminState.weaponsCategory;
        window.AdminState.blacklist = new Set(data.blacklist || []);
        window.AdminState.debug = !!data.debug;
        window.AdminState.missingImageManagerEnabled = !!data.missingImageManagerEnabled;

        applyTheme(data.theme);
        document.getElementById('missingBtn').classList.toggle('hidden', !window.AdminState.missingImageManagerEnabled);

        document.getElementById('app').classList.remove('hidden');
        document.getElementById('loadingState')?.classList.add('hidden');

        Players.setPlayers(data.players || []);
        Items.setItems(data.items || []);

        debugLog('UI åbnet', { items: (data.items || []).length, players: (data.players || []).length });
    }

    function closeUI() {
        if (!isOpen) return;
        isOpen = false;
        document.getElementById('app').classList.add('hidden');
        AddModal.close();
        nuiFetch('close', {});
    }

    function onEscape() {
        if (!document.getElementById('missingModal').classList.contains('hidden')) {
            document.getElementById('missingModal').classList.add('hidden');
            return;
        }
        if (!document.getElementById('profileModal').classList.contains('hidden')) {
            document.getElementById('profileModal').classList.add('hidden');
            return;
        }
        if (!document.getElementById('addModal').classList.contains('hidden')) {
            AddModal.close();
            return;
        }
        closeUI();
    }

    function onForceClose() {
        // Serveren/klienten har lukket tablet-systemet ned af en ekstern
        // årsag (død, køretøj, logout) - luk NUI'en helt via samme vej
        // som et normalt luk-klik, så Lua-siden også opdaterer isOpen.
        isOpen = false;
        document.getElementById('app').classList.add('hidden');
        AddModal.close();
        nuiFetch('close', {});
    }

    function onBasketSent(success, error) {
        if (success) {
            Basket.clear();
            Toast.show('Items sendt succesfuldt!', 'success');
        } else {
            Toast.show(`Fejl: ${error || 'Kunne ikke sende alle items.'}`, 'error');
        }
    }

    // ── EVENTS ──────────────────────────────────────────────────
    function bindEvents() {
        document.getElementById('closeBtn').addEventListener('click', closeUI);
        document.getElementById('sendBtn').addEventListener('click', sendBasket);
    }

    function sendBasket() {
        if (!window.AdminSelectedPlayer || Basket.size() === 0) return;
        nuiFetch('giveBasket', { targetId: window.AdminSelectedPlayer, basket: Basket.getPayload() });
    }

    function onKeyDown(e) {
        if (e.key === 'Escape') onEscape();
    }

    return { init };
})();

document.addEventListener('DOMContentLoaded', () => App.init());
