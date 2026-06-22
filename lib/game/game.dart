import 'dart:math' as math;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'entities.dart';
import 'grid.dart';
import 'missions.dart';
import 'sound.dart';

enum GameState { menu, playing, ended }

class ProductionItem {
  final UnitKind kind;
  double timeLeft;
  final double total;
  ProductionItem(this.kind, this.total) : timeLeft = total;
}

class LastColonyGame extends FlameGame {
  static const double tileSize = 32;
  late GameGrid grid;
  bool _worldReady = false;

  final SoundFx sfx = SoundFx();

  final List<Unit> units = [];
  final List<Building> buildings = [];
  final List<Bullet> bullets = [];
  final List<Explosion> effects = [];
  final List<Unit> selected = [];

  // teams
  Team controlledTeam = Team.player;
  Set<Team> aiTeams = {Team.enemy};
  bool hotseat = false;
  final Map<Team, int> _cash = {Team.player: 0, Team.enemy: 0};
  final Map<Team, List<ProductionItem>> _queues = {Team.player: [], Team.enemy: []};
  final Map<Team, Vector2> rally = {
    Team.player: Vector2.zero(),
    Team.enemy: Vector2.zero(),
  };

  // fog
  late List<List<bool>> visible;
  final Map<Team, List<List<bool>>> _explored = {};
  bool fogEnabled = true;

  // building placement
  BuildingKind? placingKind;
  Offset? hoverScreen;

  // camera
  final Vector2 viewOrigin = Vector2.zero();
  final Set<int> _panKeys = {};
  bool _centered = false;

  // selection box (screen space)
  Offset? selStartScreen;
  Offset? selCurrentScreen;

  // missions
  Mission? mission;
  final List<Trigger> _triggers = [];
  double elapsed = 0;
  bool autoWinOnBaseLoss = true;
  Team? winner;

  // HUD-reactive
  final ValueNotifier<int> cashView = ValueNotifier(0);
  final ValueNotifier<List<ProductionItem>> queueView = ValueNotifier([]);
  final ValueNotifier<String> message = ValueNotifier('');
  final ValueNotifier<String> objective = ValueNotifier('');
  final ValueNotifier<GameState> state = ValueNotifier(GameState.menu);
  final ValueNotifier<int> selectionVersion = ValueNotifier(0);
  final ValueNotifier<int> controlledVersion = ValueNotifier(0);

  double _msgTimer = 0;
  double _incomeCd = 0;
  final Map<Team, double> _aiAttackCd = {Team.player: 0, Team.enemy: 0};
  final Map<Team, double> _aiBuildCd = {Team.player: 0, Team.enemy: 0};

  @override
  Color backgroundColor() => const Color(0xFF1B2A1B);

  @override
  Future<void> onLoad() async {
    // start at the menu; a mission/skirmish is chosen from the Flutter overlay
    state.value = GameState.menu;
  }

  int cashOf(Team t) => _cash[t] ?? 0;

  // -------------------------------------------------------------------------
  // World setup API (used by missions)
  // -------------------------------------------------------------------------
  void newWorld(int cols, int rows) {
    grid = GameGrid(cols, rows, tileSize);
    visible = List.generate(rows, (_) => List.filled(cols, false));
    _explored[Team.player] = List.generate(rows, (_) => List.filled(cols, false));
    _explored[Team.enemy] = List.generate(rows, (_) => List.filled(cols, false));
    units.clear();
    buildings.clear();
    bullets.clear();
    effects.clear();
    selected.clear();
    _queues[Team.player] = [];
    _queues[Team.enemy] = [];
    _cash[Team.player] = 0;
    _cash[Team.enemy] = 0;
    _worldReady = true;
    _centered = false;
  }

  void borderRocks() {
    for (var c = 0; c < grid.cols; c++) {
      grid.setTerrain(c, 0, Terrain.rock);
      grid.setTerrain(c, grid.rows - 1, Terrain.rock);
    }
    for (var r = 0; r < grid.rows; r++) {
      grid.setTerrain(0, r, Terrain.rock);
      grid.setTerrain(grid.cols - 1, r, Terrain.rock);
    }
  }

  void scatterRocks(int seed, int clusters) {
    final rng = math.Random(seed);
    for (var i = 0; i < clusters; i++) {
      final cx = 6 + rng.nextInt(grid.cols - 12);
      final cy = 5 + rng.nextInt(grid.rows - 10);
      final n = 2 + rng.nextInt(4);
      for (var j = 0; j < n; j++) {
        final dc = cx + rng.nextInt(3) - 1;
        final dr = cy + rng.nextInt(3) - 1;
        if (dc < 8 && dr > grid.rows - 9) continue;
        if (dc > grid.cols - 9 && dr < 8) continue;
        grid.setTerrain(dc, dr, Terrain.rock);
      }
    }
  }

  void oreField(int c0, int r0, int w, int h, double amount) {
    for (var dc = 0; dc < w; dc++) {
      for (var dr = 0; dr < h; dr++) {
        grid.addOre(c0 + dc, r0 + dr, amount);
      }
    }
  }

  Building place(BuildingKind kind, int col, int row, Team team) {
    final b = Building(kind, col, row, team, grid);
    b.occupy(grid);
    buildings.add(b);
    if (kind == BuildingKind.base) rally[team] = b.pos + Vector2(0, -90);
    return b;
  }

  Unit spawn(UnitKind kind, Vector2 pos, Team team) {
    final u = Unit(kind, pos.clone(), team);
    units.add(u);
    return u;
  }

  void setCash(Team team, int amount) => _cash[team] = amount;

  // -------------------------------------------------------------------------
  // Start a game
  // -------------------------------------------------------------------------
  void startMission(int index) {
    mission = campaign[index];
    hotseat = false;
    controlledTeam = Team.player;
    aiTeams = {Team.enemy};
    autoWinOnBaseLoss = true;
    winner = null;
    elapsed = 0;
    _triggers.clear();
    mission!.build(this);
    _triggers.addAll(mission!.triggers(this));
    objective.value = mission!.objective;
    _afterStart(mission!.intro);
  }

  void startHotseat() {
    mission = null;
    hotseat = true;
    controlledTeam = Team.player;
    aiTeams = {};
    autoWinOnBaseLoss = true;
    winner = null;
    elapsed = 0;
    _triggers.clear();
    buildSkirmishMap(this);
    objective.value = 'Local 2P — destroy the rival HQ. Press TAB / SWAP to switch sides.';
    _afterStart('Blue vs Red. Take turns at the controls — press SWAP to change sides.');
  }

  void _afterStart(String intro) {
    _updateFog();
    _syncHud();
    state.value = GameState.playing;
    showMessage(intro, seconds: 5);
  }

  // -------------------------------------------------------------------------
  // Update loop
  // -------------------------------------------------------------------------
  @override
  void update(double dt) {
    super.update(dt);
    if (state.value != GameState.playing || !_worldReady) return;
    if (dt > 0.1) dt = 0.1;
    elapsed += dt;

    if (!_centered && hasLayout) {
      _centered = true;
      _centerCameraOn((_baseOf(controlledTeam)?.pos ?? rally[controlledTeam])!);
    }

    _updateCamera(dt);
    _updateProduction(dt);

    for (final u in units) {
      u.update(dt, this);
    }
    for (final b in buildings) {
      b.update(dt, this);
    }
    for (final bl in bullets) {
      bl.update(dt);
    }
    for (final e in effects) {
      e.update(dt);
    }

    _cleanupDead();
    _economyTick(dt);
    for (final t in aiTeams) {
      _updateAi(t, dt);
    }
    _runTriggers();
    _updateFog();
    sfx.tick(dt);
    _syncHud();

    if (_msgTimer > 0) {
      _msgTimer -= dt;
      if (_msgTimer <= 0) message.value = '';
    }

    if (autoWinOnBaseLoss) _checkBaseVictory();
  }

  void _updateCamera(double dt) {
    const panSpeed = 600.0;
    var dx = 0.0, dy = 0.0;
    if (_panKeys.contains(1)) dx -= 1;
    if (_panKeys.contains(2)) dx += 1;
    if (_panKeys.contains(4)) dy -= 1;
    if (_panKeys.contains(8)) dy += 1;
    if (dx != 0 || dy != 0) {
      viewOrigin.add(Vector2(dx, dy) * panSpeed * dt);
      _clampCamera();
    }
  }

  void _updateProduction(double dt) {
    for (final team in [Team.player, Team.enemy]) {
      final q = _queues[team]!;
      if (q.isEmpty) continue;
      final item = q.first;
      item.timeLeft -= dt;
      if (item.timeLeft <= 0) {
        _spawnUnit(team, item.kind);
        q.removeAt(0);
        if (team == controlledTeam) sfx.build();
      }
    }
  }

  void _spawnUnit(Team team, UnitKind kind) {
    final base = _baseOf(team);
    final spawnPos = (base?.pos ?? rally[team]!) + Vector2(0, 70);
    final u = spawn(kind, spawnPos, team);
    if (!u.isHarvester) u.orderMove(rally[team]!.clone(), grid);
  }

  void _cleanupDead() {
    bullets.removeWhere((b) => b.dead);
    effects.removeWhere((e) => e.dead);
    var blew = false;
    final hadDeadBuilding = buildings.any((b) => b.dead);
    for (final b in buildings.where((b) => b.dead)) {
      b.release(grid);
      effects.add(Explosion(b.pos.clone(), maxRadius: 42, dur: 0.6));
      blew = true;
    }
    buildings.removeWhere((b) => b.dead);
    units.removeWhere((u) {
      if (u.dead) {
        selected.remove(u);
        effects.add(Explosion(u.pos.clone()));
        blew = true;
        return true;
      }
      return false;
    });
    if (blew) sfx.explosion();
    if (hadDeadBuilding) bumpSelection();
  }

  void _economyTick(double dt) {
    _incomeCd += dt;
    if (_incomeCd < 1) return;
    _incomeCd -= 1;
    for (final team in [Team.player, Team.enemy]) {
      final powers = buildings
          .where((b) => b.team == team && b.kind == BuildingKind.power && !b.dead)
          .length;
      if (powers > 0) addCash(team, powers * 25);
      if (aiTeams.contains(team)) addCash(team, 30);
    }
  }

  // -------------------------------------------------------------------------
  // AI
  // -------------------------------------------------------------------------
  void _updateAi(Team team, double dt) {
    _aiBuildCd[team] = (_aiBuildCd[team] ?? 0) + dt;
    if (_aiBuildCd[team]! >= 9) {
      _aiBuildCd[team] = 0;
      final base = _baseOf(team);
      if (base != null && cashOf(team) >= 500) {
        addCash(team, -500);
        const pool = [
          UnitKind.scoutTank,
          UnitKind.heavyTank,
          UnitKind.scoutTank,
          UnitKind.chopper,
        ];
        final kind = pool[math.Random().nextInt(pool.length)];
        spawn(kind, base.pos + Vector2(-60, 60), team);
      }
    }

    _aiAttackCd[team] = (_aiAttackCd[team] ?? 0) + dt;
    if (_aiAttackCd[team]! >= 4) {
      _aiAttackCd[team] = 0;
      final enemyBase = _enemyBaseOf(team);
      for (final u in units) {
        if (u.team != team || u.isHarvester) continue;
        if (u.target == null && u.path.isEmpty && enemyBase != null) {
          u.orderMove(enemyBase.pos.clone(), grid, attack: true);
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Triggers / victory
  // -------------------------------------------------------------------------
  void _runTriggers() {
    for (final t in _triggers) {
      if (t.fired && !t.repeat) continue;
      if (t.condition(this)) {
        t.action(this);
        t.fired = true;
      }
    }
  }

  void _checkBaseVictory() {
    final pBase = buildings.any((b) => b.team == Team.player && b.kind == BuildingKind.base);
    final eBase = buildings.any((b) => b.team == Team.enemy && b.kind == BuildingKind.base);
    if (!eBase && pBase) {
      endGame(Team.player);
    } else if (!pBase && eBase) {
      endGame(Team.enemy);
    } else if (!pBase && !eBase) {
      endGame(controlledTeam);
    }
  }

  void endGame(Team won) {
    if (state.value == GameState.ended) return;
    winner = won;
    state.value = GameState.ended;
    if (won == controlledTeam) {
      sfx.win();
    } else {
      sfx.lose();
    }
  }

  // -------------------------------------------------------------------------
  // Queries used by entities
  // -------------------------------------------------------------------------
  Entity? nearestEnemy(Vector2 from, Team team, double range) {
    Entity? best;
    var bestD = range * range;
    for (final u in units) {
      if (u.team == team || u.dead) continue;
      final d = u.pos.distanceToSquared(from);
      if (d < bestD) {
        bestD = d;
        best = u;
      }
    }
    for (final b in buildings) {
      if (b.team == team || b.dead) continue;
      final d = b.pos.distanceToSquared(from);
      if (d < bestD) {
        bestD = d;
        best = b;
      }
    }
    return best;
  }

  Building? nearestBase(Vector2 from, Team team) {
    Building? best;
    var bestD = double.infinity;
    for (final b in buildings) {
      if (b.team != team || b.kind != BuildingKind.base || b.dead) continue;
      final d = b.pos.distanceToSquared(from);
      if (d < bestD) {
        bestD = d;
        best = b;
      }
    }
    return best;
  }

  Building? _baseOf(Team team) => nearestBase(rally[team]!, team);

  Building? _enemyBaseOf(Team team) {
    Building? best;
    var bestD = double.infinity;
    for (final b in buildings) {
      if (b.team == team || b.kind != BuildingKind.base || b.dead) continue;
      final d = b.pos.distanceToSquared(rally[team]!);
      if (d < bestD) {
        bestD = d;
        best = b;
      }
    }
    return best;
  }

  int combatUnitsOf(Team team) =>
      units.where((u) => u.team == team && !u.isHarvester && !u.dead).length;

  List<int>? findNearestOre(Vector2 from) {
    final fc = grid.colAt(from.x), fr = grid.rowAt(from.y);
    List<int>? best;
    var bestD = 1 << 30;
    const radius = 22;
    for (var dc = -radius; dc <= radius; dc++) {
      for (var dr = -radius; dr <= radius; dr++) {
        final c = fc + dc, r = fr + dr;
        if (!grid.isOre(c, r)) continue;
        final d = dc * dc + dr * dr;
        if (d < bestD) {
          bestD = d;
          best = [c, r];
        }
      }
    }
    if (best != null) return best;
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.cols; c++) {
        if (!grid.isOre(c, r)) continue;
        final d = (c - fc) * (c - fc) + (r - fr) * (r - fr);
        if (d < bestD) {
          bestD = d;
          best = [c, r];
        }
      }
    }
    return best;
  }

  double mineOre(int c, int r, double amount) {
    if (!grid.inBounds(c, r) || grid.oreAmount[r][c] <= 0) return 0;
    final mined = math.min(amount, grid.oreAmount[r][c]);
    grid.oreAmount[r][c] -= mined;
    if (grid.oreAmount[r][c] <= 0) {
      grid.oreAmount[r][c] = 0;
      grid.setTerrain(c, r, Terrain.land);
    }
    return mined;
  }

  void spawnBullet(Vector2 from, Entity target, double damage, Team team) {
    bullets.add(Bullet(from, target, damage, team));
  }

  void addCash(Team team, int amount) {
    _cash[team] = (_cash[team] ?? 0) + amount;
  }

  // -------------------------------------------------------------------------
  // Fog
  // -------------------------------------------------------------------------
  void _updateFog() {
    final explored = _explored[controlledTeam]!;
    for (var r = 0; r < grid.rows; r++) {
      final row = visible[r];
      for (var c = 0; c < grid.cols; c++) {
        row[c] = false;
      }
    }
    for (final u in units) {
      if (u.team == controlledTeam && !u.dead) _reveal(u.pos, u.stats.sight, explored);
    }
    for (final b in buildings) {
      if (b.team == controlledTeam && !b.dead) _reveal(b.pos, b.stats.sight, explored);
    }
  }

  void _reveal(Vector2 worldPos, double sightPx, List<List<bool>> explored) {
    final cc = grid.colAt(worldPos.x), cr = grid.rowAt(worldPos.y);
    final radTiles = (sightPx / tileSize).ceil();
    final radSq = (radTiles + 0.5) * (radTiles + 0.5);
    for (var dr = -radTiles; dr <= radTiles; dr++) {
      for (var dc = -radTiles; dc <= radTiles; dc++) {
        if (dc * dc + dr * dr > radSq) continue;
        final c = cc + dc, r = cr + dr;
        if (!grid.inBounds(c, r)) continue;
        visible[r][c] = true;
        explored[r][c] = true;
      }
    }
  }

  bool isWorldVisible(Vector2 worldPos) {
    if (!fogEnabled) return true;
    final c = grid.colAt(worldPos.x), r = grid.rowAt(worldPos.y);
    if (!grid.inBounds(c, r)) return true;
    return visible[r][c];
  }

  // -------------------------------------------------------------------------
  // HUD sync + helpers
  // -------------------------------------------------------------------------
  void _syncHud() {
    cashView.value = cashOf(controlledTeam);
    final q = _queues[controlledTeam]!;
    if (q.isNotEmpty || queueView.value.isNotEmpty) {
      queueView.value = List<ProductionItem>.from(q);
    }
  }

  void showMessage(String msg, {double seconds = 3.5}) {
    message.value = msg;
    _msgTimer = seconds;
  }

  void bumpSelection() => selectionVersion.value++;

  void switchSide() {
    if (!hotseat) return;
    controlledTeam = controlledTeam == Team.player ? Team.enemy : Team.player;
    for (final u in selected) {
      u.selected = false;
    }
    selected.clear();
    placingKind = null;
    _centered = false; // recenter on the new side's base
    _updateFog();
    _syncHud();
    controlledVersion.value++;
    bumpSelection();
    showMessage('${controlledTeam == Team.player ? 'BLUE' : 'RED'} player — your move.',
        seconds: 2);
  }

  // -------------------------------------------------------------------------
  // Production / construction requests (HUD)
  // -------------------------------------------------------------------------
  void requestBuild(UnitKind kind) {
    final stats = kUnitStats[kind]!;
    if (_baseOf(controlledTeam) == null) {
      showMessage('No base to produce units.');
      return;
    }
    if (cashOf(controlledTeam) < stats.cost) {
      showMessage('Not enough credits.');
      return;
    }
    addCash(controlledTeam, -stats.cost);
    _queues[controlledTeam]!.add(ProductionItem(kind, stats.buildTime));
    _syncHud();
  }

  void requestPlace(BuildingKind kind) {
    final cost = kBuildingStats[kind]!.cost;
    if (cashOf(controlledTeam) < cost) {
      showMessage('Not enough credits.');
      return;
    }
    placingKind = kind;
    showMessage('Pick a spot to build the ${kBuildingStats[kind]!.label}.', seconds: 2.5);
  }

  bool _canPlaceAt(BuildingKind kind, int col, int row) {
    final st = kBuildingStats[kind]!;
    final exp = _explored[controlledTeam]!;
    for (var dc = 0; dc < st.wTiles; dc++) {
      for (var dr = 0; dr < st.hTiles; dr++) {
        final c = col + dc, r = row + dr;
        if (!grid.inBounds(c, r)) return false;
        if (!grid.passable(c, r)) return false;
        if (grid.terrain[r][c] == Terrain.ore) return false;
        if (!exp[r][c]) return false; // must be on explored ground
      }
    }
    return true;
  }

  void _tryPlaceAt(Vector2 world) {
    final kind = placingKind!;
    final col = grid.colAt(world.x), row = grid.rowAt(world.y);
    if (!_canPlaceAt(kind, col, row)) {
      showMessage('Cannot build there.', seconds: 2);
      return;
    }
    final cost = kBuildingStats[kind]!.cost;
    if (cashOf(controlledTeam) < cost) {
      showMessage('Not enough credits.');
      placingKind = null;
      return;
    }
    addCash(controlledTeam, -cost);
    place(kind, col, row, controlledTeam);
    sfx.build();
    placingKind = null;
    _syncHud();
  }

  // -------------------------------------------------------------------------
  // Input (screen-local coords from the Flutter layer)
  // -------------------------------------------------------------------------
  Vector2 screenToWorld(Offset screen) =>
      Vector2(screen.dx + viewOrigin.x, screen.dy + viewOrigin.y);

  void setPanKey(int bit, bool down) {
    if (down) {
      _panKeys.add(bit);
    } else {
      _panKeys.remove(bit);
    }
  }

  void panBy(Offset delta) {
    viewOrigin.add(Vector2(-delta.dx, -delta.dy));
    _clampCamera();
  }

  void setHover(Offset? screen) => hoverScreen = screen;

  void _centerCameraOn(Vector2 world) {
    if (!hasLayout) {
      viewOrigin.setValues(world.x - 400, world.y - 300);
    } else {
      viewOrigin.setValues(world.x - size.x / 2, world.y - size.y / 2);
    }
    _clampCamera();
  }

  void _clampCamera() {
    final viewW = hasLayout ? size.x : 0.0;
    final viewH = hasLayout ? size.y : 0.0;
    final maxX = math.max(0.0, grid.worldWidth - viewW);
    final maxY = math.max(0.0, grid.worldHeight - viewH);
    viewOrigin.x = viewOrigin.x.clamp(0.0, maxX);
    viewOrigin.y = viewOrigin.y.clamp(0.0, maxY);
  }

  // primary press: start selection box, or place a building
  void onPrimaryDown(Offset screen) {
    if (state.value != GameState.playing) return;
    if (placingKind != null) {
      _tryPlaceAt(screenToWorld(screen));
      return;
    }
    selStartScreen = screen;
    selCurrentScreen = screen;
  }

  void onDragUpdate(Offset screen) {
    if (selStartScreen != null) selCurrentScreen = screen;
  }

  void onPrimaryUp(Offset screen) {
    final start = selStartScreen;
    selStartScreen = null;
    selCurrentScreen = null;
    if (start == null) return;
    final dragDist = (screen - start).distance;
    if (dragDist < 6) {
      _clickSelect(screenToWorld(screen));
    } else {
      _boxSelect(screenToWorld(start), screenToWorld(screen));
    }
  }

  // touch: a tap either selects an own unit or commands the current selection
  void onTouchTap(Offset screen) {
    if (state.value != GameState.playing) return;
    final world = screenToWorld(screen);
    if (placingKind != null) {
      _tryPlaceAt(world);
      return;
    }
    final own = _ownUnitAt(world);
    if (own != null) {
      _selectOnly(own);
      return;
    }
    if (selected.isNotEmpty) {
      _issueOrder(world);
    } else {
      _deselect();
    }
  }

  void _selectOnly(Unit u) {
    _deselect();
    u.selected = true;
    selected.add(u);
    sfx.select();
    bumpSelection();
  }

  void _deselect() {
    for (final u in selected) {
      u.selected = false;
    }
    selected.clear();
    bumpSelection();
  }

  Unit? _ownUnitAt(Vector2 world) {
    Unit? hit;
    var bestD = double.infinity;
    for (final u in units) {
      if (u.team != controlledTeam || u.dead) continue;
      final d = u.pos.distanceToSquared(world);
      final rr = (u.radius + 6) * (u.radius + 6);
      if (d <= rr && d < bestD) {
        bestD = d;
        hit = u;
      }
    }
    return hit;
  }

  void _clickSelect(Vector2 world) {
    _deselect();
    final hit = _ownUnitAt(world);
    if (hit != null) {
      hit.selected = true;
      selected.add(hit);
      sfx.select();
    }
    bumpSelection();
  }

  void _boxSelect(Vector2 a, Vector2 b) {
    final rect = Rect.fromPoints(Offset(a.x, a.y), Offset(b.x, b.y));
    _deselect();
    for (final u in units) {
      if (u.team != controlledTeam || u.dead) continue;
      if (rect.contains(Offset(u.pos.x, u.pos.y))) {
        u.selected = true;
        selected.add(u);
      }
    }
    if (selected.isNotEmpty) sfx.select();
    bumpSelection();
  }

  void onSecondaryDown(Offset screen) {
    if (state.value != GameState.playing) return;
    if (placingKind != null) {
      placingKind = null; // cancel placement
      return;
    }
    if (selected.isEmpty) return;
    _issueOrder(screenToWorld(screen));
  }

  void _issueOrder(Vector2 world) {
    final enemy = _entityAt(world, hostileTo: controlledTeam);
    if (enemy != null) {
      for (final u in selected) {
        if (u.isHarvester) {
          u.orderMove(world, grid);
        } else {
          u.orderAttack(enemy);
        }
      }
      showMessage('Attacking!', seconds: 1.5);
      return;
    }
    final oc = grid.colAt(world.x), or = grid.rowAt(world.y);
    final harvesters = selected.where((u) => u.isHarvester).toList();
    if (grid.isOre(oc, or) && harvesters.isNotEmpty) {
      for (final h in harvesters) {
        h.orderHarvest(oc, or, grid);
      }
      for (final u in selected.where((u) => !u.isHarvester)) {
        u.orderMove(world, grid);
      }
      showMessage('Harvesting.', seconds: 1.5);
      return;
    }
    _moveGroup(world);
  }

  void _moveGroup(Vector2 target) {
    final n = selected.length;
    if (n == 1) {
      selected.first.orderMove(target, grid);
      return;
    }
    final cols = math.sqrt(n).ceil();
    const spacing = 34.0;
    for (var i = 0; i < n; i++) {
      final gx = i % cols;
      final gy = i ~/ cols;
      final offset = Vector2(
        (gx - (cols - 1) / 2) * spacing,
        (gy - (cols - 1) / 2) * spacing,
      );
      selected[i].orderMove(target + offset, grid);
    }
  }

  Entity? _entityAt(Vector2 world, {required Team hostileTo}) {
    for (final b in buildings) {
      if (b.dead || b.team == hostileTo) continue;
      final half = b.stats.wTiles * tileSize / 2;
      if ((world.x - b.pos.x).abs() <= half && (world.y - b.pos.y).abs() <= half) {
        return b;
      }
    }
    Entity? best;
    var bestD = double.infinity;
    for (final u in units) {
      if (u.dead || u.team == hostileTo) continue;
      final d = u.pos.distanceToSquared(world);
      if (d <= (u.radius + 4) * (u.radius + 4) && d < bestD) {
        bestD = d;
        best = u;
      }
    }
    return best;
  }

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!_worldReady) return;
    canvas.save();
    canvas.translate(-viewOrigin.x, -viewOrigin.y);

    _renderTerrain(canvas);

    for (final b in buildings) {
      if (b.team != controlledTeam && !isWorldVisible(b.pos)) continue;
      b.render(canvas);
    }
    for (final u in units) {
      if (u.isAircraft) continue;
      if (u.team != controlledTeam && !isWorldVisible(u.pos)) continue;
      u.render(canvas);
    }
    for (final bl in bullets) {
      bl.render(canvas);
    }
    for (final u in units) {
      if (!u.isAircraft) continue;
      if (u.team != controlledTeam && !isWorldVisible(u.pos)) continue;
      u.render(canvas);
    }
    for (final e in effects) {
      e.render(canvas);
    }

    if (placingKind != null && hoverScreen != null) _renderGhost(canvas);
    if (fogEnabled) _renderFog(canvas);

    canvas.restore();

    if (selStartScreen != null && selCurrentScreen != null) {
      final r = Rect.fromPoints(selStartScreen!, selCurrentScreen!);
      canvas.drawRect(r, Paint()..color = const Color(0x224FC3F7));
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF4FC3F7),
      );
    }
  }

  void _renderGhost(Canvas canvas) {
    final world = screenToWorld(hoverScreen!);
    final kind = placingKind!;
    final st = kBuildingStats[kind]!;
    final col = grid.colAt(world.x), row = grid.rowAt(world.y);
    final ok = _canPlaceAt(kind, col, row);
    final rect = Rect.fromLTWH(
        col * tileSize, row * tileSize, st.wTiles * tileSize, st.hTiles * tileSize);
    canvas.drawRect(
      rect,
      Paint()
        ..color = ok ? const Color(0x5566FF66) : const Color(0x55FF5555),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ok ? const Color(0xFF66FF66) : const Color(0xFFFF5555),
    );
  }

  void _renderTerrain(Canvas canvas) {
    final c0 = math.max(0, grid.colAt(viewOrigin.x));
    final r0 = math.max(0, grid.rowAt(viewOrigin.y));
    final c1 = math.min(grid.cols - 1, grid.colAt(viewOrigin.x + (hasLayout ? size.x : 800)) + 1);
    final r1 = math.min(grid.rows - 1, grid.rowAt(viewOrigin.y + (hasLayout ? size.y : 600)) + 1);

    final land = Paint()..color = const Color(0xFF2E4A2E);
    final landAlt = Paint()..color = const Color(0xFF335233);
    final rock = Paint()..color = const Color(0xFF5A5A55);
    final rockTop = Paint()..color = const Color(0xFF6E6E66);
    final oreP = Paint()..color = const Color(0xFFC9A227);
    final gridLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0x14000000);

    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        final x = c * tileSize, y = r * tileSize;
        final rect = Rect.fromLTWH(x, y, tileSize, tileSize);
        final t = grid.terrain[r][c];
        if (t == Terrain.rock) {
          canvas.drawRect(rect, rock);
          canvas.drawRect(Rect.fromLTWH(x + 3, y + 3, tileSize - 9, tileSize - 9), rockTop);
        } else if (t == Terrain.ore && grid.oreAmount[r][c] > 0) {
          canvas.drawRect(rect, (c + r) % 2 == 0 ? land : landAlt);
          final frac = (grid.oreAmount[r][c] / 600).clamp(0.25, 1.0);
          final s = tileSize * 0.7 * frac;
          canvas.drawRect(Rect.fromCenter(center: rect.center, width: s, height: s), oreP);
        } else {
          canvas.drawRect(rect, (c + r) % 2 == 0 ? land : landAlt);
        }
        canvas.drawRect(rect, gridLine);
      }
    }
  }

  void _renderFog(Canvas canvas) {
    final explored = _explored[controlledTeam]!;
    final c0 = math.max(0, grid.colAt(viewOrigin.x));
    final r0 = math.max(0, grid.rowAt(viewOrigin.y));
    final c1 = math.min(grid.cols - 1, grid.colAt(viewOrigin.x + (hasLayout ? size.x : 800)) + 1);
    final r1 = math.min(grid.rows - 1, grid.rowAt(viewOrigin.y + (hasLayout ? size.y : 600)) + 1);

    final unseen = Paint()..color = const Color(0xFF0A0F0A);
    final dim = Paint()..color = const Color(0x88000000);

    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        if (visible[r][c]) continue;
        final rect = Rect.fromLTWH(c * tileSize, r * tileSize, tileSize, tileSize);
        canvas.drawRect(rect, explored[r][c] ? dim : unseen);
      }
    }
  }
}
