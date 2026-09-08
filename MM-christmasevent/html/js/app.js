/* ══════════════════════════════════════════════════════════
   app.js — mm-christmas NUI application
   ══════════════════════════════════════════════════════════ */

var App = (function() {
    var PlayerData      = {};
    var currentTab      = 'dashboard';
    var currentTaskTab  = 'daily';
    var currentLbTab    = 'level';
    var LeaderboardData = {};
    var uiConfig        = {};

    /* ── HELPERS ────────────────────────────────────────── */
    function fmtNum(n) {
        if (n === undefined || n === null) return '0';
        var s = Math.floor(Number(n)).toString();
        var out = '', len = s.length;
        for (var i = 0; i < len; i++) {
            if (i > 0 && (len - i) % 3 === 0) out += '.';
            out += s[i];
        }
        return out;
    }

    function pct(val, max) {
        if (!max || max <= 0) return 100;
        return Math.min(100, Math.max(0, (val / max) * 100));
    }

    function el(id) { return document.getElementById(id); }
    function qsa(sel) { return document.querySelectorAll(sel); }
    function setText(id, val) { var e = el(id); if (e) e.textContent = val; }

    function itemImg(itemName) {
        if (!itemName) return '';
        return 'nui://ox_inventory/web/images/' + itemName + '.png';
    }

    /* ── SETTINGS TAB ───────────────────────────────────── */
    function renderThemeGrid() {
        var grid = el('theme-grid');
        if (!grid) return;
        var active = Settings.get('theme');
        grid.innerHTML = '';
        THEME_LIST.forEach(function(t) {
            var card = document.createElement('div');
            card.className = 'theme-swatch' + (t.id === active ? ' active' : '');
            card.innerHTML =
                '<div class="theme-swatch-preview" style="background:' + t.swatch + '"></div>' +
                '<div class="theme-swatch-name">' + t.name + '</div>';
            card.onclick = function() {
                Settings.set('theme', t.id);
                SoundFX.click();
                renderThemeGrid();
            };
            grid.appendChild(card);
        });
    }

    function bindSettingsControls() {
        var s = Settings.getAll();

        var transparency = el('set-transparency');
        if (transparency) {
            transparency.value = s.transparency;
            transparency.oninput = function() { Settings.set('transparency', Number(this.value)); };
        }

        var uisize = el('set-uisize');
        if (uisize) {
            uisize.value = s.uiSize;
            uisize.oninput = function() { Settings.set('uiSize', Number(this.value)); };
        }

        var animations = el('set-animations');
        if (animations) {
            animations.checked = !!s.animations;
            animations.onchange = function() { Settings.set('animations', this.checked); };
        }

        var snow = el('set-snow');
        if (snow) {
            snow.checked = !!s.snow;
            snow.onchange = function() { Settings.set('snow', this.checked); };
        }

        var sounds = el('set-sounds');
        if (sounds) {
            sounds.checked = !!s.sounds;
            sounds.onchange = function() { Settings.set('sounds', this.checked); };
        }

        var reduced = el('set-reduced');
        if (reduced) {
            reduced.checked = !!s.reducedMotion;
            reduced.onchange = function() { Settings.set('reducedMotion', this.checked); };
        }
    }

    function renderSettings() {
        renderThemeGrid();
        bindSettingsControls();
    }

    /* ── SHOW / HIDE APP ────────────────────────────────── */
    function showApp() {
        el('app').classList.remove('is-closing');
        el('app').classList.add('is-open');
    }

    function close() {
        var app = el('app');
        app.classList.add('is-closing');
        app.classList.remove('is-open');
        SoundFX.click();
        Api.call('close', {});
        setTimeout(function() { app.classList.remove('is-closing'); }, 300);
    }

    /* ── TAB NAVIGATION ─────────────────────────────────── */
    var TITLES = {
        dashboard: '🎄 Dashboard', profile: '🎅 Profil', level: '⭐ Level',
        tasks: '📋 Opgaver', trees: '🌲 Juletræer', snowmen: '⛄ Snemænd',
        gifts: '🎁 Gaver', shop: '🛒 Shop', leaderboard: '🏆 Leaderboard',
        settings: '⚙️ Indstillinger',
    };

    function showTab(name) {
        currentTab = name;
        SoundFX.click();

        qsa('.nav-item').forEach(function(n) { n.classList.toggle('active', n.dataset.tab === name); });
        qsa('.tab').forEach(function(t) { t.classList.toggle('active', t.id === 'tab-' + name); });

        var titleEl = el('main-title');
        if (titleEl) titleEl.textContent = TITLES[name] || name;

        if (name === 'leaderboard') Api.call('getLeaderboard', {});

        renderTab(name);
    }

    function renderAll() {
        renderSidebar();
        renderTab(currentTab);
    }

    function renderTab(name) {
        if (name === 'dashboard')   renderDashboard();
        if (name === 'profile')     renderProfile();
        if (name === 'level')       renderLevel();
        if (name === 'tasks')       renderTasks();
        if (name === 'trees')       renderTrees();
        if (name === 'snowmen')     renderSnowmen();
        if (name === 'gifts')       renderGifts();
        if (name === 'shop')        renderShop();
        if (name === 'leaderboard') renderLeaderboard();
        if (name === 'settings')    renderSettings();
    }

    /* ── SIDEBAR ────────────────────────────────────────── */
    function renderSidebar() {
        setText('sb-level', PlayerData.level || 1);
        setText('sb-coins', fmtNum(PlayerData.coins || 0));
        setText('sb-xp',    fmtNum(PlayerData.xp    || 0));
        setText('sb-name',  PlayerData.name || 'Spiller');
        setText('sb-sub',   'Level ' + (PlayerData.level || 1));
    }

    /* ── AVATAR ─────────────────────────────────────────── */
    function setAvatar(url) {
        var fallback = 'assets/default-avatar.svg';
        [el('sb-avatar'), el('prof-avatar')].forEach(function(img) {
            if (!img) return;
            img.onerror = function() { img.onerror = null; img.src = fallback; };
            img.src = url || fallback;
        });
    }

    /* ── DASHBOARD ──────────────────────────────────────── */
    function renderDashboard() {
        var xpPct = pct(PlayerData.xp || 0, PlayerData.xpRequired || 1);

        setText('dash-level',   PlayerData.level || 1);
        setText('dash-coins',   fmtNum(PlayerData.coins || 0));
        setText('dash-trees',   fmtNum(PlayerData.treesDecorated || 0));
        setText('dash-snowmen', fmtNum(PlayerData.snowmenBuilt   || 0));
        setText('dash-gifts',   fmtNum(PlayerData.giftsFound     || 0));
        setText('dash-xp',      fmtNum(PlayerData.xp || 0) + ' / ' + fmtNum(PlayerData.xpRequired || 0));

        var fill = el('xp-fill');
        if (fill) fill.style.width = xpPct + '%';
        setText('xp-nums', fmtNum(PlayerData.xp || 0) + ' / ' + fmtNum(PlayerData.xpRequired || 0) + ' XP');

        renderDashboardHints();
    }

    function renderDashboardHints() {
        var wrap = el('daily-hints-wrap');
        if (!wrap) return;

        var hints = window._DailyHints || {};
        if (!hints.tree && !hints.snowman) { wrap.style.display = 'none'; return; }

        wrap.style.display = 'block';
        wrap.innerHTML =
            '<div class="hint-title">📍 Dagens lokation-hints</div>' +
            '<div class="hint-row"><span class="hint-icon">🌲</span><div><div class="hint-label">Juletræ i nærheden</div><div class="hint-text">' + (hints.tree || '?') + '</div></div></div>' +
            '<div class="hint-row"><span class="hint-icon">⛄</span><div><div class="hint-label">Snemand-plads i nærheden</div><div class="hint-text">' + (hints.snowman || '?') + '</div></div></div>';
    }

    /* ── PROFIL ─────────────────────────────────────────── */
    function renderProfile() {
        setText('prof-name',    PlayerData.name  || 'Spiller');
        setText('prof-level',   'Level ' + (PlayerData.level || 1));
        setText('prof-xp',      fmtNum(PlayerData.totalXP || PlayerData.xp || 0));
        setText('prof-coins',   fmtNum(PlayerData.coins || 0));
        setText('prof-trees',   fmtNum(PlayerData.treesDecorated || 0));
        setText('prof-snowmen', fmtNum(PlayerData.snowmenBuilt   || 0));
        setText('prof-gifts',   fmtNum(PlayerData.giftsFound     || 0));
        setText('prof-pgifts',  fmtNum(PlayerData.personalGifts  || 0));
        setText('prof-driven',  Math.floor((PlayerData.distanceDriven || 0) / 1000) + ' km');
        setText('prof-run',     Math.floor((PlayerData.distanceRun    || 0) / 1000) + ' km');
    }

    /* ── LEVEL ──────────────────────────────────────────── */
    function renderLevel() {
        setText('level-big', PlayerData.level || 1);

        var wrap = el('level-rewards-wrap');
        if (!wrap) return;

        var levelList = Object.keys(window._LevelRewards || {}).map(Number).sort(function(a, b) { return a - b; });
        var myLevel = PlayerData.level || 1;
        var claimed = PlayerData.claimedRewards || [];
        wrap.innerHTML = '';

        levelList.forEach(function(lvl) {
            var reward = window._LevelRewards[lvl];
            if (!reward) return;

            var unlocked  = myLevel >= lvl;
            var isClaimed = claimed.indexOf(lvl) !== -1;

            var card = document.createElement('div');
            card.className = 'level-reward-card' + (unlocked ? ' unlocked' : '') + (isClaimed ? ' claimed' : '');

            var imgHtml = '';
            if (reward.coins) {
                imgHtml += '<div class="lrc-item"><img src="' + itemImg('christmas_coin') + '" onerror="this.style.display=\'none\'" class="lrc-img"><span class="lrc-qty">x' + fmtNum(reward.coins) + '</span></div>';
            }
            if (reward.item) {
                imgHtml += '<div class="lrc-item"><img src="' + itemImg(reward.item) + '" onerror="this.style.display=\'none\'" class="lrc-img"><span class="lrc-qty">x' + (reward.amount || 1) + '</span></div>';
            }

            var btnHtml;
            if (unlocked && !isClaimed) {
                btnHtml = '<button class="btn btn-full" onclick="App.claimLevelReward(' + lvl + ')">Hent</button>';
            } else if (isClaimed) {
                btnHtml = '<div class="lrc-claimed-badge">✅ Hentet</div>';
            } else {
                btnHtml = '<div class="lrc-locked-badge">🔒 Lv ' + lvl + '</div>';
            }

            card.innerHTML =
                '<div class="lrc-level-num">Lv ' + lvl + '</div>' +
                '<div class="lrc-items-row">' + imgHtml + '</div>' +
                btnHtml;

            wrap.appendChild(card);
        });
    }

    function claimLevelReward(lvl) {
        SoundFX.click();
        Api.call('claimLevelReward', { level: lvl });
    }

    /* ── OPGAVER ────────────────────────────────────────── */
    function renderTasks() {
        renderTaskList('daily',  PlayerData.dailyTasks  || []);
        renderTaskList('weekly', PlayerData.weeklyTasks || []);
        showTaskTab(currentTaskTab);
    }

    function renderTaskList(type, tasks) {
        var wrap = el('tasks-' + type);
        if (!wrap) return;
        wrap.innerHTML = '';

        if (tasks.length === 0) {
            wrap.innerHTML = '<p class="empty-hint">Ingen opgaver</p>';
            return;
        }

        tasks.forEach(function(t) {
            var prog = Math.min(t.progress || 0, t.target);
            var p = pct(prog, t.target);

            var card = document.createElement('div');
            card.className = 'task-card' + (t.done ? ' done' : '');
            card.innerHTML =
                '<div class="task-card-top">' +
                    '<span class="task-card-label">' + t.label + '</span>' +
                    '<div class="task-card-rewards"><span class="reward-pill rp-xp">+' + fmtNum(t.xp) + ' XP</span><span class="reward-pill rp-coins">+' + fmtNum(t.coins) + ' 🪙</span></div>' +
                '</div>' +
                '<div class="task-progress-bg"><div class="task-progress-fill" style="width:' + p + '%;"></div></div>' +
                (t.done ? '<div class="task-done-badge">✅ Fuldført</div>' : '<div class="task-progress-label">' + fmtNum(prog) + ' / ' + fmtNum(t.target) + '</div>');
            wrap.appendChild(card);
        });
    }

    function showTaskTab(type) {
        currentTaskTab = type;
        qsa('.task-tab-btn').forEach(function(b) { b.classList.toggle('active', b.dataset.type === type); });
        var daily = el('tasks-daily'), weekly = el('tasks-weekly');
        if (daily)  daily.style.display  = type === 'daily'  ? 'flex' : 'none';
        if (weekly) weekly.style.display = type === 'weekly' ? 'flex' : 'none';
    }

    /* ── TRÆER / SNEMÆND / GAVER ─────────────────────────── */
    function renderTrees() {
        setText('trees-count', fmtNum(PlayerData.treesDecorated || 0));
        var done = PlayerData.treesDone || [];
        setText('trees-done-list', done.length > 0 ? done.map(function(i) { return 'Træ #' + i; }).join(', ') : 'Ingen endnu');
    }

    function renderSnowmen() {
        setText('snowmen-count', fmtNum(PlayerData.snowmenBuilt || 0));
    }

    function renderGifts() {
        setText('gifts-count',    fmtNum(PlayerData.giftsFound    || 0));
        setText('gifts-personal', fmtNum(PlayerData.personalGifts || 0));
    }

    /* ── SHOP ───────────────────────────────────────────── */
    function renderShop() {
        var wrap = el('shop-grid');
        if (!wrap) return;
        wrap.innerHTML = '';

        var items     = window._ShopItems || [];
        var purchases = PlayerData.shopPurchases || {};
        var coins     = PlayerData.coins || 0;

        items.forEach(function(item) {
            var bought = purchases[item.id] || 0;
            var maxed  = bought >= item.limit;
            var afford = coins >= item.price;

            var btnLabel = maxed ? 'MAKS ANTAL' : (!afford ? 'FOR FÅ COINS' : 'KØB');

            var card = document.createElement('div');
            card.className = 'shop-card';
            card.id = 'shop-card-' + item.id;
            card.innerHTML =
                '<div class="shop-card-icon">' + item.icon + '</div>' +
                '<div class="shop-card-label">' + item.label + '</div>' +
                '<div class="shop-card-price">🪙 ' + fmtNum(item.price) + '</div>' +
                (!afford && !maxed ? '<div class="shop-card-owned">Du har ' + fmtNum(coins) + ' 🪙</div>' : '') +
                '<div class="shop-card-limit">Købt: ' + bought + ' / ' + item.limit + '</div>' +
                '<button class="btn btn-full" ' + (maxed || !afford ? 'disabled' : '') + ' onclick="App.buyItem(\'' + item.id + '\')">' + btnLabel + '</button>';
            wrap.appendChild(card);
        });
    }

    function buyItem(id) {
        SoundFX.click();
        Api.call('shopBuy', { id: id });
    }

    function flashShopCard(id) {
        var card = el('shop-card-' + id);
        if (!card) return;
        card.classList.add('just-bought');
        setTimeout(function() { card.classList.remove('just-bought'); }, 550);
    }

    /* ── LEADERBOARD ────────────────────────────────────── */
    function renderLeaderboard() {
        var data = LeaderboardData[currentLbTab] || [];
        var wrap = el('lb-list');
        if (!wrap) return;
        wrap.innerHTML = '';

        if (data.length === 0) {
            wrap.innerHTML = '<p class="empty-hint">Ingen data endnu</p>';
            return;
        }

        data.forEach(function(row, idx) {
            var rank = idx + 1;
            var rc = rank === 1 ? 'r1' : rank === 2 ? 'r2' : rank === 3 ? 'r3' : 'rn';
            var div = document.createElement('div');
            div.className = 'lb-row';
            div.innerHTML =
                '<div class="lb-rank ' + rc + '">' + rank + '</div>' +
                '<div class="lb-name">' + (row.name || 'Ukendt') + '</div>' +
                '<div class="lb-value">' + fmtNum(row.value) + '</div>';
            wrap.appendChild(div);
        });
    }

    function showLbTab(type) {
        currentLbTab = type;
        SoundFX.click();
        qsa('.lb-tab-btn').forEach(function(b) { b.classList.toggle('active', b.dataset.type === type); });
        renderLeaderboard();
    }

    /* ── NUI MESSAGE HANDLER ────────────────────────────── */
    var previousCoins     = null;
    var previousLevel     = null;
    var previousPurchases = null;

    function handleSyncData(data) {
        var isFirst = previousCoins === null;

        if (!isFirst && data.coins > previousCoins) SoundFX.reward();
        if (!isFirst && data.level > previousLevel) SoundFX.levelup();

        if (!isFirst && previousPurchases) {
            for (var id in (data.shopPurchases || {})) {
                if ((data.shopPurchases[id] || 0) > (previousPurchases[id] || 0)) {
                    flashShopCard(id);
                }
            }
        }

        previousCoins     = data.coins;
        previousLevel     = data.level;
        previousPurchases = data.shopPurchases || {};

        PlayerData = data;
        if (el('app').classList.contains('is-open')) renderAll();
    }

    window.addEventListener('message', function(event) {
        var d = event.data;
        if (!d || !d.action) return;

        if (d.action === 'open') {
            if (d.data) PlayerData = d.data;
            SoundFX.open();
            showApp();
            Loading.run((uiConfig && uiConfig.LoadingDuration) || 900, function() {
                renderAll();
            });
        }

        if (d.action === 'close') {
            var app = el('app');
            app.classList.add('is-closing');
            app.classList.remove('is-open');
        }

        if (d.action === 'syncData' && d.data) {
            handleSyncData(d.data);
        }

        if (d.action === 'leaderboardData') {
            LeaderboardData = d.data || {};
            if (currentTab === 'leaderboard') renderLeaderboard();
        }

        if (d.action === 'profileImage') {
            setAvatar(d.url);
        }

        if (d.action === 'injectConfig') {
            window._LevelRewards = d.levelRewards || {};
            window._ShopItems    = d.shopItems    || [];
            window._DailyHints   = d.hints        || {};
            uiConfig = d.ui || {};

            Settings.applyServerDefaults(uiConfig);
            Settings.apply();

            if (el('app').classList.contains('is-open')) {
                renderShop();
                renderDashboardHints();
            }
        }
    });

    /* ── ESC closes the UI ──────────────────────────────── */
    document.addEventListener('keyup', function(e) {
        if (e.key === 'Escape') close();
    });

    /* ── INIT ───────────────────────────────────────────── */
    Settings.load();
    Settings.apply();

    return {
        showTab: showTab,
        showTaskTab: showTaskTab,
        showLbTab: showLbTab,
        buyItem: buyItem,
        claimLevelReward: claimLevelReward,
        close: close,
    };
})();
