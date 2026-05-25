import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SearchBarWidget extends StatelessWidget {
  final VoidCallback onTap;
  final String? destinationName;

  const SearchBarWidget({
    super.key,
    required this.onTap,
    this.destinationName,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: destinationName != null
              ? Border.all(color: AppTheme.primary.withOpacity(0.4), width: 1)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              destinationName != null
                  ? Icons.flag_rounded
                  : Icons.search_rounded,
              color: destinationName != null
                  ? AppTheme.primary
                  : AppTheme.onSurfaceMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                destinationName ?? 'Search destination...',
                style: TextStyle(
                  color: destinationName != null
                      ? AppTheme.onSurface
                      : AppTheme.onSurfaceMuted,
                  fontSize: 15,
                  fontWeight: destinationName != null
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (destinationName != null)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.onSurfaceMuted,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}
