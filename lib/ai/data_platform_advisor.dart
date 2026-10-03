import 'dart:convert';

import '../services/data_files.dart';
import 'anthropic_client.dart';
import 'event_describer.dart' show parseStructured;

/// One Python data platform that can open the analysis file.
class DataPlatform {
  final String name;

  /// What it's good for with this file, in a sentence.
  final String use;

  /// True when the AI is confident it fits; false for "likely".
  final bool determined;

  const DataPlatform({
    required this.name,
    required this.use,
    required this.determined,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'use': use,
    'determined': determined,
  };

  static DataPlatform fromJson(Map<String, dynamic> json) => DataPlatform(
    name: '${json['name'] ?? ''}'.trim(),
    use: '${json['use'] ?? ''}'.trim(),
    determined: json['determined'] == true,
  );
}

/// The list of platforms shown in the data guide.
class PlatformAdvice {
  final List<DataPlatform> platforms;

  /// True when no platform could be determined, not even a likely one.
  final bool noneDeterminable;

  /// True when the AI answered; false for the built-in fallback.
  final bool fromAi;

  const PlatformAdvice({
    required this.platforms,
    this.noneDeterminable = false,
    this.fromAi = true,
  });

  /// Used when the AI can't be asked (no key, offline). Lists the single
  /// most likely platform and says it wasn't checked.
  static const fallback = PlatformAdvice(
    fromAi: false,
    platforms: [
      DataPlatform(
        name: 'pandas in a Jupyter notebook',
        use: 'Most likely fit: reads the CSV in one line and works with '
            'every column type in the file.',
        determined: false,
      ),
    ],
  );

  String toJsonString() => jsonEncode({
    'platforms': [for (final p in platforms) p.toJson()],
    'none_determinable': noneDeterminable,
    'columns_version': columnsVersion,
  });

  /// Reads a cached answer; null if it's missing, broken or was made for
  /// a different set of columns.
  static PlatformAdvice? fromJsonString(String? text) {
    if (text == null) return null;
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['columns_version'] != columnsVersion) return null;
      return PlatformAdvice(
        platforms: [
          for (final p in (data['platforms'] as List))
            DataPlatform.fromJson((p as Map).cast<String, dynamic>()),
        ],
        noneDeterminable: data['none_determinable'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Changes whenever the analysis columns change, so old answers expire.
  static String get columnsVersion {
    // FNV-1a, so the value is the same on every run and app version.
    var hash = 0x811c9dc5;
    for (final unit in analysisColumns
        .map((c) => '${c.name}:${c.type}')
        .join(',')
        .codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}

/// Asks the AI which Python data platforms can use the analysis file. Only
/// the column names and types are sent, never the person's data.
class DataPlatformAdvisor {
  final AnthropicClient client;
  final String model;

  DataPlatformAdvisor({required this.client, required this.model});

  static const outputSchema = {
    'type': 'object',
    'properties': {
      'platforms': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'use': {'type': 'string'},
            'fit': {
              'type': 'string',
              'enum': ['determined', 'likely'],
            },
          },
          'required': ['name', 'use', 'fit'],
          'additionalProperties': false,
        },
      },
      'none_determinable': {'type': 'boolean'},
    },
    'required': ['platforms', 'none_determinable'],
    'additionalProperties': false,
  };

  static const instructions =
      'You help casual, non-professional users explore a CSV export of '
      'their personal photo journal with Python. Given the file\'s columns, '
      'list Python-based data platforms or libraries that can open and '
      'analyse it directly (for example notebook environments, dataframe '
      'libraries, charting libraries). For each, give the name and one '
      'plain-language sentence on what it is good for with these columns, '
      'written for a beginner. Mark fit "determined" when it clearly works '
      'with every column type, otherwise "likely". List at most 8, most '
      'useful first. If you cannot determine any platform, return an empty '
      'list with none_determinable true; if you can only guess, return the '
      'single most likely platform marked "likely".';

  Map<String, dynamic> buildRequest() => {
    'model': model,
    'max_tokens': 4000,
    'thinking': {'type': 'adaptive'},
    'output_config': {
      'effort': 'low',
      'format': {'type': 'json_schema', 'schema': outputSchema},
    },
    'fallbacks': 'default',
    'system': instructions,
    'messages': [
      {
        'role': 'user',
        'content':
            'File: eventlens-analysis.csv (UTF-8, comma-separated, header '
            'row, one row per event; list columns use | between items).\n'
            'Columns (name, type, meaning):\n'
            '${analysisColumns.map((c) => '- ${c.name} (${c.type}): ${c.meaning}').join('\n')}',
      },
    ],
  };

  static PlatformAdvice parse(Map<String, dynamic> response) {
    final data = parseStructured(response);
    final platforms = <DataPlatform>[
      for (final raw in (data['platforms'] as List? ?? const []))
        if (raw is Map)
          DataPlatform(
            name: '${raw['name'] ?? ''}'.trim(),
            use: '${raw['use'] ?? ''}'.trim(),
            determined: raw['fit'] == 'determined',
          ),
    ].where((p) => p.name.isNotEmpty).take(8).toList();
    return PlatformAdvice(
      platforms: platforms,
      noneDeterminable: platforms.isEmpty,
    );
  }

  Future<PlatformAdvice> suggest() async {
    final response = await client.createMessage(
      buildRequest(),
      betas: const [AnthropicClient.fallbackBeta],
    );
    return parse(response);
  }
}
