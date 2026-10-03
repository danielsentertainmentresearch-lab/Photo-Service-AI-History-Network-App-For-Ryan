/// Ring colours users can put on events in the timeline graph.
///
/// PLACEHOLDER palette: generic colours that fit the current app theme.
/// It will be replaced with the brand palette after this build phase and
/// before the UI/UX design phase. Keep the list order meaningful: index 0
/// is free, and the rest unlock one after another (see [ringUnlockCost]).
const ringPalette = <int>[
  0xFF3F51B5, // indigo (free; matches the app seed colour)
  0xFFE53935, // red
  0xFFFB8C00, // orange
  0xFFFDD835, // yellow
  0xFF43A047, // green
  0xFF00ACC1, // cyan
  0xFF8E24AA, // purple
  0xFF6D4C41, // brown
];

/// Number of colours available without watching any videos.
const freeRingColors = 1;

/// Rewarded videos needed to unlock the colour at [index]: the first locked
/// colour takes 5, and each one after it takes one more (6, 7, …).
int ringUnlockCost(int index) =>
    index < freeRingColors ? 0 : 5 + (index - freeRingColors);

/// ARGB colour for a palette index, or null when unset or out of range.
int? ringColorFor(int? index) =>
    index == null || index < 0 || index >= ringPalette.length
    ? null
    : ringPalette[index];
