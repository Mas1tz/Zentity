(() => {
  const app          = document.getElementById('app');
  const grid         = document.getElementById('cardsGrid');
  const detailView   = document.getElementById('detailView');
  const closeBtn     = document.getElementById('closeBtn');
  const backBtn      = document.getElementById('backBtn');
  const panelTitle   = document.getElementById('panelTitle');
  const panelSubtitle = document.getElementById('panelSubtitle');

  let imageBase = 'nui://ox_inventory/web/images/';
  let busy      = false;
  let loadouts  = [];

  function resourceName() {
    return (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'MM-PolitiJob';
  }

  async function post(endpoint, data) {
    try {
      const res = await fetch(`https://${resourceName()}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {})
      });
      return await res.json();
    } catch (err) {
      console.error('[loadout] NUI callback fejlede:', endpoint, err);
      return { ok: false, error: 'network' };
    }
  }

  function weaponImage(name) {
    return `${imageBase}${name}.png`;
  }

  function cardImage(loadout) {
    return `../image/${loadout.image}`;
  }

  function prettify(name) {
    return name.replace(/^WEAPON_/, '').replace(/_/g, ' ').toLowerCase();
  }

  async function selectLoadout(loadout, btn) {
    if (busy) return;
    busy = true;
    const originalLabel = btn.textContent;
    btn.disabled = true;
    btn.textContent = loadout.isShop ? 'ÅBNER...' : 'HENTER UDSTYR...';

    const result = await post('selectLoadout', { name: loadout.name });

    if (!result || !result.ok) {
      btn.disabled = false;
      btn.textContent = originalLabel;
      busy = false;
      return;
    }
    // Ved success lukker Lua-siden selv NUI'et (og evt. åbner ox_inventory).
  }

  // ── LIST VIEW ────────────────────────────────────────────────

  function buildImageBlock(loadout) {
    const wrap = document.createElement('div');
    wrap.className = 'card-image';

    const useFallback = () => {
      wrap.innerHTML = '';
      const icon = document.createElement('i');
      icon.className = loadout.icon || 'fa-solid fa-gun';
      wrap.appendChild(icon);
    };

    if (loadout.isShop) {
      const icon = document.createElement('i');
      icon.className = loadout.icon || 'fa-solid fa-box-open';
      wrap.appendChild(icon);
      return wrap;
    }

    if (loadout.image) {
      const img = document.createElement('img');
      img.src = cardImage(loadout);
      img.alt = loadout.name;
      img.onerror = useFallback;
      wrap.appendChild(img);
    } else {
      useFallback();
    }

    return wrap;
  }

  function buildChip(label, imgName) {
    const chip = document.createElement('div');
    chip.className = 'chip';

    if (imgName) {
      const img = document.createElement('img');
      img.src = weaponImage(imgName);
      img.alt = '';
      img.onerror = () => img.remove();
      chip.appendChild(img);
    }

    const span = document.createElement('span');
    span.textContent = label;
    chip.appendChild(span);

    return chip;
  }

  function buildCard(loadout) {
    const card = document.createElement('div');
    card.className = 'card' + (loadout.isShop ? ' shop' : '');

    card.appendChild(buildImageBlock(loadout));

    const title = document.createElement('div');
    title.className = 'card-title';
    title.innerHTML = `<i class="${loadout.icon || 'fa-solid fa-gun'}"></i><span>${loadout.name}</span>`;
    card.appendChild(title);

    const desc = document.createElement('div');
    desc.className = 'card-desc';
    desc.textContent = loadout.metadata || '';
    card.appendChild(desc);

    const actions = document.createElement('div');
    actions.className = 'card-actions';

    if (!loadout.isShop) {
      const chips = document.createElement('div');
      chips.className = 'chip-row';

      (loadout.weapons || []).slice(0, 4).forEach((weapon) => {
        chips.appendChild(buildChip(prettify(weapon), weapon));
      });

      (loadout.items || []).slice(0, 2).forEach((item) => {
        chips.appendChild(buildChip(`${item.name} x${item.amount || 1}`));
      });

      card.appendChild(chips);

      const seeBtn = document.createElement('button');
      seeBtn.className = 'ghost-btn';
      seeBtn.textContent = 'SE LOADOUT';
      seeBtn.addEventListener('click', () => showDetail(loadout));
      actions.appendChild(seeBtn);
    }

    const selectBtn = document.createElement('button');
    selectBtn.className = 'select-btn';
    selectBtn.textContent = loadout.isShop ? 'ÅBN POLITILAGER' : 'VÆLG LOADOUT';
    selectBtn.addEventListener('click', () => selectLoadout(loadout, selectBtn));
    actions.appendChild(selectBtn);

    card.appendChild(actions);
    return card;
  }

  function renderGrid() {
    grid.innerHTML = '';
    loadouts.forEach((loadout) => grid.appendChild(buildCard(loadout)));
  }

  // ── DETAIL VIEW ("Se Loadout") ──────────────────────────────

  function buildDetailItem(name, image, amount, isWeapon) {
    const cell = document.createElement('div');
    cell.className = 'detail-item';

    const imgWrap = document.createElement('div');
    imgWrap.className = 'detail-item-image';

    const img = document.createElement('img');
    img.src = weaponImage(image);
    img.alt = name;
    img.onerror = () => {
      imgWrap.innerHTML = '';
      const icon = document.createElement('i');
      icon.className = isWeapon ? 'fa-solid fa-gun' : 'fa-solid fa-box';
      imgWrap.appendChild(icon);
    };
    imgWrap.appendChild(img);
    cell.appendChild(imgWrap);

    const label = document.createElement('div');
    label.className = 'detail-item-name';
    label.textContent = name;
    cell.appendChild(label);

    if (amount) {
      const amountEl = document.createElement('div');
      amountEl.className = 'detail-item-amount';
      amountEl.textContent = `x${amount}`;
      cell.appendChild(amountEl);
    }

    return cell;
  }

  function buildAttachmentRow(entry) {
    const row = document.createElement('div');
    row.className = 'attachment-row';

    const title = document.createElement('div');
    title.className = 'attachment-weapon';
    title.textContent = prettify(entry.weapon);
    row.appendChild(title);

    const chips = document.createElement('div');
    chips.className = 'attachment-chips';
    (entry.attachments || []).forEach((att) => {
      const chip = document.createElement('span');
      chip.className = 'attachment-chip';
      chip.textContent = att.replace(/_/g, ' ');
      chips.appendChild(chip);
    });
    row.appendChild(chips);

    return row;
  }

  function showDetail(loadout) {
    detailView.innerHTML = '';

    const intro = document.createElement('div');
    intro.className = 'detail-intro';

    const hero = document.createElement('div');
    hero.className = 'detail-hero';
    if (loadout.image) {
      const img = document.createElement('img');
      img.src = cardImage(loadout);
      img.alt = loadout.name;
      img.onerror = () => {
        hero.innerHTML = '';
        const icon = document.createElement('i');
        icon.className = loadout.icon || 'fa-solid fa-gun';
        hero.appendChild(icon);
      };
      hero.appendChild(img);
    } else {
      const icon = document.createElement('i');
      icon.className = loadout.icon || 'fa-solid fa-gun';
      hero.appendChild(icon);
    }
    intro.appendChild(hero);

    const introText = document.createElement('div');
    introText.className = 'detail-intro-text';
    introText.innerHTML = `<h2>${loadout.name}</h2><p>${loadout.metadata || ''}</p>`;
    intro.appendChild(introText);

    detailView.appendChild(intro);

    if ((loadout.weapons || []).length) {
      const label = document.createElement('div');
      label.className = 'detail-section-label';
      label.textContent = 'Våben & udstyr';
      detailView.appendChild(label);

      const itemsGrid = document.createElement('div');
      itemsGrid.className = 'detail-items';
      loadout.weapons.forEach((weapon) => {
        itemsGrid.appendChild(buildDetailItem(prettify(weapon), weapon, null, true));
      });
      detailView.appendChild(itemsGrid);
    }

    if ((loadout.items || []).length) {
      const label = document.createElement('div');
      label.className = 'detail-section-label';
      label.textContent = 'Items';
      detailView.appendChild(label);

      const itemsGrid = document.createElement('div');
      itemsGrid.className = 'detail-items';
      loadout.items.forEach((item) => {
        itemsGrid.appendChild(buildDetailItem(item.name, item.name, item.amount, false));
      });
      detailView.appendChild(itemsGrid);
    }

    if ((loadout.attachments || []).length) {
      const label = document.createElement('div');
      label.className = 'detail-section-label';
      label.textContent = 'Tilladte Attachments';
      detailView.appendChild(label);

      const attachmentList = document.createElement('div');
      attachmentList.className = 'attachment-list';
      loadout.attachments.forEach((entry) => {
        attachmentList.appendChild(buildAttachmentRow(entry));
      });
      detailView.appendChild(attachmentList);
    }

    const footer = document.createElement('div');
    footer.className = 'detail-footer';

    const backFooterBtn = document.createElement('button');
    backFooterBtn.className = 'ghost-btn';
    backFooterBtn.textContent = 'TILBAGE';
    backFooterBtn.addEventListener('click', hideDetail);
    footer.appendChild(backFooterBtn);

    const selectBtn = document.createElement('button');
    selectBtn.className = 'select-btn';
    selectBtn.textContent = 'VÆLG LOADOUT';
    selectBtn.addEventListener('click', () => selectLoadout(loadout, selectBtn));
    footer.appendChild(selectBtn);

    detailView.appendChild(footer);

    grid.classList.add('hidden');
    detailView.classList.remove('hidden');
    backBtn.classList.remove('hidden');
    panelTitle.textContent = loadout.name;
    panelSubtitle.textContent = 'Indhold i dette loadout';
  }

  function hideDetail() {
    detailView.classList.add('hidden');
    grid.classList.remove('hidden');
    backBtn.classList.add('hidden');
    panelTitle.textContent = 'Politi Loadout';
    panelSubtitle.textContent = 'Vælg dit udstyr og din enhed';
  }

  // ── OPEN / CLOSE ─────────────────────────────────────────────

  function open(payload) {
    imageBase = payload.imageBase || imageBase;
    loadouts  = payload.loadouts || [];
    busy      = false;

    hideDetail();
    renderGrid();

    app.classList.remove('hidden');
    requestAnimationFrame(() => app.classList.add('visible'));
  }

  function close() {
    app.classList.remove('visible');
    window.setTimeout(() => app.classList.add('hidden'), 180);
  }

  backBtn.addEventListener('click', hideDetail);
  closeBtn.addEventListener('click', () => post('close'));

  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || !app.classList.contains('visible')) return;

    if (!detailView.classList.contains('hidden')) {
      hideDetail();
    } else {
      post('close');
    }
  });

  window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    if (data.action === 'open') {
      open(data);
    } else if (data.action === 'close') {
      close();
    }
  });
})();