import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../graph/force_layout.dart';
import '../models/memory_graph.dart';
import '../state/app_state.dart';
import 'event_detail_screen.dart';
import 'graph_editor_screen.dart';

/// The connected timeline: a graph view of events, people, places, tags,
/// themes and memories, plus the AI's chapters.
class GraphScreen extends StatelessWidget {
  const GraphScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Timeline graph'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Graph'),
              Tab(text: 'Chapters'),
            ],
          ),
          actions: [
            if (state.graphBuilding)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              tooltip: 'Edit timeline',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => const GraphEditorScreen(),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            _StatusBar(state: state),
            const Expanded(
              child: TabBarView(
                physics: NeverScrollableScrollPhysics(),
                children: [_GraphView(), _ChaptersView()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final AppState state;

  const _StatusBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String text;
    if (state.graphBuilding) {
      text = 'The AI is organising your timeline…';
    } else if (state.graphError != null) {
      text = state.graphError!;
    } else {
      final snapshot = state.graphSnapshot;
      final next = state.photosUntilNextGraph;
      final built = snapshot == null
          ? 'Not organised yet.'
          : 'Organised ${DateFormat.yMMMd().add_jm().format(snapshot.createdAt)}.';
      final upcoming = next == null
          ? ' Automatic AI rebuilds are off.'
          : next == 0
          ? ''
          : ' The AI rebuilds after $next more described '
                'photo${next == 1 ? '' : 's'}.';
      text = '$built$upcoming';
    }
    return Container(
      width: double.infinity,
      color: state.graphError != null
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}

// ---- Graph view -------------------------------------------------------------

Color kindColor(NodeKind kind, ColorScheme scheme) => switch (kind) {
  NodeKind.event => scheme.primary,
  NodeKind.person => const Color(0xFFE91E63),
  NodeKind.place => const Color(0xFF009688),
  NodeKind.tag => const Color(0xFF9E9E9E),
  NodeKind.theme => const Color(0xFFFF9800),
  NodeKind.memory => const Color(0xFF795548),
};

/// Colour of links between events (found by the AI or added by the user).
const linkColor = Color(0xFF7E57C2);

String kindLabel(NodeKind kind) => switch (kind) {
  NodeKind.event => 'Event',
  NodeKind.person => 'Person',
  NodeKind.place => 'Place',
  NodeKind.tag => 'Tag',
  NodeKind.theme => 'Theme',
  NodeKind.memory => 'Memory',
};

String provenanceLabel(Provenance p) => switch (p) {
  Provenance.human => 'From you',
  Provenance.ai => 'From the AI',
  Provenance.both => 'Your photos and notes + AI account',
};

class _GraphView extends StatefulWidget {
  const _GraphView();

  @override
  State<_GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<_GraphView>
    with AutomaticKeepAliveClientMixin {
  static const double _padding = 80;

  GraphData? _graph;
  Map<String, (double, double)>? _positions;
  Set<NodeKind> _visible = NodeKind.values.toSet();
  String? _selected;
  Object? _layoutKey;
  final _transform = TransformationController();
  bool _needsFit = true;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Zooms out so the whole graph fits the viewport.
  void _fit(Size canvas, Size viewport) {
    final scale = min(
      viewport.width / canvas.width,
      viewport.height / canvas.height,
    ).clamp(0.1, 1.0);
    final dx = (viewport.width - canvas.width * scale) / 2;
    final dy = (viewport.height - canvas.height * scale) / 2;
    _transform.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _relayout(GraphData graph) async {
    final positions = await compute(forceLayout, LayoutInput.fromGraph(graph));
    if (!mounted) return;
    setState(() {
      _graph = graph;
      _positions = positions;
      _needsFit = true;
    });
  }

  int _degree(String id) =>
      _graph!.edges.where((e) => e.from == id || e.to == id).length;

  double radiusOf(GraphNode n) => switch (n.kind) {
    NodeKind.event => 16,
    NodeKind.theme => 14,
    _ => 7 + min(_degree(n.id), 8).toDouble(),
  };

  void _onTap(Offset local) {
    final graph = _graph, positions = _positions;
    if (graph == null || positions == null) return;
    GraphNode? hit;
    var best = double.infinity;
    for (final n in graph.nodes) {
      if (!_visible.contains(n.kind)) continue;
      final (x, y) = positions[n.id]!;
      final d = (Offset(x + _padding, y + _padding) - local).distance;
      if (d < radiusOf(n) + 12 && d < best) {
        best = d;
        hit = n;
      }
    }
    setState(() => _selected = hit?.id);
    if (hit != null) _showNode(hit);
  }

  void _showNode(GraphNode node) {
    final graph = _graph!;
    final neighbours = <(GraphNode, GraphEdge)>[];
    for (final e in graph.edges) {
      final other = e.from == node.id
          ? e.to
          : e.to == node.id
          ? e.from
          : null;
      final n = other == null ? null : graph.node(other);
      if (n != null) neighbours.add((n, e));
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _NodeSheet(node: node, neighbours: neighbours),
    ).whenComplete(() {
      if (mounted) setState(() => _selected = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    // Re-layout only when the underlying data changes (lists are replaced,
    // never mutated, on every reload).
    final key = Object.hash(
      state.allEvents,
      state.memories,
      state.graphSnapshot,
    );
    if (key != _layoutKey) {
      _layoutKey = key;
      _relayout(state.graph);
    }
    final graph = _graph, positions = _positions;
    if (graph == null || positions == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (graph.nodes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Describe a few events and they will appear here, connected by '
            'the people, places and themes they share.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    var maxX = 0.0, maxY = 0.0;
    for (final (x, y) in positions.values) {
      maxX = max(maxX, x);
      maxY = max(maxY, y);
    }
    final size = Size(maxX + _padding * 2, maxY + _padding * 2);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final kind in NodeKind.values)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: FilterChip(
                    avatar: CircleAvatar(
                      backgroundColor: kindColor(kind, scheme),
                      radius: 6,
                    ),
                    label: Text(kindLabel(kind)),
                    selected: _visible.contains(kind),
                    onSelected: (on) => setState(
                      () => _visible = on
                          ? {..._visible, kind}
                          : ({..._visible}..remove(kind)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (_needsFit) {
                _needsFit = false;
                _fit(size, constraints.biggest);
              }
              return InteractiveViewer(
                transformationController: _transform,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.05,
                maxScale: 4,
                child: GestureDetector(
                  onTapUp: (d) => _onTap(d.localPosition),
                  child: CustomPaint(
                    size: size,
                    painter: _GraphPainter(
                      graph: graph,
                      positions: positions,
                      padding: _padding,
                      visible: _visible,
                      selected: _selected,
                      scheme: scheme,
                      labelStyle:
                          Theme.of(context).textTheme.bodySmall ??
                          const TextStyle(),
                      radiusOf: radiusOf,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const _Legend(),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    final coloured =
        (context.watch<AppState>().graphSnapshot?.chapters ??
                const <TimelineChapter>[])
            .where((c) => c.color != null)
            .toList();
    Widget ring(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c, width: 3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: style),
      ],
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final c in coloured) ring(Color(c.color!), c.title),
            Text(
              coloured.isEmpty
                  ? 'Events run left to right in time · purple lines: links '
                        'between events · colour chapters in Edit'
                  : 'Events run left to right in time · purple lines: links '
                        'between events',
              style: style,
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final GraphData graph;
  final Map<String, (double, double)> positions;
  final double padding;
  final Set<NodeKind> visible;
  final String? selected;
  final ColorScheme scheme;
  final TextStyle labelStyle;
  final double Function(GraphNode) radiusOf;

  _GraphPainter({
    required this.graph,
    required this.positions,
    required this.padding,
    required this.visible,
    required this.selected,
    required this.scheme,
    required this.labelStyle,
    required this.radiusOf,
  });

  Offset _at(String id) {
    final (x, y) = positions[id]!;
    return Offset(x + padding, y + padding);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final kinds = {for (final n in graph.nodes) n.id: n.kind};
    bool shown(String id) => visible.contains(kinds[id]);

    for (final e in graph.edges) {
      if (!shown(e.from) || !shown(e.to)) continue;
      final highlighted =
          selected != null && (e.from == selected || e.to == selected);
      final paint = Paint()
        ..strokeWidth = switch (e.kind) {
          EdgeKind.chronology => 3,
          EdgeKind.aiLink => 2.5,
          _ => 1,
        }
        ..color = (switch (e.kind) {
          EdgeKind.chronology => scheme.primary,
          EdgeKind.aiLink => linkColor,
          EdgeKind.theme => const Color(0xFFFF9800),
          _ => scheme.outline,
        }).withValues(alpha: selected == null || highlighted ? 0.7 : 0.15);
      canvas.drawLine(_at(e.from), _at(e.to), paint);
    }

    for (final n in graph.nodes) {
      if (!visible.contains(n.kind)) continue;
      final c = _at(n.id);
      final r = radiusOf(n);
      final dim = selected != null && selected != n.id;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = kindColor(n.kind, scheme).withValues(alpha: dim ? 0.4 : 1),
      );
      // Ring in the colour the user picked for this event's chapter.
      if (n.ringColor != null) {
        canvas.drawCircle(
          c,
          r + 3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = Color(n.ringColor!).withValues(alpha: dim ? 0.4 : 1),
        );
      }
      if (n.id == selected) {
        canvas.drawCircle(
          c,
          r + 7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = scheme.onSurface,
        );
      }

      final label = n.kind == NodeKind.event && n.time != null
          ? '${n.label}\n${DateFormat.yMMMd().format(n.time!)}'
          : n.label;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          // Based on the app's text theme so labels use the app font.
          style: labelStyle.copyWith(
            fontSize: n.kind == NodeKind.event || n.kind == NodeKind.theme
                ? 12
                : 10,
            fontWeight: n.kind == NodeKind.event
                ? FontWeight.w600
                : FontWeight.normal,
            color: scheme.onSurface.withValues(alpha: dim ? 0.4 : 1),
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: 140);
      tp.paint(canvas, c + Offset(-tp.width / 2, r + 5));
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.graph != graph ||
      old.positions != positions ||
      old.visible != visible ||
      old.selected != selected ||
      old.scheme != scheme ||
      old.labelStyle != labelStyle;
}

class _NodeSheet extends StatelessWidget {
  final GraphNode node;
  final List<(GraphNode, GraphEdge)> neighbours;

  const _NodeSheet({required this.node, required this.neighbours});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void openEvent(String id) {
      Navigator.of(context)
        ..pop()
        ..push(
          MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: id)),
        );
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(node.label, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${kindLabel(node.kind)} · ${provenanceLabel(node.provenance)}',
            style: theme.textTheme.labelMedium,
          ),
          if (node.detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(node.detail),
          ],
          if (node.eventId != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () => openEvent(node.eventId!),
                child: const Text('Open event'),
              ),
            ),
          ],
          if (neighbours.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Connected to', style: theme.textTheme.titleSmall),
            for (final (n, e) in neighbours)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 6,
                  backgroundColor: kindColor(n.kind, theme.colorScheme),
                ),
                title: Text(n.label),
                subtitle: e.label.isEmpty
                    ? Text(kindLabel(n.kind))
                    : Text('${kindLabel(n.kind)} · ${e.label}'),
                onTap: n.eventId == null ? null : () => openEvent(n.eventId!),
              ),
          ],
        ],
      ),
    );
  }
}

// ---- Chapters view ----------------------------------------------------------

class _ChaptersView extends StatelessWidget {
  const _ChaptersView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final snapshot = state.graphSnapshot;
    final theme = Theme.of(context);
    if (snapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Once enough photos are described, the AI groups your events '
                'into chapters, links related moments and finds recurring '
                'themes. You can also organise them yourself.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: state.graphBuilding || state.describedCount < 2
                    ? null
                    : state.buildGraphNow,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Organise with AI'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const GraphEditorScreen(),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Organise by hand'),
              ),
            ],
          ),
        ),
      );
    }

    Widget eventChip(String id) {
      final e = state.eventById(id);
      if (e == null) return const SizedBox.shrink();
      return ActionChip(
        label: Text(e.title.isEmpty ? 'Untitled' : e.title),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: id)),
        ),
      );
    }

    Widget chapterCard(TimelineChapter c) {
      final number = snapshot.chapters.indexOf(c) + 1;
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: c.color == null
              ? null
              : BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Color(c.color!), width: 6),
                  ),
                ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chapter $number', style: theme.textTheme.labelMedium),
              Text(c.title, style: theme.textTheme.titleMedium),
              if (c.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(c.summary),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final id in c.eventIds) eventChip(id)],
              ),
            ],
          ),
        ),
      );
    }

    final groupIds = snapshot.groups.map((g) => g.id).toSet();
    final ungrouped = snapshot.chapters
        .where((c) => !groupIds.contains(c.groupId))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (snapshot.overview.isNotEmpty) ...[
          Text('Overview', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(snapshot.overview),
          const SizedBox(height: 24),
        ],
        for (final g in snapshot.groups) ...[
          Row(
            children: [
              const Icon(Icons.folder_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$groupingLabel: ${g.name}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...snapshot.chapters.where((c) => c.groupId == g.id).map(chapterCard),
          if (!snapshot.chapters.any((c) => c.groupId == g.id))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'No chapters yet. Add some in Edit.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (snapshot.groups.isNotEmpty && ungrouped.isNotEmpty) ...[
          Text(
            'Not in a ${groupingLabel.toLowerCase()}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
        ],
        ...ungrouped.map(chapterCard),
        if (snapshot.themes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Themes', style: theme.textTheme.titleMedium),
          for (final t in snapshot.themes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.hub_outlined, color: Color(0xFFFF9800)),
              title: Text(t.name),
              subtitle: Text(
                '${t.description}${t.description.isEmpty ? '' : '\n'}'
                '${t.eventIds.length} event${t.eventIds.length == 1 ? '' : 's'}'
                '${t.manual ? ' · added by you' : ''}',
              ),
              isThreeLine: t.description.isNotEmpty,
            ),
        ],
        if (snapshot.links.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Connections', style: theme.textTheme.titleMedium),
          for (final l in snapshot.links)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link, color: linkColor),
              title: Text(l.relation),
              subtitle: Text(
                '${state.eventById(l.fromEventId)?.title ?? '?'}  to  '
                '${state.eventById(l.toEventId)?.title ?? '?'}'
                '${l.manual ? ' · added by you' : ''}',
              ),
            ),
        ],
      ],
    );
  }
}
