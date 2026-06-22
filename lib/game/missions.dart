import 'package:flame/components.dart';

import 'entities.dart';
import 'game.dart';

typedef GameFn = void Function(LastColonyGame g);
typedef GameCond = bool Function(LastColonyGame g);

/// A scripted event: when [condition] is true, [action] runs (once, unless
/// [repeat]).
class Trigger {
  final GameCond condition;
  final GameFn action;
  final bool repeat;
  bool fired = false;
  Trigger(this.condition, this.action, {this.repeat = false});
}

class Mission {
  final String name;
  final String intro;
  final String objective;
  final GameFn build;
  final List<Trigger> Function(LastColonyGame g) triggers;
  const Mission({
    required this.name,
    required this.intro,
    required this.objective,
    required this.build,
    required this.triggers,
  });
}

// ---------------------------------------------------------------------------
// Shared map helpers
// ---------------------------------------------------------------------------
void _standardTerrain(LastColonyGame g, int cols, int rows, int seed) {
  g.newWorld(cols, rows);
  g.borderRocks();
  g.scatterRocks(seed, (cols * rows / 170).round());
}

/// Spawn a hostile wave of [kinds] near [team]'s base and send it at the rival.
void spawnWave(LastColonyGame g, Team team, List<UnitKind> kinds) {
  final base = g.nearestBase(g.rally[team]!, team);
  if (base == null) return;
  final target = g.rally[team == Team.player ? Team.enemy : Team.player]!;
  for (var i = 0; i < kinds.length; i++) {
    final u = g.spawn(
      kinds[i],
      base.pos + Vector2(-40.0 - (i % 3) * 26, 30.0 + (i ~/ 3) * 26),
      team,
    );
    u.orderMove(target.clone(), g.grid, attack: true);
  }
}

Vector2 _v(double x, double y) => Vector2(x, y);

// ---------------------------------------------------------------------------
// Campaign
// ---------------------------------------------------------------------------
final List<Mission> campaign = [
  // -- Mission 1 ------------------------------------------------------------
  Mission(
    name: '1 · Outpost Assault',
    intro: 'Command, the colonists are pinned. Wipe out the rebel outpost to the north-east.',
    objective: 'Destroy the enemy HQ.',
    build: (g) {
      _standardTerrain(g, 40, 30, 11);
      g.oreField(5, g.grid.rows - 7, 4, 4, 600);
      g.setCash(Team.player, 1500);
      g.setCash(Team.enemy, 600);
      final pBase = g.place(BuildingKind.base, 3, g.grid.rows - 5, Team.player);
      g.place(BuildingKind.base, g.grid.cols - 6, 2, Team.enemy);
      g.spawn(UnitKind.harvester, pBase.pos + _v(40, -75), Team.player);
      g.spawn(UnitKind.scoutTank, pBase.pos + _v(70, -40), Team.player);
      g.spawn(UnitKind.scoutTank, pBase.pos + _v(95, -10), Team.player);
      final eBase = g.nearestBase(g.rally[Team.enemy]!, Team.enemy)!;
      g.spawn(UnitKind.scoutTank, eBase.pos + _v(-60, 50), Team.enemy);
    },
    triggers: (g) => [
      Trigger((g) => g.elapsed > 4,
          (g) => g.showMessage('Use your scout tanks. Right-click / tap to give orders.')),
      Trigger((g) => g.elapsed > 22, (g) {
        g.showMessage('Enemy reinforcements spotted!');
        spawnWave(g, Team.enemy, [UnitKind.scoutTank, UnitKind.scoutTank]);
      }),
    ],
  ),

  // -- Mission 2 ------------------------------------------------------------
  Mission(
    name: '2 · Hold the Line',
    intro: 'They know we are here. Survive the assault waves, then break their base.',
    objective: 'Survive the waves, then destroy the enemy HQ.',
    build: (g) {
      _standardTerrain(g, 46, 34, 23);
      g.oreField(5, g.grid.rows - 8, 4, 4, 700);
      g.oreField(g.grid.cols ~/ 2 - 1, g.grid.rows ~/ 2 - 1, 3, 3, 500);
      g.setCash(Team.player, 1800);
      g.setCash(Team.enemy, 2500);
      final pBase = g.place(BuildingKind.base, 3, g.grid.rows - 6, Team.player);
      g.place(BuildingKind.base, g.grid.cols - 6, 2, Team.enemy);
      g.place(BuildingKind.turret, g.grid.cols - 8, 6, Team.enemy);
      g.spawn(UnitKind.harvester, pBase.pos + _v(40, -75), Team.player);
      g.spawn(UnitKind.scoutTank, pBase.pos + _v(80, -30), Team.player);
    },
    triggers: (g) => [
      Trigger((g) => g.elapsed > 8, (g) {
        g.showMessage('First wave incoming!');
        spawnWave(g, Team.enemy, [UnitKind.scoutTank, UnitKind.scoutTank]);
      }),
      Trigger((g) => g.elapsed > 22, (g) {
        g.showMessage('Second wave!');
        spawnWave(g, Team.enemy, [UnitKind.scoutTank, UnitKind.heavyTank]);
      }),
      Trigger((g) => g.elapsed > 40, (g) {
        g.showMessage('Reinforcements have arrived — push them back!');
        final b = g.nearestBase(g.rally[Team.player]!, Team.player);
        if (b != null) {
          g.spawn(UnitKind.heavyTank, b.pos + _v(60, -40), Team.player);
          g.spawn(UnitKind.heavyTank, b.pos + _v(90, -10), Team.player);
        }
      }),
    ],
  ),

  // -- Mission 3 ------------------------------------------------------------
  Mission(
    name: '3 · Last Colony',
    intro: 'This is the final stand. Their fortress is heavily defended. End it.',
    objective: 'Destroy the enemy fortress HQ.',
    build: (g) {
      _standardTerrain(g, 50, 40, 7);
      g.oreField(6, g.grid.rows - 8, 4, 4, 600);
      g.oreField(g.grid.cols ~/ 2 - 1, g.grid.rows ~/ 2 - 1, 3, 3, 500);
      g.oreField(g.grid.cols - 9, 5, 3, 3, 600);
      g.setCash(Team.player, 2200);
      g.setCash(Team.enemy, 4000);
      final pBase = g.place(BuildingKind.base, 3, g.grid.rows - 5, Team.player);
      final eBase = g.place(BuildingKind.base, g.grid.cols - 6, 2, Team.enemy);
      g.place(BuildingKind.turret, g.grid.cols - 8, 6, Team.enemy);
      g.place(BuildingKind.turret, g.grid.cols - 4, 7, Team.enemy);
      g.place(BuildingKind.power, g.grid.cols - 9, 2, Team.enemy);
      g.spawn(UnitKind.harvester, pBase.pos + _v(40, -75), Team.player);
      g.spawn(UnitKind.scoutTank, pBase.pos + _v(70, -40), Team.player);
      g.spawn(UnitKind.scoutTank, pBase.pos + _v(95, -10), Team.player);
      g.spawn(UnitKind.harvester, eBase.pos + _v(-40, 75), Team.enemy);
      g.spawn(UnitKind.scoutTank, eBase.pos + _v(-70, 40), Team.enemy);
      g.spawn(UnitKind.chopper, eBase.pos + _v(-30, 90), Team.enemy);
    },
    triggers: (g) => [
      Trigger((g) => g.elapsed > 5,
          (g) => g.showMessage('Build Power Plants for income and Turrets for defense.')),
      Trigger((g) => g.elapsed > 35, (g) {
        g.showMessage('Air raid!');
        spawnWave(g, Team.enemy, [UnitKind.chopper, UnitKind.chopper]);
      }),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Local 2-player skirmish (hotseat)
// ---------------------------------------------------------------------------
void buildSkirmishMap(LastColonyGame g) {
  _standardTerrain(g, 48, 36, 31);
  g.oreField(5, g.grid.rows - 8, 4, 4, 700);
  g.oreField(g.grid.cols - 9, 4, 4, 4, 700);
  g.oreField(g.grid.cols ~/ 2 - 1, g.grid.rows ~/ 2 - 1, 3, 3, 600);
  g.setCash(Team.player, 2000);
  g.setCash(Team.enemy, 2000);
  final blue = g.place(BuildingKind.base, 3, g.grid.rows - 6, Team.player);
  final red = g.place(BuildingKind.base, g.grid.cols - 6, 2, Team.enemy);
  g.spawn(UnitKind.harvester, blue.pos + _v(40, -75), Team.player);
  g.spawn(UnitKind.scoutTank, blue.pos + _v(75, -30), Team.player);
  g.spawn(UnitKind.harvester, red.pos + _v(-40, 75), Team.enemy);
  g.spawn(UnitKind.scoutTank, red.pos + _v(-75, 30), Team.enemy);
}
