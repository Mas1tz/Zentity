(function () {
  'use strict';

  const NUI = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'mm-faktura';
  function nuiPost(name, data) {
    return fetch(`https://${NUI}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then(r => r.json()).catch(() => ({}));
  }

  function qsel(q) { return document.querySelector(q); }
  function formatNumber(n) { return (n || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, "."); }

  function toast(message, type) {
    const container = document.getElementById('toast-container');
    const el = document.createElement('div');
    el.className = 'toast';
    const icon = type === 'error' ? 'fa-triangle-exclamation' : type === 'success' ? 'fa-circle-check' : 'fa-circle-info';
    const color = type === 'error' ? 'var(--red)' : type === 'success' ? 'var(--green)' : 'var(--accent)';
    el.innerHTML = `<i class="fa-solid ${icon}" style="color:${color};margin-right:8px"></i>${message}`;
    container.appendChild(el);
    setTimeout(() => el.remove(), 4500);
  }

  // ============================================================
  //  STATE
  // ============================================================
  const state = {
    canSend: false,
    myJob: null,
    config: null,
    currentTargetId: null,
    prices: {}, labels: {},
    invoices: [],
    manageableJobs: [],
    isAdmin: false,
    currentAdminJob: null,
    adminCategories: [],
  };

  // ============================================================
  //  TABS
  // ============================================================
  const titles = {
    send: ['Send Regning', 'Vælg en spiller og de varer/bøder regningen skal indeholde'],
    invoices: ['Mine Regninger', 'Regninger du selv har modtaget'],
    admin: ['Administrer Kategorier', 'Tilføj, redigér eller slet varer/bøder for dit job'],
  };

  document.querySelectorAll('.side-tab').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.side-tab').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
      btn.classList.add('active');
      const panel = btn.dataset.panel;
      document.getElementById(`panel-${panel}`).classList.add('active');
      const t = titles[panel];
      document.getElementById('page-title').textContent = t[0];
      document.getElementById('page-sub').textContent = t[1];
    });
  });

  function activatePanel(panel) {
    const btn = document.querySelector(`.side-tab[data-panel="${panel}"]`);
    if (btn) btn.click();
  }

  // ============================================================
  //  CLOSE
  // ============================================================
  function closeApp() {
    document.getElementById('app').classList.add('hidden');
    resetSendTab();
    nuiPost('escape');
  }
  document.getElementById('closeBtn').addEventListener('click', closeApp);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeApp(); });

  function resetSendTab() {
    state.currentTargetId = null;
    document.getElementById('playerName').textContent = 'Ingen valgt';
    document.getElementById('playerMeta').textContent = '';
    document.getElementById('playerUnpaidCount').textContent = '0';
    document.getElementById('playerUnpaidTotal').textContent = '0';
    document.getElementById('playerList').innerHTML = '';
    document.querySelectorAll('.fine-amount').forEach(i => i.value = 0);

    document.getElementById('categoriesLocked').classList.remove('hidden');
    document.getElementById('categoriesUnlockWrap').classList.add('hidden');
    document.getElementById('categoriesContent').classList.add('hidden');
    const toggleBtn = document.getElementById('toggleCategoriesBtn');
    toggleBtn.querySelector('span').textContent = 'Åbn Bøder/Varer';
    toggleBtn.querySelector('i').className = 'fa-solid fa-folder-open';

    updateTotal();
  }

  // ============================================================
  //  NUI MESSAGE LISTENER
  // ============================================================
  window.addEventListener('message', (event) => {
    try {
      handleNuiMessage(event.data);
    } catch (err) {
      console.error('[mm-faktura] Fejl i besked-håndtering:', err, event.data);
    }
  });

  function handleNuiMessage(data) {

    if (data.action === 'open') {
      document.getElementById('app').classList.remove('hidden');
      state.config = data.config || {};
      applyTheme(state.config.Tablet);
      state.canSend = !!data.data.canSend;
      state.myJob = data.data.job || null;

      populateDiscounts(state.config.Discounts || [0, 5, 10, 15, 25]);
      resetSendTab();

      const sendTabBtn = document.querySelector('.side-tab[data-panel="send"]');
      if (state.canSend) {
        sendTabBtn.classList.remove('hidden');
        activatePanel('send');
        nuiPost('requestCategories', { job: state.myJob });
      } else {
        sendTabBtn.classList.add('hidden');
        activatePanel('invoices');
      }

      nuiPost('requestInvoices');
    }

    if (data.action === 'toast') {
      toast(data.message, data.type);
    }

    if (data.action === 'close') {
      document.getElementById('app').classList.add('hidden');
    }

    if (data.action === 'playerInfo') {
      renderPlayerSearchResult(data.playerId, data.info);
    }

    if (data.action === 'playerSummary') {
      if (state.currentTargetId === data.playerId) {
        document.getElementById('playerUnpaidCount').textContent = data.summary.unpaidCount ?? 0;
        document.getElementById('playerUnpaidTotal').textContent = formatNumber(data.summary.unpaidTotal || 0);
      }
    }

    if (data.action === 'nearbyPlayers') {
      renderNearbyList(data.players || []);
    }

    if (data.action === 'invoicesList') {
      state.invoices = data.invoices || [];
      renderInvoicesFull();
    }

    if (data.action === 'categoriesData') {
      if (data.job === state.myJob) buildCategories(data.categories || []);
      if (data.job === state.currentAdminJob) {
        state.adminCategories = data.categories || [];
        renderAdminCategories();
      }
    }

    if (data.action === 'permissions') {
      state.isAdmin = !!data.data.isAdmin;
      state.manageableJobs = data.data.manageableJobs || [];
      const adminBtn = document.getElementById('tab-admin-btn');
      if (state.manageableJobs.length > 0) {
        adminBtn.classList.remove('hidden');
        buildJobTabs();
      } else {
        adminBtn.classList.add('hidden');
      }
    }
  }

  function hexToRgbString(hex) {
    const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    if (!m) return null;
    return `${parseInt(m[1], 16)}, ${parseInt(m[2], 16)}, ${parseInt(m[3], 16)}`;
  }

  function applyTheme(tablet) {
    if (!tablet) return;
    const root = document.documentElement.style;
    if (tablet.accent1) root.setProperty('--accent-2', tablet.accent1);
    if (tablet.accent2) root.setProperty('--accent', tablet.accent2);
    if (tablet.themeBg) {
      root.setProperty('--bg-base', tablet.themeBg);
      const rgb = hexToRgbString(tablet.themeBg);
      if (rgb) root.setProperty('--bg-base-rgb', rgb);
    }
  }

  function populateDiscounts(list) {
    const sel = document.getElementById('discountSelect');
    sel.innerHTML = '';
    list.forEach(v => {
      const opt = document.createElement('option');
      opt.value = v;
      opt.textContent = v > 0 ? `${v}% rabat` : 'Ingen rabat';
      sel.appendChild(opt);
    });
  }

  // ============================================================
  //  SPILLER-SØGNING / NÆRVED DIG
  // ============================================================
  document.getElementById('searchInput').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      const id = e.target.value.trim();
      if (!id) return;
      nuiPost('searchPlayer', { id });
    }
  });

  function renderPlayerSearchResult(playerId, info) {
    const list = document.getElementById('playerList');
    list.innerHTML = '';
    if (!info) {
      list.innerHTML = `<div class="player-row" style="cursor:default">Ingen spiller fundet</div>`;
      toast('Ingen spiller fundet med det ID', 'error');
      return;
    }
    const div = document.createElement('div');
    div.className = 'player-row';
    div.innerHTML = `<span>${playerId} — ${info.name}</span><span class="dist">${info.job}</span>`;
    div.onclick = () => showPlayerInfo(playerId, info);
    list.appendChild(div);
    showPlayerInfo(playerId, info);
  }

  const visibilityRange = document.getElementById('visibilityRange');
  visibilityRange.addEventListener('input', () => {
    document.getElementById('visibilityValue').textContent = visibilityRange.value;
    nuiPost('setVisibility', { radius: parseInt(visibilityRange.value) });
  });

  const opacityRange = document.getElementById('opacityRange');
  opacityRange.addEventListener('input', () => {
    const val = parseInt(opacityRange.value);
    document.getElementById('opacityValue').textContent = `${val}%`;
    document.documentElement.style.setProperty('--tablet-alpha', val / 100);
  });

  function renderNearbyList(players) {
    const list = document.getElementById('nearbyList');
    list.innerHTML = '';
    if (!players.length) {
      list.innerHTML = `<div class="player-row" style="cursor:default">Ingen i nærheden</div>`;
      return;
    }
    players.forEach(p => {
      const div = document.createElement('div');
      div.className = 'nearby-row';
      div.innerHTML = `<span>${p.name}</span><span class="dist">${p.distance}m</span>`;
      div.onclick = () => nuiPost('selectNearby', { id: p.serverId });
      list.appendChild(div);
    });
  }

  function showPlayerInfo(id, info) {
    state.currentTargetId = id;
    document.getElementById('playerName').textContent = info.name || 'Ukendt';
    document.getElementById('playerMeta').textContent = `${info.job || ''} ${info.grade || ''}`.trim();
    document.getElementById('playerUnpaidCount').textContent = info.unpaidCount ?? 0;
    document.getElementById('playerUnpaidTotal').textContent = formatNumber(info.unpaidTotal || 0);

    document.getElementById('categoriesLocked').classList.add('hidden');
    document.getElementById('categoriesUnlockWrap').classList.remove('hidden');
  }

  const toggleCategoriesBtn = document.getElementById('toggleCategoriesBtn');
  toggleCategoriesBtn.addEventListener('click', () => {
    const content = document.getElementById('categoriesContent');
    const opening = content.classList.contains('hidden');
    content.classList.toggle('hidden', !opening);
    const label = toggleCategoriesBtn.querySelector('span');
    const icon = toggleCategoriesBtn.querySelector('i');
    label.textContent = opening ? 'Luk Bøder/Varer' : 'Åbn Bøder/Varer';
    icon.classList.toggle('fa-folder-open', opening);
    icon.classList.toggle('fa-folder', !opening);
  });

  // ============================================================
  //  KATEGORIER (Send-fanen)
  // ============================================================
  function buildCategories(groups) {
    const container = document.getElementById('categoriesList');
    container.innerHTML = '';
    state.prices = {};
    state.labels = {};

    if (!groups.length) {
      container.innerHTML = `<div class="empty-state"><i class="fa-solid fa-box-open"></i>Ingen kategorier for dette job endnu</div>`;
      return;
    }

    groups.forEach(group => {
      const groupEl = document.createElement('div');
      groupEl.className = 'cat-group collapsed';
      groupEl.innerHTML = `
        <div class="cat-group-header"><span>${group.group}</span><i class="fa-solid fa-chevron-up"></i></div>
        <div class="cat-group-items"></div>
      `;
      const headerIcon = groupEl.querySelector('.cat-group-header i');
      groupEl.querySelector('.cat-group-header').addEventListener('click', () => {
        const collapsed = groupEl.classList.toggle('collapsed');
        headerIcon.classList.toggle('fa-chevron-up', collapsed);
        headerIcon.classList.toggle('fa-chevron-down', !collapsed);
      });

      const itemsWrap = groupEl.querySelector('.cat-group-items');
      group.items.forEach(cat => {
        state.prices[cat.id] = cat.price;
        state.labels[cat.id] = cat.label;

        const wrapper = document.createElement('div');
        wrapper.className = 'category';
        wrapper.dataset.label = cat.label.toLowerCase();
        wrapper.innerHTML = `
          <div>
            <strong>${cat.label}</strong>
            <div class="price">${formatNumber(cat.price)} DKK</div>
          </div>
          <input type="number" class="fine-amount" data-id="${cat.id}" min="0" value="0">
        `;
        const input = wrapper.querySelector('.fine-amount');
        input.addEventListener('input', updateTotal);
        input.addEventListener('click', e => e.stopPropagation());
        wrapper.addEventListener('click', () => {
          if (parseInt(input.value) === 0) { input.value = 1; updateTotal(); }
        });
        itemsWrap.appendChild(wrapper);
      });

      container.appendChild(groupEl);
    });

    updateTotal();
  }

  document.getElementById('categorySearch').addEventListener('input', (e) => {
    const term = e.target.value.trim().toLowerCase();
    document.querySelectorAll('.cat-group').forEach(group => {
      let anyVisible = false;
      group.querySelectorAll('.category').forEach(cat => {
        const match = !term || cat.dataset.label.includes(term);
        cat.style.display = match ? 'flex' : 'none';
        if (match) anyVisible = true;
      });
      group.style.display = anyVisible ? 'block' : 'none';
      if (term && anyVisible) {
        group.classList.remove('collapsed');
        const icon = group.querySelector('.cat-group-header i');
        icon.classList.remove('fa-chevron-up');
        icon.classList.add('fa-chevron-down');
      }
    });
  });

  function updateTotal() {
    let total = 0;
    const selected = [];
    document.querySelectorAll('.fine-amount').forEach(input => {
      const id = input.dataset.id;
      const antal = parseInt(input.value) || 0;
      if (antal > 0) {
        const subtotal = state.prices[id] * antal;
        total += subtotal;
        selected.push({ label: state.labels[id], antal, subtotal });
      }
    });
    document.getElementById('totalPrice').textContent = formatNumber(total);

    const cart = document.getElementById('cartPreview');
    if (!selected.length) {
      cart.innerHTML = `<div class="empty-state" style="padding:24px 8px"><i class="fa-solid fa-cart-shopping"></i>Vælg varer/bøder i midten</div>`;
    } else {
      cart.innerHTML = selected.map(s => `
        <div class="cart-row"><span><span class="qty">${s.antal}x</span> ${s.label}</span><span>${formatNumber(s.subtotal)},-</span></div>
      `).join('');
    }
  }
  document.getElementById('discountSelect').addEventListener('change', updateTotal);

  document.getElementById('sendInvoiceBtn').addEventListener('click', () => {
    if (!state.currentTargetId) {
      return toast('Vælg en spiller først', 'error');
    }
    const items = [];
    document.querySelectorAll('.fine-amount').forEach(input => {
      const antal = parseInt(input.value) || 0;
      if (antal > 0) items.push({ id: input.dataset.id, antal });
    });
    if (!items.length) {
      return toast('Vælg mindst én vare/bøde', 'error');
    }
    const discountPct = parseInt(document.getElementById('discountSelect').value) || 0;
    nuiPost('sendInvoice', { targetId: state.currentTargetId, job: state.myJob, items, discountPct });
    document.querySelectorAll('.fine-amount').forEach(i => i.value = 0);
    updateTotal();
  });

  // ============================================================
  //  REGNINGER (Mine Regninger + mini-liste)
  // ============================================================
  function invoiceCard(inv) {
    const el = document.createElement('div');
    el.className = 'invoice-card';

    let itemsHtml = '';
    try {
      const meta = inv.meta ? JSON.parse(inv.meta) : null;
      if (meta && Array.isArray(meta.items) && meta.items.length) {
        itemsHtml = `<div class="invoice-items">${meta.items.map(it => `
          <div class="invoice-item-row">
            <span><span class="qty">${it.antal}x</span> ${it.label}</span>
            <span>${formatNumber(it.subtotal)},-</span>
          </div>
        `).join('')}</div>`;
      }
    } catch (e) { /* gammel/simpel regning uden itemiseret meta - vis bare category_label */ }

    el.innerHTML = `
      <div class="invoice-top">
        <div>
          <div class="invoice-amount">${formatNumber(inv.amount)} DKK</div>
          <div class="invoice-cat">${!itemsHtml ? (inv.category_label || 'Diverse') : ''}</div>
        </div>
        <div class="invoice-from">
          <div class="invoice-from-label">Fra</div>
          <div>${inv.from_name || 'Ukendt'}</div>
          <span class="invoice-status ${inv.paid ? 'paid' : 'unpaid'}">${inv.paid ? 'Betalt' : 'Ubetalt'}</span>
        </div>
      </div>
      ${itemsHtml}
      <div class="invoice-date">${new Date(inv.created_at).toLocaleString('da-DK')}</div>
      <div class="invoice-actions">
        ${!inv.paid ? `<button class="btn primary small" data-pay="${inv.id}"><i class="fa-solid fa-credit-card"></i> Betal</button>` : ''}
        ${inv.paid ? `<button class="btn danger small" data-del="${inv.id}"><i class="fa-solid fa-trash"></i> Slet regning</button>` : ''}
      </div>
    `;
    const payBtn = el.querySelector('[data-pay]');
    if (payBtn) payBtn.addEventListener('click', () => nuiPost('payInvoice', { id: inv.id }));
    const delBtn = el.querySelector('[data-del]');
    if (delBtn) delBtn.addEventListener('click', () => nuiPost('deleteInvoice', { id: inv.id }));
    return el;
  }

  function renderInvoicesFull() {
    const container = document.getElementById('invoicesFull');
    container.innerHTML = '';
    if (!state.invoices.length) {
      container.innerHTML = `<div class="empty-state"><i class="fa-solid fa-receipt"></i>Du har ingen regninger</div>`;
      return;
    }
    state.invoices.forEach(inv => container.appendChild(invoiceCard(inv)));
  }

  // ============================================================
  //  ADMINISTRER KATEGORIER
  // ============================================================
  function buildJobTabs() {
    const wrap = document.getElementById('jobTabs');
    wrap.innerHTML = '';
    state.manageableJobs.forEach((job, i) => {
      const btn = document.createElement('button');
      btn.className = 'job-tab' + (i === 0 ? ' active' : '');
      btn.textContent = (state.config.BillingJobs && state.config.BillingJobs[job] && state.config.BillingJobs[job].label) || job;
      btn.addEventListener('click', () => {
        document.querySelectorAll('.job-tab').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        state.currentAdminJob = job;
        nuiPost('requestCategories', { job });
      });
      wrap.appendChild(btn);
    });
    if (state.manageableJobs.length > 0) {
      state.currentAdminJob = state.manageableJobs[0];
      nuiPost('requestCategories', { job: state.currentAdminJob });
    }
  }

  function renderAdminCategories() {
    const container = document.getElementById('adminCategories');
    container.innerHTML = '';

    state.adminCategories.forEach(group => {
      const groupEl = document.createElement('div');
      groupEl.className = 'admin-group';

      const itemsHtml = group.items.map(item => `
        <div class="admin-item ${item.custom ? '' : 'readonly'}" data-cat="${item.id}">
          <span><strong>${item.label}</strong><span class="price">${formatNumber(item.price)} DKK</span></span>
          ${item.custom ? `
            <span class="actions">
              <button data-edit="${item.id}" title="Redigér"><i class="fa-solid fa-pen"></i></button>
              <button data-del="${item.id}" title="Slet"><i class="fa-solid fa-trash"></i></button>
            </span>` : `<span class="actions" title="Fast kategori fra config.lua"><i class="fa-solid fa-lock" style="color:var(--text-dim)"></i></span>`}
        </div>
      `).join('');

      groupEl.innerHTML = `
        <div class="admin-group-header">
          <h4>${group.group}</h4>
          <button class="btn small danger" data-delgroup="${group.group}"><i class="fa-solid fa-trash"></i> Slet gruppe</button>
        </div>
        ${itemsHtml}
        <div class="add-item-form">
          <input type="text" placeholder="Ny vare/bøde..." data-newlabel>
          <input type="number" placeholder="Pris" class="price" data-newprice min="1">
          <button class="btn primary small" data-addto="${group.group}"><i class="fa-solid fa-plus"></i> Tilføj</button>
        </div>
      `;

      groupEl.querySelector('[data-delgroup]').addEventListener('click', () => {
        if (!confirm(`Slet hele gruppen "${group.group}"? Dette sletter kun jeres selv-oprettede varer i den.`)) return;
        nuiPost('deleteGroup', { job: state.currentAdminJob, group: group.group });
      });

      groupEl.querySelectorAll('[data-del]').forEach(btn => {
        btn.addEventListener('click', () => {
          if (!confirm('Slet denne vare?')) return;
          nuiPost('deleteItem', { job: state.currentAdminJob, catId: btn.dataset.del });
        });
      });

      groupEl.querySelectorAll('[data-edit]').forEach(btn => {
        btn.addEventListener('click', () => {
          const row = groupEl.querySelector(`.admin-item[data-cat="${btn.dataset.edit}"]`);
          const currentLabel = row.querySelector('strong').textContent;
          const currentPrice = state.adminCategories
            .flatMap(g => g.items).find(i => i.id === btn.dataset.edit)?.price || 0;
          row.innerHTML = `
            <input type="text" value="${currentLabel}" data-editlabel style="flex:1;margin-right:8px">
            <input type="number" value="${currentPrice}" data-editprice style="width:90px;margin-right:8px">
            <button class="btn primary small" data-save><i class="fa-solid fa-check"></i></button>
          `;
          row.querySelector('[data-save]').addEventListener('click', () => {
            const label = row.querySelector('[data-editlabel]').value.trim();
            const price = parseInt(row.querySelector('[data-editprice]').value) || 0;
            if (!label || price <= 0) return toast('Udfyld navn og gyldig pris', 'error');
            nuiPost('editItem', { job: state.currentAdminJob, catId: btn.dataset.edit, label, price });
          });
        });
      });

      const addBtn = groupEl.querySelector('[data-addto]');
      addBtn.addEventListener('click', () => {
        const label = groupEl.querySelector('[data-newlabel]').value.trim();
        const price = parseInt(groupEl.querySelector('[data-newprice]').value) || 0;
        if (!label || price <= 0) return toast('Udfyld navn og gyldig pris', 'error');
        nuiPost('addItem', { job: state.currentAdminJob, group: group.group, label, price });
      });

      container.appendChild(groupEl);
    });

    // Formular til at oprette en helt ny gruppe (via første vare i den)
    const newGroupEl = document.createElement('div');
    newGroupEl.className = 'admin-group';
    newGroupEl.innerHTML = `
      <div class="admin-group-header"><h4><i class="fa-solid fa-plus"></i> Ny Gruppe</h4></div>
      <div class="add-item-form">
        <input type="text" placeholder="Gruppenavn (fx Våbenloven)..." data-newgroupname>
        <input type="text" placeholder="Vare/bøde navn..." data-newlabel>
        <input type="number" placeholder="Pris" class="price" data-newprice min="1">
        <button class="btn primary small" data-createGroup><i class="fa-solid fa-plus"></i> Opret</button>
      </div>
    `;
    newGroupEl.querySelector('[data-createGroup]').addEventListener('click', () => {
      const groupName = newGroupEl.querySelector('[data-newgroupname]').value.trim();
      const label = newGroupEl.querySelector('[data-newlabel]').value.trim();
      const price = parseInt(newGroupEl.querySelector('[data-newprice]').value) || 0;
      if (!groupName || !label || price <= 0) return toast('Udfyld gruppenavn, vare og pris', 'error');
      nuiPost('addItem', { job: state.currentAdminJob, group: groupName, label, price });
    });
    container.appendChild(newGroupEl);
  }
})();
