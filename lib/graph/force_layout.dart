import 'dart:math';

import '../models/memory_graph.dart';

/// Plain, isolate-friendly input for [forceLayout].
class LayoutInput {
  final List<String> ids;

  /// For event nodes, 0..1 position along the timeline; null otherwise.
  final List<double?> timeAnchors;
  final List<(int, int)> edges;
  final int iterations;

  const LayoutInput(
    this.ids,
    this.timeAnchors,
    this.edges, {
    this.iterations = 300,
  });

  factory LayoutInput.fromGraph(GraphData graph) {
    final index = {
      for (var i = 0; i < graph.nodes.length; i++) graph.nodes[i].id: i,
    };
    final times = graph.nodes
        .where((n) => n.time != null)
        .map((n) => n.time!.millisecondsSinceEpoch)
        .toList();
    final minT = times.isEmpty ? 0 : times.reduce(min);
    final maxT = times.isEmpty ? 0 : times.reduce(max);
    return LayoutInput(
      [for (final n in graph.nodes) n.id],
      [
        for (final n in graph.nodes)
          n.time == null
              ? null
              : maxT == minT
              ? 0.5
              : (n.time!.millisecondsSinceEpoch - minT) / (maxT - minT),
      ],
      [
        for (final e in graph.edges)
          if (index[e.from] != null && index[e.to] != null)
            (index[e.from]!, index[e.to]!),
      ],
    );
  }
}

/// Force-directed layout (Fruchterman–Reingold) with events pinned to their
/// place on a left-to-right timeline, like a knowledge-base graph view
/// that also reads as a chronology. Deterministic for a given input.
///
/// Returns positions keyed by node id, normalised so the minimum x and y
/// are 0.
Map<String, (double, double)> forceLayout(LayoutInput input) {
  final n = input.ids.length;
  if (n == 0) return const {};
  final random = Random(42);
  final width = 260.0 * sqrt(n) + 400;
  final height = 180.0 * sqrt(n) + 300;
  final k = sqrt(width * height / n) * 0.6;

  final xs = List<double>.generate(n, (i) {
    final anchor = input.timeAnchors[i];
    return anchor != null ? anchor * width : random.nextDouble() * width;
  });
  final ys = List<double>.generate(n, (_) => random.nextDouble() * height);

  var temperature = width / 10;
  final cooling = temperature / (input.iterations + 1);
  final dx = List<double>.filled(n, 0), dy = List<double>.filled(n, 0);

  for (var iter = 0; iter < input.iterations; iter++) {
    dx.fillRange(0, n, 0);
    dy.fillRange(0, n, 0);

    // Repulsion between every pair.
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        var ddx = xs[i] - xs[j], ddy = ys[i] - ys[j];
        var dist = sqrt(ddx * ddx + ddy * ddy);
        if (dist < 0.01) {
          ddx = random.nextDouble() - 0.5;
          ddy = random.nextDouble() - 0.5;
          dist = 0.01;
        }
        final force = k * k / dist;
        final fx = ddx / dist * force, fy = ddy / dist * force;
        dx[i] += fx;
        dy[i] += fy;
        dx[j] -= fx;
        dy[j] -= fy;
      }
    }

    // Attraction along edges.
    for (final (a, b) in input.edges) {
      final ddx = xs[a] - xs[b], ddy = ys[a] - ys[b];
      final dist = max(sqrt(ddx * ddx + ddy * ddy), 0.01);
      final force = dist * dist / k;
      final fx = ddx / dist * force, fy = ddy / dist * force;
      dx[a] -= fx;
      dy[a] -= fy;
      dx[b] += fx;
      dy[b] += fy;
    }

    // Gentle gravity toward the vertical centre.
    for (var i = 0; i < n; i++) {
      dy[i] += (height / 2 - ys[i]) * 0.05;
      // Events are pinned to their date on the x axis and only move
      // vertically, so the graph always reads left-to-right in time.
      if (input.timeAnchors[i] != null) dx[i] = 0;
    }

    for (var i = 0; i < n; i++) {
      final len = sqrt(dx[i] * dx[i] + dy[i] * dy[i]);
      if (len > 0) {
        final step = min(len, temperature);
        xs[i] += dx[i] / len * step;
        ys[i] += dy[i] / len * step;
      }
      // Keep loosely connected nodes from drifting off into the distance.
      xs[i] = xs[i].clamp(-0.1 * width, 1.1 * width);
      ys[i] = ys[i].clamp(0, height);
    }
    temperature = max(temperature - cooling, 1);
  }

  final minX = xs.reduce(min), minY = ys.reduce(min);
  return {
    for (var i = 0; i < n; i++) input.ids[i]: (xs[i] - minX, ys[i] - minY),
  };
}
