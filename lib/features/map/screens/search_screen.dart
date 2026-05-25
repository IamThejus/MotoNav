import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/nominatim_service.dart';
import '../providers/map_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    final userLocation = ref.read(mapProvider).userLocation;
    ref.read(searchProvider.notifier).onQueryChanged(
      query,
      userLocation: userLocation,
    );
  }

  void _selectResult(SearchResult result) {
    ref.read(mapProvider.notifier).setDestination(result);
    ref.read(searchProvider.notifier).clear();
    Navigator.of(context).pop(result);
  }

  void _clear() {
    _controller.clear();
    ref.read(searchProvider.notifier).clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _buildSearchField(),
        titleSpacing: 0,
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: _clear,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1, thickness: 1, color: AppTheme.surfaceElevated),
          Expanded(
            child: _buildBody(searchState),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      onChanged: _onQueryChanged,
      style: const TextStyle(
        color: AppTheme.onSurface,
        fontSize: 16,
      ),
      cursorColor: AppTheme.primary,
      decoration: const InputDecoration(
        hintText: 'Search destination...',
        hintStyle: TextStyle(color: AppTheme.onSurfaceMuted),
        border: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }

  Widget _buildBody(SearchState state) {
    return switch (state.status) {
      SearchStatus.idle => _buildIdleState(),
      SearchStatus.loading => _buildLoadingState(),
      SearchStatus.results => _buildResultsList(state.results),
      SearchStatus.empty => _buildEmptyState(state.query),
      SearchStatus.error => _buildErrorState(state.errorMessage),
    };
  }

  Widget _buildIdleState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_rounded,
            size: 56,
            color: AppTheme.onSurfaceMuted.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Search for your destination',
            style: TextStyle(
              color: AppTheme.onSurfaceMuted.withOpacity(0.7),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(AppTheme.primary),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Searching...',
            style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(List<SearchResult> results) {
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        indent: 56,
        color: AppTheme.surfaceElevated,
      ),
      itemBuilder: (context, index) {
        final result = results[index];
        return _SearchResultTile(
          result: result,
          onTap: () => _selectResult(result),
        );
      },
    );
  }

  Widget _buildEmptyState(String query) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_off_rounded,
            size: 48,
            color: AppTheme.onSurfaceMuted.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No results for "$query"',
            style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try a different spelling or more detail',
            style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String? message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: AppTheme.error),
            const SizedBox(height: 16),
            Text(
              message ?? 'Search failed',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 15),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _onQueryChanged(_controller.text),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const _SearchResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: AppTheme.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.shortName,
                    style: const TextStyle(
                      color: AppTheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    result.displayName,
                    style: const TextStyle(
                      color: AppTheme.onSurfaceMuted,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.north_east_rounded,
              color: AppTheme.onSurfaceMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
