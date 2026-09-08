/* ══════════════════════════════════════════════════════════
   settings.js — persistence layer for theme/transparency/UI size/
   animations/snow/sounds/reduced-motion, plus small self-contained
   Toast, Loading and SoundFX helpers.

   Everything here is pure client-side (localStorage) - it never
   touches the server, matching the fact that these are per-player
   cosmetic preferences, not game state.
   ══════════════════════════════════════════════════════════ */

var THEME_LIST = [
    { id: 'snow',     name: 'Christmas Snow', swatch: 'linear-gradient(135deg,#1a7a3a,#c0392b)' },
    { id: 'santa',    name: 'Santa',          swatch: 'linear-gradient(135deg,#c0392b,#fdf6f0)' },
    { id: 'trees',    name: 'Christmas Trees',swatch: 'linear-gradient(135deg,#0e2a18,#e8c34a)' },
    { id: 'reindeer', name: 'Reindeer',       swatch: 'linear-gradient(135deg,#8c3b2e,#4c7a4a)' },
];

var Settings = (function() {
    var STORAGE_KEY = 'mm_christmas_settings_v1';
    var DEFAULTS = {
        theme: 'snow',
        transparency: 72,
        uiSize: 0,
        animations: true,
        snow: true,
        sounds: true,
        reducedMotion: false,
    };

    var current = Object.assign({}, DEFAULTS);
    var bounds  = { minW: 1000, minH: 640, maxW: 1280, maxH: 800 };
    var hadStoredSettings = false;

    function load() {
        try {
            var raw = localStorage.getItem(STORAGE_KEY);
            if (raw) {
                hadStoredSettings = true;
                current = Object.assign({}, DEFAULTS, JSON.parse(raw));
            }
        } catch (e) {
            current = Object.assign({}, DEFAULTS);
        }
        return current;
    }

    function save() {
        try { localStorage.setItem(STORAGE_KEY, JSON.stringify(current)); } catch (e) {}
    }

    // Called once when Lua injects Config.UI. Only seeds defaults the
    // FIRST time (no stored settings yet) — never overrides a
    // returning player's own saved choices.
    function applyServerDefaults(ui) {
        if (!ui) return;
        bounds.minW = ui.MinWidth  || bounds.minW;
        bounds.minH = ui.MinHeight || bounds.minH;
        bounds.maxW = ui.MaxWidth  || bounds.maxW;
        bounds.maxH = ui.MaxHeight || bounds.maxH;

        if (!hadStoredSettings) {
            if (ui.DefaultTheme) current.theme = ui.DefaultTheme;
            current.animations = ui.EnableAnimations !== false;
            current.snow       = ui.EnableSnow !== false;
            current.sounds     = ui.EnableSounds !== false;
        }
    }

    function apply() {
        var root = document.documentElement;
        root.setAttribute('data-theme', current.theme);
        root.setAttribute('data-snow', current.snow ? 'on' : 'off');
        root.setAttribute('data-reduced-motion', (current.reducedMotion || !current.animations) ? 'true' : 'false');

        var alpha = 0.25 + (current.transparency / 100) * 0.70;
        root.style.setProperty('--panel-alpha', alpha.toFixed(2));
        root.style.setProperty('--panel-alpha-hi', Math.min(0.95, alpha + 0.08).toFixed(2));

        var w = Math.round(bounds.minW + (current.uiSize / 100) * (bounds.maxW - bounds.minW));
        var h = Math.round(bounds.minH + (current.uiSize / 100) * (bounds.maxH - bounds.minH));
        root.style.setProperty('--ui-width', w + 'px');
        root.style.setProperty('--ui-height', h + 'px');
    }

    function set(key, value) {
        current[key] = value;
        save();
        apply();
    }

    return {
        load: load,
        apply: apply,
        set: set,
        get: function(key) { return current[key]; },
        getAll: function() { return current; },
        getBounds: function() { return bounds; },
        applyServerDefaults: applyServerDefaults,
    };
})();

/* ── TOAST (central NUI error/info banner, section 28) ────── */
var Toast = {
    show: function(message, type) {
        var wrap = document.getElementById('toast-wrap');
        if (!wrap) return;

        var t = document.createElement('div');
        t.className = 'toast' + (type === 'error' ? ' toast-error' : type === 'success' ? ' toast-success' : '');
        t.textContent = message;
        wrap.appendChild(t);

        setTimeout(function() {
            t.style.transition = 'opacity .25s, transform .25s';
            t.style.opacity = '0';
            t.style.transform = 'translateY(-8px)';
            setTimeout(function() { t.remove(); }, 260);
        }, 3200);
    }
};

/* ── LOADING SCREEN ─────────────────────────────────────── */
var Loading = {
    run: function(durationMs, onDone) {
        var el   = document.getElementById('loading');
        var fill = document.getElementById('loading-bar-fill');

        if (!durationMs || durationMs <= 0 || Settings.get('reducedMotion')) {
            if (el) el.classList.add('is-hidden');
            if (fill) fill.style.width = '100%';
            if (onDone) onDone();
            return;
        }

        if (el) el.classList.remove('is-hidden');
        if (fill) fill.style.width = '0%';

        var start = performance.now();
        function frame(now) {
            var elapsed = now - start;
            var pct = Math.min(100, (elapsed / durationMs) * 100);
            if (fill) fill.style.width = pct + '%';
            if (elapsed < durationMs) {
                requestAnimationFrame(frame);
            } else {
                if (el) el.classList.add('is-hidden');
                if (onDone) onDone();
            }
        }
        requestAnimationFrame(frame);
    }
};

/* ── SOUND FX (synth tones — no external/binary audio assets) ── */
var SoundFX = (function() {
    var ctx = null;

    function ensureCtx() {
        if (ctx) return ctx;
        try {
            ctx = new (window.AudioContext || window.webkitAudioContext)();
        } catch (e) {
            ctx = null;
        }
        return ctx;
    }

    function tone(freq, duration, type, delay) {
        if (!Settings.get('sounds')) return;
        setTimeout(function() {
            var c = ensureCtx();
            if (!c) return;
            try {
                var osc  = c.createOscillator();
                var gain = c.createGain();
                osc.type = type || 'sine';
                osc.frequency.value = freq;
                gain.gain.setValueAtTime(0.08, c.currentTime);
                gain.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + (duration || 0.18));
                osc.connect(gain).connect(c.destination);
                osc.start();
                osc.stop(c.currentTime + (duration || 0.18));
            } catch (e) { /* never let a sound error break the UI */ }
        }, delay || 0);
    }

    return {
        open:     function() { tone(520, .12); tone(660, .14, 'sine', 90); },
        click:    function() { tone(440, .06); },
        purchase: function() { tone(660, .10); tone(880, .16, 'sine', 80); },
        reward:   function() { tone(784, .12); tone(988, .20, 'sine', 100); },
        levelup:  function() { tone(523, .10); tone(659, .10, 'sine', 90); tone(784, .22, 'sine', 180); },
        error:    function() { tone(220, .18, 'sawtooth'); },
    };
})();
