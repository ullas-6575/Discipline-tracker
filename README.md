# Daily Discipline Tracker

Daily Discipline is a local habit and money tracker for Android, built with Flutter. It keeps habits, tasks, history, and money records on the device. The Flutter project contains only the Android app; it has no browser, Linux, Windows, or other platform version.

## Features

- **Today:** track recurring habits and one-off tasks, assign points, and see the completion score update immediately.
- **Reminders:** schedule Android notifications for one-off tasks.
- **Dashboard:** review streaks, days logged, personal best, average score, and a monthly calendar.
- **Money ledger:** track cash, bKash, and bank transactions by category.
- **Loans:** record loans given to and taken from named people, see open balances, and filter transactions by person.
- **Backup and restore:** export app data as JSON and restore it on this or another device.
- **Local storage:** app data stays on-device; there is no account, server, or cloud sync.

## Requirements

- Flutter SDK 3.24 or newer
- Java 17 or newer
- Android SDK with Android platform 35
- Android NDK 26.1.10909125 recommended by the notification and file plugins

## Run on Android

From the repository root:

```sh
flutter pub get
flutter run
```

## Build the Android APK

```sh
flutter build apk --release
```

The APK is created at `build/app/outputs/flutter-apk/app-release.apk`.

## User Manual

### Daily habits

1. Open **Today** and choose a date if you are logging a previous day.
2. Tick a habit when it is complete; the score ring and totals update immediately.
3. Add a task, assign points, and choose **Repeat daily** to make it a recurring habit.
4. Use the task menu to edit or remove items. Drag a task to reorder the list.
5. For a one-off task, enable **Reminder** and select a notification time.

### Dashboard

Open **Dashboard** to review your current streak, average score, personal best, and monthly calendar. Gray days have no logged work. Select a calendar day to view its tasks on the **Today** screen.

### Money and loans

1. Open **Money**, add a transaction, and choose its date, category, account, movement, and amount.
2. Use **Reduce** for money spent and **Add** for money received.
3. For a loan, enter the other person's name. The app calculates each person's open balance automatically.
4. Select an open loan to filter the transaction list by that person.
5. Use the undo control beside a transaction to remove that entry and recalculate balances.

### Backup and restore

Open the top-right menu and choose **Backup** to share or save a JSON export. Choose **Restore** and select a backup file to replace the current app data. Restore a backup only if you trust it.

To move data from the previous Android app, export its JSON backup before uninstalling it, then restore that file in Flutter. The previous wrapper signing key is not included, so remove the old app after exporting the backup and before installing this APK.

## Data and Privacy

The app stores habits, tasks, completion history, reminders, and money transactions locally using Android shared preferences. Non-loan money transactions older than seven days are removed. Loan records are kept until you remove them. There is no login, remote database, or cloud sync.

## Development Notes

The Flutter source is in `lib/`, and the Android app project is in `android/`. The application ID is `com.dailydiscipline.tracker`. Only the Android runner is generated and maintained in this repository.
