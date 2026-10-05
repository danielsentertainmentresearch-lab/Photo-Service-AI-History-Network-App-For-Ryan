import 'package:flutter/material.dart';

import '../widgets/markdown_text.dart';

/// How every support feature works and why it exists (owner, 6 Oct 2026),
/// bundled from SUPPORT_AND_SAFETY.md so the app and the web copy match.
class HowSupportWorksScreen extends StatelessWidget {
  /// The document; read from the bundled SUPPORT_AND_SAFETY.md when null.
  final String? text;

  const HowSupportWorksScreen({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How support works')),
      body: FutureBuilder<String>(
        future: text != null
            ? Future.value(text)
            : DefaultAssetBundle.of(context)
                  .loadString('SUPPORT_AND_SAFETY.md'),
        builder: (context, snap) => snap.data == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: renderMarkdown(context, snap.data!),
              ),
      ),
    );
  }
}
