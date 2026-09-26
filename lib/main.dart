import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const ink = Color(0xff14181f),
    paper = Color(0xff1b212a),
    raised = Color(0xff212834);
const gold = Color(0xffd9a441),
    cream = Color(0xfff2ede3),
    mist = Color(0xff8d97a6);
final notificationPlugin = FlutterLocalNotificationsPlugin();
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await notificationPlugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  runApp(const DisciplineApp());
}

class DisciplineApp extends StatelessWidget {
  const DisciplineApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Discipline Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: ink,
          colorScheme: ColorScheme.fromSeed(
              seedColor: gold, brightness: Brightness.dark, surface: paper),
          appBarTheme:
              const AppBarTheme(backgroundColor: ink, foregroundColor: cream),
          cardTheme: const CardTheme(
              color: paper, margin: EdgeInsets.only(bottom: 10)),
          inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: raised,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none)),
          navigationBarTheme: NavigationBarThemeData(
              backgroundColor: paper, indicatorColor: gold.withOpacity(.2))),
      home: const TrackerHome());
}

class TrackerHome extends StatefulWidget {
  const TrackerHome({super.key});
  @override
  State<TrackerHome> createState() => _TrackerHomeState();
}

class _TrackerHomeState extends State<TrackerHome> {
  Map<String, dynamic> db = {
    'habits': <dynamic>[],
    'logs': <dynamic>[],
    'customTasks': <dynamic>[],
    'moneyTransactions': <dynamic>[]
  };
  DateTime selected = DateTime.now(), month = DateTime.now();
  int tab = 0, nextId = 1;
  bool ready = false;
  String? loanFilter;
  List<Map<String, dynamic>> get habits =>
      (db['habits'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get logs =>
      (db['logs'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get tasks =>
      (db['customTasks'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get money =>
      (db['moneyTransactions'] as List).cast<Map<String, dynamic>>();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tracker_data');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map;
        db = decoded.map((k, v) => MapEntry(
            k,
            v is List
                ? v.map((e) => Map<String, dynamic>.from(e)).toList()
                : v));
        nextId = _allIds().fold<int>(0, (a, b) => a > b ? a : b) + 1;
      } catch (_) {}
    }
    final today = dayKey(DateTime.now()),
        tomorrow = dayKey(DateTime.now().add(const Duration(days: 1)));
    final due = tasks
        .where((x) => x['date'] == today && x['completed'] != true)
        .toList();
    final keys =
        tasks.where((x) => x['date'] == tomorrow).map(_taskKey).toSet();
    for (final task in due) {
      if (keys.add(_taskKey(task))) {
        tasks.add({
          'id': nextId++,
          'date': tomorrow,
          'name': task['name'],
          'points': task['points'],
          'completed': false,
          'sortOrder': tasks.where((x) => x['date'] == tomorrow).length,
          'reminderTime': task['reminderTime'] ?? ''
        });
      }
    }
    final oldCount = money.length,
        cutoff = dayKey(DateTime.now().subtract(const Duration(days: 6)));
    money.removeWhere((x) =>
        !['loan-given', 'loan-taken'].contains(x['category']) &&
        (x['date'] as String).compareTo(cutoff) < 0);
    if (due.isNotEmpty || oldCount != money.length) {
      await prefs.setString('tracker_data', jsonEncode(db));
    }
    if (mounted) setState(() => ready = true);
  }

  String _taskKey(Map<String, dynamic> x) =>
      '${(x['name'] as String).trim().toLowerCase()}|${x['points']}|${x['reminderTime'] ?? ''}';
  List<int> _allIds() => [...habits, ...tasks, ...money]
      .map((e) => (e['id'] as num?)?.toInt() ?? 0)
      .toList();
  int _points(String raw) {
    final value = int.tryParse(raw) ?? 1;
    return value < 1 ? 1 : value;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('tracker_data', jsonEncode(db));
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get dayHabits {
    final done = {
      for (final l in logs.where((x) => x['date'] == dayKey(selected)))
        l['habitId']: l['completed'] == true
    };
    final out = habits
        .map((x) => {...x, 'completed': done[x['id']] == true})
        .toList()
      ..sort((a, b) => ((a['sortOrder'] ?? 0) as num)
          .compareTo((b['sortOrder'] ?? 0) as num));
    return out;
  }

  List<Map<String, dynamic>> get dayTasks => tasks
      .where((x) => x['date'] == dayKey(selected))
      .toList()
    ..sort((a, b) =>
        ((a['sortOrder'] ?? 0) as num).compareTo((b['sortOrder'] ?? 0) as num));
  int get possible => [...dayHabits, ...dayTasks]
      .fold(0, (s, x) => s + ((x['points'] ?? 1) as num).toInt());
  int get earned => [...dayHabits, ...dayTasks]
      .where((x) => x['completed'] == true)
      .fold(0, (s, x) => s + ((x['points'] ?? 1) as num).toInt());
  int get pct => possible == 0 ? 0 : (earned * 100 / possible).round();
  List<Map<String, dynamic>> get history {
    final dates = <String>{
      ...logs.map((x) => x['date'] as String),
      ...tasks.map((x) => x['date'] as String)
    };
    return dates.map((date) {
      final done =
          logs.where((x) => x['date'] == date && x['completed'] == true);
      final fixed = done.fold(0, (s, x) {
        final h = habits.where((v) => v['id'] == x['habitId']);
        return s + (h.isEmpty ? 0 : (h.first['points'] as num).toInt());
      });
      final day = tasks.where((x) => x['date'] == date).toList();
      final got = fixed +
          day
              .where((x) => x['completed'] == true)
              .fold(0, (s, x) => s + (x['points'] as num).toInt());
      final max = habits.fold(0, (s, x) => s + (x['points'] as num).toInt()) +
          day.fold(0, (s, x) => s + (x['points'] as num).toInt());
      return {
        'date': date,
        'earned': got,
        'possible': max,
        'pct': max == 0 ? 0 : (got * 100 / max).round()
      };
    }).toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  }

  Future<void> addHabit(String name, int points) async {
    habits.add({
      'id': nextId++,
      'name': name,
      'points': points,
      'sortOrder': habits.length
    });
    await save();
  }

  Future<void> addTask(String name, int points,
      {bool daily = false, String reminder = ''}) async {
    if (daily) {
      await addHabit(name, points);
      return;
    }
    final task = <String, dynamic>{
      'id': nextId++,
      'date': dayKey(selected),
      'name': name,
      'points': points,
      'completed': false,
      'sortOrder': dayTasks.length,
      'reminderTime': reminder
    };
    tasks.add(task);
    if (reminder.isNotEmpty) await _schedule(task);
    await save();
  }

  Future<void> _schedule(Map<String, dynamic> task) async {
    final id = (task['id'] as num).toInt();
    await notificationPlugin.cancel(id);
    final value = (task['reminderTime'] ?? '').toString();
    if (value.isEmpty) return;
    final hm = value.split(':'), d = DateTime.parse(task['date'] as String);
    final when =
        DateTime(d.year, d.month, d.day, int.parse(hm[0]), int.parse(hm[1]));
    if (!when.isAfter(DateTime.now())) return;
    final android = notificationPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await notificationPlugin.zonedSchedule(
        id,
        'Daily Discipline',
        task['name'] as String,
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(
            android: AndroidNotificationDetails(
                'task-reminders', 'Task reminders',
                channelDescription: 'Task reminders')),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime);
  }

  Future<void> toggle(Map<String, dynamic> x, bool habit, bool value) async {
    if (habit) {
      logs.removeWhere(
          (l) => l['date'] == dayKey(selected) && l['habitId'] == x['id']);
      logs.add({
        'key': '${dayKey(selected)}:${x['id']}',
        'date': dayKey(selected),
        'habitId': x['id'],
        'completed': value
      });
    } else {
      x['completed'] = value;
    }
    await save();
  }

  Future<void> reorder(List<Map<String, dynamic>> items, bool fixed,
      int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final next = [...items], item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    for (var i = 0; i < next.length; i++) {
      final source = fixed
          ? habits.firstWhere((x) => x['id'] == next[i]['id'])
          : tasks.firstWhere((x) => x['id'] == next[i]['id']);
      source['sortOrder'] = i;
    }
    await save();
  }

  Future<void> editTask(Map<String, dynamic> x, bool fixed) async {
    final name = TextEditingController(text: x['name']),
        points = TextEditingController(text: '${x['points']}');
    bool remind = (x['reminderTime'] ?? '').toString().isNotEmpty;
    final p = (x['reminderTime'] ?? '09:00').toString().split(':');
    TimeOfDay time = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, setD) => AlertDialog(
                    title: Text(fixed ? 'Edit habit' : 'Edit task'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Name')),
                      TextField(
                          controller: points,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Points')),
                      if (!fixed)
                        SwitchListTile(
                            value: remind,
                            onChanged: (v) => setD(() => remind = v),
                            title: const Text('Reminder')),
                      if (!fixed && remind)
                        TextButton.icon(
                            onPressed: () async {
                              final t = await showTimePicker(
                                  context: c, initialTime: time);
                              if (t != null) setD(() => time = t);
                            },
                            icon: const Icon(Icons.alarm),
                            label: Text(time.format(c)))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Save'))
                    ])));
    if (ok == true && name.text.trim().isNotEmpty) {
      x['name'] = name.text.trim();
      x['points'] = _points(points.text);
      if (!fixed) {
        x['reminderTime'] = remind
            ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
            : '';
        await _schedule(x);
      }
      await save();
    }
  }

  Future<void> taskDialog() async {
    final name = TextEditingController(),
        points = TextEditingController(text: '1');
    bool daily = false, remind = false;
    TimeOfDay time = const TimeOfDay(hour: 9, minute: 0);
    await showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, setD) => AlertDialog(
                    title: const Text('Add task'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'Task name')),
                      TextField(
                          controller: points,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Points')),
                      SwitchListTile(
                          value: daily,
                          onChanged: (v) => setD(() => daily = v),
                          title: const Text('Repeat daily')),
                      if (!daily)
                        SwitchListTile(
                            value: remind,
                            onChanged: (v) => setD(() => remind = v),
                            title: const Text('Reminder')),
                      if (!daily && remind)
                        TextButton.icon(
                            onPressed: () async {
                              final t = await showTimePicker(
                                  context: c, initialTime: time);
                              if (t != null) setD(() => time = t);
                            },
                            icon: const Icon(Icons.alarm),
                            label: Text(time.format(c)))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            if (name.text.trim().isEmpty) return;
                            addTask(name.text.trim(), _points(points.text),
                                daily: daily,
                                reminder: remind
                                    ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
                                    : '');
                            Navigator.pop(c);
                          },
                          child: const Text('Add'))
                    ])));
  }

  Future<void> moneyDialog() async {
    final amount = TextEditingController(), note = TextEditingController();
    String category = 'eat', account = 'cash', direction = 'out';
    DateTime date = selected;
    await showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, setD) => AlertDialog(
                    title: const Text('Add transaction'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Date'),
                          subtitle: Text(dayKey(date)),
                          leading: const Icon(Icons.calendar_today),
                          onTap: () async {
                            final d = await showDatePicker(
                                context: c,
                                initialDate: date,
                                firstDate: DateTime(2010),
                                lastDate: DateTime(2100));
                            if (d != null) setD(() => date = d);
                          }),
                      DropdownButtonFormField<String>(
                          value: category,
                          decoration:
                              const InputDecoration(labelText: 'Category'),
                          items: const [
                            DropdownMenuItem(value: 'eat', child: Text('Food')),
                            DropdownMenuItem(
                                value: 'payment', child: Text('Payment')),
                            DropdownMenuItem(
                                value: 'others', child: Text('Others')),
                            DropdownMenuItem(
                                value: 'loan-given',
                                child: Text('Loans given')),
                            DropdownMenuItem(
                                value: 'loan-taken', child: Text('Loans taken'))
                          ],
                          onChanged: (v) => setD(() => category = v!)),
                      DropdownButtonFormField<String>(
                          value: account,
                          decoration:
                              const InputDecoration(labelText: 'Account'),
                          items: const [
                            DropdownMenuItem(
                                value: 'cash', child: Text('Cash')),
                            DropdownMenuItem(
                                value: 'bkash', child: Text('bKash')),
                            DropdownMenuItem(value: 'bank', child: Text('Bank'))
                          ],
                          onChanged: (v) => setD(() => account = v!)),
                      if (!category.startsWith('loan-'))
                        DropdownButtonFormField<String>(
                            value: direction,
                            decoration:
                                const InputDecoration(labelText: 'Movement'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'out', child: Text('Reduce')),
                              DropdownMenuItem(value: 'in', child: Text('Add'))
                            ],
                            onChanged: (v) => setD(() => direction = v!)),
                      TextField(
                          controller: amount,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              const InputDecoration(labelText: 'Amount')),
                      TextField(
                          controller: note,
                          maxLength: 80,
                          decoration: InputDecoration(
                              labelText: category.startsWith('loan-')
                                  ? 'Person name (required)'
                                  : 'Note (optional)'))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            final value = double.tryParse(amount.text) ?? 0;
                            if (value <= 0 ||
                                (category.startsWith('loan-') &&
                                    note.text.trim().isEmpty)) return;
                            money.add({
                              'id': nextId++,
                              'date': dayKey(date),
                              'category': category,
                              'account': account,
                              'direction': category == 'loan-given'
                                  ? 'out'
                                  : category == 'loan-taken'
                                      ? 'in'
                                      : direction,
                              'amount': value,
                              'note': note.text.trim(),
                              'createdAt': DateTime.now().millisecondsSinceEpoch
                            });
                            save();
                            Navigator.pop(c);
                          },
                          child: const Text('Add'))
                    ])));
  }

  Future<void> backup() async {
    final data = {
      'format': 'daily-discipline-backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'habits': habits,
      'logs': logs,
      'customTasks': tasks,
      'moneyTransactions': money
    };
    await Share.shareXFiles([
      XFile.fromData(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
          mimeType: 'application/json',
          name: 'daily-discipline-backup-${dayKey(DateTime.now())}.json')
    ]);
  }

  Future<void> restore() async {
    final f = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: true);
    if (f == null || !mounted) return;
    try {
      final d = jsonDecode(utf8.decode(f.files.single.bytes!))
          as Map<String, dynamic>;
      if (d['format'] != 'daily-discipline-backup' ||
          d['habits'] is! List ||
          d['logs'] is! List ||
          d['customTasks'] is! List) throw const FormatException();
      final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Restore backup?'),
                  content: const Text('Current phone data will be replaced.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Restore'))
                  ]));
      if (ok != true) return;
      db = {
        'habits': (d['habits'] as List)
            .map((x) => Map<String, dynamic>.from(x))
            .toList(),
        'logs': (d['logs'] as List)
            .map((x) => Map<String, dynamic>.from(x))
            .toList(),
        'customTasks': (d['customTasks'] as List)
            .map((x) => Map<String, dynamic>.from(x))
            .toList(),
        'moneyTransactions': ((d['moneyTransactions'] ?? []) as List)
            .map((x) => Map<String, dynamic>.from(x))
            .toList()
      };
      nextId = _allIds().fold<int>(0, (a, b) => a > b ? a : b) + 1;
      await save();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not restore this backup.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
        appBar: AppBar(
            title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('◈  Discipline Tracker',
                      style: TextStyle(
                          fontFamily: 'serif', fontWeight: FontWeight.w700)),
                  Text('a ledger of small, kept promises',
                      style: TextStyle(
                          color: mist,
                          fontSize: 11,
                          fontStyle: FontStyle.italic))
                ]),
            actions: [
              PopupMenuButton<String>(
                  onSelected: (v) => v == 'backup' ? backup() : restore(),
                  itemBuilder: (_) => const [
                        PopupMenuItem(value: 'backup', child: Text('Backup')),
                        PopupMenuItem(value: 'restore', child: Text('Restore'))
                      ])
            ]),
        body: [_today(), _dashboard(), _moneyPage()][tab],
        bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (v) => setState(() => tab = v),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.check_circle_outline), label: 'Today'),
              NavigationDestination(
                  icon: Icon(Icons.insights_outlined), label: 'Dashboard'),
              NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  label: 'Money')
            ]));
  }

  Widget _today() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Viewing', style: TextStyle(color: mist)),
                          TextButton.icon(
                              onPressed: () async {
                                final d = await showDatePicker(
                                    context: context,
                                    initialDate: selected,
                                    firstDate: DateTime(2010),
                                    lastDate: DateTime(2100));
                                if (d != null) setState(() => selected = d);
                              },
                              icon: const Icon(Icons.calendar_month),
                              label: Text(dayKey(selected))),
                        ]),
                    const SizedBox(height: 8),
                    SizedBox(
                        width: 170,
                        height: 170,
                        child: Stack(alignment: Alignment.center, children: [
                          SizedBox.expand(
                              child: CircularProgressIndicator(
                                  value: possible == 0 ? 0 : earned / possible,
                                  strokeWidth: 10,
                                  backgroundColor: raised,
                                  strokeCap: StrokeCap.round,
                                  color: pct >= 90
                                      ? const Color(0xff6f9e78)
                                      : pct >= 60
                                          ? gold
                                          : pct >= 30
                                              ? const Color(0xffc98a4c)
                                              : const Color(0xffb5533c))),
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('$pct%',
                                style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace')),
                            Text('$earned / $possible pts',
                                style: const TextStyle(color: mist)),
                          ]),
                        ])),
                    const SizedBox(height: 8),
                    Text(
                        pct >= 100
                            ? 'Day sealed. Well kept.'
                            : pct >= 95
                                ? 'Almost a perfect ledger.'
                                : pct >= 75
                                    ? 'The frog is nearly eaten.'
                                    : pct >= 50
                                        ? 'Halfway to the seal.'
                                        : pct >= 25
                                            ? 'Small steps, kept.'
                                            : 'Begin the day.',
                        style: const TextStyle(
                            color: mist, fontStyle: FontStyle.italic)),
                  ]))),
          _section('Daily tasks'),
          if (dayHabits.isEmpty) const _Empty('Add your first daily task.'),
          _sortable(dayHabits, true),
          _section('Today’s tasks'),
          if (dayTasks.isEmpty) const _Empty('No one-off tasks for this day.'),
          _sortable(dayTasks, false),
          FilledButton.icon(
              onPressed: taskDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add a task')),
        ],
      );

  Widget _sortable(List<Map<String, dynamic>> items, bool fixed) =>
      ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (a, b) => reorder(items, fixed, a, b),
          children: [
            for (var i = 0; i < items.length; i++)
              ReorderableDelayedDragStartListener(
                  key: ValueKey('${fixed ? 'h' : 't'}-${items[i]['id']}'),
                  index: i,
                  child: _taskTile(items[i], fixed))
          ]);
  Widget _taskTile(Map<String, dynamic> x, bool fixed) => Card(
        key: ValueKey('tile-${fixed ? 'h' : 't'}-${x['id']}'),
        child: ListTile(
          leading: Checkbox(
              value: x['completed'] == true,
              activeColor: gold,
              onChanged: (v) => toggle(x, fixed, v ?? false)),
          title: Text('${x['name']}',
              style: TextStyle(
                  decoration: x['completed'] == true
                      ? TextDecoration.lineThrough
                      : null)),
          subtitle: Text(
              '${x['points']} pt${x['points'] == 1 ? '' : 's'}${!fixed && (x['reminderTime'] ?? '').toString().isNotEmpty ? ' · ⏰ ${x['reminderTime']}' : ''}',
              style: const TextStyle(color: mist)),
          trailing: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') await editTask(x, fixed);
              if (value == 'delete') {
                if (fixed) {
                  habits.removeWhere((h) => h['id'] == x['id']);
                  logs.removeWhere((l) => l['habitId'] == x['id']);
                } else {
                  await notificationPlugin.cancel((x['id'] as num).toInt());
                  tasks.removeWhere((task) => task['id'] == x['id']);
                }
                await save();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Remove'))
            ],
          ),
        ),
      );

  Widget _dashboard() {
    final records = history;
    final scores = records.map((x) => (x['pct'] as num).toInt()).toList();
    final byDate = {for (final record in records) record['date']: record};
    var streak = 0;
    var cursor = selected;
    while (byDate[dayKey(cursor)] != null &&
        (byDate[dayKey(cursor)]?['pct'] as num) >= 86) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    final average = scores.isEmpty
        ? 0
        : (scores.reduce((a, b) => a + b) / scores.length).round();
    final best = scores.isEmpty ? 0 : scores.reduce((a, b) => a > b ? a : b);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        _stat('$streak', 'day streak'),
        _stat('${records.length}', 'days logged'),
        _stat('$best%', 'personal best'),
        _stat('$average%', 'avg. score'),
      ]),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                          onPressed: () => setState(() =>
                              month = DateTime(month.year, month.month - 1)),
                          icon: const Icon(Icons.chevron_left)),
                      Text('${_month(month.month)} ${month.year}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      IconButton(
                          onPressed: () => setState(() =>
                              month = DateTime(month.year, month.month + 1)),
                          icon: const Icon(Icons.chevron_right)),
                    ]),
                const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('S'),
                      Text('M'),
                      Text('T'),
                      Text('W'),
                      Text('T'),
                      Text('F'),
                      Text('S')
                    ]),
                const SizedBox(height: 10),
                _calendar(byDate),
              ]))),
    ]);
  }

  Widget _calendar(Map byDate) {
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday % 7;
    final count = DateTime(month.year, month.month + 1, 0).day;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7, mainAxisSpacing: 7, crossAxisSpacing: 7),
      itemCount: offset + count,
      itemBuilder: (context, index) {
        if (index < offset) return const SizedBox();
        final day = index - offset + 1;
        final date = dayKey(DateTime(month.year, month.month, day));
        final score = byDate[date]?['pct'] as num?;
        final color = score == null || score <= 0
            ? const Color(0xff8f949b)
            : score < 25
                ? const Color(0xff9bb89e)
                : score < 50
                    ? const Color(0xff78a77f)
                    : score < 75
                        ? const Color(0xff568f63)
                        : score < 90
                            ? const Color(0xff3c7b4f)
                            : const Color(0xff28633c);
        return InkWell(
          onTap: () =>
              setState(() => selected = DateTime(month.year, month.month, day)),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: date == dayKey(selected)
                    ? Border.all(color: gold, width: 2)
                    : null),
            child: Text('$day',
                style: TextStyle(
                    color: score != null && score >= 60 ? cream : ink)),
          ),
        );
      },
    );
  }

  Widget _moneyPage() {
    final spent = money
            .where((x) => x['direction'] == 'out')
            .fold(0.0, (s, x) => s + (x['amount'] as num).toDouble()),
        added = money
            .where((x) => x['direction'] == 'in')
            .fold(0.0, (s, x) => s + (x['amount'] as num).toDouble());
    final loans = <String, double>{};
    for (final x in money.where((x) =>
        x['category'] == 'loan-given' || x['category'] == 'loan-taken')) {
      final n = (x['note'] ?? '').toString().trim();
      loans[n] = (loans[n] ?? 0) +
          (x['category'] == 'loan-given' ? 1 : -1) *
              (x['amount'] as num).toDouble();
    }
    final open = loans.entries.where((e) => e.value.abs() > .005).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final visible = money
        .where((x) =>
            loanFilter == null ||
            (x['note'] ?? '').toString().trim() == loanFilter)
        .toList()
      ..sort((a, b) {
        final d = (b['date'] as String).compareTo(a['date'] as String);
        return d != 0
            ? d
            : ((b['id'] as num?)?.toInt() ?? 0)
                .compareTo((a['id'] as num?)?.toInt() ?? 0);
      });
    final accounts = {
      for (final a in ['cash', 'bkash', 'bank'])
        a: money.where((x) => x['account'] == a).fold(
            0.0,
            (s, x) =>
                s +
                (x['direction'] == 'in' ? 1 : -1) *
                    (x['amount'] as num).toDouble())
    };
    final acMax =
        accounts.values.fold(1.0, (m, v) => m > v.abs() ? m : v.abs());
    final cats = {
      'eat': money
          .where((x) => x['category'] == 'eat' && x['direction'] == 'out')
          .fold(0.0, (s, x) => s + (x['amount'] as num).toDouble()),
      'payment': money
          .where((x) => x['category'] == 'payment' && x['direction'] == 'out')
          .fold(0.0, (s, x) => s + (x['amount'] as num).toDouble()),
      'others': money
          .where((x) => x['category'] == 'others' && x['direction'] == 'out')
          .fold(0.0, (s, x) => s + (x['amount'] as num).toDouble()),
      'loan-given':
          open.where((x) => x.value > 0).fold(0.0, (s, x) => s + x.value),
      'loan-taken':
          open.where((x) => x.value < 0).fold(0.0, (s, x) => s + x.value.abs())
    };
    final catMax = cats.values.fold(1.0, (m, v) => m > v ? m : v);
    final net = added - spent;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Personal ledger',
          style: TextStyle(color: gold, letterSpacing: 1.4, fontSize: 11)),
      const Text('Money dashboard',
          style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.bold, fontFamily: 'serif')),
      const SizedBox(height: 12),
      FilledButton.icon(
          onPressed: moneyDialog,
          icon: const Icon(Icons.add),
          label: const Text('Add transaction')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _stat(_bdt(spent), 'total spent'),
        _stat(_bdt(added), 'total added'),
        _stat(_bdt(net), 'net balance')
      ]),
      _section('Account balances'),
      ...accounts.entries.map((e) => _moneyRow(
          _label(e.key), e.value, e.value.abs() / acMax,
          negative: e.value < 0)),
      _section('By category'),
      ...cats.entries
          .map((e) => _moneyRow(_label(e.key), e.value, e.value / catMax)),
      _section('Open loans'),
      if (open.isEmpty) const _Empty('No open loan accounts.'),
      ...open.map((e) => Card(
          child: ListTile(
              title: Text(e.key),
              subtitle: Text(e.value > 0 ? 'You lent' : 'You owe'),
              trailing: Text(_bdt(e.value),
                  style:
                      TextStyle(color: e.value < 0 ? Colors.redAccent : gold)),
              selected: loanFilter == e.key,
              onTap: () => setState(
                  () => loanFilter = loanFilter == e.key ? null : e.key)))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _section('Transactions'),
        if (loanFilter != null)
          TextButton(
              onPressed: () => setState(() => loanFilter = null),
              child: const Text('Clear filter'))
      ]),
      Text(
          '${visible.length} ${visible.length == 1 ? 'entry' : 'entries'}${loanFilter == null ? '' : ' · $loanFilter'}',
          style: const TextStyle(color: mist)),
      if (visible.isEmpty) const _Empty('No transactions yet.'),
      ...visible.map((x) => Card(
          child: ListTile(
              title: Text(_label(x['category'] as String)),
              subtitle: Text(
                  '${x['date']} · ${_label(x['account'] as String)}${(x['note'] ?? '').toString().isEmpty ? '' : ' · ${x['note']}'}'),
              leading: Icon(
                  x['direction'] == 'in' ? Icons.south_west : Icons.north_east,
                  color: x['direction'] == 'in'
                      ? const Color(0xff6f9e78)
                      : const Color(0xffb5533c)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    '${x['direction'] == 'in' ? '+' : '−'}${_bdt((x['amount'] as num).toDouble())}'),
                IconButton(
                    tooltip: 'Undo',
                    onPressed: () async {
                      money.removeWhere((m) => m['id'] == x['id']);
                      await save();
                    },
                    icon: const Icon(Icons.undo, size: 20))
              ]))))
    ]);
  }

  Widget _moneyRow(String label, double value, double fraction,
          {bool negative = false}) =>
      Card(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              child: Column(children: [
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    trailing: Text(_bdt(value),
                        style: TextStyle(
                            color: negative ? Colors.redAccent : cream,
                            fontWeight: FontWeight.bold))),
                ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: fraction.clamp(0, 1),
                        backgroundColor: raised,
                        color: negative ? const Color(0xffb5533c) : gold,
                        minHeight: 5))
              ])));
  Widget _section(String x) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(x,
          style: const TextStyle(
              fontFamily: 'serif', fontSize: 17, fontWeight: FontWeight.w600)));
  Widget _stat(String v, String l) => SizedBox(
      width: (MediaQuery.sizeOf(context).width - 42) / 2,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v,
                        style: const TextStyle(
                            fontSize: 23,
                            color: gold,
                            fontWeight: FontWeight.bold)),
                    Text(l, style: const TextStyle(color: mist))
                  ]))));
  String _bdt(double n) => '৳${n.toStringAsFixed(2)}';
  String _label(String s) => s == 'bkash'
      ? 'bKash'
      : s == 'eat'
          ? 'Food'
          : s == 'loan-given'
              ? 'Loans given'
              : s == 'loan-taken'
                  ? 'Loans taken'
                  : s[0].toUpperCase() + s.substring(1);
  String _month(int x) => const [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ][x - 1];
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext c) => Padding(
      padding: const EdgeInsets.all(12),
      child: Text(text, style: const TextStyle(color: mist)));
}
