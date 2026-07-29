/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

// Flutter has an ImageCache of its own; the registered service is fastedgy's.
import 'package:flutter/material.dart' hide ImageCache;
import 'package:flutter_fastedgy/flutter_fastedgy.dart';

import '../icons.dart';
import '../rich_text/rich_text_controls.dart';
import '../rich_text/rich_text_theme.dart';

/// The cover image a document page wears: a wide band above the title, with the
/// actions to replace or drop it surfacing over it on hover.
///
/// The image is the record's storage path, rendered through the API's own
/// resizing so the page never downloads the full-size original.
class DocumentCover extends StatefulWidget {
  /// Storage path of the image.
  final String path;

  final VoidCallback? onChange;
  final VoidCallback? onRemove;

  /// An upload in flight: the actions step aside for a progress bar rather than
  /// letting a second one start.
  final bool busy;

  const DocumentCover({
    required this.path,
    super.key,
    this.onChange,
    this.onRemove,
    this.busy = false,
  });

  /// Tall enough to read as a cover, short enough to leave the subject on
  /// screen under it.
  static const double height = 200;

  @override
  State<DocumentCover> createState() => _DocumentCoverState();
}

class _DocumentCoverState extends State<DocumentCover> {
  bool _hovering = false;

  /// Width rounded up to a step: the image is re-requested whenever the width
  /// it was asked for changes, and a window being dragged wider would otherwise
  /// fire one download per pixel. The band is covered either way — the extra is
  /// cropped locally.
  static double _requestedWidth(double available) {
    const step = 200.0;
    final width = available.isFinite && available > 0 ? available : step;

    return (width / step).ceil() * step;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        height: DocumentCover.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // No image pipeline registered - a headless run - shows the band
            // rather than failing on a missing service.
            if (hasService<ImageCache>())
              LayoutBuilder(
                // Both dimensions, always: an image given only its height keeps
                // its intrinsic width and sits letterboxed in the middle of the
                // band, whatever the fit says. The width is also what the API
                // crops to, so the page downloads the band and not the original.
                builder: (context, constraints) => CachedApiImage(
                  path: widget.path,
                  width: _requestedWidth(constraints.maxWidth),
                  height: DocumentCover.height,
                  mode: ImageMode.cover,
                  format: 'webp',
                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                    color: RichTextTheme.of(context).subtleSurface,
                  ),
                ),
              )
            else
              ColoredBox(color: RichTextTheme.of(context).subtleSurface),
            if (widget.busy)
              Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: RichTextTheme.of(context).ink,
                ),
              )
            else
              Positioned(
                right: 16,
                bottom: 16,
                child: AnimatedOpacity(
                  opacity: _hovering ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CoverAction(
                        icon: FastEdgyIcons.of(context)[FastEdgyGlyph.image],
                        label: t('Change'),
                        onTap: _hovering ? widget.onChange : null,
                      ),
                      const SizedBox(width: 8),
                      _CoverAction(
                        icon: FastEdgyIcons.of(context)[FastEdgyGlyph.delete],
                        label: t('Remove'),
                        onTap: _hovering ? widget.onRemove : null,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One action floating over the image: opaque enough to stay legible whatever
/// the picture under it.
class _CoverAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _CoverAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);

    return RichTextControls.of(context).tappable(
      context,
      RichTextTapSpec(
        onTap: onTap ?? () {},
        radius: theme.chipRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            // Barely translucent: it stands over a picture and has to stay
            // readable whatever is under it.
            color: theme.surface.withValues(alpha: 0.92),
            borderRadius: theme.chipRadius,
            border: Border.all(color: theme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: theme.mutedText),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.fieldText.copyWith(
                  fontSize: (theme.fieldText.fontSize ?? 14) - 2,
                  fontWeight: FontWeight.w500,
                  color: theme.mutedText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
