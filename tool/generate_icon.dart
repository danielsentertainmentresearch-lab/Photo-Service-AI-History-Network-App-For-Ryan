// Draws the launcher icon sources used by flutter_launcher_icons.
// Run: dart run tool/generate_icon.dart && dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const size = 1024;
final indigo = img.ColorRgba8(0x3F, 0x51, 0xB5, 255);
final deep = img.ColorRgba8(0x28, 0x35, 0x93, 255);
final white = img.ColorRgba8(255, 255, 255, 255);
final amber = img.ColorRgba8(0xFF, 0xC1, 0x07, 255);
final clear = img.ColorRgba8(0, 0, 0, 0);

/// The lens mark: a ring with a sparkle, drawn at [scale] of the canvas so
/// the adaptive foreground stays inside Android's safe zone.
void drawMark(img.Image canvas, double scale) {
  const c = size ~/ 2;
  final outer = (300 * scale).round();
  final inner = (215 * scale).round();
  img.fillCircle(canvas, x: c, y: c, radius: outer, color: white, antialias: true);
  img.fillCircle(canvas, x: c, y: c, radius: inner, color: deep, antialias: true);
  // Four-point sparkle inside the lens.
  final r = 150 * scale;
  final w = 38 * scale;
  final points = <img.Point>[];
  for (var i = 0; i < 8; i++) {
    final angle = i * pi / 4 - pi / 2;
    final len = i.isEven ? r : w;
    points.add(img.Point(c + len * cos(angle), c + len * sin(angle)));
  }
  img.fillPolygon(canvas, vertices: points, color: amber);
}

void main() {
  final full = img.Image(width: size, height: size, numChannels: 4);
  img.fill(full, color: indigo);
  drawMark(full, 1.0);
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(full));

  final foreground = img.Image(width: size, height: size, numChannels: 4);
  img.fill(foreground, color: clear);
  drawMark(foreground, 0.62);
  File('assets/icon/icon_foreground.png')
      .writeAsBytesSync(img.encodePng(foreground));
  // Google Play store listing assets.
  File('store/play_icon_512.png')
      .writeAsBytesSync(img.encodePng(img.copyResize(full, width: 512)));
  final banner = img.Image(width: 1024, height: 500, numChannels: 4);
  img.fill(banner, color: indigo);
  final mark = img.copyResize(full, width: 360);
  img.compositeImage(banner, mark, dstX: 70, dstY: 70);
  img.drawString(banner, 'EventLens',
      font: img.arial48, x: 480, y: 190, color: white);
  img.drawString(banner, 'Your life, remembered in detail',
      font: img.arial24, x: 480, y: 260, color: white);
  File('store/feature_graphic_1024x500.png')
      .writeAsBytesSync(img.encodePng(banner));
  stdout.writeln('Wrote launcher icon sources and store graphics');
}
