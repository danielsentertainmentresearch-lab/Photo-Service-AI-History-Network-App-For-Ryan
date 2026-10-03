import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/event.dart';

class PlacesException implements Exception {
  final String message;

  const PlacesException(this.message);

  @override
  String toString() => message;
}

/// Place names and weather from open, non-Google services:
///
/// * Place names: OpenStreetMap Nominatim (reverse) and Open-Meteo
///   geocoding (search). Only coordinates or the place text are sent.
/// * Weather: Open-Meteo forecast (recent days) and historical archive.
///
/// Both have usage policies; heavy or commercial use needs their paid plans
/// or a self-hosted instance (see docs/LAUNCH_CHECKLIST.md). Base URLs are
/// overridable so a self-hosted instance can be used.
class PlacesService {
  final http.Client _http;
  final String nominatimBase;
  final String geocodingBase;
  final String forecastBase;
  final String archiveBase;
  final DateTime Function() _now;

  static const _userAgent =
      'EventLens/1.0 (+https://github.com/danielsentertainmentresearch-lab/'
      'Photo-Service-AI-History-Network-App-For-Ryan)';

  PlacesService({
    http.Client? httpClient,
    this.nominatimBase = 'https://nominatim.openstreetmap.org',
    this.geocodingBase = 'https://geocoding-api.open-meteo.com',
    this.forecastBase = 'https://api.open-meteo.com',
    this.archiveBase = 'https://archive-api.open-meteo.com',
    DateTime Function()? now,
  }) : _http = httpClient ?? http.Client(),
       _now = now ?? DateTime.now;

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final http.Response response;
    try {
      response = await _http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const PlacesException('The weather service took too long.');
    } catch (_) {
      throw const PlacesException('No internet connection.');
    }
    if (response.statusCode != 200) {
      throw PlacesException(
        'The service answered with an error (${response.statusCode}).',
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  /// A short place name ("Fallen Leaf Lake, California") for coordinates,
  /// or null when nothing useful comes back.
  Future<String?> placeName(double latitude, double longitude) async {
    final data = await _get(
      Uri.parse('$nominatimBase/reverse').replace(
        queryParameters: {
          'format': 'jsonv2',
          'lat': '$latitude',
          'lon': '$longitude',
          'zoom': '14',
        },
      ),
    );
    final address = (data['address'] as Map?)?.cast<String, dynamic>() ?? {};
    final local = [
      'natural', 'leisure', 'tourism', 'amenity', 'neighbourhood', 'suburb',
      'village', 'town', 'city',
    ].map((k) => address[k] as String?).whereType<String>().firstOrNull;
    final region = (address['state'] ?? address['country']) as String?;
    if (local == null) return data['name'] as String?;
    return region == null || region == local ? local : '$local, $region';
  }

  /// Coordinates for a typed place name, or null when not found.
  Future<(double, double)?> findPlace(String name) async {
    if (name.trim().isEmpty) return null;
    final data = await _get(
      Uri.parse('$geocodingBase/v1/search').replace(
        queryParameters: {'name': name.trim(), 'count': '1'},
      ),
    );
    final results = (data['results'] as List?) ?? const [];
    if (results.isEmpty) return null;
    final first = results.first as Map<String, dynamic>;
    return (
      (first['latitude'] as num).toDouble(),
      (first['longitude'] as num).toDouble(),
    );
  }

  /// Weather at [latitude], [longitude] for the hour of [when] (local time
  /// at the place). Recent dates use the forecast service, older ones the
  /// historical archive.
  Future<EventWeather> weatherAt(
    double latitude,
    double longitude,
    DateTime when,
  ) async {
    final day = DateFormat('yyyy-MM-dd').format(when);
    final recent = _now().difference(when).inDays < 60;
    final base = recent ? '$forecastBase/v1/forecast' : '$archiveBase/v1/archive';
    final data = await _get(
      Uri.parse(base).replace(
        queryParameters: {
          'latitude': '$latitude',
          'longitude': '$longitude',
          'start_date': day,
          'end_date': day,
          'hourly':
              'temperature_2m,weather_code,precipitation,wind_speed_10m',
          'timezone': 'auto',
        },
      ),
    );
    final hourly = (data['hourly'] as Map?)?.cast<String, dynamic>();
    final times = (hourly?['time'] as List?)?.cast<String>() ?? const [];
    final target = DateFormat("yyyy-MM-dd'T'HH:00").format(when);
    final index = times.indexOf(target);
    num? at(String key) {
      final list = hourly?[key] as List?;
      if (list == null || index < 0 || index >= list.length) return null;
      return list[index] as num?;
    }

    final temp = at('temperature_2m');
    final code = at('weather_code');
    if (temp == null || code == null) {
      throw const PlacesException(
        'No weather is available for that date and place yet.',
      );
    }
    return EventWeather(
      temperatureC: temp.toDouble(),
      weatherCode: code.toInt(),
      precipitationMm: (at('precipitation') ?? 0).toDouble(),
      windKmh: (at('wind_speed_10m') ?? 0).toDouble(),
      fetchedAt: _now(),
    );
  }
}
