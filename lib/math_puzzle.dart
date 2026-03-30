import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'ad_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MathPuzzlePage extends StatefulWidget {
  const MathPuzzlePage({super.key});

  @override
  State<MathPuzzlePage> createState() => _MathPuzzlePageState();
}

class _MathPuzzlePageState extends State<MathPuzzlePage> with TickerProviderStateMixin {
  final _rand = Random();
  int _a = 0, _b = 0;
  String _op = '+';
  int _score = 0;
  int _streak = 0; 
  int _bestStreak = 0;
  int _attempts = 0;
  int _correct = 0;
  int? _fastestMs; // fastest answer time in milliseconds
  int? _qStartMs;  // per-question start timestamp
  int _timeLeft = 60;
  String _input = '';
  Timer? _timer;
  bool _running = true;
  String _difficulty = 'easy'; // easy | medium | hard
  String _mode = 'timed'; // timed | practice
  bool _online = true;
  String? _error;
  bool _loading = false;
  int _qSeq = 0; // to avoid race conditions for async fetch
  List<int> _options = const [];
  int? _selectedOption;
  bool? _wasCorrect;
  late final AnimationController _shakeCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _shakeAnim; // -1..1
  late final Animation<double> _pulseAnim; // scale
  bool _endDialogShown = false;
  // Persistent stats
  int _pbBestStreak = 0;
  int? _pbFastestMs;
  int _lifetimeXp = 0;
  bool _newPBStreak = false;
  bool _newPBFastest = false;
  // Adaptive difficulty tracking
  final List<bool> _recentAnswers = <bool>[]; // rolling window of correctness
  int _questionsSinceAdjust = 0;
  static const int _adaptWindow = 10;
  static const int _adaptCooldown = 6;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 4), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeOut));
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _loadPersistentStats();
    _initOnline();
    // Preload an interstitial ad for math puzzles
    AdService().loadInterstitialAd();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shakeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_mode == 'timed') {
      _timeLeft = 60;
      _running = true;
      _endDialogShown = false;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() {
          _timeLeft--;
          if (_timeLeft <= 0) {
            _running = false;
            t.cancel();
            // End-of-round: schedule interstitial, then score dialog after dismissal
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (AdService().isInterstitialAdReady) {
                AdService().showInterstitialAd(onDismiss: () {
                  if (!mounted) return;
                  if (!_endDialogShown) {
                    _endDialogShown = true;
                    _showScoreDialog();
                  }
                });
              } else {
                // No ad ready: preload for next time and show dialog now
                AdService().loadInterstitialAd();
                if (!_endDialogShown) {
                  _endDialogShown = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showScoreDialog();
                  });
                }
              }
            });
          }
        });
      });
    } else {
      // practice mode: no timer
      _timeLeft = 0;
      _running = true;
      _endDialogShown = false;
    }
  }

  Future<void> _initOnline() async {
    await _checkOnline();
    if (_online) {
      await _nextQuestion();
      _startTimer();
    }
  }

  Future<void> _loadPersistentStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _pbBestStreak = prefs.getInt('pb_best_streak') ?? 0;
        _pbFastestMs = prefs.getInt('pb_fastest_ms');
        _lifetimeXp = prefs.getInt('lifetime_xp') ?? 0;
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _updatePersistentStats({required int bestStreak, required int? fastestMs, required int xpEarned}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prevBest = prefs.getInt('pb_best_streak') ?? 0;
      final prevFast = prefs.getInt('pb_fastest_ms');
      int lifeXp = prefs.getInt('lifetime_xp') ?? 0;

      final newBestStreak = bestStreak > prevBest;
      final newFastest = fastestMs != null && (prevFast == null || fastestMs < prevFast);

      if (newBestStreak) {
        await prefs.setInt('pb_best_streak', bestStreak);
      }
      if (newFastest) {
        await prefs.setInt('pb_fastest_ms', fastestMs!);
      }
      lifeXp += xpEarned;
      await prefs.setInt('lifetime_xp', lifeXp);

      if (!mounted) return;
      setState(() {
        _pbBestStreak = newBestStreak ? bestStreak : prevBest;
        _pbFastestMs = newFastest ? fastestMs : prevFast;
        _lifetimeXp = lifeXp;
        _newPBStreak = newBestStreak;
        _newPBFastest = newFastest;
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _checkOnline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      final connected = result != ConnectivityResult.none;
      setState(() {
        _online = connected;
        if (!connected) {
          _error = 'No internet connection';
          _running = false;
        }
      });
    } catch (e) {
      setState(() {
        _online = false;
        _running = false;
        _error = 'Network check failed';
      });
    }
  }

  Future<void> _nextQuestion({String? difficulty}) async {
    if (_loading) return;
    final localSeq = ++_qSeq;
    setState(() {
      _loading = true;
      _selectedOption = null;
      _wasCorrect = null;
    });
    final diff = difficulty ?? _difficulty;
    int maxN;
    switch (diff) {
      case 'hard':
        maxN = 99;
        break;
      case 'medium':
        maxN = 50;
        break;
      case 'easy':
      default:
        maxN = 20;
    }
    // Require online: fetch two random numbers from public API
    try {
      await _checkOnline();
      if (!_online) return;
      final url = Uri.parse('https://www.randomnumberapi.com/api/v1.0/random?min=1&max=$maxN&count=2');
      final resp = await http.get(url).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        // Parse JSON array safely
        final List<dynamic> arr = List<dynamic>.from(jsonDecode(resp.body) as List<dynamic>);
        if (arr.length >= 2) {
          _a = (arr[0] as num).toInt();
          _b = (arr[1] as num).toInt();
        } else {
          _a = _rand.nextInt(maxN) + 1;
          _b = _rand.nextInt(maxN) + 1;
        }
        final ops = ['+', '-', '×', '÷'];
        _op = ops[_rand.nextInt(ops.length)];
        if (_op == '÷') {
          // ensure divisible using fetched numbers
          _b = (_b == 0) ? 1 : _b.abs();
          // choose a quotient in range to build divisible a
          final q = _rand.nextInt(max(2, maxN ~/ 2)) + 1;
          _a = _b * q;
        }
        if (!mounted || localSeq != _qSeq) return;
        // Build multiple-choice options
        final correct = _answer();
        final opts = <int>{correct};
        int spread;
        switch (diff) {
          case 'hard':
            spread = 20;
            break;
          case 'medium':
            spread = 12;
            break;
          case 'easy':
          default:
            spread = 8;
        }
        while (opts.length < 4) {
          final delta = (_rand.nextInt(spread) + 1) * (_rand.nextBool() ? 1 : -1);
          final v = max(0, correct + delta);
          opts.add(v);
        }
        final list = opts.toList()..shuffle(_rand);
        setState(() {
          _input = '';
          _error = null;
          _options = list.map((e) => e.toInt()).toList();
          _qStartMs = DateTime.now().millisecondsSinceEpoch;
        });
      } else {
        if (!mounted || localSeq != _qSeq) return;
        setState(() {
          _error = 'Failed to load question (${resp.statusCode})';
          _running = false;
        });
      }
    } catch (e) {
      if (!mounted || localSeq != _qSeq) return;
      setState(() {
        _error = 'Failed to load question';
        _running = false;
        _online = false;
      });
    } finally {
      if (mounted && localSeq == _qSeq) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  int _answer() {
    switch (_op) {
      case '+':
        return _a + _b;
      case '-':
        return _a - _b;
      case '×':
        return _a * _b;
      case '÷':
        return _a ~/ _b;
      default:
        return 0;
    }
  }

  void _submit() {
    // unused in MC mode
  }

  void _restart() {
    // Defer showing interstitial to the next frame to avoid presenting during state mutation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (AdService().isInterstitialAdReady) {
        AdService().showInterstitialAd();
      } else {
        AdService().loadInterstitialAd();
      }
    });
    setState(() {
      _score = 0;
      _streak = 0;
      _bestStreak = 0;
      _attempts = 0;
      _correct = 0;
      _fastestMs = null;
      _qStartMs = null;
      _recentAnswers.clear();
      _questionsSinceAdjust = 0;
      _input = '';
      _error = null;
    });
    _nextQuestion().then((_) => _startTimer());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final compact = media.size.height < 600;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Math Puzzles'),
        actions: [
          IconButton(
            tooltip: 'Restart',
            icon: const Icon(Icons.refresh),
            onPressed: _restart,
          )
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surfaceVariant.withOpacity(0.15),
              theme.colorScheme.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: EdgeInsets.all(compact ? 12 : 16),
                child: isLandscape
                    ? Row(
                        children: [
                          Expanded(
                            child: _buildTopPanel(theme),
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: _buildOptionsPanel(theme)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                            fit: FlexFit.loose,
                            child: _buildTopPanel(theme),
                          ),
                          const SizedBox(height: 16),
                          Expanded(child: _buildOptionsPanel(theme)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopPanel(ThemeData theme) {
    final size = MediaQuery.of(context).size;
    final compact = size.height < 600;
    final base = (size.shortestSide) * 0.12;
    final qFont = base.clamp(compact ? 20.0 : 22.0, compact ? 42.0 : 48.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
            if (_mode == 'timed')
              Padding(
                padding: EdgeInsets.only(bottom: compact ? 6 : 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: compact ? 6 : 8,
                    value: _timeLeft.clamp(0, 60) / 60.0,
                    backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                  ),
                ),
              ),
            // Mode & Difficulty controls
            Wrap(
              spacing: compact ? 6 : 8,
              runSpacing: compact ? 6 : 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.bolt_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  label: Text('Easy', style: TextStyle(fontSize: compact ? 12 : 14)),
                  selected: _difficulty == 'easy',
                  onSelected: (v) {
                    if (!v) return;
                    setState(() {
                      _difficulty = 'easy';
                      _recentAnswers.clear();
                      _questionsSinceAdjust = 0;
                      _nextQuestion(difficulty: _difficulty);
                    });
                  },
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.speed_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  label: Text('Medium', style: TextStyle(fontSize: compact ? 12 : 14)),
                  selected: _difficulty == 'medium',
                  onSelected: (v) {
                    if (!v) return;
                    setState(() {
                      _difficulty = 'medium';
                      _recentAnswers.clear();
                      _questionsSinceAdjust = 0;
                      _nextQuestion(difficulty: _difficulty);
                    });
                  },
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.local_fire_department_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  label: Text('Hard', style: TextStyle(fontSize: compact ? 12 : 14)),
                  selected: _difficulty == 'hard',
                  onSelected: (v) {
                    if (!v) return;
                    setState(() {
                      _difficulty = 'hard';
                      _recentAnswers.clear();
                      _questionsSinceAdjust = 0;
                      _nextQuestion(difficulty: _difficulty);
                    });
                  },
                ),
                const SizedBox(width: 12),
                FilterChip(
                  avatar: Icon(_mode == 'timed' ? Icons.timer_outlined : Icons.school_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  label: Text(_mode == 'timed' ? 'Timed (60s)' : 'Practice', style: TextStyle(fontSize: compact ? 12 : 14)),
                  selected: _mode == 'timed',
                  onSelected: (isTimed) {
                    setState(() {
                      _mode = isTimed ? 'timed' : 'practice';
                      _recentAnswers.clear();
                      _questionsSinceAdjust = 0;
                      _startTimer();
                    });
                  },
                ),
              ],
            ),
            SizedBox(height: compact ? 6 : 8),
            if (!_online || _error != null)
              Container(
                padding: EdgeInsets.all(compact ? 10 : 12),
                margin: EdgeInsets.only(bottom: compact ? 6 : 8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error ?? 'Offline: Internet required to play.')),
                    TextButton(
                      onPressed: () async {
                        await _initOnline();
                        if (mounted) setState(() {});
                      },
                      child: const Text('Retry'),
                    )
                  ],
                ),
              ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runAlignment: WrapAlignment.center,
              spacing: compact ? 6 : 8,
              runSpacing: compact ? 6 : 8,
              children: [
                Chip(avatar: const Icon(Icons.star_border), label: Text('Score: $_score', style: TextStyle(fontSize: compact ? 12 : 14))),
                Chip(avatar: const Icon(Icons.trending_up), label: Text('Streak: $_streak', style: TextStyle(fontSize: compact ? 12 : 14))),
                if (_mode == 'timed') Chip(avatar: const Icon(Icons.timer_outlined), label: Text('$_timeLeft s', style: TextStyle(fontSize: compact ? 12 : 14))),
                if (_mode == 'practice') Chip(avatar: const Icon(Icons.school_outlined), label: Text('Practice', style: TextStyle(fontSize: compact ? 12 : 14))),
              ],
            ),
            SizedBox(height: compact ? 12 : 16),
            Flexible(
              fit: FlexFit.loose,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: compact ? 12 : 16, horizontal: compact ? 14 : 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_shakeCtrl, _pulseCtrl]),
                    builder: (context, child) {
                      final dx = _shakeAnim.value;
                      final scale = _pulseAnim.value;
                      return Transform.translate(
                        offset: Offset(dx, 0),
                        child: Transform.scale(
                          scale: scale,
                          child: child,
                        ),
                      );
                    },
                    child: _loading
                        ? const SizedBox(
                            key: ValueKey('loading'),
                            height: 40,
                            width: 40,
                            child: CircularProgressIndicator(),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              key: ValueKey('q$_a$_op$_b'),
                              '$_a $_op $_b = ?',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontSize: qFont,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            if (!_running)
              Card(
                elevation: 0,
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text("Time's up!", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text('Final score: $_score'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _restart,
                        icon: const Icon(Icons.replay),
                        label: const Text('Play again'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
  }

  Widget _buildOptionsPanel(ThemeData theme) {
    final enabled = _running && _error == null && _online && !_loading;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 420;
    final textStyle = TextStyle(fontSize: isWide ? 22 : 18, fontWeight: FontWeight.w700);
    Color? tileColorFor(int v) {
      if (_selectedOption == null) return null;
      if (v == _answer()) return Colors.green.withOpacity(0.15);
      if (v == _selectedOption && _wasCorrect == false) return Colors.red.withOpacity(0.15);
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              final w = constraints.maxWidth;
              double aspect;
              if (h < 260) {
                aspect = 1.05;
              } else if (h < 340) {
                aspect = 1.2;
              } else if (h < 420) {
                aspect = 1.35;
              } else {
                aspect = 1.5;
              }
              final spacing = h < 340 || w < 360 ? 8.0 : 12.0;
              return GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: aspect,
                ),
                itemCount: _options.length,
                itemBuilder: (context, index) {
                  final v = _options[index];
                  final isCorrect = v == _answer();
                  final selected = _selectedOption == v;
                  return AnimatedScale(
                    duration: const Duration(milliseconds: 160),
                    scale: selected ? 0.98 : 1.0,
                    child: Material(
                      color: tileColorFor(v) ?? theme.colorScheme.surface,
                      elevation: selected ? 2 : 1,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: enabled && _selectedOption == null ? () => _chooseOption(v) : null,
                        child: Stack(
                          children: [
                            Center(
                              child: Text('$v', style: textStyle),
                            ),
                            if (_selectedOption != null)
                              Positioned(
                                right: 8,
                                top: 8,
                                child: AnimatedOpacity(
                                  opacity: selected ? 1 : 0.0,
                                  duration: const Duration(milliseconds: 150),
                                  child: Icon(
                                    isCorrect ? Icons.check_circle : Icons.cancel,
                                    color: isCorrect ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: enabled ? () => _nextQuestion() : null,
          icon: const Icon(Icons.skip_next_outlined),
          label: const Text('Skip'),
        ),
      ],
    );
  }

  void _chooseOption(int value) {
    if (!_running || _loading || _error != null || !_online) return;
    final correct = _answer();
    final isCorrect = value == correct;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsed = (_qStartMs != null) ? max(0, nowMs - (_qStartMs!)) : null;
    setState(() {
      _selectedOption = value;
      _wasCorrect = isCorrect;
      _attempts += 1;
      if (isCorrect) {
        _score += 10;
        _streak += 1;
        _correct += 1;
        if (elapsed != null) {
          if (_fastestMs == null || elapsed < _fastestMs!) {
            _fastestMs = elapsed;
          }
        }
      } else {
        if (_streak > _bestStreak) _bestStreak = _streak;
        _streak = 0;
      }
    });
    // Adaptive difficulty: update rolling window and maybe adjust
    _recentAnswers.add(isCorrect);
    if (_recentAnswers.length > _adaptWindow) {
      _recentAnswers.removeAt(0);
    }
    _questionsSinceAdjust += 1;
    if (_mode == 'timed' && _questionsSinceAdjust >= _adaptCooldown && _recentAnswers.length >= (_adaptWindow ~/ 2)) {
      final correctCount = _recentAnswers.where((e) => e).length;
      final acc = correctCount / _recentAnswers.length;
      String? newDiff;
      if (acc >= 0.8 && _difficulty != 'hard') {
        newDiff = _difficulty == 'easy' ? 'medium' : 'hard';
      } else if (acc < 0.5 && _difficulty != 'easy') {
        newDiff = _difficulty == 'hard' ? 'medium' : 'easy';
      }
      if (newDiff != null) {
        setState(() {
          _difficulty = newDiff!;
          _questionsSinceAdjust = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Difficulty adjusted to ${_difficulty.toUpperCase()}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    // Haptics, sounds, and animations
    if (isCorrect) {
      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
      _pulseCtrl.forward(from: 0);
    } else {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.alert);
      _shakeCtrl.forward(from: 0);
    }
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (_mode == 'timed' && !_running) return; // time might have ended
      _nextQuestion();
    });
  }

  void _showScoreDialog() {
    final bestStreak = max(_bestStreak, _streak);
    final acc = _attempts == 0 ? 0.0 : (_correct * 100.0 / _attempts);
    final int xp = _score + (acc ~/ 10);
    // Fire-and-forget persistence update
    _newPBStreak = false;
    _newPBFastest = false;
    _updatePersistentStats(bestStreak: bestStreak, fastestMs: _fastestMs, xpEarned: xp);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final fastestSec = _fastestMs == null ? '-' : ( (_fastestMs! / 1000.0).toStringAsFixed(1) + 's');
        // Simple XP formula: base on score + accuracy bonus (computed above)
        Text _metric(String label, String value) {
          return Text.rich(
            TextSpan(children: [
              TextSpan(text: '$label\n  ', style: Theme.of(context).textTheme.bodyMedium),
              TextSpan(text: value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          );
        }
        final shareText = 'Math Puzzles — Round Summary\n'
            'Score: $_score\n'
            'Best streak: $bestStreak\n'
            'Accuracy: ${acc.toStringAsFixed(0)}% ($_correct/$_attempts)\n'
            'Fastest answer: $fastestSec\n'
            'XP earned: $xp';
        return AlertDialog(
          title: const Text("Time's up!"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.star_border),
                title: _metric('Score:', '$_score'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.trending_up),
                title: _metric('Best streak:', '$bestStreak'),
                trailing: _newPBStreak ? const Chip(label: Text('New!')) : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.analytics_outlined),
                title: _metric('Accuracy:', '${acc.toStringAsFixed(0)}%  ($_correct/$_attempts)'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timer_outlined),
                title: _metric('Fastest answer:', '$fastestSec'),
                trailing: _newPBFastest ? const Chip(label: Text('New!')) : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.military_tech_outlined),
                title: _metric('XP earned:', '$xp'),
              ),
              if (_lifetimeXp > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Lifetime XP: $_lifetimeXp', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Share.share(shareText),
              icon: const Icon(Icons.ios_share),
              label: const Text('Share'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.replay),
              onPressed: () {
                Navigator.of(context).pop();
                _restart();
              },
              label: const Text('Replay'),
            ),
          ],
        );
      },
    );
  }
}
