# Daily Discipline Tracker

Daily Discipline is a local habit and money tracker built for one user.
The app runs as a static web app in the browser or as an Android wrapper, and
it stores all data on-device with IndexedDB rather than sending anything to a
server.

## Features

- **Today:** track recurring habits, add one-off tasks, assign points, and
  see the score ring update immediately.
- **Reminders:** schedule a notification time for a custom task in the browser
  or Android app.
- **Dashboard:** review streaks, days logged, personal best, average score,
  and a month calendar.
- **Money ledger:** track cash, bKash, and bank movement by category.
- **Loans:** record loans given and taken to named people, then filter the
  transaction list by the open loan account.
- **Backup and restore:** export the full IndexedDB dataset to JSON and restore
  it later on the same or another device.
- **Installable PWA:** the app can be installed and used offline in supported
  browsers or the Android package.

## Requirements

For browser development:

- [Node.js](https://nodejs.org) 22.13.0 or newer
- npm

For the APK build:

- Java 17 or newer
- Android SDK with platform `android-35` and build-tools `35.0.0`

## Run In A Browser

```powershell
npm install
npm start
```

Then open http://localhost:3000 in your browser. Use `PORT=4000 npm start` if
port 3000 is already occupied.

## Build The Android APK

```powershell
npm install
npm run build:android
```

The output is saved as `DailyDiscipline.apk` in the project root. Install it
with ADB:

```powershell
adb install -r .\DailyDiscipline.apk
```

The first build also creates a local signing key at
`android/daily-discipline.keystore`. Keep that file if you want to continue
publishing updates over the same app installation.

## Connect A Phone For Development

```powershell
npm start
npm run deploy:android
```

This serves the current browser version on http://localhost:3000 for USB
connection testing. For Wi‑Fi debugging, run:

```powershell
npm start
npm run deploy:wifi -- -Device ip:port
```

Replace `ip:port` with the device address shown in Android wireless debugging.

## How The App Works

- The browser app lives in `public/` and uses plain HTML, CSS, and JavaScript.
- Data is stored in IndexedDB through `public/storage.js`.
- `server.js` only serves the static files for local development.
- The Android project wraps the same `public/` app in a WebView and uses the
  Android document picker for backup/restore.

## User Manual

### Daily habits

1. Open **Today** and choose a date if you are logging a previous day.
2. Tick a habit when it is complete; the seal and totals update immediately.
3. Add a custom task, assign points, and choose **Repeat daily** for recurring
   work.
4. Use **Edit**, drag handles, and the remove control to manage the lists.

### Dashboard

Open **Dashboard** to review the current streak, average score, personal best,
and the monthly calendar. Unworked days are shown in gray.

### Money and loans

1. Open **Money** and choose the date, category, account, and amount.
2. Use **Reduce** for money spent and **Add** for money received.
3. For a loan, enter the other person's name in the note field. The app
   calculates each person's open loan balance automatically.
4. Click a loan name to filter the ledger to that person.
5. Use **Undo** beside a transaction to remove that single entry and recalculate
   balances.

### Backup and restore

Select **Backup** to save a JSON export. Select **Restore** and choose a file
from the device to replace the current IndexedDB data. Only restore a backup
that you trust.

## Data And Privacy

This project stores habits, tasks, history, money movements, and loan records
in IndexedDB on the device. There is no login system, no remote database, and
no cloud sync in the default app flow.

## Development Notes

The web app is intentionally lightweight and dependency-driven. The project
keeps the browser frontend and Android wrapper in sync by packaging the same
`public/` directory into both the browser and APK flows.
