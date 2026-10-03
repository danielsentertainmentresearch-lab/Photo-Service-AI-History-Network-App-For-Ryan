import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/event.dart';
import '../state/app_state.dart';

/// Shows a photo from the vault, decoded at roughly display size.
class VaultImage extends StatelessWidget {
  final String fileName;
  final double? size;
  final BoxFit fit;

  const VaultImage(this.fileName, {super.key, this.size, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final vault = context.read<AppState>().vault;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return Image.file(
      vault.fileFor(fileName),
      width: size,
      height: size,
      fit: fit,
      cacheWidth: size == null ? null : (size! * ratio).round(),
      errorBuilder: (context, _, _) => Container(
        width: size,
        height: size,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final EventStatus status;

  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, icon) = switch (status) {
      EventStatus.draft => ('Not described', scheme.outline, Icons.edit_note),
      EventStatus.describing =>
        ('Describing…', scheme.primary, Icons.hourglass_top),
      EventStatus.described =>
        ('Described', scheme.tertiary, Icons.check_circle_outline),
      EventStatus.failed => ('Needs retry', scheme.error, Icons.error_outline),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color)),
      ],
    );
  }
}
