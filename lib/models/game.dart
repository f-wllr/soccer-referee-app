import 'package:flutter/widgets.dart';
import 'package:rcj_scoreboard/models/module.dart';
import 'dart:async';
import 'package:rcj_scoreboard/models/team.dart';
import 'package:rcj_scoreboard/services/mqtt.dart';
import 'package:rcj_scoreboard/services/match_data.dart';
import 'package:rcj_scoreboard/services/vibration_service.dart';

enum MatchStage {
  firstHalf,
  halfTime,
  secondHalf,
  fullTime,
}

class Game with ChangeNotifier, WidgetsBindingObserver {
  String timerButtonText = 'START';
  final int _maxPlayer = 5;
  List<Team> teams = [];
  int numberOfPLayers = 2;
  int _remainingTime = 0;
  int penaltyTime = 60;
  int periodTime = 600;
  int halfTimeDuration = 300;
  bool _isGameRunning = false;
  bool inGame = false;
  bool isTimeRunning = false;
  int _numberOfPlaying = 0;
  MatchStage currentStage = MatchStage.firstHalf;
  Timer? _timer;
  DateTime? _runClockStartedAt;
  int? _runClockStartRemainingTime;
  //MQTT
  MqttService mqttService = MqttService();
  MatchDataService matchDataService = MatchDataService();
  VibrationService vibrationService = VibrationService();


  // Callback to request showing the dialog
  void Function()? onRequestSwitchTeamOrderDialog;

  Game() {
    WidgetsBinding.instance.addObserver(this);

    String teamID;

    // A team (0)
    teamID = 'A';
    Module moduleA1 = Module(this, teamID, 'A1');
    Module moduleA2 = Module(this, teamID, 'A2');
    Module moduleA3 = Module(this, teamID, 'A3');
    Module moduleA4 = Module(this, teamID, 'A4');
    Module moduleA5 = Module(this, teamID, 'A5');
    teams.add(Team('Team A', [moduleA1, moduleA2, moduleA3, moduleA4 ,moduleA5], teamID));

    // B team (1)
    teamID = 'B';
    Module moduleB1 = Module(this, teamID, 'B1');
    Module moduleB2 = Module(this, teamID, 'B2');
    Module moduleB3 = Module(this, teamID, 'B3');
    Module moduleB4 = Module(this, teamID, 'B4');
    Module moduleB5 = Module(this, teamID, 'B5');
    teams.add(Team('Team B', [moduleB1, moduleB2, moduleB3, moduleB4 ,moduleB5], teamID));


    gameInit();
  }

  void gameInit() {
    currentStage = MatchStage.firstHalf;
    _remainingTime = periodTime;
    isTimeRunning = false;
    _isGameRunning = false;
    timerButtonText = 'START';
    inGame = false;

    stopTimer();


    // enable or disable players based on player number;
    for (var team in teams) {
      team.score = 0;
      for (var i = 0; i < _maxPlayer; i++) {
        i < numberOfPLayers ? team.modules[i].enable() : team.modules[i].disable();
        team.modules[i].init();
      }
    }
    notifyListeners();

    // mqtt publish default values
    mqttService.publishGameState(currentStage);
    mqttService.publishTime(_remainingTime);
    mqttService.publishTeamNames(teams);
    mqttService.publishTeam(teams);
    mqttService.publishScore(teams);
  }

  void gameRefresh() {


    // refresh all mqtt values
    mqttService.publishGameState(currentStage);
    mqttService.publishTime(_remainingTime);
    mqttService.publishTeamNames(teams);
    mqttService.publishTeam(teams);
    mqttService.publishScore(teams);
  }


  // Timer

  void startTimer() {
    _timer?.cancel();
    inGame = true;
    if (currentStage == MatchStage.firstHalf || currentStage == MatchStage.secondHalf) {
      _isGameRunning = true;
    }
    isTimeRunning = true;
    _runClockStartedAt = DateTime.now();
    _runClockStartRemainingTime = _remainingTime;
    notifyListeners();
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (isTimeRunning) {
        _tickTimer();
      }
    });
  }

  void _tickTimer() {
    if (_remainingTime > 0) {
      _remainingTime--;
      _checkGameTimerVibration();
      notifyAllModulesTimer();
      mqttService.publishTime(_remainingTime);
    }

    if (_remainingTime <= 0) {
      _isGameRunning = false;
      isTimeRunning = false;
      _timer?.cancel();

      switch (currentStage) {
        case MatchStage.firstHalf:
          currentStage = MatchStage.halfTime;
          _remainingTime = halfTimeDuration;
          startTimer();
          timerButtonText = 'SKIP';
          halfTimeAll();
          // Trigger the callback to show the dialog
          if (onRequestSwitchTeamOrderDialog != null) {
            onRequestSwitchTeamOrderDialog!();
          }
        case MatchStage.halfTime:
          currentStage = MatchStage.secondHalf;
          _remainingTime = periodTime;
          stopAll(true, force: true);
          timerButtonText = 'START';
        case MatchStage.secondHalf:
          currentStage = MatchStage.fullTime;
          stopAll(true);
          timerButtonText = 'REPEAT';
          gameOverAll();
        default:
          print('unknown match stage');
      }

      mqttService.publishGameState(currentStage);
      mqttService.publishTime(_remainingTime);
    }

    if (currentStage == MatchStage.halfTime && _remainingTime % 30 == 0) {
      halfTimeSyncTimeAll();
    }

    notifyListeners();
  }

  int _maxResumeCatchUpTicks() {
    switch (currentStage) {
      case MatchStage.firstHalf:
        return _remainingTime + halfTimeDuration + periodTime;
      case MatchStage.halfTime:
        return _remainingTime + periodTime;
      case MatchStage.secondHalf:
        return _remainingTime;
      case MatchStage.fullTime:
        return 0;
    }
  }

  void toggleTimer() {
    if (currentStage == MatchStage.firstHalf || currentStage == MatchStage.secondHalf) {
      if (_isGameRunning) {
        stopTimer();
        timerButtonText = 'START';
        stopAll(false);
      } else {
        timerButtonText = 'STOP';
        startTimer();
        playAll(false);
      }
    } else if (currentStage == MatchStage.halfTime) {
      // SKIP
      _isGameRunning = false;
      isTimeRunning = false;
      _timer?.cancel();
      _runClockStartedAt = null;
      _runClockStartRemainingTime = null;
      currentStage = MatchStage.secondHalf;
      _remainingTime = periodTime;
      stopAll(true, force: true);
      timerButtonText = 'START';
      
      mqttService.publishGameState(currentStage);
      mqttService.publishTime(_remainingTime);

      notifyListeners();
    } else {
      // GAME OVER
      gameInit();
      setTeamToDefaultOrder();
      notifyListeners();
      notifyModulesScore();
    }
  }


  void toggleTeamOrder() {
    teams = teams.reversed.toList();

    notifyListeners();

    mqttService.publishTeamNames(teams);
    mqttService.publishTeam(teams);
    mqttService.publishScore(teams);
  }

  /// Toggles all modules based on the current game stage.
  void toggleAllModules() {
    if (currentStage == MatchStage.fullTime) {
      disconnectAll();
    } else if (_numberOfPlaying > 0) {
      stopAll(true);
    } else {
      if (!_isGameRunning && (currentStage == MatchStage.firstHalf || currentStage == MatchStage.secondHalf)) {
        startTimer();
        timerButtonText = 'STOP';
      }
      playAll(true);
    }
  }

  void notifyAllModulesTimer() {
    // Use flags so that at most one vibration fires per timer tick even if
    // multiple modules hit a threshold simultaneously.
    bool vibrateEndTriggered = false;
    bool vibrateWarningTriggered = false;

    for (var team in teams) {
      for (var module in team.modules.where((module) => module.isEnabled && module.state == ModuleState.damage)) {
        final penaltyBefore = module.penaltyTime;
        module.notifyTimer();

        if (vibrationService.damageTimerEnabled && penaltyBefore > 0) {
          final penaltyAfter = module.penaltyTime;
          if (vibrationService.damageTimerAlerts.contains(penaltyAfter)) {
            if (penaltyAfter == 0 && !vibrateEndTriggered) {
              vibrateEndTriggered = true;
              VibrationService.vibrateEnd();
            } else if (penaltyAfter > 0 && !vibrateWarningTriggered) {
              vibrateWarningTriggered = true;
              VibrationService.vibrateWarning();
            }
          }
        }
      }
    }
  }

  void _checkGameTimerVibration() {
    if (!vibrationService.gameTimerEnabled) return;
    if (currentStage != MatchStage.firstHalf &&
        currentStage != MatchStage.secondHalf) return;
    if (!vibrationService.gameTimerAlerts.contains(_remainingTime)) return;

    if (_remainingTime == 0) {
      VibrationService.vibrateEnd();
    } else {
      VibrationService.vibrateWarning();
    }
  }


  void stopTimer() {
    _isGameRunning = false;
    isTimeRunning = false;
    _timer?.cancel();
    _runClockStartedAt = null;
    _runClockStartRemainingTime = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isTimeRunning) {
      return;
    }

    if (state == AppLifecycleState.resumed &&
        _runClockStartedAt != null &&
        _runClockStartRemainingTime != null) {
      final elapsedSeconds = DateTime.now().difference(_runClockStartedAt!).inSeconds;
      final expectedRemaining = (_runClockStartRemainingTime! - elapsedSeconds)
          .clamp(0, _runClockStartRemainingTime!)
          .toInt();

      if (_remainingTime < expectedRemaining) {
        _remainingTime = expectedRemaining;
        mqttService.publishTime(_remainingTime);
        notifyListeners();
        return;
      }

      // If remaining time is higher than expected, the local timer lagged behind.
      final ticksBehind = _remainingTime > expectedRemaining
          ? _remainingTime - expectedRemaining
          : 0;
      final maxResumeCatchUpTicks = _maxResumeCatchUpTicks();
      final ticksToProcess = ticksBehind < maxResumeCatchUpTicks
          ? ticksBehind
          : maxResumeCatchUpTicks;
      for (var tickIndex = 0; tickIndex < ticksToProcess && isTimeRunning; tickIndex++) {
        _tickTimer();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }



  void playAll(bool removeDamage) async {
    for (var team in teams) {
      for (var module in team.modules.where((module) => module.isEnabled)) {
        if (removeDamage) {
          module.playAll();
        } else {
          module.playOrDamageAll();
        }

      }
    }
    notifyListeners();
  }

  void stopAll(bool removePenalty, {bool force = false}) {
    for (var team in teams) {
      for (var module in team.modules.where((module) => module.isEnabled)) {
        module.stopAll(removePenalty, force: force);
      }
    }
    notifyListeners();
  }

  void disconnectAll() {
    for (var team in teams) {
      for (var module in team.modules.where((module) => module.isEnabled && module.isConnected)) {
        module.bleDisconnect();
      }
    }
  }

  void halfTimeAll() async {
    stopAll(true);
    await Future.delayed(const Duration(seconds: 1));

    for (var team in teams) {
      for (var module in team.modules.where((module) => module.isEnabled)) {
        module.halfTime();
      }
    }
    notifyListeners();
  }

  void gameOverAll() async {
    stopAll(true);
    await Future.delayed(const Duration(seconds: 1));

    for (var team in teams) {
      for (var module in team.modules.where((module) => module.isEnabled)) {
        module.gameOver();
      }
    }
    notifyListeners();
  }

  void halfTimeSyncTimeAll() {
    for (var team in teams) {
      for (var module in team.modules.where((module) => module.isEnabled && module.isConnected)) {
        module.halfTimeSyncTime();
      }
    }
  }

int getScore(String team, {bool oppositeTeam = false}) {
  final foundTeam = teams.firstWhere(
    (t) => oppositeTeam ? t.id != team : t.id == team,
    orElse: () => throw Exception('Team not found'),
  );
  return foundTeam.score;
}

  void notifyModulesScore() {
    for (var team in teams) {
      for (var module in team.modules.where((module) => module.isEnabled && module.isConnected)) {
        module.bleSendScore();
        print('score sent');
      }
    }
    // mqtt publish team scores
    // mqtt publish default values
    mqttService.publishScore(teams);
  }


  void changeNumberOfPlaying(int add) {
    _numberOfPlaying += add;

    if (_numberOfPlaying < 0) _numberOfPlaying = 0;
    if (_numberOfPlaying > numberOfPLayers*2) _numberOfPlaying = numberOfPLayers*2;

    if (_numberOfPlaying < 2) notifyListeners();
  }

  // void checkNumOfPlaying() {
  //   bool current = false;
  //   for (var team in teams) {
  //     for (var module in team.modules.where((module) => module.isEnabled)) {
  //       if (module.isPlaying) {
  //         current = true;
  //         break;
  //       }
  //       if(current) break;
  //     }
  //   }
  //
  //   //if (!current) stopAll();
  //
  //   if (current != _isSomeonePlaying) {
  //     _isSomeonePlaying = current;
  //     notifyListeners();
  //   }
  //
  // }

  void setTeamToDefaultOrder() {
    // check team order and if necessary switch them
    if (teams.length == 2 && teams[0].id == 'B' && teams[1].id == 'A') {
      toggleTeamOrder();
    }

    // // set default team names
    // teams[0].name = 'Team A';
    // teams[1].name = 'Team B';
  }

  int get remainingTime => _remainingTime;
  bool get isSomeonePlaying => _numberOfPlaying > 0 ? true : false;
  bool get isTimerRunning => isTimeRunning;
  bool get isGameRunning => _isGameRunning;
  String get gameStageString {
    switch (currentStage) {
      case MatchStage.firstHalf:
        return '1';
      case MatchStage.halfTime:
        return 'Half-Time';
      case MatchStage.secondHalf:
        return '2';
      case MatchStage.fullTime:
        return 'Game Over';
    }
  }

  void loadMatchData() async {
   var match = await matchDataService.loadMatch();
    notifyListeners();

    if (match != null) {
      teams[0].name = match.team1;
      teams[1].name = match.team2;
      mqttService.topic_field = match.field;
      mqttService.publishTeamNames(teams);
      mqttService.publishTeam(teams);

    }
  }

  void notifyMQTT() {
    // mqttService.publishGameState(currentStage);
    // mqttService.publishTime(_remainingTime);
    mqttService.publishTeamNames(teams);
    // mqttService.publishTeam(teams);
    // mqttService.publishScore(teams);
  }

}
