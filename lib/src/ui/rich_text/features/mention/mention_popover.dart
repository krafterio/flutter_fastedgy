/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_fastedgy/flutter_fastedgy.dart'
    show getLogger, getService, hasService, t;
import '../../rich_text_controls.dart';
import '../../rich_text_popover.dart';
import '../../rich_text_theme.dart';
import 'mention_address.dart';
import 'mention_preview.dart';
import 'mention_source.dart';
import 'mention_span.dart';

final _log = getLogger('rich_text_mention_popover');

const _width = 300.0;

/// Opens the card of [mention], anchored on the chip that was clicked.
///
/// What it holds comes from the source that knows the model — a member reads as
/// a member, a flow as a flow — so nothing here has to know what either is.
void showMentionPopover(BuildContext context, Mention mention) {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final screen = overlay?.context.findRenderObject() as RenderBox?;

  if (box == null || overlay == null || screen == null || !box.attached) {
    return;
  }

  final chip = box.localToGlobal(Offset.zero) & box.size;
  final source = _registry?.forModel(mention.address.model);

  // The card is built inside an OverlayEntry, which is not under the caller:
  // an ambient theme is simply not found there, and the card would draw on the
  // floor instead of the application's design.
  final themes = InheritedTheme.capture(from: context, to: overlay.context);

  OverlayEntry? entry;

  void dismiss() {
    entry?.remove();
    entry = null;
  }

  entry = OverlayEntry(
    builder: (context) => themes.wrap(
      Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dismiss,
            ),
          ),
          Positioned.fill(
            child: CustomSingleChildLayout(
              // The chip stands in for the selection: the card lands under it,
              // flips above when there is no room, and stays on screen.
              delegate: RichTextPopoverLayout(
                selection: chip,
                editor: Offset.zero & screen.size,
                width: _width,
              ),
              child: _Card(
                mention: mention,
                source: source,
                onDismiss: dismiss,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  overlay.insert(entry!);
}

MentionSources? get _registry =>
    hasService<MentionSources>() ? getService<MentionSources>() : null;

class _Card extends StatefulWidget {
  final Mention mention;
  final MentionSource? source;
  final VoidCallback onDismiss;

  const _Card({
    required this.mention,
    required this.source,
    required this.onDismiss,
  });

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  /// Taken as the card opens, so Escape reaches it wherever the focus was —
  /// the editor keeps its own otherwise, and answers the key first.
  final _scope = FocusScopeNode(debugLabel: 'mention card');

  MentionPreview? _preview;
  bool _loading = true;

  /// What the card will settle on, which is what stands in for it meanwhile.
  MentionPreviewShape get _shape =>
      widget.source?.previewShape ?? MentionPreviewShape.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scope.requestFocus();
    });
    unawaited(_read());
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final preview = widget.source?.preview;

    if (preview == null) {
      if (mounted) setState(() => _loading = false);

      return;
    }

    try {
      final read = await preview(widget.mention.address.id);

      if (mounted) {
        setState(() {
          _preview = read;
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to read the ${widget.mention.address.model} behind a mention',
        error,
        stackTrace,
      );

      if (mounted) setState(() => _loading = false);
    }
  }

  /// The card names the record; turning that name into a screen is the
  /// application's routing, and the whole reason [RecordOpener] is a port.
  Future<void> _open() async {
    final opener = recordOpener;

    widget.onDismiss();

    if (opener == null) {
      return;
    }

    try {
      await opener.open(widget.mention.address);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to open the ${widget.mention.address.model} behind a mention',
        error,
        stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return Material(
      color: Colors.transparent,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
        },
        child: FocusScope(
          node: _scope,
          child: Container(
            width: _width,
            padding: const EdgeInsets.all(12),
            decoration: RichTextTheme.of(context).floatingSurface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Title(
                  leading: preview?.leading,
                  // The label the document carries, which is what the card
                  // falls back to when the record turns out to be gone. It is
                  // not shown while the record is on its way: a name at full
                  // size beside a skeleton reads as a card half-arrived, and
                  // then jumps when the real one lands under it.
                  title: preview?.title ?? widget.mention.label,
                  subtitle: preview?.subtitle,
                  shape: _shape,
                  loading: _loading,
                ),
                if (_loading && _shape.facts > 0) ...[
                  const SizedBox(height: 10),
                  for (var row = 0; row < _shape.facts; row++)
                    const _FactSkeleton(),
                ] else if (preview != null && preview.facts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final (label, value) in preview.facts)
                    _Fact(label: label, value: value),
                ],
                if ((widget.source?.openable ?? false) &&
                    recordOpener != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: RichTextControls.of(context).button(
                      context,
                      RichTextButtonSpec(
                        label: t('Open'),
                        onTap: () => unawaited(_open()),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final MentionPreviewShape shape;
  final bool loading;

  const _Title({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.shape,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading && shape.leading != MentionLeading.none) ...[
          _LeadingSkeleton(leading: shape.leading),
          const SizedBox(width: 10),
        ] else if (leading case final leading?) ...[
          leading,
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: _bone(context, 140, 11),
                )
              else
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: theme.fieldText.copyWith(fontWeight: FontWeight.w600),
                ),
              if (loading && shape.subtitle)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: _bone(context, 120, 9),
                )
              else if (subtitle case final subtitle? when subtitle.isNotEmpty)
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: theme.fieldText.copyWith(
                    fontSize: (theme.fieldText.fontSize ?? 14) - 2,
                    color: theme.mutedText,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A face is round and twice the size of a glyph, and standing in with the
/// wrong one is what makes a card jump when it arrives.
class _LeadingSkeleton extends StatelessWidget {
  final MentionLeading leading;

  const _LeadingSkeleton({required this.leading});

  @override
  Widget build(BuildContext context) {
    return leading == MentionLeading.avatar
        ? _bone(context, 32, 32, radius: 16)
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _bone(context, 16, 16, radius: 4),
          );
  }
}

/// A row of fact, laid out exactly as [_Fact] lays one out.
class _FactSkeleton extends StatelessWidget {
  const _FactSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _bone(context, 52, 9),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _bone(context, 88, 9),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;

  const _Fact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);
    final small = theme.fieldText.copyWith(
      fontSize: (theme.fieldText.fontSize ?? 14) - 2,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: small.copyWith(color: theme.mutedText)),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: small.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the application draws for something still loading.
Widget _bone(
  BuildContext context,
  double width,
  double height, {
  double? radius,
}) {
  return RichTextControls.of(context).placeholder(
    context,
    RichTextPlaceholderSpec(
      width: width,
      height: height,
      radius: radius == null ? null : BorderRadius.circular(radius),
    ),
  );
}
