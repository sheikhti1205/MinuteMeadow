import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/storage/pack_archive.dart';
import '../marketplace/catalogue.dart';
import '../marketplace/catalogue_repository.dart';
import '../marketplace/catalogue_scope.dart';
import '../marketplace/marketplace_page.dart';
import 'companion_library.dart';
import 'companion_scope.dart';
import 'companion_session.dart';
import 'pack_manifest.dart';

/// The installed companion library.
///
/// The library is restored from [initialSnapshot] and every accepted change is
/// written back through [onSnapshot]. Importing a pack is the only way content
/// enters the library until the catalogue lists a release.
class CompanionPage extends StatefulWidget {
  const CompanionPage({
    required this.initialSnapshot,
    required this.onSnapshot,
    this.previewBuilder,
    super.key,
  });

  final String? initialSnapshot;
  final Future<void> Function(String) onSnapshot;

  /// Draws the installed companion in the library detail.
  ///
  /// The shell supplies a layered renderer here; without one the library shows
  /// the pack's declared preview image.
  final Widget Function(BuildContext, InstalledPack)? previewBuilder;

  @override
  State<CompanionPage> createState() => _CompanionPageState();
}

enum _ImportChoice { file, text }

class _CompanionPageState extends State<CompanionPage> {
  CompanionSession? _session;
  bool _ownsSession = false;
  CatalogueController? _catalogue;
  Listenable? _repaint;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final seed = CompanionCatalogueScope.maybeOf(context);
    final catalogue = CatalogueController(seed: seed);
    _catalogue = catalogue;
    unawaited(catalogue.load());
    final shared = CompanionSessionScope.maybeOf(context);
    if (shared != null) {
      _session = shared;
    } else {
      _session = CompanionSession(
        initialSnapshot: widget.initialSnapshot,
        onSnapshot: widget.onSnapshot,
      );
      _ownsSession = true;
    }
    _repaint = Listenable.merge([_session!, catalogue]);
  }

  @override
  void dispose() {
    if (_ownsSession) _session?.dispose();
    _catalogue?.dispose();
    super.dispose();
  }

  void _message(String? text) {
    if (!mounted || text == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showImportOptions() async {
    final choice = await showModalBottomSheet<_ImportChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Choose a pack file'),
              subtitle: const Text('A .zip pack archive or a .json envelope'),
              onTap: () => Navigator.pop(context, _ImportChoice.file),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_outlined),
              title: const Text('Paste pack JSON'),
              subtitle: const Text('For a pack shared as text'),
              onTap: () => Navigator.pop(context, _ImportChoice.text),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _ImportChoice.file:
        await _importFile();
      case _ImportChoice.text:
        await _importText();
      case null:
        break;
    }
  }

  Future<void> _importFile() async {
    const group = XTypeGroup(
      label: 'Companion packs',
      extensions: <String>['zip', 'json'],
      mimeTypes: <String>['application/zip', 'application/json'],
    );
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
    } catch (_) {
      _message('The file picker is unavailable.');
      return;
    }
    if (file == null || !mounted) return;
    try {
      final length = await file.length();
      if (!mounted) return;
      if (length > PackArchive.maximumBytes) {
        _message('That file is too large to import.');
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > PackArchive.maximumBytes) {
        _message('That file is too large to import.');
        return;
      }
      final ok = await _session!.importBytes(bytes);
      if (!mounted) return;
      _message(ok ? _session!.success : _session!.error);
    } on Exception {
      if (mounted) _message('Could not read that file.');
    }
  }

  Future<void> _importText() async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _ImportDialog(),
    );
    if (text == null || !mounted) return;
    final ok = await _session!.importText(text);
    if (!mounted) return;
    _message(ok ? _session!.success : _session!.error);
  }

  Future<void> _openMarketplace() async {
    final catalogue = CompanionCatalogueScope.maybeOf(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MarketplacePage(
          initialSnapshot: null,
          onSnapshot: widget.onSnapshot,
          catalogue: catalogue,
          session: _session,
        ),
      ),
    );
  }

  void _openPack(InstalledPack pack, CompanionCatalogue catalogue) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _InstalledPackPage(
          session: _session!,
          id: pack.id,
          catalogue: catalogue,
          previewBuilder: widget.previewBuilder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repaint = _repaint;
    if (repaint == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: repaint,
      builder: (context, _) {
        final session = _session!;
        final library = session.library;
        final catalogue = _catalogue?.catalogue ?? CompanionCatalogue.empty;
        final notice = _libraryNotice(session);
        final theme = Theme.of(context);
        return Column(
          children: [
            if (session.busy) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Installed',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Import pack',
                    onPressed: session.busy ? null : _showImportOptions,
                  ),
                  if (!library.isEmpty)
                    IconButton(
                      icon: const Icon(Icons.storefront_outlined),
                      tooltip: 'Marketplace',
                      onPressed: session.busy ? null : _openMarketplace,
                    ),
                ],
              ),
            ),
            if (notice != null)
              _LibraryNotice(
                message: notice,
                onDismiss: session.dismissLoadNotice,
              ),
            Expanded(
              child: library.isEmpty
                  ? _LibraryEmpty(onBrowse: _openMarketplace)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: library.packs.length,
                      itemBuilder: (context, index) {
                        final pack = library.packs[index];
                        final latest = catalogue.latestFor(pack.id);
                        final update = latest != null &&
                            comparePackVersions(latest.version, pack.version) > 0;
                        return ListTile(
                          leading: _PackPreview(pack: pack, size: 48),
                          title: Text(
                            pack.manifest.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'v${pack.version} · ${pack.manifest.author}'
                            '${update ? ' · Update available' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _openPack(pack, catalogue),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  String? _libraryNotice(CompanionSession session) {
    final error = session.loadError;
    final rejected = session.rejected;
    final unread = rejected == 1
        ? '1 installed companion could not be read.'
        : '$rejected installed companions could not be read.';
    if (error != null && rejected > 0) return '$error $unread';
    if (error != null) return error;
    if (rejected > 0) return unread;
    return null;
  }
}

class _InstalledPackPage extends StatelessWidget {
  const _InstalledPackPage({
    required this.session,
    required this.id,
    required this.catalogue,
    required this.previewBuilder,
  });

  final CompanionSession session;
  final String id;
  final CompanionCatalogue catalogue;
  final Widget Function(BuildContext, InstalledPack)? previewBuilder;

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _update(BuildContext context, CatalogueEntry entry) async {
    final ok = await session.installPack(entry.toBundle);
    if (!context.mounted) return;
    final text = ok ? session.success : session.error;
    if (text != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _remove(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text('This companion is removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await session.remove(id);
    if (!context.mounted) return;
    final text = ok ? session.success : session.error;
    if (text != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final theme = Theme.of(context);
        final pack = session.library.pack(id);
        if (pack == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Companion')),
            body: Center(
              child: Text(
                'This companion is not installed.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          );
        }
        final manifest = pack.manifest;
        final latest = catalogue.latestFor(id);
        final newer =
            latest != null && comparePackVersions(latest.version, pack.version) > 0
            ? latest
            : null;
        return Scaffold(
          appBar: AppBar(title: Text(manifest.name)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (previewBuilder != null) ...[
                  previewBuilder!(context, pack),
                  const SizedBox(height: 12),
                  _PackHeading(manifest: manifest),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PackPreview(pack: pack, size: 96),
                      const SizedBox(width: 16),
                      Expanded(child: _PackHeading(manifest: manifest)),
                    ],
                  ),
                if (manifest.description != null) ...[
                  const SizedBox(height: 16),
                  Text(manifest.description!, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 16),
                _DetailRow('Version', manifest.version),
                _DetailRow('License', manifest.license),
                _DetailRow('Canvas', '${manifest.canvasWidth} × ${manifest.canvasHeight}'),
                _DetailRow('Clips', '${manifest.clips.length}'),
                _DetailRow('Size', _size(manifest.byteSize)),
                _DetailRow(
                  'Installed',
                  MaterialLocalizations.of(context).formatShortDate(
                    pack.installedAt.toLocal(),
                  ),
                ),
                if (manifest.homepage != null) _DetailRow('Homepage', manifest.homepage!),
                if (manifest.attribution != null)
                  _DetailRow('Attribution', manifest.attribution!),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final colour in manifest.palette)
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _colour(colour),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (newer != null)
                  FilledButton.tonal(
                    onPressed: session.busy ? null : () => _update(context, newer),
                    child: Text('Update to ${newer.version}'),
                  ),
                if (newer != null) const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: session.busy ? null : () => _remove(context, manifest.name),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Color _colour(String hex) =>
    Color(int.parse('FF${hex.substring(1)}', radix: 16));

class _PackHeading extends StatelessWidget {
  const _PackHeading({required this.manifest});

  final PackManifest manifest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(manifest.name, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '${manifest.author} · v${manifest.version}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PackPreview extends StatelessWidget {
  const _PackPreview({required this.pack, required this.size});

  final InstalledPack pack;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = pack.assets[pack.manifest.preview];
    final placeholder = Icon(
      Icons.pets_outlined,
      size: size * 0.5,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: asset == null
          ? placeholder
          : Image.memory(
              asset.bytes,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
    );
  }
}

class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pets_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No companions installed', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'A companion keeps you company while you focus. '
              'Browse the marketplace or import a pack file.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Browse marketplace'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    return AlertDialog(
      scrollable: true,
      title: const Text('Paste pack JSON'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste a companion pack envelope. '
            'The pack is validated before it is installed.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Pack JSON',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: text.isEmpty ? null : () => Navigator.pop(context, text),
          child: const Text('Install'),
        ),
      ],
    );
  }
}

class _LibraryNotice extends StatelessWidget {
  const _LibraryNotice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Dismiss',
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(label, style: theme.textTheme.labelMedium),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
