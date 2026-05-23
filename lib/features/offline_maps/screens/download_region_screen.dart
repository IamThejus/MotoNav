import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/api_config.dart';
import '../../../core/theme/app_theme.dart';

const _minZoom = 13;
const _maxZoom = 17;
const _avgTileSizeKB = 15.0;
const _hPad = 20.0;
const _topBarH = 56.0;
const _botPanelH = 130.0;

class DownloadRegionScreen extends StatefulWidget {
  final LatLng initialCenter;

  const DownloadRegionScreen({
    super.key,
    required this.initialCenter,
  });

  @override
  State<DownloadRegionScreen> createState() => _DownloadRegionScreenState();
}

class _DownloadRegionScreenState extends State<DownloadRegionScreen> {
  final _mapController = MapController();

  int _totalTiles = 0;
  double _sizeMB = 0;
  bool _downloading = false;
  bool _done = false;
  int _downloadedTiles = 0;

  StreamSubscription<DownloadProgress>? _progressSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateEstimate());
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd) _updateEstimate();
  }

  void _updateEstimate() {
    if (!mounted) return;
    final bounds = _selectionBounds();
    if (bounds == null) return;
    final count = _tileCount(bounds, _minZoom, _maxZoom);
    setState(() {
      _totalTiles = count;
      _sizeMB = count * _avgTileSizeKB / 1024;
    });
  }

  LatLngBounds? _selectionBounds() {
    try {
      final camera = _mapController.camera;
      final vb = camera.visibleBounds;
      final size = MediaQuery.of(context).size;
      final padding = MediaQuery.of(context).padding;

      final rectTop = padding.top + _topBarH + 8.0;
      final rectBottom = size.height - _botPanelH - padding.bottom;

      final lngSpan = vb.east - vb.west;
      final latSpan = vb.north - vb.south;

      return LatLngBounds(
        LatLng(
          vb.north - (rectBottom / size.height) * latSpan,
          vb.west + (_hPad / size.width) * lngSpan,
        ),
        LatLng(
          vb.north - (rectTop / size.height) * latSpan,
          vb.west + ((size.width - _hPad) / size.width) * lngSpan,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _startDownload() async {
    final bounds = _selectionBounds();
    if (bounds == null) return;

    setState(() {
      _downloading = true;
      _downloadedTiles = 0;
      _done = false;
    });

    try {
      await FMTCStore('offline').manage.create();

      final downloadable = RectangleRegion(bounds).toDownloadable(
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        options: TileLayer(
          urlTemplate: ApiConfig.osmTileUrl,
          userAgentPackageName: 'com.thejus.motonav',
        ),
      );

      _progressSub = FMTCStore('offline')
          .download
          .startForeground(
            region: downloadable,
            parallelThreads: 3,
            maxBufferLength: 100,
            skipExistingTiles: true,
            skipSeaTiles: true,
          )
          .listen(
            (p) {
              if (!mounted) return;
              setState(() {
                _downloadedTiles = p.successfulTiles;
                _totalTiles = p.maxTiles;
              });
            },
            onError: (Object e) {
              if (!mounted) return;
              setState(() => _downloading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Download failed: $e')),
              );
            },
            onDone: () {
              if (!mounted) return;
              setState(() {
                _downloading = false;
                _done = true;
              });
            },
            cancelOnError: true,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download error: $e')),
      );
    }
  }

  Future<void> _cancelDownload() async {
    await _progressSub?.cancel();
    _progressSub = null;
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    final selRect = Rect.fromLTRB(
      _hPad,
      padding.top + _topBarH + 8.0,
      size.width - _hPad,
      size.height - _botPanelH - padding.bottom,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: 14.0,
              onMapEvent: _onMapEvent,
              backgroundColor: AppTheme.surface,
            ),
            children: [
              TileLayer(
                urlTemplate: ApiConfig.osmTileUrl,
                userAgentPackageName: 'com.thejus.motonav',
                tileBuilder: _darkTileBuilder,
              ),
            ],
          ),

          // ── Selection overlay ─────────────────────────────────────────────
          IgnorePointer(
            child: CustomPaint(
              size: size,
              painter: _SelectionPainter(rect: selRect),
            ),
          ),

          // ── Top bar ───────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black87,
              padding: EdgeInsets.only(top: padding.top),
              height: padding.top + _topBarH,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Select Area to Download',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Text(
                      'Zoom to fit area',
                      style: TextStyle(
                          color: AppTheme.onSurfaceMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom panel ──────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + padding.bottom),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Colors.black54, blurRadius: 20),
                ],
              ),
              child: _done
                  ? _buildDone()
                  : _downloading
                      ? _buildProgress()
                      : _buildDownloadBar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadBar() {
    final sizeStr = _sizeMB < 1
        ? '${(_sizeMB * 1024).round()} KB'
        : '${_sizeMB.toStringAsFixed(1)} MB';

    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '~$sizeStr',
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '$_totalTiles tiles · zoom $_minZoom–$_maxZoom',
              style: const TextStyle(
                  color: AppTheme.onSurfaceMuted, fontSize: 12),
            ),
          ],
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: _totalTiles > 0 ? _startDownload : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.black,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.download_rounded, size: 20),
          label: const Text(
            'Download',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildProgress() {
    final pct = _totalTiles > 0 ? _downloadedTiles / _totalTiles : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Downloading… ${(pct * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            TextButton(
              onPressed: _cancelDownload,
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.error)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '$_downloadedTiles / $_totalTiles tiles',
            style: const TextStyle(
                color: AppTheme.onSurfaceMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Row(
      children: [
        const Icon(Icons.check_circle_rounded,
            color: AppTheme.success, size: 24),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Area downloaded — available offline',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _darkTileBuilder(
      BuildContext ctx, Widget tileWidget, TileImage tile) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.28, 0, 0, 0, 0,
        0, 0.28, 0, 0, 0,
        0, 0, 0.30, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: tileWidget,
    );
  }
}

// ── Tile count estimate (Mercator tile math) ──────────────────────────────────

int _tileCount(LatLngBounds bounds, int minZoom, int maxZoom) {
  int total = 0;
  for (int z = minZoom; z <= maxZoom; z++) {
    final sw = _toTile(bounds.southWest, z);
    final ne = _toTile(bounds.northEast, z);
    total += ((ne[0] - sw[0]).abs() + 1) * ((sw[1] - ne[1]).abs() + 1);
  }
  return total;
}

List<int> _toTile(LatLng ll, int z) {
  final n = 1 << z;
  final x = ((ll.longitude + 180) / 360 * n).floor().clamp(0, n - 1);
  final latR = ll.latitude * math.pi / 180;
  final y =
      ((1 - math.log(math.tan(latR) + 1 / math.cos(latR)) / math.pi) /
              2 *
              n)
          .floor()
          .clamp(0, n - 1);
  return [x, y];
}

// ── Selection overlay painter ─────────────────────────────────────────────────

class _SelectionPainter extends CustomPainter {
  final Rect rect;

  const _SelectionPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.55);

    // Draw four dark rectangles around the selection box
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, rect.top), overlay); // top
    canvas.drawRect(
        Rect.fromLTWH(0, rect.bottom, size.width, size.height - rect.bottom),
        overlay); // bottom
    canvas.drawRect(
        Rect.fromLTWH(0, rect.top, rect.left, rect.height), overlay); // left
    canvas.drawRect(
        Rect.fromLTWH(
            rect.right, rect.top, size.width - rect.right, rect.height),
        overlay); // right

    // Selection border
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Yellow corner handles
    final handle = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 18.0;

    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      final dx = corner.dx == rect.left ? len : -len;
      final dy = corner.dy == rect.top ? len : -len;
      canvas.drawLine(corner, corner + Offset(dx, 0), handle);
      canvas.drawLine(corner, corner + Offset(0, dy), handle);
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) =>
      old.rect != rect;
}
