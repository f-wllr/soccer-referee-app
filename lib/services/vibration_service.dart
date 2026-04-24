import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

const List<int> kVibrationAlertOptions = [10, 5, 3, 0];

enum VibrationPattern {
  short,
  long,
  doubleBuzz,
  pulse,
}

extension VibrationPatternDisplay on VibrationPattern {
  String get displayName {
    switch (this) {
      case VibrationPattern.short:
        return 'Short (200ms)';
      case VibrationPattern.long:
        return 'Long (600ms)';
      case VibrationPattern.doubleBuzz:
        return 'Double buzz';
      case VibrationPattern.pulse:
        return 'Pulse (long-short-long)';
    }
  }
}

class VibrationService with ChangeNotifier {
  bool _gameTimerEnabled = true;
  bool _damageTimerEnabled = true;
  Set<int> _gameTimerAlerts = {10, 5, 3, 0};
  Set<int> _damageTimerAlerts = {5, 0};
  VibrationPattern _gameTimerPattern = VibrationPattern.pulse;
  VibrationPattern _damageTimerPattern = VibrationPattern.doubleBuzz;

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

    final gamePatternIdx = _prefs.getInt('vibration_game_timer_pattern');
    if (gamePatternIdx != null &&
        gamePatternIdx >= 0 &&
        gamePatternIdx < VibrationPattern.values.length) {
      _gameTimerPattern = VibrationPattern.values[gamePatternIdx];
    }

    final damagePatternIdx = _prefs.getInt('vibration_damage_timer_pattern');
    if (damagePatternIdx != null &&
        damagePatternIdx >= 0 &&
        damagePatternIdx < VibrationPattern.values.length) {
      _damageTimerPattern = VibrationPattern.values[damagePatternIdx];
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

  VibrationPattern get gameTimerPattern => _gameTimerPattern;
  set gameTimerPattern(VibrationPattern value) {
    _gameTimerPattern = value;
    if (_prefsLoaded) {
      _prefs.setInt('vibration_game_timer_pattern', value.index);
    }
    notifyListeners();
  }

  VibrationPattern get damageTimerPattern => _damageTimerPattern;
  set damageTimerPattern(VibrationPattern value) {
    _damageTimerPattern = value;
    if (_prefsLoaded) {
      _prefs.setInt('vibration_damage_timer_pattern', value.index);
    }
    notifyListeners();
  }

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

  /// Vibrate using the game-timer pattern.
  Future<void> vibrateGameTimer() async {
    if (!_gameTimerEnabled || kIsWeb) return;
    await _executeVibration(_gameTimerPattern);
  }

  /// Vibrate using the damage-timer pattern.
  Future<void> vibrateDamageTimer() async {
    if (!_damageTimerEnabled || kIsWeb) return;
    await _executeVibration(_damageTimerPattern);
  }

  /// Executes the given [pattern], falling back to a plain duration on
  /// platforms that don't support custom vibration sequences (e.g. iOS).
  static Future<void> _executeVibration(VibrationPattern pattern) async {
    try {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) return;
      final hasCustom =
          await Vibration.hasCustomVibrationsSupport() ?? false;

      switch (pattern) {
        case VibrationPattern.short:
          await Vibration.vibrate(duration: 200);
        case VibrationPattern.long:
          await Vibration.vibrate(duration: 600);
        case VibrationPattern.doubleBuzz:
          if (hasCustom) {
            await Vibration.vibrate(pattern: [0, 200, 100, 200]);
          } else {
            await Vibration.vibrate(duration: 300);
          }
        case VibrationPattern.pulse:
          if (hasCustom) {
            await Vibration.vibrate(pattern: [0, 400, 200, 400]);
          } else {
            await Vibration.vibrate(duration: 500);
          }
      }
    } catch (_) {}
  }
}
