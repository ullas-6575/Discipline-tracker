const state = {
  date: todayStr(),
  habits: [],
  customTasks: [],
  history: [],
  moneyTransactions: [],
  moneyLoanFilter: null,
  totalPossibleFixed: 0,
};

function todayStr() {
  const d = new Date();
  const off = d.getTimezoneOffset();
  const local = new Date(d.getTime() - off * 60000);
  return local.toISOString().slice(0, 10);
}

// ---------- Installable app ----------
let deferredInstallPrompt;
const installButton = document.getElementById('install-button');
const exportButton = document.getElementById('export-button');
const importButton = document.getElementById('import-button');
const importFile = document.getElementById('import-file');
if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});

exportButton.addEventListener('click', async () => {
  const backup = await localStore.exportData();
  const filename = `daily-discipline-backup-${todayStr()}.json`;
  if (window.AndroidBridge) {
    window.AndroidBridge.saveBackup(JSON.stringify(backup, null, 2), filename);
    return;
  }
  const file = new Blob([JSON.stringify(backup, null, 2)], { type: 'application/json' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(file);
  link.download = filename;
  link.click();
  URL.revokeObjectURL(link.href);
});
importButton.addEventListener('click', () => importFile.click());
importFile.addEventListener('change', async () => {
  const file = importFile.files[0];
  if (!file || !confirm('Restore this backup? Current phone data will be replaced.')) return;
  try {
    await localStore.importData(JSON.parse(await file.text()));
    alert('Backup restored.');
    await loadDay();
    await loadMoney();
  } catch (error) {
    alert(error.message || 'Could not restore backup.');
  } finally {
    importFile.value = '';
  }
});
window.addEventListener('beforeinstallprompt', (event) => {
  event.preventDefault();
  deferredInstallPrompt = event;
  installButton.hidden = false;
});
installButton.addEventListener('click', async () => {
  if (!deferredInstallPrompt) return;
  deferredInstallPrompt.prompt();
  await deferredInstallPrompt.userChoice;
  deferredInstallPrompt = null;
  installButton.hidden = true;
});
window.addEventListener('appinstalled', () => { installButton.hidden = true; });

// ---------- Tabs ----------
document.querySelectorAll('.tab-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach((b) => b.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach((p) => p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById('tab-' + btn.dataset.tab).classList.add('active');
    if (btn.dataset.tab === 'dashboard') loadHistory();
    if (btn.dataset.tab === 'money') loadMoney();
  });
});

let calendarMonth = new Date(`${state.date}T00:00:00`);
document.getElementById('calendar-prev').addEventListener('click', () => {
  calendarMonth.setMonth(calendarMonth.getMonth() - 1);
  renderCalendar();
});
document.getElementById('calendar-next').addEventListener('click', () => {
  calendarMonth.setMonth(calendarMonth.getMonth() + 1);
  renderCalendar();
});

// ---------- Date picker ----------
const dateInput = document.getElementById('date-input');
dateInput.value = state.date;
dateInput.addEventListener('change', () => {
  state.date = dateInput.value;
  calendarMonth = new Date(`${state.date}T00:00:00`);
  loadDay();
});

const moneyDate = document.getElementById('money-date');
const moneyCategory = document.getElementById('money-category');
const moneyDirection = document.getElementById('money-direction');
moneyDate.value = state.date;
moneyCategory.addEventListener('change', () => {
  const isLoan = moneyCategory.value === 'loan-taken' || moneyCategory.value === 'loan-given';
  moneyDirection.disabled = isLoan;
  document.getElementById('money-note-hint').textContent = isLoan ? '(person\'s name, required)' : '(optional)';
  document.getElementById('money-note').placeholder = isLoan ? 'Name of the other party' : 'What was this for?';
  if (moneyCategory.value === 'loan-taken') moneyDirection.value = 'in';
  if (moneyCategory.value === 'loan-given') moneyDirection.value = 'out';
});

document.getElementById('money-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const amount = Number(document.getElementById('money-amount').value);
  const category = moneyCategory.value;
  const note = document.getElementById('money-note').value.trim();
  if (!Number.isFinite(amount) || amount <= 0) return;
  if ((category === 'loan-given' || category === 'loan-taken') && !note) {
    document.getElementById('money-note').focus();
    return;
  }
  await localStore.addMoney({
    date: moneyDate.value,
    category,
    account: document.getElementById('money-account').value,
    direction: category === 'loan-given' ? 'out' : category === 'loan-taken' ? 'in' : moneyDirection.value,
    amount,
    note,
  });
  event.target.reset();
  moneyDate.value = state.date;
  moneyCategory.dispatchEvent(new Event('change'));
  await loadMoney();
});

// ---------- Load a day ----------
async function loadDay() {
  const today = todayStr();
  if (state.date === today) await localStore.moveUnfinishedCustomTasks(state.date);
  const data = await localStore.getDay(state.date);
  state.habits = data.habits;
  state.customTasks = data.customTasks;
  renderEditableLists();
  renderSeal();
  await loadHistory();
}

function escapeHtml(s) {
  const d = document.createElement('div');
  d.textContent = String(s ?? '');
  return d.innerHTML.replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function renderEditableLists() {
  const render = (listId, items, type) => {
    const list = document.getElementById(listId);
    list.innerHTML = '';
    items.forEach((task) => {
      const li = document.createElement('li');
      li.className = 'habit-item' + (task.completed ? ' done' : '');
      li.draggable = true;
      li.dataset.id = task.id;
      li.innerHTML = `<span class="drag-handle" title="Drag to reorder">⋮⋮</span><input type="checkbox" class="habit-check" ${task.completed ? 'checked' : ''} /><span class="habit-name">${escapeHtml(task.name)}</span><span class="habit-points${task.points >= 5 ? ' big' : ''}">${task.points} pt${task.points > 1 ? 's' : ''}</span><button class="habit-edit" type="button">Edit</button><button class="habit-remove" type="button" title="Remove">×</button>`;
      li.querySelector('.habit-check').addEventListener('change', (event) => type === 'custom' ? toggleCustom(task.id, event.target.checked) : toggleHabit(task.id, event.target.checked));
      li.querySelector('.habit-edit').addEventListener('click', () => editTask(type, task));
      li.querySelector('.habit-remove').addEventListener('click', () => type === 'custom' ? deleteCustom(task.id) : deleteHabit(task.id));
      list.appendChild(li);
    });
    list.querySelectorAll('.habit-item').forEach((item) => {
      item.addEventListener('dragstart', () => item.classList.add('dragging'));
      item.addEventListener('dragend', () => {
        item.classList.remove('dragging');
        const ids = [...list.children].map((row) => Number(row.dataset.id));
        type === 'custom' ? localStore.reorderCustom(ids) : localStore.reorderHabits(ids);
      });
    });
    list.addEventListener('dragover', (event) => {
      event.preventDefault();
      const dragged = list.querySelector('.dragging');
      const target = event.target.closest('.habit-item');
      if (!dragged || !target || dragged === target) return;
      const before = event.clientY < target.getBoundingClientRect().top + target.offsetHeight / 2;
      list.insertBefore(dragged, before ? target : target.nextSibling);
    });
  };
  render('habit-list', state.habits, 'habit');
  render('custom-list', state.customTasks, 'custom');
}

async function editTask(type, task) {
  const listId = type === 'custom' ? 'custom-list' : 'habit-list';
  const row = [...document.querySelectorAll(`#${listId} .habit-item`)].find((item) => Number(item.dataset.id) === task.id);
  if (!row) return;
  const button = row.querySelector('.habit-edit');
  if (!row.classList.contains('editing')) {
    const nameInput = document.createElement('input');
    nameInput.className = 'task-edit-name';
    nameInput.value = task.name;
    const pointsInput = document.createElement('input');
    pointsInput.className = 'task-edit-points';
    pointsInput.type = 'number';
    pointsInput.min = '1';
    pointsInput.value = task.points;
    row.querySelector('.habit-name').replaceWith(nameInput);
    row.querySelector('.habit-points').replaceWith(pointsInput);
    if (type === 'custom') {
      const reminderEnabled = document.createElement('input');
      reminderEnabled.type = 'checkbox';
      reminderEnabled.checked = !!task.reminderTime;
      reminderEnabled.className = 'task-edit-reminder-toggle';
      const reminderTime = document.createElement('input');
      reminderTime.type = 'time';
      reminderTime.className = 'task-edit-reminder-time';
      reminderTime.value = task.reminderTime || '';
      reminderTime.disabled = !reminderEnabled.checked;
      reminderEnabled.addEventListener('change', () => {
        reminderTime.disabled = !reminderEnabled.checked;
        if (reminderEnabled.checked && !reminderTime.value) reminderTime.value = '09:00';
      });
      const reminderWrap = document.createElement('div');
      reminderWrap.className = 'task-edit-reminder';
      reminderWrap.append(reminderEnabled, document.createTextNode('Remind'), reminderTime);
      row.appendChild(reminderWrap);
    }
    row.classList.add('editing');
    button.textContent = 'Save';
    nameInput.focus();
    return;
  }

  const nameInput = row.querySelector('.task-edit-name');
  const pointsInput = row.querySelector('.task-edit-points');
  const name = nameInput.value.trim();
  if (!name) { nameInput.focus(); return; }
  const points = Number(pointsInput.value) || 1;

  if (type === 'habit') {
    await localStore.updateHabit(task.id, name, points);
  } else {
    const reminderToggle = row.querySelector('.task-edit-reminder-toggle');
    const reminderTimeInput = row.querySelector('.task-edit-reminder-time');
    const reminderTime = reminderToggle && reminderToggle.checked ? reminderTimeInput.value : '';
    await localStore.updateCustom(task.id, name, points, reminderTime);
    task.reminderTime = reminderTime;
    if (reminderTime) {
      await scheduleReminder({ ...task, date: task.date, name, reminderTime });
    }
  }

  task.name = name;
  task.points = points;
  renderEditableLists();
  renderSeal();
  await loadHistory();
}

async function toggleHabit(id, completed) {
  const h = state.habits.find((x) => x.id === id);
  if (h) h.completed = completed;
  renderEditableLists();
  renderSeal();
  await localStore.toggleHabit(state.date, id, completed);
  await loadHistory();
}

async function toggleCustom(id, completed) {
  const t = state.customTasks.find((x) => x.id === id);
  if (t) t.completed = completed;
  renderEditableLists();
  renderSeal();
  await localStore.toggleCustom(id, completed);
  await loadHistory();
}

async function deleteHabit(id) {
  state.habits = state.habits.filter((x) => x.id !== id);
  renderEditableLists();
  renderSeal();
  await localStore.deleteHabit(id);
  await loadHistory();
}

async function deleteCustom(id) {
  state.customTasks = state.customTasks.filter((x) => x.id !== id);
  renderEditableLists();
  renderSeal();
  await localStore.deleteCustom(id);
  await loadHistory();
}

document.getElementById('custom-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const nameEl = document.getElementById('custom-name');
  const ptsEl = document.getElementById('custom-points');
  const name = nameEl.value.trim();
  const points = Number(ptsEl.value) || 1;
  const reminderEnabled = document.getElementById('custom-reminder').checked;
  const reminderTime = document.getElementById('custom-reminder-time').value;
  if (!name) return;
  if (reminderEnabled && !reminderTime) {
    document.getElementById('custom-reminder-time').focus();
    return;
  }
  if (document.getElementById('custom-type').value === 'daily') {
    const id = await localStore.addHabit(name, points);
    state.habits.push({ id, name, points, completed: false });
    nameEl.value = '';
    ptsEl.value = 1;
    renderEditableLists();
    renderSeal();
    await loadDay();
    await loadHistory();
    return;
  }
  const id = await localStore.addCustom(state.date, name, points, reminderEnabled ? reminderTime : '');
  const task = { id, date: state.date, name, points, completed: 0, reminderTime: reminderEnabled ? reminderTime : '' };
  state.customTasks.push(task);
  if (reminderEnabled) await scheduleReminder(task);
  nameEl.value = '';
  ptsEl.value = 1;
  document.getElementById('custom-reminder').checked = false;
  document.getElementById('custom-reminder-time').value = '';
  document.getElementById('custom-reminder-time').disabled = true;
  await loadDay();
  await loadHistory();
});

const reminderToggle = document.getElementById('custom-reminder');
const reminderTime = document.getElementById('custom-reminder-time');
reminderToggle.addEventListener('change', () => { reminderTime.disabled = !reminderToggle.checked; });

const browserReminders = new Map();
async function scheduleReminder(task) {
  if (!task.reminderTime) return;
  const when = new Date(`${task.date}T${task.reminderTime}`).getTime();
  if (!Number.isFinite(when) || when <= Date.now()) return;
  if (window.AndroidBridge) {
    window.AndroidBridge.scheduleNotification(String(task.id), task.name, when);
    return;
  }
  if (!('Notification' in window)) return;
  if (Notification.permission !== 'granted' && await Notification.requestPermission() !== 'granted') return;
  const delay = when - Date.now();
  if (delay > 2147483647) return;
  clearTimeout(browserReminders.get(task.id));
  browserReminders.set(task.id, setTimeout(() => new Notification('Daily Discipline', { body: task.name }), delay));
}

// ---------- Seal (score ring) ----------
const SEAL_CIRC = 552.9; // 2 * PI * 88

function renderSeal() {
  const earned =
    state.habits.filter((h) => h.completed).reduce((s, h) => s + h.points, 0) +
    state.customTasks.filter((t) => t.completed).reduce((s, t) => s + t.points, 0);
  const possible =
    state.habits.reduce((s, h) => s + h.points, 0) +
    state.customTasks.reduce((s, t) => s + t.points, 0);
  const pct = possible ? Math.round((earned / possible) * 100) : 0;

  document.getElementById('seal-pct').textContent = pct + '%';
  document.getElementById('seal-pts').textContent = `${earned} / ${possible} pts`;

  const offset = SEAL_CIRC - (SEAL_CIRC * pct) / 100;
  const ring = document.getElementById('seal-progress');
  ring.style.strokeDashoffset = offset;

  let color = '#b5533c';
  if (pct >= 90) color = '#6f9e78';
  else if (pct >= 60) color = '#d9a441';
  else if (pct >= 30) color = '#c98a4c';
  ring.style.stroke = color;

  const statusEl = document.getElementById('seal-status');
  const statuses = [
    [0, 'Begin the day.'],
    [25, 'Small steps, kept.'],
    [50, 'Halfway to the seal.'],
    [75, 'The frog is nearly eaten.'],
    [95, 'Almost a perfect ledger.'],
    [100, 'Day sealed. Well kept.'],
  ];
  let msg = statuses[0][1];
  for (const [t, m] of statuses) if (pct >= t) msg = m;
  statusEl.textContent = msg;
}

// ---------- Dashboard ----------
async function loadHistory() {
  const data = await localStore.getHistory();
  state.history = data.history;
  state.totalPossibleFixed = data.totalPossibleFixed;
  renderStats();
  renderCalendar();
}

function renderCalendar() {
  const calendar = document.getElementById('calendar-grid');
  calendar.innerHTML = '';
  const year = calendarMonth.getFullYear();
  const month = calendarMonth.getMonth();
  const firstDay = new Date(year, month, 1);
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const scores = new Map(state.history.map((record) => [record.date, record.pct]));
  document.getElementById('calendar-title').textContent = firstDay.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
  for (let i = 0; i < firstDay.getDay(); i++) {
    const spacer = document.createElement('div');
    spacer.className = 'calendar-day spacer';
    calendar.appendChild(spacer);
  }
  for (let day = 1; day <= daysInMonth; day++) {
    const date = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    const pct = scores.get(date);
    const hasScore = pct !== undefined;
    const cell = document.createElement('div');
    cell.className = 'calendar-day ' + (hasScore ? 'marked' : 'missed') + (date === state.date ? ' today' : '');
    const color = scoreColor(hasScore ? pct : 0);
    cell.style.background = color;
    cell.style.borderColor = color;
    cell.style.color = hasScore && pct >= 60 ? 'var(--cream)' : 'var(--ink)';
    cell.title = `${date} — ${hasScore ? `${pct}% completed` : 'no completed work'}`;
    cell.textContent = day;
    calendar.appendChild(cell);
  }
}

async function loadMoney() {
  state.moneyTransactions = await localStore.getMoney();
  renderMoneyDashboard();
}

function moneyValue(amount) {
  return `৳${new Intl.NumberFormat('en-BD', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(amount)}`;
}

function moneyLabel(value) {
  return value === 'bkash' ? 'bKash' : value === 'loan-given' ? 'Loans given' : value === 'loan-taken' ? 'Loans taken' : value[0].toUpperCase() + value.slice(1);
}

function loanAccounts(transactions) {
  const balances = new Map();
  transactions.filter((item) => (item.category === 'loan-given' || item.category === 'loan-taken') && item.note).forEach((item) => {
    const name = item.note.trim();
    const change = item.category === 'loan-given' ? item.amount : -item.amount;
    balances.set(name, (balances.get(name) || 0) + change);
  });
  return [...balances.entries()]
    .filter(([, balance]) => Math.abs(balance) > 0.005)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([name, balance]) => ({ name, balance }));
}

function renderMoneyDashboard() {
  const transactions = state.moneyTransactions;
  const spent = transactions.filter((item) => item.direction === 'out').reduce((sum, item) => sum + item.amount, 0);
  const added = transactions.filter((item) => item.direction === 'in').reduce((sum, item) => sum + item.amount, 0);
  const balance = added - spent;
  document.getElementById('money-total-spent').textContent = moneyValue(spent);
  document.getElementById('money-total-added').textContent = moneyValue(added);
  document.getElementById('money-total-balance').textContent = moneyValue(balance);
  const badge = document.getElementById('money-net-badge');
  badge.textContent = `${balance < 0 ? 'Deficit' : 'Balance'} ${moneyValue(Math.abs(balance))}`;
  badge.classList.toggle('negative', balance < 0);

  const accounts = ['cash', 'bkash', 'bank'].map((account) => ({
    account,
    balance: transactions.filter((item) => item.account === account).reduce((sum, item) => sum + (item.direction === 'in' ? item.amount : -item.amount), 0),
  }));
  const accountMax = Math.max(...accounts.map((item) => Math.abs(item.balance)), 1);
  document.getElementById('money-accounts').innerHTML = accounts.map((item) => `
    <div class="account-row">
      <div class="money-row-label"><span>${moneyLabel(item.account)}</span><strong class="${item.balance < 0 ? 'negative-text' : ''}">${moneyValue(item.balance)}</strong></div>
      <div class="money-bar"><span class="${item.balance < 0 ? 'negative-bar' : ''}" style="width:${Math.min(Math.abs(item.balance) / accountMax * 100, 100)}%"></span></div>
    </div>
  `).join('');

  const loans = loanAccounts(transactions);
  const openLoanGiven = loans.filter((loan) => loan.balance > 0).reduce((sum, loan) => sum + loan.balance, 0);
  const openLoanTaken = loans.filter((loan) => loan.balance < 0).reduce((sum, loan) => sum + Math.abs(loan.balance), 0);
  const categoryNames = ['eat', 'payment', 'others', 'loan-given', 'loan-taken'];
  const categories = categoryNames.map((category) => ({
    category,
    amount: category === 'loan-given' ? openLoanGiven : category === 'loan-taken' ? openLoanTaken : transactions.filter((item) => item.category === category && item.direction === 'out').reduce((sum, item) => sum + item.amount, 0),
  }));
  const categoryMax = Math.max(...categories.map((item) => item.amount), 1);
  document.getElementById('money-categories').innerHTML = categories.map((item) => `
    <div class="category-row">
      <div class="money-row-label"><span>${moneyLabel(item.category)}</span><strong>${moneyValue(item.amount)}</strong></div>
      <div class="money-bar"><span style="width:${item.amount / categoryMax * 100}%"></span></div>
    </div>
  `).join('');

  if (state.moneyLoanFilter && !loans.some((loan) => loan.name === state.moneyLoanFilter)) state.moneyLoanFilter = null;
  const loanList = document.getElementById('money-loans');
  loanList.innerHTML = loans.length ? loans.map((loan) => `
    <button class="loan-row${state.moneyLoanFilter === loan.name ? ' selected' : ''}" type="button" data-loan-name="${escapeHtml(loan.name)}">
      <span>${escapeHtml(loan.name)}</span>
      <strong class="${loan.balance < 0 ? 'negative-text' : ''}">${loan.balance > 0 ? '+' : ''}${moneyValue(loan.balance)}</strong>
    </button>
  `).join('') : '<p class="money-empty">No open loan accounts.</p>';
  loanList.querySelectorAll('.loan-row').forEach((button) => {
    button.addEventListener('click', () => {
      const name = button.dataset.loanName;
      state.moneyLoanFilter = state.moneyLoanFilter === name ? null : name;
      renderMoneyDashboard();
    });
  });

  const visibleTransactions = state.moneyLoanFilter
    ? transactions.filter((item) => item.note.trim() === state.moneyLoanFilter)
    : transactions;
  document.getElementById('money-transaction-count').textContent = `${visibleTransactions.length} ${visibleTransactions.length === 1 ? 'entry' : 'entries'}${state.moneyLoanFilter ? ` · ${escapeHtml(state.moneyLoanFilter)}` : ''}`;
  const ledger = document.getElementById('money-transactions');
  ledger.innerHTML = visibleTransactions.length ? visibleTransactions.map((item) => `
    <div class="money-transaction">
      <div class="transaction-date">${escapeHtml(item.date)}</div>
      <div class="transaction-detail"><strong>${moneyLabel(item.category)}</strong><span>${moneyLabel(item.account)}${item.note ? ` · ${escapeHtml(item.note)}` : ''}</span></div>
      <strong class="transaction-amount ${item.direction === 'in' ? 'income' : 'expense'}">${item.direction === 'in' ? '+' : '-'}${moneyValue(item.amount)}</strong>
      <button class="transaction-delete" type="button" data-id="${item.id}" aria-label="Undo transaction" title="Undo transaction">Undo</button>
    </div>
  `).join('') : state.moneyLoanFilter ? '<p class="money-empty">No transactions for this person.</p>' : '<p class="money-empty">No transactions yet. Add your first movement above.</p>';
  ledger.querySelectorAll('.transaction-delete').forEach((button) => {
    button.addEventListener('click', async () => {
      await localStore.deleteMoney(Number(button.dataset.id));
      await loadMoney();
    });
  });
}

function scoreColor(pct) {
  if (pct <= 0) return '#8f949b';
  if (pct < 25) return '#9bb89e';
  if (pct < 50) return '#78a77f';
  if (pct < 75) return '#568f63';
  if (pct < 90) return '#3c7b4f';
  return '#28633c';
}

function renderStats() {
  const h = state.history;
  document.getElementById('stat-days').textContent = h.length;

  // streak: consecutive days up to (and including) today with pct >= 86
  let streak = 0;
  const byDate = {};
  h.forEach((d) => (byDate[d.date] = d));
  let cursor = new Date(state.date);
  while (true) {
    const key = cursor.toISOString().slice(0, 10);
    const rec = byDate[key];
    if (rec && rec.pct >= 86) {
      streak++;
      cursor.setDate(cursor.getDate() - 1);
    } else {
      break;
    }
  }
  document.getElementById('stat-streak').textContent = streak;

  const best = h.length ? Math.max(...h.map((d) => d.pct)) : 0;
  document.getElementById('stat-best').textContent = best + '%';

  const avg = h.length ? Math.round(h.reduce((s, d) => s + d.pct, 0) / h.length) : 0;
  document.getElementById('stat-avg').textContent = avg + '%';
}

function heatColor(pct) {
  if (pct === undefined || pct === 0) return '#8f949b';
  if (pct < 30) return '#5a3226';
  if (pct < 60) return '#8a6b34';
  if (pct < 90) return '#c98a4c';
  return '#6f9e78';
}

// ---------- Init ----------
loadDay();
