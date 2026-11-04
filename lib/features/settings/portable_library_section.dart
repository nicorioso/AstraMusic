import 'package:astramusic/features/playlists/presentation/playlist_providers.dart';
import 'package:astramusic/features/settings/portable_library_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PortableLibrarySection extends ConsumerStatefulWidget {
  const PortableLibrarySection({super.key});

  @override
  ConsumerState<PortableLibrarySection> createState() => _PortableLibrarySectionState();
}

class _PortableLibrarySectionState extends ConsumerState<PortableLibrarySection> {
  bool busy = false;

  Future<void> run(Future<String?> Function(PortableLibraryActions) action) async {
    if (busy) return;
    setState(() => busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await action(PortableLibraryActions(ref));
      if (mounted && message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('No se pudo completar: $error')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> askName(String title) async {
    var name = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 340,
          child: TextField(
            autofocus: true,
            maxLength: 80,
            onChanged: (value) => name = value,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            if (name.trim().isNotEmpty) Navigator.pop(dialogContext, name.trim());
          }, child: const Text('Continuar')),
        ],
      ),
    );
  }

  Future<void> exportPlaylist() async {
    final playlists = await ref.read(playlistRepositoryProvider).watchAll().first;
    if (!mounted) return;
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay playlists para exportar.')));
      return;
    }
    final playlist = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Exportar playlist'),
        content: SizedBox(
          width: 360,
          height: 320,
          child: ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (_, index) => ListTile(
              title: Text(playlists[index].name),
              onTap: () => Navigator.pop(dialogContext, playlists[index].id),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar'))],
      ),
    );
    if (playlist == null || !mounted) return;
    final selected = playlists.firstWhere((item) => item.id == playlist);
    await run((actions) async {
      return await actions.exportPlaylist(selected.id, selected.name) ? 'Playlist exportada.' : null;
    });
  }

  Future<void> importPlaylist() async {
    final name = await askName('Importar playlist M3U');
    if (name == null || !mounted) return;
    await run((actions) async {
      final result = await actions.importPlaylist(name);
      return result == null ? null : '${result.added} canciones importadas; ${result.missing} sin coincidencia.';
    });
  }

  Future<void> restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar respaldo'),
        content: const Text('Se reemplazarán la biblioteca, las playlists y los datos locales actuales.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await run((actions) async => await actions.restoreBackup() ? 'Respaldo restaurado.' : null);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text('Archivos y respaldo', style: Theme.of(context).textTheme.titleSmall),
      ),
      ListTile(key: const Key('settings-export-m3u'), leading: const Icon(Icons.upload_file_outlined), title: const Text('Exportar playlist M3U8'), enabled: !busy, onTap: exportPlaylist),
      ListTile(key: const Key('settings-import-m3u'), leading: const Icon(Icons.playlist_add_outlined), title: const Text('Importar playlist M3U'), enabled: !busy, onTap: importPlaylist),
      ListTile(key: const Key('settings-create-backup'), leading: const Icon(Icons.backup_outlined), title: const Text('Crear copia de seguridad'), enabled: !busy, onTap: () => run((actions) async { return await actions.createBackup() ? 'Copia de seguridad creada.' : null; })),
      ListTile(key: const Key('settings-restore-backup'), leading: const Icon(Icons.restore_outlined), title: const Text('Restaurar copia de seguridad'), enabled: !busy, onTap: restore),
      ListTile(key: const Key('settings-repair-tracks'), leading: const Icon(Icons.folder_open_outlined), title: const Text('Reparar rutas de canciones'), enabled: !busy, onTap: () => run((actions) async {
        final result = await actions.repair();
        return result == null ? null : '${result.repaired} reparadas; ${result.unmatched} sin coincidencia; ${result.ambiguous} ambiguas.';
      })),
    ],
  );
}
