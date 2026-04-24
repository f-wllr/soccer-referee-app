import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

const List<int> kVibrationAlertOptions = [10, 5, 3, 0];

class VibrationService with ChangeNotifier {
  bool _gameTimerEnabled = true;
  bool _damageTimerEnabled = true;
  Set<int> _gameTimerAlerts = {10, 5, 3, 0};
  Set<int> _damageTimerAlerts = {5, 0};

  late SharedPreferences _prefs;
  bool _prefsLoaded = false;

  VibrationService() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _gameTimerEnabled =
        _prefs.getBool('vibration_game_timer_enabled') ?? true;
    _damageTimerEnabled =
        _prefs.getBool('vibration_damage_timer_enabled') ?? true;

    final gameAlerts =
        _prefs.getStringList('vibration_game_timer_alerts');
    if (gameAlerts != null) {
      _gameTimerAlerts =
          gameAlerts.map((e) => int.parse(e)).toSet();
    }

    final damageAlerts =
        _prefs.getStringList('vibration_damage_timer_alerts');
    if (damageAlerts != null) {
      _damageTimerAlerts =
          damageAlerts.map((e) => int.parse(e)).toSet();
    }

    _prefsLoaded = true;
    notifyListeners();
  }

  bool get gameTimerEnabled => _gameTimerEnabled;
  set gameTimerEnabled(bool value) {
    _gameTimerEnabled = value;
    if (_prefsLoaded) {
      _prefs.setBool('vibration_game_timer_enabled', value);
    }
    notifyListeners();
  }

  bool get damageTimerEnabled => _damageTimerEnabled;
  set damageTimerEnabled(bool value) {
    _damageTimerEnabled = value;
    if (_prefsLoaded) {
      _prefs.setBool('vibration_damage_timer_enabled', value);
    }
    notifyListeners();
  }

  Set<int> get gameTimerAlerts => _gameTimerAlerts;
  Set<int> get damageTimerAlerts => _damageTimerAlerts;

  void toggleGameTimerAlert(int seconds) {
    if (_gameTimerAlerts.contains(seconds)) {
      _gameTimerAlerts.remove(seconds);
    } else {
      _gameTimerAlerts.add(seconds);
    }
    if (_prefsLoaded) {
      _prefs.setStringList('vibration_game_timer_alerts',
          _gameTimerAlerts.map((e) => e.toString()).toList());
    }
    notifyListeners();
  }

  void toggleDamageTimerAlert(int seconds) {
    if (_damageTimerAlerts.contains(seconds)) {
      _damageTimerAlerts.remove(seconds);
    } else {
      _damageTimerAlerts.add(seconds);
    }
    if (_prefsLoaded) {
      _prefs.setStringList('vibration_damage_timer_alerts',
          _damageTimerAlerts.map((e) => e.toString()).toList());
    }
    notifyListeners();
  }

  /// Short vibration for timer warning alerts (e.g. 10, 5, 3 sec remaining).
  static Future<void> vibrateWarning() async {
    if (kIsWeb) return;
    try {
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(duration: 200);
      }
    } catch (_) {}
  }

  /// Longer vibration pattern when a timer reaches zero.
  static Future<void> vibrateEnd() async {
    if (kIsWeb) return;
    try {
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(pattern: [0, 400, 200, 400]);
      }
    } catch (_) {}
  }
}
