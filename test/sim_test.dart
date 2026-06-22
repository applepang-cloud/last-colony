import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_colony/game/entities.dart';
import 'package:last_colony/game/game.dart';
import 'package:last_colony/game/grid.dart';
import 'package:last_colony/game/missions.dart';

/// Step the headless game simulation for [seconds] at a fixed timestep.
void simulate(LastColonyGame g, double seconds, {double dt = 0.1}) {
  final steps = (seconds / dt).round();
  for (var i = 0; i < steps; i++) {
    g.update(dt);
  }
}

LastColonyGame startedGame(int mission) {
  final g = LastColonyGame();
  g.startMission(mission);
  return g;
}

void main() {
  test('mission builds with both bases and starting units', () {
    final g = startedGame(2);
    expect(g.buildings.any((b) => b.team == Team.player && b.kind == BuildingKind.base), true);
    expect(g.buildings.any((b) => b.team == Team.enemy && b.kind == BuildingKind.base), true);
    expect(g.units.where((u) => u.team == Team.player).length, greaterThanOrEqualTo(3));
  });

  test('harvester gathers ore and deposits credits at the base', () {
    final g = startedGame(2);
    g.aiTeams = {}; // isolate player economy
    final startCash = g.cashOf(Team.player);
    simulate(g, 60);
    expect(g.cashOf(Team.player), greaterThan(startCash));
  });

  test('production queues a unit and spawns it after the build time', () {
    final g = startedGame(2);
    g.aiTeams = {};
    g.setCash(Team.player, 5000);
    final before = g.units.where((u) => u.team == Team.player).length;
    g.requestBuild(UnitKind.scoutTank);
    expect(g.queueView.value.length, 1);
    simulate(g, kUnitStats[UnitKind.scoutTank]!.buildTime + 1);
    expect(g.queueView.value.isEmpty, true);
    expect(g.units.where((u) => u.team == Team.player).length, before + 1);
  });

  test('player can construct a turret on explored ground', () {
    final g = startedGame(2);
    g.aiTeams = {};
    g.setCash(Team.player, 5000);
    final before = g.buildings.where((b) => b.team == Team.player).length;
    final base = g.nearestBase(g.rally[Team.player]!, Team.player)!;
    final bc = g.grid.colAt(base.pos.x), br = g.grid.rowAt(base.pos.y);

    // find a passable, non-ore, currently-visible (=explored) cell near base
    Vector2? world;
    outer:
    for (var rad = 2; rad < 8 && world == null; rad++) {
      for (var dc = -rad; dc <= rad; dc++) {
        for (var dr = -rad; dr <= rad; dr++) {
          final c = bc + dc, r = br + dr;
          if (!g.grid.inBounds(c, r)) continue;
          if (!g.grid.passable(c, r)) continue;
          if (g.grid.terrain[r][c] == Terrain.ore) continue;
          final w = g.grid.cellCenter(c, r);
          if (!g.isWorldVisible(w)) continue;
          world = w;
          break outer;
        }
      }
    }
    expect(world, isNotNull, reason: 'should find a buildable cell near the base');

    g.requestPlace(BuildingKind.turret);
    g.onPrimaryDown(Offset(world!.x - g.viewOrigin.x, world.y - g.viewOrigin.y));
    expect(g.buildings.where((b) => b.team == Team.player).length, before + 1);
    expect(g.buildings.any((b) => b.team == Team.player && b.kind == BuildingKind.turret), true);
  });

  test('combat: a heavy tank destroys a nearby scout', () {
    final g = startedGame(2);
    g.aiTeams = {};
    g.units.clear();
    final mid = Vector2(g.grid.worldWidth / 2, g.grid.worldHeight / 2);
    final ally = Unit(UnitKind.heavyTank, mid.clone(), Team.player);
    final foe = Unit(UnitKind.scoutTank, mid + Vector2(80, 0), Team.enemy);
    g.units.addAll([ally, foe]);
    simulate(g, 1.0);
    expect(foe.hp, lessThan(foe.maxHp));
    simulate(g, 15.0);
    expect(foe.dead, true);
  });

  test('aircraft fly in a straight line over impassable terrain', () {
    final g = startedGame(2);
    g.aiTeams = {};
    g.units.clear();
    final start = Vector2(100, 100);
    final dest = Vector2(100, 900);
    for (var r = 0; r < g.grid.rows; r++) {
      g.grid.setTerrain(3, r, Terrain.rock);
    }
    final chop = Unit(UnitKind.chopper, start.clone(), Team.player);
    g.units.add(chop);
    chop.orderMove(dest, g.grid);
    expect(chop.isAircraft, true);
    expect(chop.path.length, 1);
    simulate(g, 12);
    expect(chop.pos.distanceTo(dest), lessThan(40));
  });

  test('fog hides the unexplored enemy base but reveals the player base', () {
    final g = startedGame(2);
    final playerBase =
        g.buildings.firstWhere((b) => b.team == Team.player && b.kind == BuildingKind.base);
    final enemyBase =
        g.buildings.firstWhere((b) => b.team == Team.enemy && b.kind == BuildingKind.base);
    expect(g.isWorldVisible(playerBase.pos), true);
    expect(g.isWorldVisible(enemyBase.pos), false);
  });

  test('victory triggers when the enemy base is destroyed', () {
    final g = startedGame(2);
    final enemyBase =
        g.buildings.firstWhere((b) => b.team == Team.enemy && b.kind == BuildingKind.base);
    enemyBase.damage(enemyBase.maxHp);
    simulate(g, 0.2);
    expect(g.state.value, GameState.ended);
    expect(g.winner, Team.player);
  });

  test('hotseat starts with no AI and switches controlled side', () {
    final g = LastColonyGame();
    g.startHotseat();
    expect(g.hotseat, true);
    expect(g.aiTeams.isEmpty, true);
    expect(g.controlledTeam, Team.player);
    g.switchSide();
    expect(g.controlledTeam, Team.enemy);
  });

  test('campaign defines three missions', () {
    expect(campaign.length, 3);
  });
}
