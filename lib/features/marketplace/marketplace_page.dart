import 'dart:async';

import 'package:flutter/material.dart';

import '../companion/companion_scope.dart';
import '../companion/companion_session.dart';
import '../companion/pack_manifest.dart';
import 'catalogue.dart';
import 'catalogue_repository.dart';
import 'catalogue_scope.dart';

/// The curated marketplace.
///
/// A catalogue can be passed directly (tests, development builds) or loaded
/// from the bundled production document. An empty catalogue is a supported
/// state and leaves browsing in place.
class MarketplacePage extends StatefulWidget {
  const MarketplacePage({
    required this.initialSnapshot,
    required this.onSnapshot,
    this.catalogue,
    this.session,
    this.repository = const BundledCatalogueRepository(),
    super.key,
  });

  final String? initialSnapshot;
  final Future<void> Function(String) onSnapshot;
  final CompanionCatalogue? catalogue;
  final CompanionSession? session;
  final CompanionCatalogueRepository repository;

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final _search = TextEditingController();
  CompanionSession? _session;
  bool _ownsSession = false;
  CatalogueController? _controller;
  Listenable? _repaint;
  bool _started = false;
  String _query = '';
  PackCategory? _category;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final seed = widget.catalogue ?? CompanionCatalogueScope.maybeOf(context);
    final controller = CatalogueController(seed: seed, repository: widget.repository);
    _controller = controller;
    unawaited(controller.load());
    final shared = widget.session ?? CompanionSessionScope.maybeOf(context);
    if (shared != null) {
      _session = shared;
    } else {
      _session = CompanionSession(
        initialSnapshot: widget.initialSnapshot,
        onSnapshot: widget.onSnapshot,
      );
      _ownsSession = true;
    }
    _repaint = Listenable.merge([_session!, controller]);
  }

  @override
  void dispose() {
    _search.dispose();
    if (_ownsSession) _session?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _notify(String? text) {
    if (!mounted || text == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _install(CatalogueEntry entry) async {
    final ok = await _session!.installPack(entry.toBundle);
    _notify(ok ? _session!.success : _session!.error);
  }

  void _open(CatalogueEntry entry) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _CataloguePackPage(entry: entry, session: _session!),
      ),
    );
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final repaint = _repaint;
    if (repaint == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: repaint,
      builder: (context, _) {
        final controller = _controller!;
        final session = _session!;
        final catalogue = controller.catalogue;
        final results = catalogue.search(_query, category: _category);
        return Scaffold(
          appBar: AppBar(title: const Text('Marketplace')),
          body: SafeArea(
            child: Column(
              children: [
                if (controller.loading) const LinearProgressIndicator(minHeight: 2),
                if (controller.error != null)
                  _CatalogueNotice(
                    message: controller.error!,
                    onRetry: controller.retry,
                    onDismiss: controller.dismissError,
                  ),
                if (!catalogue.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search companions',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: 'Clear search',
                                onPressed: _clearSearch,
                              ),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                if (!catalogue.isEmpty)
                  SizedBox(
                    height: 48,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('All'),
                            selected: _category == null,
                            onSelected: (_) => setState(() => _category = null),
                          ),
                          for (final category in catalogue.categories) ...[
                            const SizedBox(width: 8),
                            FilterChip(
                              label: Text(category.label),
                              selected: _category == category,
                              onSelected: (_) => setState(() => _category = category),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: catalogue.isEmpty
                      ? _MarketplaceEmpty(loading: controller.loading)
                      : results.isEmpty
                      ? _NoMatches(query: _query, onClear: _clearSearch)
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final entry = results[index];
                            return _CatalogueTile(
                              entry: entry,
                              session: session,
                              onOpen: () => _open(entry),
                              onInstall: () => _install(entry),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CatalogueTile extends StatelessWidget {
  const _CatalogueTile({
    required this.entry,
    required this.session,
    required this.onOpen,
    required this.onInstall,
  });

  final CatalogueEntry entry;
  final CompanionSession session;
  final VoidCallback onOpen;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final installed = session.library.pack(entry.id);
    final newer =
        installed != null && comparePackVersions(entry.version, installed.version) > 0;
    final busy = session.busy;
    return ListTile(
      leading: _PackSwatch(
        manifest: entry.manifest,
        category: entry.category,
        size: 44,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              entry.manifest.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (entry.featured) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.star,
              size: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${entry.manifest.author} · v${entry.version}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: installed == null
          ? FilledButton.tonal(
              onPressed: busy ? null : onInstall,
              child: const Text('Install'),
            )
          : newer
          ? FilledButton.tonal(
              onPressed: busy ? null : onInstall,
              child: const Text('Update'),
            )
          : Text('Installed', style: Theme.of(context).textTheme.labelMedium),
      onTap: onOpen,
    );
  }
}

class _CataloguePackPage extends StatelessWidget {
  const _CataloguePackPage({required this.entry, required this.session});

  final CatalogueEntry entry;
  final CompanionSession session;

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _install(BuildContext context) async {
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
    final ok = await session.remove(entry.id);
    if (!context.mounted) return;
    final text = ok ? session.success : session.error;
    if (text != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manifest = entry.manifest;
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final installed = session.library.pack(entry.id);
        final newer =
            installed != null && comparePackVersions(entry.version, installed.version) > 0;
        return Scaffold(
          appBar: AppBar(title: Text(manifest.name)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PackSwatch(
                      manifest: manifest,
                      category: entry.category,
                      size: 72,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
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
                          const SizedBox(height: 4),
                          Text(entry.category.label, style: theme.textTheme.labelMedium),
                        ],
                      ),
                    ),
                  ],
                ),
                if (manifest.description != null) ...[
                  const SizedBox(height: 16),
                  Text(manifest.description!, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 16),
                _DetailRow('Version', manifest.version),
                _DetailRow('Category', entry.category.label),
                _DetailRow('License', manifest.license),
                _DetailRow('Canvas', '${manifest.canvasWidth} × ${manifest.canvasHeight}'),
                _DetailRow('Clips', '${manifest.clips.length}'),
                _DetailRow('Size', _size(manifest.byteSize)),
                if (manifest.homepage != null) _DetailRow('Homepage', manifest.homepage!),
                if (manifest.attribution != null)
                  _DetailRow('Attribution', manifest.attribution!),
                if (manifest.minimumAppVersion != null)
                  _DetailRow('Requires', 'Version ${manifest.minimumAppVersion}'),
                const SizedBox(height: 20),
                if (installed == null || newer)
                  FilledButton(
                    onPressed: session.busy ? null : () => _install(context),
                    child: Text(installed == null ? 'Install' : 'Update to ${manifest.version}'),
                  ),
                if (installed != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Installed version ${installed.version}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: session.busy ? null : () => _remove(context, manifest.name),
                    child: const Text('Remove'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PackSwatch extends StatelessWidget {
  const _PackSwatch({
    required this.manifest,
    required this.category,
    required this.size,
  });

  final PackManifest manifest;
  final PackCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final base = Color(
      int.parse('FF${manifest.palette.first.substring(1)}', radix: 16),
    );
    final foreground = ThemeData.estimateBrightnessForColor(base) == Brightness.dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF1A1A1A);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(size * 0.16),
      ),
      child: Icon(
        _categoryIcon(category),
        size: size * 0.5,
        color: foreground.withValues(alpha: 0.85),
      ),
    );
  }
}

IconData _categoryIcon(PackCategory category) => switch (category) {
  PackCategory.geometric => Icons.hexagon_outlined,
  PackCategory.animal => Icons.pets_outlined,
  PackCategory.plant => Icons.eco_outlined,
  PackCategory.object => Icons.inventory_2_outlined,
  PackCategory.other => Icons.extension_outlined,
};

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

class _CatalogueNotice extends StatelessWidget {
  const _CatalogueNotice({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final Future<void> Function() onRetry;
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
            TextButton(onPressed: () => onRetry(), child: const Text('Retry')),
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

class _MarketplaceEmpty extends StatelessWidget {
  const _MarketplaceEmpty({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('The marketplace is empty', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              loading
                  ? 'Reading the catalogue.'
                  : 'Catalogue packs appear here. You can still import a pack file from the library.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No companions match "$query".',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onClear, child: const Text('Clear search')),
          ],
        ),
      ),
    );
  }
}
