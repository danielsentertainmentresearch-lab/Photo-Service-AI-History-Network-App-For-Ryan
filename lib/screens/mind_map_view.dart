import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mindmap/mind_map.dart';
import '../models/memory_graph.dart';
import '../state/app_state.dart';
import 'event_detail_screen.dart';
import 'graph_screen.dart' show kindColor, kindLabel, provenanceLabel;

/// The mind map: one idea in the centre with ideas branching out of it.
/// Tapping a branch opens or closes it; any idea can become the centre;
/// the trail at the top leads back. Read-only, like the graph it draws on.
class MindMapView extends StatefulWidget {
  const MindMapView({super.key});

  @override
  State<MindMapView> createState() => _MindMapViewState();
}

class _MindMapViewState extends State<MindMapView>
    with AutomaticKeepAliveClientMixin {
  static const double _margin = 120;
  static const double _hitRadius = 34;

  final _transform = TransformationController();
  List<String> _trail = [storyFocus];
  Set<String> _open = {};
  Set<String> _showAll = {};
  String? _selected;
  Object? _dataKey;
  late MindMapIndex _index;
  bool _needsFit = true;
  Offset? _lastOrigin;

  String get _focus => _trail.last;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _fit(Size canvas, Size viewport) {
    final scale = min(
      viewport.width / canvas.width,
      viewport.height / canvas.height,
    ).clamp(0.1, 1.0);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (viewport.width - canvas.width * scale) / 2,
        (viewport.height - canvas.height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _centre(String target) => setState(() {
    final at = _trail.indexOf(target);
    _trail = at >= 0 ? _trail.sublist(0, at + 1) : [..._trail, target];
    _open = {};
    _showAll = {};
    _selected = null;
    _needsFit = true;
  });

  void _tapBranch(PlacedBranch p) => setState(() {
    final b = p.branch;
    if (b.kind == BranchKind.more) {
      _showAll = {..._showAll, b.target!};
      _selected = null;
      return;
    }
    _selected = b.key;
    if (p.depth > 0 && b.kind != BranchKind.group && b.canOpen) {
      _open = b.isOpen ? ({..._open}..remove(b.key)) : {..._open, b.key};
    }
  });

  void _onTap(Offset local, List<PlacedBranch> placed, Offset origin) {
    PlacedBranch? hit;
    var best = double.infinity;
    for (final p in placed) {
      final d = (Offset(p.x, p.y) + origin - local).distance;
      if (d < _hitRadius && d < best) {
        best = d;
        hit = p;
      }
    }
    if (hit != null) {
      _tapBranch(hit);
    } else if (_selected != null) {
      setState(() => _selected = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    final key = Object.hash(
      state.allEvents,
      state.memories,
      state.graphSnapshot,
    );
    if (key != _dataKey) {
      _dataKey = key;
      _index = MindMapIndex(state.graph, state.graphSnapshot);
      // Ideas that no longer exist (a deleted event) drop off the trail.
      _trail = [storyFocus, ..._trail.skip(1).where(_index.has)];
    }

    final root = _index.build(focus: _focus, open: _open, showAll: _showAll);
    final placed = layoutMindMap(root);
    var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0;
    for (final p in placed) {
      minX = min(minX, p.x);
      maxX = max(maxX, p.x);
      minY = min(minY, p.y);
      maxY = max(maxY, p.y);
    }
    final origin = Offset(_margin - minX, _margin - minY);
    final size = Size(maxX - minX + _margin * 2, maxY - minY + _margin * 2);
    final byKey = {for (final p in placed) p.branch.key: p};
    final theme = Theme.of(context);

    return Column(
      children: [
        _Trail(
          labels: [for (final f in _trail) _index.labelOf(f)],
          onCrumb: (i) => _centre(_trail[i]),
          onFit: () => setState(() => _needsFit = true),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (_needsFit) {
                _needsFit = false;
                _fit(size, constraints.biggest);
              } else if (_lastOrigin != null && _lastOrigin != origin) {
                // Opening a branch can grow the page up or left; keep what's
                // on screen where it was.
                final d = origin - _lastOrigin!;
                _transform.value = _transform.value.clone()
                  ..translateByDouble(-d.dx, -d.dy, 0, 1);
              }
              _lastOrigin = origin;
              return InteractiveViewer(
                transformationController: _transform,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.05,
                maxScale: 4,
                child: GestureDetector(
                  onTapUp: (d) => _onTap(d.localPosition, placed, origin),
                  child: CustomPaint(
                    size: size,
                    painter: MindMapPainter(
                      placed: placed,
                      byKey: byKey,
                      origin: origin,
                      index: _index,
                      selected: _selected,
                      scheme: theme.colorScheme,
                      labelStyle:
                          theme.textTheme.bodySmall ?? const TextStyle(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _Details(
          selected: byKey[_selected],
          index: _index,
          focus: _focus,
          onCentre: _centre,
        ),
      ],
    );
  }
}

class _Trail extends StatelessWidget {
  final List<String> labels;
  final void Function(int) onCrumb;
  final VoidCallback onFit;

  const _Trail({
    required this.labels,
    required this.onCrumb,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (var i = labels.length - 1; i >= 0; i--)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: i == labels.length - 1
                        ? Chip(label: Text(labels[i]))
                        : ActionChip(
                            avatar: const Icon(Icons.chevron_left, size: 18),
                            label: Text(labels[i]),
                            onPressed: () => onCrumb(i),
                          ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fit to screen',
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed: onFit,
          ),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  final PlacedBranch? selected;
  final MindMapIndex index;
  final String focus;
  final void Function(String) onCentre;

  const _Details({
    required this.selected,
    required this.index,
    required this.focus,
    required this.onCentre,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = selected?.branch;
    final node = b?.target == null ? null : index.node(b!.target!);
    final canCentre =
        b != null &&
        b.target != null &&
        b.target != focus &&
        (b.kind == BranchKind.node ||
            b.kind == BranchKind.chapter ||
            b.kind == BranchKind.story);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: b == null
              ? Text(
                  'Tap a branch to open it. Center on any idea to explore '
                  'from there.',
                  style: theme.textTheme.bodySmall,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(b.label, style: theme.textTheme.titleMedium),
                    Text(switch (b.kind) {
                      BranchKind.story => 'Your story · From the AI',
                      BranchKind.chapter => 'Chapter · From the AI',
                      BranchKind.group => 'Group',
                      BranchKind.more => '',
                      BranchKind.node =>
                        node == null
                            ? ''
                            : '${kindLabel(node.kind)} · '
                                  '${provenanceLabel(node.provenance)}',
                    }, style: theme.textTheme.labelMedium),
                    if (b.detail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        b.detail,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (canCentre || node?.eventId != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (canCentre)
                            FilledButton.tonal(
                              onPressed: () => onCentre(b.target!),
                              child: const Text('Center here'),
                            ),
                          if (node?.eventId != null)
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EventDetailScreen(
                                    eventId: node!.eventId!,
                                  ),
                                ),
                              ),
                              child: const Text('Open event'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Draws the placed branches. Each limb from the centre keeps one colour,
/// taken from what it holds (people, places, themes…), so a limb can be
/// followed by eye however far it is opened.
class MindMapPainter extends CustomPainter {
  final List<PlacedBranch> placed;
  final Map<String, PlacedBranch> byKey;
  final Offset origin;
  final MindMapIndex index;
  final String? selected;
  final ColorScheme scheme;
  final TextStyle labelStyle;

  MindMapPainter({
    required this.placed,
    required this.byKey,
    required this.origin,
    required this.index,
    required this.selected,
    required this.scheme,
    required this.labelStyle,
  });

  Offset _at(PlacedBranch p) => Offset(p.x, p.y) + origin;

  Color _colorOf(MindBranch b) => switch (b.kind) {
    BranchKind.story => scheme.primary,
    BranchKind.chapter => scheme.tertiary,
    BranchKind.more => scheme.outline,
    BranchKind.group || BranchKind.node =>
      b.nodeKind == null ? scheme.tertiary : kindColor(b.nodeKind!, scheme),
  };

  late final List<Color> _limbColors = [
    for (final p in placed)
      if (p.depth == 1) _colorOf(p.branch),
  ];

  Color _limbColor(PlacedBranch p) => p.limb >= 0 && p.limb < _limbColors.length
      ? _limbColors[p.limb]
      : scheme.primary;

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    double size = 11,
    FontWeight weight = FontWeight.normal,
    Color? color,
    double maxWidth = 130,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(
          fontSize: size,
          fontWeight: weight,
          color: color ?? scheme.onSurface,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, at - Offset(tp.width / 2, 0));
  }

  void _badge(Canvas canvas, Offset at, bool open, Color color) {
    canvas.drawCircle(at, 7, Paint()..color = scheme.surface);
    canvas.drawCircle(
      at,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color,
    );
    final line = Paint()
      ..strokeWidth = 1.5
      ..color = color;
    canvas.drawLine(at - const Offset(3.5, 0), at + const Offset(3.5, 0), line);
    if (!open) {
      canvas.drawLine(
        at - const Offset(0, 3.5),
        at + const Offset(0, 3.5),
        line,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in placed) {
      final parent = p.parentKey == null ? null : byKey[p.parentKey];
      if (parent == null) continue;
      final a = _at(parent), b = _at(p);
      final midX = (a.dx + b.dx) / 2;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(midX, a.dy, midX, b.dy, b.dx, b.dy);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = max(1.5, 6 - p.depth * 1.5)
          ..color = _limbColor(p).withValues(alpha: 0.55),
      );
    }

    for (final p in placed) {
      final b = p.branch;
      final c = _at(p);
      final color = _limbColor(p);
      // Where the open/close badge goes: beside a dot, or on the corner of a
      // chapter's bubble so it never covers the title.
      var badgeAt = c + const Offset(12, -12);
      switch (b.kind) {
        case BranchKind.story || BranchKind.chapter:
          final tp = TextPainter(
            text: TextSpan(
              text: b.label,
              style: labelStyle.copyWith(
                fontSize: b.kind == BranchKind.story ? 16 : 13,
                fontWeight: FontWeight.w600,
                color: b.kind == BranchKind.story
                    ? scheme.onPrimaryContainer
                    : scheme.onSurface,
              ),
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            maxLines: 2,
            ellipsis: '…',
          )..layout(maxWidth: 150);
          final box = RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: c,
              width: tp.width + 28,
              height: tp.height + 16,
            ),
            const Radius.circular(999),
          );
          canvas.drawRRect(
            box,
            Paint()
              ..color = b.kind == BranchKind.story
                  ? scheme.primaryContainer
                  : scheme.surface,
          );
          if (b.kind == BranchKind.chapter) {
            canvas.drawRRect(
              box,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = scheme.tertiary,
            );
          }
          tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
          badgeAt = box.outerRect.topRight + const Offset(-4, 4);
        case BranchKind.group:
          canvas.drawCircle(c, 5, Paint()..color = color);
          _label(
            canvas,
            b.label,
            c + const Offset(0, 8),
            size: 12,
            weight: FontWeight.w700,
            color: color,
          );
        case BranchKind.more:
          canvas.drawCircle(
            c,
            9,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = scheme.outline,
          );
          _label(canvas, '+', c - const Offset(0, 8), size: 13);
          _label(canvas, b.label, c + const Offset(0, 12), size: 10);
        case BranchKind.node:
          final node = index.node(b.target!);
          canvas.drawCircle(c, 10, Paint()..color = _colorOf(b));
          if (node?.ringColor != null) {
            canvas.drawCircle(
              c,
              13,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3.5
                ..color = Color(node!.ringColor!),
            );
          }
          _label(
            canvas,
            b.label,
            c + const Offset(0, 15),
            size: b.nodeKind == NodeKind.event ? 12 : 11,
            weight: b.nodeKind == NodeKind.event
                ? FontWeight.w600
                : FontWeight.normal,
          );
      }
      if (p.depth > 0 &&
          b.canOpen &&
          (b.kind == BranchKind.node || b.kind == BranchKind.chapter)) {
        _badge(canvas, badgeAt, b.isOpen, color);
      }
      if (b.key == selected) {
        canvas.drawCircle(
          c,
          b.kind == BranchKind.node ? 18 : 22,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = scheme.onSurface,
        );
      }
    }
  }

  @override
  bool shouldRepaint(MindMapPainter old) =>
      old.placed != placed ||
      old.selected != selected ||
      old.scheme != scheme ||
      old.labelStyle != labelStyle;
}
