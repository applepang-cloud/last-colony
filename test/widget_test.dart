import 'package:flutter_test/flutter_test.dart';

import 'package:last_colony/game/grid.dart';

void main() {
  test('A* finds a path across open ground', () {
    final grid = GameGrid(10, 10, 32);
    final path = grid.findPath(0, 0, 9, 9);
    expect(path.isNotEmpty, true);
    expect(path.last, [9, 9]);
  });

  test('A* routes around an obstacle wall', () {
    final grid = GameGrid(10, 10, 32);
    for (var r = 0; r < 9; r++) {
      grid.setTerrain(5, r, Terrain.rock);
    }
    final path = grid.findPath(0, 0, 9, 0);
    expect(path.isNotEmpty, true);
    // must detour below the wall
    expect(path.any((c) => c[1] >= 9), true);
  });
}
