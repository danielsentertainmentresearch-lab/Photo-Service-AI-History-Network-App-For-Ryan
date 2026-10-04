import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/photo_metadata.dart';
import '../state/app_state.dart';
import '../widgets/free_write_box.dart';
import 'event_detail_screen.dart';

class NewEventScreen extends StatefulWidget {
  const NewEventScreen({super.key});

  @override
  State<NewEventScreen> createState() => _NewEventScreenState();
}

class _NewEventScreenState extends State<NewEventScreen> {
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  final _experience = TextEditingController();
  final List<File> _photos = [];
  DateTime _occurredAt = DateTime.now();
  bool _saving = false;
  bool _userPickedDate = false;
  double? _latitude;
  double? _longitude;
  String? _filledFromPhoto;

  int get _remaining => AppState.maxPhotosPerEvent - _photos.length;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    _experience.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    if (_remaining <= 0) return;
    final picked = await _picker.pickMultiImage(limit: _remaining);
    if (picked.isEmpty) return;
    setState(() =>
        _photos.addAll(picked.take(_remaining).map((x) => File(x.path))));
    _fillFromPhoto();
  }

  Future<void> _takePhoto() async {
    if (_remaining <= 0) return;
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    setState(() => _photos.add(File(picked.path)));
    _fillFromPhoto();
  }

  /// Uses the first photo's EXIF capture time and GPS position to fill in
  /// "when" and "where", without overriding anything the user set.
  Future<void> _fillFromPhoto() async {
    if (_photos.isEmpty) return;
    final PhotoMetadata meta;
    try {
      final bytes = await _photos.first.readAsBytes();
      meta = await compute(readPhotoMetadata, bytes);
    } catch (_) {
      return;
    }
    if (!mounted || meta.isEmpty) return;
    final filled = <String>[];
    setState(() {
      if (meta.takenAt != null && !_userPickedDate) {
        _occurredAt = meta.takenAt!;
        filled.add('date');
      }
      if (meta.hasLocation && _latitude == null) {
        _latitude = meta.latitude;
        _longitude = meta.longitude;
        filled.add('place');
      }
      if (filled.isNotEmpty) {
        _filledFromPhoto = 'Filled in the ${filled.join(' and ')} from your photo.';
      }
    });
    if (meta.hasLocation && _location.text.trim().isEmpty) {
      try {
        final name = await context.read<AppState>().places.placeName(
              meta.latitude!,
              meta.longitude!,
            );
        if (mounted && name != null && _location.text.trim().isEmpty) {
          setState(() => _location.text = name);
        }
      } catch (_) {
        // Offline or the service is busy: the coordinates are still kept.
      }
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_occurredAt));
    setState(() {
      _userPickedDate = true;
      _occurredAt = DateTime(date.year, date.month, date.day,
          time?.hour ?? _occurredAt.hour, time?.minute ?? _occurredAt.minute);
    });
  }

  Future<void> _save({required bool describe}) async {
    if (_photos.isEmpty &&
        _notes.text.trim().isEmpty &&
        _experience.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add at least one photo or some notes.')));
      return;
    }
    setState(() => _saving = true);
    final state = context.read<AppState>();
    try {
      final event = await state.createEvent(
        title: _title.text,
        notes: _notes.text,
        location: _location.text,
        occurredAt: _occurredAt,
        photos: _photos,
        latitude: _latitude,
        longitude: _longitude,
        experience: _experience.text,
      );
      if (describe) {
        // Runs in the background; the detail screen shows its progress.
        state.describeEvent(event.id);
      }
      if (_experience.text.trim().isNotEmpty) {
        state.labelExperience(event.id);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: event.id)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = context.select<AppState, bool>((s) => s.hasApiKey);
    return Scaffold(
      appBar: AppBar(title: const Text('New event')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Photos (${_photos.length}/${AppState.maxPhotosPerEvent})',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 104,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    _Thumb(
                      file: _photos[i],
                      onRemove: () => setState(() => _photos.removeAt(i)),
                    ),
                  if (_remaining > 0) ...[
                    _AddTile(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        onTap: _pickFromGallery),
                    _AddTile(
                        icon: Icons.photo_camera_outlined,
                        label: 'Camera',
                        onTap: _takePhoto),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(DateFormat.yMMMEd().add_jm().format(_occurredAt)),
              subtitle: Text(_filledFromPhoto ?? 'When it happened'),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDateTime,
            ),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title (optional)',
                helperText: 'Leave blank and the AI will suggest one',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _location,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Where (optional)',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 5,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What\'s happening?',
                alignLabelWithHint: true,
                hintText: 'Who is here, what led up to this, anything the '
                    'photos can\'t show…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FreeWriteBox(controller: _experience),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(describe: hasKey),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(hasKey ? 'Save and describe' : 'Save'),
            ),
            if (hasKey) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _saving ? null : () => _save(describe: false),
                child: const Text('Save without describing'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;

  const _Thumb({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(file,
                width: 104,
                height: 104,
                fit: BoxFit.cover,
                cacheWidth: (104 * ratio).round()),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove',
              icon: const Icon(Icons.close, size: 16),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AddTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 104,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon), const SizedBox(height: 4), Text(label)],
          ),
        ),
      ),
    );
  }
}
