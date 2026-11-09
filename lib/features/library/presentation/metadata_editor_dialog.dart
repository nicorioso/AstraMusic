import 'package:astramusic/core/platform/image_file_picker.dart';
import 'package:astramusic/features/library/application/metadata_editor_service.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final metadataEditorServiceProvider = Provider<MetadataEditorService>((ref) {
  return LocalMetadataEditorService(ref.watch(trackRepositoryProvider));
});

final metadataImagePickerProvider = Provider<ImageFilePicker>((ref) {
  return const SystemImageFilePicker();
});

Future<void> showMetadataEditor(BuildContext context, Track track) =>
    showDialog<void>(
      context: context,
      builder: (_) => MetadataEditorDialog(track: track),
    );

class MetadataEditorDialog extends ConsumerStatefulWidget {
  const MetadataEditorDialog({required this.track, super.key});

  final Track track;

  @override
  ConsumerState<MetadataEditorDialog> createState() =>
      _MetadataEditorDialogState();
}

class _MetadataEditorDialogState extends ConsumerState<MetadataEditorDialog> {
  late final _title = TextEditingController(text: widget.track.title);
  late final _artist = TextEditingController(text: widget.track.artist);
  late final _album = TextEditingController(text: widget.track.album);
  late final _year = TextEditingController(text: widget.track.year?.toString());
  late final _genre = TextEditingController(text: widget.track.genre);
  final _form = GlobalKey<FormState>();
  String? _imagePath;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _year.dispose();
    _genre.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final selected = await ref.read(metadataImagePickerProvider).pickImage();
      if (mounted && selected != null) setState(() => _imagePath = selected);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir la imagen: $error');
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(metadataEditorServiceProvider)
          .save(
            widget.track,
            MetadataEdit(
              title: _title.text,
              artist: _artist.text,
              album: _album.text,
              year: _year.text.trim().isEmpty
                  ? null
                  : int.parse(_year.text.trim()),
              genre: _genre.text,
              imagePath: _imagePath,
            ),
          );
      if (mounted) navigator.pop();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudieron guardar los tags: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Editar metadatos'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const Key('metadata-title'),
                controller: _title,
                decoration: const InputDecoration(labelText: 'Título'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'El título es obligatorio'
                    : null,
              ),
              TextField(
                controller: _artist,
                decoration: const InputDecoration(labelText: 'Artista'),
              ),
              TextField(
                controller: _album,
                decoration: const InputDecoration(labelText: 'Álbum'),
              ),
              TextFormField(
                controller: _year,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Año'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final year = int.tryParse(value.trim());
                  return year == null || year < 1 || year > 9999
                      ? 'Ingresa un año entre 1 y 9999'
                      : null;
                },
              ),
              TextField(
                controller: _genre,
                decoration: const InputDecoration(labelText: 'Género'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('metadata-select-cover'),
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  _imagePath == null
                      ? 'Seleccionar carátula'
                      : 'Carátula seleccionada',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('metadata-save'),
        onPressed: _saving ? null : _save,
        child: const Text('Guardar'),
      ),
    ],
  );
}
