import 'package:flutter/material.dart';

/// The person's own free write about an event: an empty box with no label,
/// hint or question, so nothing steers what they write. The "?" beside it
/// explains what the box is for.
class FreeWriteBox extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  /// Puts the cursor here when the screen opens.
  final bool autofocus;

  const FreeWriteBox({
    super.key,
    required this.controller,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
  });

  static const explanation =
      'This box is yours. Write anything you like about your experience '
      'at this event, in your own way. There are no questions to answer '
      'and no right way to fill it.\n\n'
      'The AI never changes what you write here. It reads it to make a few '
      'short labels for Your data, and to notice if you might need support, '
      'so help is easy to reach. No one else sees it.';

  static Future<void> explain(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: const Text(explanation),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color, width: width),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Semantics(
            label: 'Your free write',
            child: TextField(
              key: const ValueKey('free-write'),
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              onChanged: onChanged,
              minLines: 6,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                filled: true,
                fillColor: scheme.surface,
                contentPadding: const EdgeInsets.all(12),
                enabledBorder: border(scheme.outline, 1.5),
                focusedBorder: border(scheme.primary, 2),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'What is this box for?',
          icon: const Icon(Icons.help_outline),
          onPressed: () => explain(context),
        ),
      ],
    );
  }
}
