import 'dart:collection';
import 'package:flame/components.dart';

/// Terrain types for each tile.
class Terrain {
  static const int land = 0;
  static const int rock = 1; // impassable obstacle
  static const int ore = 2; // harvestable resource
}

/// Tile-based world grid + A* pathfinding.
class GameGrid {
  final int cols;
  final int rows;
  final double tile;
  late final List<List<int>> terrain;
  late final List<List<double>> oreAmount; // remaining ore per tile

  /// Dynamic blocking from buildings (grid cells occupied by structures).
  final Set<int> blocked = {};

  GameGrid(this.cols, this.rows, this.tile) {
    terrain = List.generate(rows, (_) => List.filled(cols, Terrain.land));
    oreAmount = List.generate(rows, (_) => List.filled(cols, 0));
  }

  double get worldWidth => cols * tile;
  double get worldHeight => rows * tile;

  int _key(int c, int r) => r * cols + c;

  bool inBounds(int c, int r) => c >= 0 && r >= 0 && c < cols && r < rows;

  void setTerrain(int c, int r, int t) {
    if (inBounds(c, r)) terrain[r][c] = t;
  }

  void addOre(int c, int r, double amount) {
    if (inBounds(c, r)) {
      terrain[r][c] = Terrain.ore;
      oreAmount[r][c] = amount;
    }
  }

  bool isOre(int c, int r) =>
      inBounds(c, r) && terrain[r][c] == Terrain.ore && oreAmount[r][c] > 0;

  /// Whether a tile can be walked through (terrain + building occupancy).
  bool passable(int c, int r) {
    if (!inBounds(c, r)) return false;
    if (terrain[r][c] == Terrain.rock) return false;
    if (blocked.contains(_key(c, r))) return false;
    return true;
  }

  void blockCell(int c, int r) {
    if (inBounds(c, r)) blocked.add(_key(c, r));
  }

  void unblockCell(int c, int r) {
    if (inBounds(c, r)) blocked.remove(_key(c, r));
  }

  // ---- coordinate helpers ----
  int colAt(double x) => (x / tile).floor();
  int rowAt(double y) => (y / tile).floor();

  Vector2 cellCenter(int c, int r) =>
      Vector2((c + 0.5) * tile, (r + 0.5) * tile);

  /// Find the nearest passable tile to (c,r) using an expanding ring search.
  List<int>? nearestPassable(int c, int r, {int maxRadius = 12}) {
    if (passable(c, r)) return [c, r];
    for (var rad = 1; rad <= maxRadius; rad++) {
      for (var dc = -rad; dc <= rad; dc++) {
        for (var dr = -rad; dr <= rad; dr++) {
          if (dc.abs() != rad && dr.abs() != rad) continue; // ring only
          final nc = c + dc, nr = r + dr;
          if (passable(nc, nr)) return [nc, nr];
        }
      }
    }
    return null;
  }

  /// A* pathfinding returning a list of [col,row] cells from start to goal
  /// (excluding the start cell). Allows diagonal movement.
  List<List<int>> findPath(int sc, int sr, int gc, int gr) {
    if (!inBounds(gc, gr) || !passable(gc, gr)) {
      final near = nearestPassable(gc, gr);
      if (near == null) return [];
      gc = near[0];
      gr = near[1];
    }
    if (sc == gc && sr == gr) return [];

    final open = HashMap<int, _Node>();
    final closed = HashSet<int>();
    final pq = _PriorityQueue();

    final startKey = _key(sc, sr);
    final start = _Node(sc, sr, 0, _heuristic(sc, sr, gc, gr), null);
    open[startKey] = start;
    pq.add(start);

    const dirs = [
      [1, 0], [-1, 0], [0, 1], [0, -1],
      [1, 1], [1, -1], [-1, 1], [-1, -1],
    ];

    var iterations = 0;
    while (pq.isNotEmpty) {
      if (iterations++ > 12000) break; // safety cap
      final cur = pq.removeFirst();
      final curKey = _key(cur.c, cur.r);
      if (closed.contains(curKey)) continue;
      closed.add(curKey);

      if (cur.c == gc && cur.r == gr) {
        return _reconstruct(cur);
      }

      for (final d in dirs) {
        final nc = cur.c + d[0];
        final nr = cur.r + d[1];
        if (!passable(nc, nr)) continue;
        final diagonal = d[0] != 0 && d[1] != 0;
        // prevent cutting through wall corners diagonally
        if (diagonal && (!passable(cur.c + d[0], cur.r) || !passable(cur.c, cur.r + d[1]))) {
          continue;
        }
        final nKey = _key(nc, nr);
        if (closed.contains(nKey)) continue;
        final stepCost = diagonal ? 1.414 : 1.0;
        final g = cur.g + stepCost;
        final existing = open[nKey];
        if (existing == null || g < existing.g) {
          final node = _Node(nc, nr, g, g + _heuristic(nc, nr, gc, gr), cur);
          open[nKey] = node;
          pq.add(node);
        }
      }
    }
    return [];
  }

  double _heuristic(int c, int r, int gc, int gr) {
    final dx = (c - gc).abs().toDouble();
    final dy = (r - gr).abs().toDouble();
    // octile distance
    return (dx + dy) + (1.414 - 2) * (dx < dy ? dx : dy);
  }

  List<List<int>> _reconstruct(_Node end) {
    final path = <List<int>>[];
    _Node? n = end;
    while (n != null && n.parent != null) {
      path.add([n.c, n.r]);
      n = n.parent;
    }
    return path.reversed.toList();
  }
}

class _Node {
  final int c, r;
  final double g, f;
  final _Node? parent;
  _Node(this.c, this.r, this.g, this.f, this.parent);
}

/// Minimal binary-heap priority queue ordered by node.f.
class _PriorityQueue {
  final List<_Node> _heap = [];

  bool get isNotEmpty => _heap.isNotEmpty;

  void add(_Node node) {
    _heap.add(node);
    var i = _heap.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_heap[parent].f <= _heap[i].f) break;
      _swap(i, parent);
      i = parent;
    }
  }

  _Node removeFirst() {
    final first = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      var i = 0;
      final n = _heap.length;
      while (true) {
        final l = 2 * i + 1, r = 2 * i + 2;
        var smallest = i;
        if (l < n && _heap[l].f < _heap[smallest].f) smallest = l;
        if (r < n && _heap[r].f < _heap[smallest].f) smallest = r;
        if (smallest == i) break;
        _swap(i, smallest);
        i = smallest;
      }
    }
    return first;
  }

  void _swap(int a, int b) {
    final t = _heap[a];
    _heap[a] = _heap[b];
    _heap[b] = t;
  }
}
