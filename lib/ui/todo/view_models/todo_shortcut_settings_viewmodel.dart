import 'package:flutter/foundation.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/todo_shortcut_settings.dart';
import 'package:memex/utils/result.dart';

class TodoShortcutSettingsViewModel extends ChangeNotifier {
  TodoShortcutSettingsViewModel({required MemexRouter router})
      : _router = router;

  final MemexRouter _router;

  TodoShortcutSettings settings = TodoShortcutSettings.defaults;
  bool loading = false;
  bool saving = false;
  bool loadFailed = false;
  String? errorMessage;

  Future<void> load() async {
    loading = true;
    loadFailed = false;
    errorMessage = null;
    notifyListeners();
    (await _router.loadTodoShortcutSettings()).when(
      onOk: (value) => settings = value,
      onError: (error, _) {
        errorMessage = '$error';
        loadFailed = true;
      },
    );
    loading = false;
    notifyListeners();
  }

  Future<void> update(TodoShortcutSettings value) async {
    if (saving) return;
    saving = true;
    errorMessage = null;
    notifyListeners();
    (await _router.saveTodoShortcutSettings(value)).when(
      onOk: (_) => settings = value,
      onError: (error, _) => errorMessage = '$error',
    );
    saving = false;
    notifyListeners();
  }
}
