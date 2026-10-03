import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// When and where a photo was taken, from its EXIF data.
class PhotoMetadata {
  final DateTime? takenAt;
  final double? latitude;
  final double? longitude;

  const PhotoMetadata({this.takenAt, this.latitude, this.longitude});

  bool get hasLocation => latitude != null && longitude != null;
  bool get isEmpty => takenAt == null && !hasLocation;
}

/// Reads the capture time and GPS position from a JPEG's EXIF block without
/// decoding the image. Anything missing or unreadable is left null; other
/// formats (PNG, most screenshots) carry no EXIF and return empty.
PhotoMetadata readPhotoMetadata(Uint8List bytes) {
  final img.ExifData? exif;
  try {
    exif = img.decodeJpgExif(bytes);
  } catch (_) {
    return const PhotoMetadata();
  }
  if (exif == null) return const PhotoMetadata();

  DateTime? takenAt;
  try {
    final raw = exif.exifIfd[0x9003]?.toString() ?? // DateTimeOriginal
        exif.imageIfd[0x0132]?.toString(); // DateTime
    takenAt = raw == null ? null : parseExifDate(raw);
  } catch (_) {
    takenAt = null;
  }

  double? latitude, longitude;
  try {
    final gps = exif.gpsIfd;
    latitude = _coordinate(gps[0x0002], gps[0x0001]?.toString(), 'S');
    longitude = _coordinate(gps[0x0004], gps[0x0003]?.toString(), 'W');
    // 0,0 is what some cameras write when they have no fix.
    if (latitude == 0 && longitude == 0) latitude = longitude = null;
  } catch (_) {
    latitude = longitude = null;
  }
  if (latitude == null || longitude == null) latitude = longitude = null;

  return PhotoMetadata(
    takenAt: takenAt,
    latitude: latitude,
    longitude: longitude,
  );
}

/// EXIF dates look like "2026:06:06 20:10:33" in the camera's local time.
DateTime? parseExifDate(String raw) {
  final m = RegExp(
    r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(raw.trim());
  if (m == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.tryParse(m.group(i) ?? '0') ?? 0];
  if (parts[0] < 1900 || parts[1] < 1 || parts[1] > 12 || parts[2] < 1) {
    return null;
  }
  return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
}

/// GPS values are degrees/minutes/seconds rationals (or one decimal value),
/// with a reference letter giving the hemisphere.
double? _coordinate(img.IfdValue? value, String? ref, String negativeRef) {
  if (value == null) return null;
  double part(int i) {
    try {
      return value.toDouble(i);
    } catch (_) {
      return 0;
    }
  }

  final degrees = part(0) + part(1) / 60 + part(2) / 3600;
  if (degrees.isNaN || degrees.isInfinite) return null;
  final negative = (ref ?? '').trim().toUpperCase() == negativeRef;
  return negative ? -degrees : degrees;
}
