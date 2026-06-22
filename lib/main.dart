import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/entities.dart';
import 'game/game.dart';
import 'game/missions.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    BrowserContextMenu.disableContextMenu();
  }
  runApp(const LastColonyApp());
}

class LastColonyApp extends StatelessWidget {
  const LastColonyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Last Colony',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late LastColonyGame game;
  final FocusNode _focus = FocusNode();

  // touch tracking
  Offset _touchStart = Offset.zero;
  Offset _touchLast = Offset.zero;
  bool _touchActive = false;
  bool _touchMoved = false;

  int? _lastMission;
  bool _lastHotseat = false;

  @override
  void initState() {
    super.initState();
    game = LastColonyGame();
    game.sfx.init();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _startMission(int i) {
    _lastMission = i;
    _lastHotseat = false;
    game.startMission(i);
    _focus.requestFocus();
  }

  void _startHotseat() {
    _lastHotseat = true;
    game.startHotseat();
    _focus.requestFocus();
  }

  void _toMenu() {
    game.state.value = GameState.menu;
  }

  void _rematch() {
    if (_lastHotseat) {
      _startHotseat();
    } else {
      _startMission(_lastMission ?? 0);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final isDown = event is! KeyUpEvent;
    final k = event.logicalKey;

    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      game.setPanKey(1, isDown);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      game.setPanKey(2, isDown);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW) {
      game.setPanKey(4, isDown);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) {
      game.setPanKey(8, isDown);
      return KeyEventResult.handled;
    }
    if (!down) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.digit1) {
      game.requestBuild(UnitKind.scoutTank);
    } else if (k == LogicalKeyboardKey.digit2) {
      game.requestBuild(UnitKind.heavyTank);
    } else if (k == LogicalKeyboardKey.digit3) {
      game.requestBuild(UnitKind.harvester);
    } else if (k == LogicalKeyboardKey.digit4) {
      game.requestBuild(UnitKind.chopper);
    } else if (k == LogicalKeyboardKey.digit5) {
      game.requestBuild(UnitKind.wraith);
    } else if (k == LogicalKeyboardKey.keyT) {
      game.requestPlace(BuildingKind.turret);
    } else if (k == LogicalKeyboardKey.keyP) {
      game.requestPlace(BuildingKind.power);
    } else if (k == LogicalKeyboardKey.tab) {
      game.switchSide();
    } else if (k == LogicalKeyboardKey.escape) {
      game.placingKind = null;
    }
    return KeyEventResult.ignored;
  }

  void _onPointerDown(PointerDownEvent e) {
    _focus.requestFocus();
    if (e.kind == PointerDeviceKind.touch) {
      _touchActive = true;
      _touchMoved = false;
      _touchStart = e.localPosition;
      _touchLast = e.localPosition;
      return;
    }
    if (e.buttons & kSecondaryButton != 0) {
      game.onSecondaryDown(e.localPosition);
    } else if (e.buttons & kPrimaryButton != 0) {
      game.onPrimaryDown(e.localPosition);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      if (!_touchActive) return;
      final delta = e.localPosition - _touchLast;
      _touchLast = e.localPosition;
      if ((e.localPosition - _touchStart).distance > 10) _touchMoved = true;
      if (_touchMoved) game.panBy(delta);
      return;
    }
    game.setHover(e.localPosition);
    if (e.buttons & kPrimaryButton != 0) {
      game.onDragUpdate(e.localPosition);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_touchActive) {
      _touchActive = false;
      if (!_touchMoved) game.onTouchTap(_touchStart);
      return;
    }
    game.onPrimaryUp(e.localPosition);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101810),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerHover: (e) => game.setHover(e.localPosition),
          onPointerUp: _onPointerUp,
          child: Stack(
            children: [
              Positioned.fill(child: GameWidget(game: game)),
              _TopBar(game: game),
              _Sidebar(game: game),
              _MessageBanner(game: game),
              _MenuOverlay(
                  game: game,
                  onMission: _startMission,
                  onHotseat: _startHotseat),
              _EndOverlay(game: game, onMenu: _toMenu, onRematch: _rematch),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar: cash, side indicator, objective, toggles
// ---------------------------------------------------------------------------
class _TopBar extends StatelessWidget {
  final LastColonyGame game;
  const _TopBar({required this.game});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<int>(
        valueListenable: game.controlledVersion,
        builder: (_, __, ___) {
          final isBlue = game.controlledTeam == Team.player;
          return Container(
            height: 46,
            color: const Color(0xCC0E140E),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('⛏', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                ValueListenableBuilder<int>(
                  valueListenable: game.cashView,
                  builder: (_, cash, __) => Text('$cash',
                      style: const TextStyle(
                          color: Color(0xFFFFD54F),
                          fontSize: 19,
                          fontWeight: FontWeight.bold)),
                ),
                if (game.hotseat) ...[
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isBlue ? const Color(0xFF1565C0) : const Color(0xFFC62828),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(isBlue ? 'BLUE' : 'RED',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: game.switchSide,
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.white),
                    child: const Text('SWAP ⇄', style: TextStyle(fontSize: 12)),
                  ),
                ],
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: game.objective,
                    builder: (_, obj, __) => Text(
                      obj,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
                _ToggleIcon(
                  onIcon: Icons.volume_up,
                  offIcon: Icons.volume_off,
                  initial: () => game.sfx.enabled,
                  onChanged: (v) => game.sfx.enabled = v,
                  tooltip: 'Sound',
                ),
                _ToggleIcon(
                  onIcon: Icons.visibility,
                  offIcon: Icons.visibility_off,
                  initial: () => game.fogEnabled,
                  onChanged: (v) => game.fogEnabled = v,
                  tooltip: 'Fog',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Build sidebar
// ---------------------------------------------------------------------------
class _Sidebar extends StatelessWidget {
  final LastColonyGame game;
  const _Sidebar({required this.game});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameState>(
      valueListenable: game.state,
      builder: (_, st, __) {
        if (st != GameState.playing) return const SizedBox.shrink();
        return Positioned(
          top: 54,
          right: 8,
          child: Container(
            width: 138,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xCC0E140E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ValueListenableBuilder<List<ProductionItem>>(
              valueListenable: game.queueView,
              builder: (_, q, __) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _label('UNITS'),
                    _unitBtn(UnitKind.scoutTank, '1', q),
                    _unitBtn(UnitKind.heavyTank, '2', q),
                    _unitBtn(UnitKind.harvester, '3', q),
                    _unitBtn(UnitKind.chopper, '4', q),
                    _unitBtn(UnitKind.wraith, '5', q),
                    const SizedBox(height: 6),
                    _label('STRUCTURES'),
                    _structBtn(BuildingKind.turret, 'T'),
                    _structBtn(BuildingKind.power, 'P'),
                    if (q.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: 1 - (q.first.timeLeft / q.first.total),
                        backgroundColor: Colors.black26,
                        color: const Color(0xFF4FC3F7),
                        minHeight: 4,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white54, fontSize: 11, letterSpacing: 2)),
      );

  Widget _unitBtn(UnitKind kind, String hotkey, List<ProductionItem> q) {
    final s = kUnitStats[kind]!;
    final building = q.where((p) => p.kind == kind).length;
    return _costBtn(
      title: '$hotkey · ${s.label}',
      cost: s.cost,
      badge: building > 0 ? '$building' : null,
      onTap: () => game.requestBuild(kind),
    );
  }

  Widget _structBtn(BuildingKind kind, String hotkey) {
    final s = kBuildingStats[kind]!;
    return _costBtn(
      title: '$hotkey · ${s.label}',
      cost: s.cost,
      badge: null,
      onTap: () => game.requestPlace(kind),
    );
  }

  Widget _costBtn({
    required String title,
    required int cost,
    required String? badge,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: ValueListenableBuilder<int>(
        valueListenable: game.cashView,
        builder: (_, cash, __) {
          final afford = cash >= cost;
          return Material(
            color: afford ? const Color(0xFF24402A) : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: TextStyle(
                                  color:
                                      afford ? Colors.white : Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          Text('$cost',
                              style: const TextStyle(
                                  color: Color(0xFFFFD54F), fontSize: 11)),
                        ],
                      ),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Color(0xFF4FC3F7), shape: BoxShape.circle),
                        child: Text(badge,
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToggleIcon extends StatefulWidget {
  final IconData onIcon;
  final IconData offIcon;
  final bool Function() initial;
  final ValueChanged<bool> onChanged;
  final String tooltip;
  const _ToggleIcon({
    required this.onIcon,
    required this.offIcon,
    required this.initial,
    required this.onChanged,
    required this.tooltip,
  });

  @override
  State<_ToggleIcon> createState() => _ToggleIconState();
}

class _ToggleIconState extends State<_ToggleIcon> {
  late bool _on = widget.initial();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '${widget.tooltip}: ${_on ? 'on' : 'off'}',
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      color: _on ? Colors.white : Colors.white38,
      icon: Icon(_on ? widget.onIcon : widget.offIcon),
      onPressed: () {
        setState(() => _on = !_on);
        widget.onChanged(_on);
      },
    );
  }
}

class _MessageBanner extends StatelessWidget {
  final LastColonyGame game;
  const _MessageBanner({required this.game});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 18,
      left: 0,
      right: 0,
      child: Center(
        child: ValueListenableBuilder<String>(
          valueListenable: game.message,
          builder: (_, msg, __) {
            if (msg.isEmpty) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xDD0E140E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF4FC3F7), width: 1),
              ),
              child: Text(msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mission-select menu
// ---------------------------------------------------------------------------
class _MenuOverlay extends StatelessWidget {
  final LastColonyGame game;
  final void Function(int) onMission;
  final VoidCallback onHotseat;
  const _MenuOverlay(
      {required this.game, required this.onMission, required this.onHotseat});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameState>(
      valueListenable: game.state,
      builder: (_, st, __) {
        if (st != GameState.menu) return const SizedBox.shrink();
        return Positioned.fill(
          child: Container(
            color: const Color(0xF20A0F0A),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('LAST COLONY',
                        style: TextStyle(
                            color: Color(0xFF4FC3F7),
                            fontSize: 44,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 6)),
                    const SizedBox(height: 4),
                    const Text('a real-time strategy skirmish',
                        style: TextStyle(color: Colors.white54, fontSize: 14)),
                    const SizedBox(height: 24),
                    const Text('CAMPAIGN',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            letterSpacing: 3)),
                    const SizedBox(height: 10),
                    for (var i = 0; i < campaign.length; i++)
                      _menuButton(
                        campaign[i].name,
                        campaign[i].objective,
                        const Color(0xFF24402A),
                        () => onMission(i),
                      ),
                    const SizedBox(height: 18),
                    const Text('LOCAL MULTIPLAYER',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            letterSpacing: 3)),
                    const SizedBox(height: 10),
                    _menuButton(
                      '2P Hotseat',
                      'Two players, one device — swap sides with TAB / SWAP',
                      const Color(0xFF2A3550),
                      onHotseat,
                    ),
                    const SizedBox(height: 22),
                    const SizedBox(
                      width: 420,
                      child: Text(
                        'Drag to box-select · right-click (or tap) to order · WASD/arrows pan · '
                        '1-5 build units · T turret · P power plant',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _menuButton(
      String title, String subtitle, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: 420,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Victory / defeat overlay
// ---------------------------------------------------------------------------
class _EndOverlay extends StatelessWidget {
  final LastColonyGame game;
  final VoidCallback onMenu;
  final VoidCallback onRematch;
  const _EndOverlay(
      {required this.game, required this.onMenu, required this.onRematch});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameState>(
      valueListenable: game.state,
      builder: (_, st, __) {
        if (st != GameState.ended) return const SizedBox.shrink();
        final controlledWon = game.winner == game.controlledTeam;
        final String title;
        final Color color;
        if (game.hotseat) {
          final blue = game.winner == Team.player;
          title = blue ? 'BLUE WINS' : 'RED WINS';
          color = blue ? const Color(0xFF42A5F5) : const Color(0xFFEF5350);
        } else {
          title = controlledWon ? 'VICTORY' : 'DEFEAT';
          color =
              controlledWon ? const Color(0xFF7CFF6B) : const Color(0xFFEF5350);
        }
        return Positioned.fill(
          child: Container(
            color: const Color(0xCC000000),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onMenu,
                        icon: const Icon(Icons.list),
                        label: const Text('Menu'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: onRematch,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Rematch'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
