// ================================================================
//  mm-adminpakke V2 — SPILLER-MODUL
//  Søgning, valg af spiller, profil-modal med Steam-avatar.
// ================================================================
'use strict';

window.AdminSelectedPlayer = null;

const Players = (() => {
    let allPlayers = [];
    let listEl, searchInput;

    function init() {
        listEl = document.getElementById('playerList');
        searchInput = document.getElementById('playerSearch');

        searchInput.addEventListener('input', () => render(searchInput.value));
        document.getElementById('refreshPlayersBtn').addEventListener('click', () => {
            nuiFetch('refreshPlayers', {});
            Toast.show('Opdaterer spillerliste...', 'info');
        });
        document.getElementById('selectedPlayerClear').addEventListener('click', clearSelection);
        document.getElementById('selectedPlayerBar').addEventListener('click', (e) => {
            if (e.target.closest('#selectedPlayerClear')) return;
            if (window.AdminSelectedPlayer) openProfile(window.AdminSelectedPlayer);
        });
        document.getElementById('profileModalClose').addEventListener('click', closeProfile);
        document.getElementById('profileModal').addEventListener('click', (e) => {
            if (e.target === document.getElementById('profileModal')) closeProfile();
        });
    }

    function setPlayers(players) {
        allPlayers = players || [];
        render(searchInput.value);
        document.getElementById('headerPlayerCount').textContent = `${allPlayers.length} online`;

        // Hvis den valgte spiller er disconnected, ryd valget.
        if (window.AdminSelectedPlayer && !allPlayers.some(p => p.id === window.AdminSelectedPlayer)) {
            clearSelection();
        }
    }

    function render(filter) {
        filter = (filter || '').trim().toLowerCase();
        const filtered = filter
            ? allPlayers.filter(p => p.name.toLowerCase().includes(filter) || String(p.id).includes(filter))
            : allPlayers;

        if (!filtered.length) {
            listEl.innerHTML = `<div class="empty-state">${filter ? 'Ingen match' : 'Ingen spillere online'}</div>`;
            return;
        }

        listEl.innerHTML = '';
        const frag = document.createDocumentFragment();
        filtered.forEach(p => {
            const row = document.createElement('div');
            row.className = `player-item${window.AdminSelectedPlayer === p.id ? ' selected' : ''}`;
            row.dataset.id = p.id;
            row.innerHTML = `
                <div class="player-online-dot"></div>
                <span>${escapeHtml(p.name)}</span>
                <span class="player-id">[${p.id}]</span>`;
            row.addEventListener('click', () => select(p));
            frag.appendChild(row);
        });
        listEl.appendChild(frag);
    }

    function select(player) {
        window.AdminSelectedPlayer = player.id;
        listEl.querySelectorAll('.player-item').forEach(el => {
            el.classList.toggle('selected', el.dataset.id == player.id);
        });

        const bar = document.getElementById('selectedPlayerBar');
        bar.classList.add('visible');
        document.getElementById('selectedPlayerName').textContent = player.name;
        document.getElementById('selectedPlayerMeta').textContent = `ID: ${player.id}${player.job ? ' · ' + player.job : ''}`;
        document.getElementById('selectedPlayerAvatar').src = ImageResolver.PLACEHOLDER_SVG;

        // Lazy Steam-opslag KUN for den faktisk valgte spiller.
        nuiFetch('getPlayerProfile', { targetId: player.id }).then(profile => {
            if (profile && profile.steamAvatar && window.AdminSelectedPlayer === player.id) {
                document.getElementById('selectedPlayerAvatar').src = profile.steamAvatar;
            }
        });

        Basket.updateCount();
    }

    function clearSelection() {
        window.AdminSelectedPlayer = null;
        document.getElementById('selectedPlayerBar').classList.remove('visible');
        listEl.querySelectorAll('.player-item').forEach(el => el.classList.remove('selected'));
        Basket.updateCount();
    }

    function openProfile(targetId) {
        const player = allPlayers.find(p => p.id === targetId);
        if (!player) return;

        document.getElementById('profileModal').classList.remove('hidden');
        document.getElementById('profileName').textContent = player.name;
        document.getElementById('profileId').textContent = player.id;
        document.getElementById('profileJob').textContent = player.job || '—';
        document.getElementById('profilePing').textContent = player.ping ? `${player.ping} ms` : '—';
        document.getElementById('profileAvatar').src = ImageResolver.PLACEHOLDER_SVG;
        document.getElementById('profileSteamName').textContent = '';
        document.getElementById('profileIdentifier').textContent = '…';

        nuiFetch('getPlayerProfile', { targetId }).then(profile => {
            if (!profile) {
                document.getElementById('profileIdentifier').textContent = 'Ukendt';
                return;
            }
            if (profile.steamAvatar) document.getElementById('profileAvatar').src = profile.steamAvatar;
            if (profile.steamName) document.getElementById('profileSteamName').textContent = profile.steamName;
            document.getElementById('profileIdentifier').textContent = profile.identifier || 'Ukendt';
            if (profile.jobGrade) document.getElementById('profileJob').textContent = `${player.job || ''} (${profile.jobGrade})`;
        });
    }

    function closeProfile() {
        document.getElementById('profileModal').classList.add('hidden');
    }

    function escapeHtml(str) {
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    return { init, setPlayers, clearSelection };
})();
window.Players = Players;
