const localStore = (() => {
  const DB_NAME = 'daily-discipline-local';
  const DB_VERSION = 3;
  const ready = new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains('habits')) db.createObjectStore('habits', { keyPath: 'id', autoIncrement: true });
      if (!db.objectStoreNames.contains('logs')) {
        const logs = db.createObjectStore('logs', { keyPath: 'key' });
        logs.createIndex('date', 'date');
        logs.createIndex('habitId', 'habitId');
      }
      if (!db.objectStoreNames.contains('customTasks')) {
        const tasks = db.createObjectStore('customTasks', { keyPath: 'id', autoIncrement: true });
        tasks.createIndex('date', 'date');
      }
      if (!db.objectStoreNames.contains('moneyTransactions')) {
        const money = db.createObjectStore('moneyTransactions', { keyPath: 'id', autoIncrement: true });
        money.createIndex('date', 'date');
        money.createIndex('account', 'account');
        money.createIndex('category', 'category');
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });

  async function transaction(storeNames, mode, work) {
    const db = await ready;
    return new Promise((resolve, reject) => {
      const tx = db.transaction(storeNames, mode);
      const result = work(tx);
      tx.oncomplete = () => resolve(result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  }

  async function all(storeName) {
    const db = await ready;
    return new Promise((resolve, reject) => {
      const request = db.transaction(storeName).objectStore(storeName).getAll();
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  function isLoan(item) {
    return item.category === 'loan-given' || item.category === 'loan-taken';
  }

  function retentionCutoff() {
    const cutoff = new Date();
    cutoff.setHours(0, 0, 0, 0);
    cutoff.setDate(cutoff.getDate() - 6);
    return cutoff.toISOString().slice(0, 10);
  }

  async function removeExpiredMoney() {
    const cutoff = retentionCutoff();
    const expired = (await all('moneyTransactions')).filter((item) => !isLoan(item) && item.date < cutoff);
    if (!expired.length) return;
    await transaction('moneyTransactions', 'readwrite', (tx) => {
      const store = tx.objectStore('moneyTransactions');
      expired.forEach((item) => store.delete(item.id));
    });
  }

  const sortHabits = (items) => items.sort((a, b) => a.sortOrder - b.sortOrder || a.id - b.id);
  const sortTasks = (items) => items.sort((a, b) => a.sortOrder - b.sortOrder || a.id - b.id);

  return {
    async exportData() {
      return {
        format: 'daily-discipline-backup',
        version: 1,
        exportedAt: new Date().toISOString(),
        habits: await all('habits'),
        logs: await all('logs'),
        customTasks: await all('customTasks'),
        moneyTransactions: await all('moneyTransactions'),
      };
    },
    async importData(data) {
      if (!data || data.format !== 'daily-discipline-backup' || !Array.isArray(data.habits) || !Array.isArray(data.logs) || !Array.isArray(data.customTasks)) {
        throw new Error('Invalid Daily Discipline backup file.');
      }
      return transaction(['habits', 'logs', 'customTasks', 'moneyTransactions'], 'readwrite', (tx) => {
        const habits = tx.objectStore('habits');
        const logs = tx.objectStore('logs');
        const tasks = tx.objectStore('customTasks');
        const money = tx.objectStore('moneyTransactions');
        habits.clear(); logs.clear(); tasks.clear(); money.clear();
        data.habits.forEach((item) => habits.put(item));
        data.logs.forEach((item) => logs.put(item));
        data.customTasks.forEach((item) => tasks.put(item));
        (data.moneyTransactions || []).forEach((item) => money.put(item));
      });
    },
    async moveUnfinishedCustomTasks(date) {
      const day = new Date(`${date}T00:00:00`);
      if (!Number.isFinite(day.getTime())) return;
      day.setDate(day.getDate() + 1);
      const tomorrow = day.toISOString().slice(0, 10);
      const allTasks = await all('customTasks');
      const tasksDueToday = allTasks.filter((task) => task.date === date && !task.completed);
      if (!tasksDueToday.length) return;
      const tomorrowTasks = allTasks.filter((task) => task.date === tomorrow);
      const tomorrowKeys = new Set(tomorrowTasks.map((task) => `${task.name.trim().toLowerCase()}|${task.points}|${task.reminderTime || ''}`));
      const additions = tasksDueToday.filter((task) => !tomorrowKeys.has(`${task.name.trim().toLowerCase()}|${task.points}|${task.reminderTime || ''}`));
      if (!additions.length) return;
      await transaction('customTasks', 'readwrite', (tx) => {
        const store = tx.objectStore('customTasks');
        const nextSortOrder = tomorrowTasks.length;
        additions.forEach((task, index) => {
          store.add({
            date: tomorrow,
            name: task.name,
            points: task.points,
            completed: false,
            sortOrder: nextSortOrder + index,
            reminderTime: task.reminderTime || '',
          });
        });
      });
    },
    async getDay(date) {
      const habits = sortHabits(await all('habits'));
      const logs = await all('logs');
      const customTasks = sortTasks((await all('customTasks')).filter((task) => task.date === date));
      const completed = new Map(logs.filter((log) => log.date === date).map((log) => [log.habitId, !!log.completed]));
      return { habits: habits.map((habit) => ({ ...habit, completed: completed.get(habit.id) || false })), customTasks };
    },
    async toggleHabit(date, id, completed) {
      return transaction('logs', 'readwrite', (tx) => tx.objectStore('logs').put({ key: `${date}:${id}`, date, habitId: id, completed }));
    },
    async toggleCustom(id, completed) {
      return transaction('customTasks', 'readwrite', (tx) => {
        const store = tx.objectStore('customTasks');
        const request = store.get(id);
        request.onsuccess = () => { const task = request.result; if (task) store.put({ ...task, completed }); };
      });
    },
    async addHabit(name, points) {
      const habits = await all('habits');
      return transaction('habits', 'readwrite', (tx) => new Promise((resolve) => {
        const request = tx.objectStore('habits').add({ name, points, sortOrder: habits.length });
        request.onsuccess = () => resolve(request.result);
      }));
    },
    async updateHabit(id, name, points) {
      return transaction('habits', 'readwrite', (tx) => {
        const store = tx.objectStore('habits'); const request = store.get(id);
        request.onsuccess = () => { const habit = request.result; if (habit) store.put({ ...habit, name, points }); };
      });
    },
    async deleteHabit(id) {
      return transaction(['habits', 'logs'], 'readwrite', (tx) => {
        const habits = tx.objectStore('habits');
        const logs = tx.objectStore('logs');
        const habitRequest = habits.get(id);
        habitRequest.onsuccess = () => {
          if (habitRequest.result) habits.delete(id);
        };
        const logRequest = logs.getAll();
        logRequest.onsuccess = () => {
          logRequest.result.filter((log) => log.habitId === id).forEach((log) => logs.delete(log.key));
        };
      });
    },
    async reorderHabits(ids) {
      return transaction('habits', 'readwrite', (tx) => {
        const store = tx.objectStore('habits');
        ids.forEach((id, sortOrder) => { const request = store.get(id); request.onsuccess = () => { const item = request.result; if (item) store.put({ ...item, sortOrder }); }; });
      });
    },
    async addCustom(date, name, points, reminderTime = '') {
      const tasks = (await all('customTasks')).filter((task) => task.date === date);
      return transaction('customTasks', 'readwrite', (tx) => new Promise((resolve) => {
        const request = tx.objectStore('customTasks').add({ date, name, points, completed: false, sortOrder: tasks.length, reminderTime });
        request.onsuccess = () => resolve(request.result);
      }));
    },
    async updateCustom(id, name, points, reminderTime) {
      return transaction('customTasks', 'readwrite', (tx) => {
        const store = tx.objectStore('customTasks'); const request = store.get(id);
        request.onsuccess = () => { const task = request.result; if (task) store.put({ ...task, name, points, reminderTime: reminderTime ?? task.reminderTime ?? '' }); };
      });
    },
    async deleteCustom(id) {
      return transaction('customTasks', 'readwrite', (tx) => tx.objectStore('customTasks').delete(id));
    },
    async reorderCustom(ids) {
      return transaction('customTasks', 'readwrite', (tx) => {
        const store = tx.objectStore('customTasks');
        ids.forEach((id, sortOrder) => { const request = store.get(id); request.onsuccess = () => { const item = request.result; if (item) store.put({ ...item, sortOrder }); }; });
      });
    },
    async addMoney(entry) {
      await removeExpiredMoney();
      return transaction('moneyTransactions', 'readwrite', (tx) => new Promise((resolve) => {
        const request = tx.objectStore('moneyTransactions').add({
          date: entry.date,
          category: entry.category,
          account: entry.account,
          direction: entry.direction,
          amount: entry.amount,
          note: entry.note || '',
          createdAt: Date.now(),
        });
        request.onsuccess = () => resolve(request.result);
      }));
    },
    async deleteMoney(id) {
      return transaction('moneyTransactions', 'readwrite', (tx) => tx.objectStore('moneyTransactions').delete(id));
    },
    async getMoney() {
      await removeExpiredMoney();
      return (await all('moneyTransactions')).sort((a, b) => b.date.localeCompare(a.date) || b.id - a.id);
    },
    async getHistory() {
      const habits = await all('habits'); const logs = await all('logs'); const tasks = await all('customTasks');
      const fixedPoints = habits.reduce((sum, habit) => sum + habit.points, 0);
      const dates = new Set([...logs, ...tasks].map((item) => item.date));
      const history = [...dates].sort().map((date) => {
        const earnedFixed = logs.filter((log) => log.date === date && log.completed).reduce((sum, log) => sum + (habits.find((habit) => habit.id === log.habitId)?.points || 0), 0);
        const dayTasks = tasks.filter((task) => task.date === date);
        const earnedCustom = dayTasks.filter((task) => task.completed).reduce((sum, task) => sum + task.points, 0);
        const totalCustom = dayTasks.reduce((sum, task) => sum + task.points, 0);
        const possible = fixedPoints + totalCustom; const earned = earnedFixed + earnedCustom;
        return { date, earned, possible, pct: possible ? Math.round(earned / possible * 100) : 0 };
      });
      return { history, totalPossibleFixed: fixedPoints };
    },
  };
})();
