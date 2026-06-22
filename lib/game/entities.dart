import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'game.dart';
import 'grid.dart';

enum Team { player, enemy }

enum UnitKind { scoutTank, heavyTank, harvester, chopper, wraith }

enum BuildingKind { base, turret, power }

/// Shared base for everything that lives on the battlefield.
abstract class Entity {
  Vector2 pos; // center, world pixels
  Team team;
  double hp;
  double maxHp;
  bool dead = false;

  Entity(this.pos, this.team, this.maxHp) : hp = maxHp;

  double get radius;

  void damage(double amount) {
    hp -= amount;
    if (hp <= 0) {
      hp = 0;
      dead = true;
    }
  }

  void update(double dt, LastColonyGame game);
  void render(Canvas canvas);

  Color get teamColor =>
      team == Team.player ? const Color(0xFF4FC3F7) : const Color(0xFFEF5350);

  void renderHealthBar(Canvas canvas, double w) {
    if (hp >= maxHp) return;
    final frac = (hp / maxHp).clamp(0.0, 1.0);
    final top = pos.y - radius - 8;
    final left = pos.x - w / 2;
    final bg = Paint()..color = const Color(0xCC000000);
    canvas.drawRect(Rect.fromLTWH(left, top, w, 4), bg);
    final fg = Paint()
      ..color = frac > 0.5
          ? const Color(0xFF66BB6A)
          : frac > 0.25
              ? const Color(0xFFFFCA28)
              : const Color(0xFFEF5350);
    canvas.drawRect(Rect.fromLTWH(left, top, w * frac, 4), fg);
  }
}

// ---------------------------------------------------------------------------
// Units
// ---------------------------------------------------------------------------

class UnitStats {
  final double maxHp;
  final double speed; // px/sec
  final double sight; // px
  final double range; // px
  final double damage;
  final double fireRate; // shots/sec
  final double radius;
  final int cost;
  final double buildTime;
  final String label;
  const UnitStats({
    required this.maxHp,
    required this.speed,
    required this.sight,
    required this.range,
    required this.damage,
    required this.fireRate,
    required this.radius,
    required this.cost,
    required this.buildTime,
    required this.label,
  });
}

const Map<UnitKind, UnitStats> kUnitStats = {
  UnitKind.scoutTank: UnitStats(
    maxHp: 50,
    speed: 95,
    sight: 220,
    range: 120,
    damage: 9,
    fireRate: 1.6,
    radius: 11,
    cost: 500,
    buildTime: 4,
    label: 'Scout Tank',
  ),
  UnitKind.heavyTank: UnitStats(
    maxHp: 120,
    speed: 60,
    sight: 240,
    range: 150,
    damage: 18,
    fireRate: 1.0,
    radius: 14,
    cost: 1200,
    buildTime: 8,
    label: 'Heavy Tank',
  ),
  UnitKind.harvester: UnitStats(
    maxHp: 90,
    speed: 70,
    sight: 160,
    range: 0,
    damage: 0,
    fireRate: 0,
    radius: 13,
    cost: 800,
    buildTime: 6,
    label: 'Harvester',
  ),
  UnitKind.chopper: UnitStats(
    maxHp: 70,
    speed: 150,
    sight: 280,
    range: 140,
    damage: 11,
    fireRate: 2.2,
    radius: 13,
    cost: 1100,
    buildTime: 7,
    label: 'Chopper',
  ),
  UnitKind.wraith: UnitStats(
    maxHp: 110,
    speed: 200,
    sight: 300,
    range: 160,
    damage: 22,
    fireRate: 1.4,
    radius: 14,
    cost: 1600,
    buildTime: 10,
    label: 'Wraith',
  ),
};

enum HarvestState { idle, toOre, mining, toBase, depositing }

class Unit extends Entity {
  final UnitKind kind;
  final UnitStats stats;
  bool selected = false;

  // movement
  List<Vector2> path = [];
  double angle = 0;

  // combat
  Entity? target;
  bool attackMove = false;
  double _fireCd = 0;
  double turretAngle = 0;
  double muzzle = 0; // muzzle-flash timer

  // harvester
  double ore = 0;
  static const double oreCapacity = 500;
  HarvestState hState = HarvestState.idle;
  double _mineTimer = 0;
  int? oreCol, oreRow;

  Unit(this.kind, Vector2 pos, Team team)
      : stats = kUnitStats[kind]!,
        super(pos, team, kUnitStats[kind]!.maxHp);

  bool get isHarvester => kind == UnitKind.harvester;
  bool get isAircraft => kind == UnitKind.chopper || kind == UnitKind.wraith;

  @override
  double get radius => stats.radius;

  void orderMove(Vector2 worldTarget, GameGrid grid, {bool attack = false}) {
    target = null;
    attackMove = attack;
    if (isHarvester) hState = HarvestState.idle;
    _computePath(worldTarget, grid);
  }

  void orderAttack(Entity enemy) {
    target = enemy;
    attackMove = false;
    path = [];
    if (isHarvester) hState = HarvestState.idle;
  }

  void orderHarvest(int col, int row, GameGrid grid) {
    if (!isHarvester) return;
    oreCol = col;
    oreRow = row;
    hState = HarvestState.toOre;
    final adj = grid.nearestPassable(col, row);
    if (adj != null) _computePath(grid.cellCenter(adj[0], adj[1]), grid);
  }

  void _computePath(Vector2 worldTarget, GameGrid grid) {
    if (isAircraft) {
      // aircraft ignore terrain and fly in a straight line
      path = [worldTarget.clone()];
      return;
    }
    final sc = grid.colAt(pos.x), sr = grid.rowAt(pos.y);
    final gc = grid.colAt(worldTarget.x), gr = grid.rowAt(worldTarget.y);
    final cells = grid.findPath(sc, sr, gc, gr);
    path = cells.map((cell) => grid.cellCenter(cell[0], cell[1])).toList();
    if (path.isNotEmpty) {
      // last waypoint uses exact requested point for smoother arrival
      path[path.length - 1] = worldTarget.clone();
    }
  }

  @override
  void update(double dt, LastColonyGame game) {
    if (_fireCd > 0) _fireCd -= dt;
    if (muzzle > 0) muzzle -= dt;

    if (isHarvester) {
      _updateHarvester(dt, game);
    } else {
      _updateCombat(dt, game);
    }

    _followPath(dt);
    _separate(game);
  }

  // ---- combat units ----
  void _updateCombat(double dt, LastColonyGame game) {
    // drop dead target
    if (target != null && target!.dead) target = null;

    // acquire target if idle or attack-moving
    if (target == null && (path.isEmpty || attackMove)) {
      final enemy = game.nearestEnemy(pos, team, stats.sight);
      if (enemy != null) {
        target = enemy;
        if (path.isNotEmpty && !attackMove) target = null;
      }
    }

    if (target != null) {
      final d = target!.pos.distanceTo(pos);
      turretAngle = math.atan2(target!.pos.y - pos.y, target!.pos.x - pos.x);
      if (d <= stats.range) {
        path = []; // stop and fire
        if (_fireCd <= 0) {
          game.spawnBullet(pos.clone(), target!, stats.damage, team);
          game.sfx.shoot();
          muzzle = 0.06;
          _fireCd = 1 / stats.fireRate;
        }
      } else if (d > stats.sight * 1.3) {
        target = null; // lost it
      } else if (path.isEmpty) {
        _computePath(target!.pos, game.grid);
      }
    }
  }

  // ---- harvester ----
  void _updateHarvester(double dt, LastColonyGame game) {
    switch (hState) {
      case HarvestState.idle:
        if (ore >= oreCapacity) {
          _headToBase(game);
        } else {
          final found = game.findNearestOre(pos);
          if (found != null) {
            orderHarvest(found[0], found[1], game.grid);
          }
        }
        break;
      case HarvestState.toOre:
        if (path.isEmpty) {
          if (oreCol != null && game.grid.isOre(oreCol!, oreRow!)) {
            hState = HarvestState.mining;
            _mineTimer = 0;
          } else {
            hState = HarvestState.idle;
          }
        }
        break;
      case HarvestState.mining:
        _mineTimer += dt;
        if (_mineTimer >= 0.25) {
          _mineTimer = 0;
          final mined = game.mineOre(oreCol!, oreRow!, 25);
          ore += mined;
          if (mined <= 0 || ore >= oreCapacity) {
            _headToBase(game);
          }
        }
        break;
      case HarvestState.toBase:
        if (path.isEmpty) {
          hState = HarvestState.depositing;
          _mineTimer = 0;
        }
        break;
      case HarvestState.depositing:
        _mineTimer += dt;
        if (_mineTimer >= 0.4) {
          game.addCash(team, ore.round());
          ore = 0;
          hState = HarvestState.idle;
        }
        break;
    }
  }

  void _headToBase(LastColonyGame game) {
    final base = game.nearestBase(pos, team);
    if (base == null) {
      hState = HarvestState.idle;
      return;
    }
    hState = HarvestState.toBase;
    _computePath(base.pos, game.grid);
  }

  void _followPath(double dt) {
    if (path.isEmpty) return;
    final next = path.first;
    final toNext = next - pos;
    final dist = toNext.length;
    if (dist < 2) {
      path.removeAt(0);
      return;
    }
    final dir = toNext / dist;
    angle = math.atan2(dir.y, dir.x);
    final step = stats.speed * dt;
    if (step >= dist) {
      pos.setFrom(next);
      path.removeAt(0);
    } else {
      pos.add(dir * step);
    }
  }

  /// Soft collision: push apart from overlapping units.
  void _separate(LastColonyGame game) {
    if (isAircraft) return; // aircraft don't jostle on the ground
    for (final other in game.units) {
      if (identical(other, this) || other.dead || other.isAircraft) continue;
      final delta = pos - other.pos;
      final d = delta.length;
      final minD = radius + other.radius;
      if (d > 0 && d < minD) {
        final push = (minD - d) * 0.5;
        pos.add(delta / d * push);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(pos.x, pos.y);

    if (selected) {
      canvas.drawCircle(
        Offset.zero,
        radius + 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF7CFF6B),
      );
    }

    if (isAircraft) {
      // ground shadow, drawn unrotated and offset down-right
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(radius * 0.5, radius * 0.9),
            width: radius * 1.8,
            height: radius * 0.9),
        Paint()..color = const Color(0x55000000),
      );
    }

    final body = Paint()..color = teamColor;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black54;

    if (isHarvester) {
      canvas.save();
      canvas.rotate(angle);
      final r = Rect.fromCenter(
          center: Offset.zero, width: radius * 2.2, height: radius * 1.7);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(3)),
          Paint()..color = const Color(0xFFB08D57));
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(3)), outline);
      // ore fill indicator
      final fill = (ore / oreCapacity).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(-radius, -radius * 0.5, radius * 2 * fill, radius),
        Paint()..color = const Color(0xFFFFD54F),
      );
      canvas.restore();
    } else if (isAircraft) {
      canvas.save();
      canvas.rotate(angle);
      final r = Rect.fromCenter(
          center: Offset.zero, width: radius * 2.2, height: radius * 0.9);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(radius * 0.45)), body);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(radius * 0.45)), outline);
      canvas.drawCircle(
          Offset(radius * 0.8, 0), radius * 0.28, Paint()..color = Colors.black54);
      if (kind == UnitKind.wraith) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset(-radius * 0.2, 0),
                    width: radius * 0.8,
                    height: radius * 2.4),
                const Radius.circular(2)),
            body);
      } else {
        canvas.drawCircle(
          Offset.zero,
          radius * 1.25,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0x66FFFFFF),
        );
      }
      if (muzzle > 0) {
        canvas.drawCircle(Offset(radius * 1.3, 0), 4,
            Paint()..color = const Color(0xFFFFE082));
      }
      canvas.restore();
    } else {
      // tank: body + treads turn with movement; turret aims independently
      canvas.save();
      canvas.rotate(angle);
      final tread = Paint()..color = const Color(0xFF263238);
      canvas.drawRect(
          Rect.fromLTWH(-radius, -radius * 0.85 - 1, radius * 2, 4), tread);
      canvas.drawRect(
          Rect.fromLTWH(-radius, radius * 0.85 - 3, radius * 2, 4), tread);
      final r = Rect.fromCenter(
          center: Offset.zero, width: radius * 2, height: radius * 1.5);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(2)), body);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(2)), outline);
      canvas.restore();

      canvas.save();
      canvas.rotate(turretAngle);
      canvas.drawRect(
        Rect.fromLTWH(0, -2.5, radius + 9, 5),
        Paint()..color = Colors.black87,
      );
      canvas.drawCircle(Offset.zero, radius * 0.6, Paint()..color = const Color(0xFF1C262B));
      if (muzzle > 0) {
        canvas.drawCircle(Offset(radius + 10, 0), 4.5,
            Paint()..color = const Color(0xFFFFE082));
      }
      canvas.restore();
    }
    canvas.restore();

    renderHealthBar(canvas, radius * 2.2);
  }
}

// ---------------------------------------------------------------------------
// Visual effects
// ---------------------------------------------------------------------------

/// Short-lived expanding blast used for deaths and impacts.
class Explosion {
  final Vector2 pos;
  final double maxRadius;
  double t = 0;
  final double dur;
  Explosion(this.pos, {this.maxRadius = 26, this.dur = 0.45});

  bool get dead => t >= dur;

  void update(double dt) => t += dt;

  void render(Canvas canvas) {
    final p = (t / dur).clamp(0.0, 1.0);
    final r = maxRadius * Curves.easeOut.transform(p);
    final fade = (1 - p);
    canvas.drawCircle(
      Offset(pos.x, pos.y),
      r,
      Paint()..color = Color.fromRGBO(255, 170, 60, 0.55 * fade),
    );
    canvas.drawCircle(
      Offset(pos.x, pos.y),
      r * 0.6,
      Paint()..color = Color.fromRGBO(255, 240, 180, 0.7 * fade),
    );
  }
}

// ---------------------------------------------------------------------------
// Buildings
// ---------------------------------------------------------------------------

class BuildingStats {
  final double maxHp;
  final int wTiles;
  final int hTiles;
  final double sight;
  final double range;
  final double damage;
  final double fireRate;
  final int cost;
  final String label;
  const BuildingStats({
    required this.maxHp,
    required this.wTiles,
    required this.hTiles,
    required this.sight,
    required this.range,
    required this.damage,
    required this.fireRate,
    required this.cost,
    required this.label,
  });
}

const Map<BuildingKind, BuildingStats> kBuildingStats = {
  BuildingKind.base: BuildingStats(
    maxHp: 600,
    wTiles: 3,
    hTiles: 3,
    sight: 260,
    range: 0,
    damage: 0,
    fireRate: 0,
    cost: 0,
    label: 'Command Base',
  ),
  BuildingKind.turret: BuildingStats(
    maxHp: 200,
    wTiles: 1,
    hTiles: 1,
    sight: 240,
    range: 200,
    damage: 14,
    fireRate: 1.2,
    cost: 600,
    label: 'Turret',
  ),
  BuildingKind.power: BuildingStats(
    maxHp: 250,
    wTiles: 2,
    hTiles: 2,
    sight: 140,
    range: 0,
    damage: 0,
    fireRate: 0,
    cost: 800,
    label: 'Power Plant',
  ),
};

class Building extends Entity {
  final BuildingKind kind;
  final BuildingStats stats;
  final int col, row; // top-left grid cell
  bool selected = false;

  Entity? target;
  double _fireCd = 0;
  double turretAngle = 0;
  double muzzle = 0;

  Building(this.kind, this.col, this.row, Team team, GameGrid grid)
      : stats = kBuildingStats[kind]!,
        super(
          grid.cellCenter(col, row) +
              Vector2((kBuildingStats[kind]!.wTiles - 1) * grid.tile / 2,
                  (kBuildingStats[kind]!.hTiles - 1) * grid.tile / 2),
          team,
          kBuildingStats[kind]!.maxHp,
        );

  @override
  double get radius => stats.wTiles * 16.0;

  void occupy(GameGrid grid) {
    for (var dc = 0; dc < stats.wTiles; dc++) {
      for (var dr = 0; dr < stats.hTiles; dr++) {
        grid.blockCell(col + dc, row + dr);
      }
    }
  }

  void release(GameGrid grid) {
    for (var dc = 0; dc < stats.wTiles; dc++) {
      for (var dr = 0; dr < stats.hTiles; dr++) {
        grid.unblockCell(col + dc, row + dr);
      }
    }
  }

  @override
  void update(double dt, LastColonyGame game) {
    if (_fireCd > 0) _fireCd -= dt;
    if (muzzle > 0) muzzle -= dt;
    if (stats.range <= 0) return;

    if (target != null && (target!.dead || target!.pos.distanceTo(pos) > stats.sight * 1.2)) {
      target = null;
    }
    target ??= game.nearestEnemy(pos, team, stats.sight);
    if (target != null) {
      turretAngle = math.atan2(target!.pos.y - pos.y, target!.pos.x - pos.x);
      if (target!.pos.distanceTo(pos) <= stats.range && _fireCd <= 0) {
        game.spawnBullet(pos.clone(), target!, stats.damage, team);
        game.sfx.shoot();
        muzzle = 0.06;
        _fireCd = 1 / stats.fireRate;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final w = stats.wTiles * 32.0;
    final h = stats.hTiles * 32.0;
    final rect = Rect.fromCenter(center: Offset(pos.x, pos.y), width: w - 4, height: h - 4);

    if (selected) {
      canvas.drawRect(
        rect.inflate(4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF7CFF6B),
      );
    }

    if (kind == BuildingKind.base) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = team == Team.player ? const Color(0xFF37474F) : const Color(0xFF4E342E),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = teamColor,
      );
      // central pad
      canvas.drawCircle(Offset(pos.x, pos.y), w * 0.22,
          Paint()..color = teamColor.withValues(alpha: 0.8));
    } else if (kind == BuildingKind.power) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = const Color(0xFF3A3F2E),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = teamColor,
      );
      // lightning glyph
      final p = Path()
        ..moveTo(pos.x + 3, pos.y - h * 0.28)
        ..lineTo(pos.x - 6, pos.y + 2)
        ..lineTo(pos.x, pos.y + 2)
        ..lineTo(pos.x - 3, pos.y + h * 0.28)
        ..lineTo(pos.x + 8, pos.y - 4)
        ..lineTo(pos.x + 1, pos.y - 4)
        ..close();
      canvas.drawPath(p, Paint()..color = const Color(0xFFFFE082));
    } else {
      // turret base
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = const Color(0xFF455A64),
      );
      canvas.drawCircle(Offset(pos.x, pos.y), w * 0.28, Paint()..color = teamColor);
      // barrel
      canvas.save();
      canvas.translate(pos.x, pos.y);
      canvas.rotate(turretAngle);
      canvas.drawRect(Rect.fromLTWH(0, -3, w * 0.5, 6), Paint()..color = Colors.black87);
      if (muzzle > 0) {
        canvas.drawCircle(
            Offset(w * 0.5 + 3, 0), 4, Paint()..color = const Color(0xFFFFE082));
      }
      canvas.restore();
    }

    renderHealthBar(canvas, w);
  }
}

// ---------------------------------------------------------------------------
// Bullets
// ---------------------------------------------------------------------------

class Bullet {
  Vector2 pos;
  final Entity target;
  Vector2 _vel;
  final double damage;
  final Team team;
  bool dead = false;
  static const double speed = 420;

  Bullet(this.pos, this.target, this.damage, this.team)
      : _vel = Vector2.zero();

  void update(double dt) {
    if (target.dead) {
      dead = true;
      return;
    }
    final to = target.pos - pos;
    final d = to.length;
    if (d < 6) {
      target.damage(damage);
      dead = true;
      return;
    }
    _vel = to / d * speed;
    pos.add(_vel * dt);
  }

  void render(Canvas canvas) {
    canvas.drawCircle(
      Offset(pos.x, pos.y),
      2.5,
      Paint()
        ..color = team == Team.player ? const Color(0xFFB3E5FC) : const Color(0xFFFFAB91),
    );
  }
}
