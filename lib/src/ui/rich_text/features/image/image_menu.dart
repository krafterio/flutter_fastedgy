/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:convert';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show getLogger, t;

import '../../rich_text_controls.dart';
import '../../../icons.dart';
import '../../rich_text_popover.dart';
import '../../rich_text_theme.dart';
import 'image_source.dart';

final _log = getLogger('rich_text_image_menu');

/// Stores a picked image and answers with the attachment it became.
///
/// Null when there is nowhere to put it — no record yet, or the upload failed
/// with the device offline. The picture then travels in the document as a data
/// URI, and a save turns it into an attachment.
typedef ImageStore = Future<int?> Function(File file);

/// Where a picture comes from on this device.
///
/// A port rather than a dependency: picking a file is a native plugin and a set
/// of permissions an application already owns. Null simply drops the "from this
/// device" half of the card — an address still inserts a picture.
typedef ImageFilePicker = Future<File?> Function();

/// Puts an image at [selection].
///
/// Replaces the block the cursor sits in when it holds nothing: choosing Image
/// from the "/" menu leaves that paragraph empty behind it, and a picture under
/// a stray blank line is not what was asked for.
Future<void> insertImage(
  EditorState editorState,
  Selection selection,
  String url,
) async {
  final at = selection.end.path;
  final node = editorState.getNodeAtPath(at);
  final replaceable =
      node != null &&
      node.type == ParagraphBlockKeys.type &&
      (node.delta?.isEmpty ?? true);
  final transaction = editorState.transaction;

  if (replaceable) {
    transaction.insertNode(at, imageNode(url: url));
    transaction.deleteNode(node);
  } else {
    transaction.insertNode(at.next, imageNode(url: url));
  }

  await editorState.apply(transaction);
}

/// Opens the card that puts an image into the document, at [selection].
void showImageEditor(
  BuildContext context,
  EditorState editorState,
  Selection selection, {
  ImageStore? store,
  ImageFilePicker? pickFile,
}) {
  Future<void> insert(String url) => insertImage(editorState, selection, url);

  showRichTextPopover(
    context,
    editorState,
    selection,
    builder: (context, dismiss) => _ImageMenu(
      store: store,
      pickFile: pickFile,
      onInsert: (url) async {
        await insert(url);
        dismiss();
      },
      onDismiss: dismiss,
    ),
  );
}

/// Reads [file] back as the data URI that carries it until it is stored.
Future<String?> inlineImageOf(File file) async {
  try {
    final bytes = await file.readAsBytes();
    final extension = file.path.split('.').last.toLowerCase();
    final mime = extension == 'jpg' ? 'jpeg' : extension;

    return 'data:image/$mime;base64,${base64Encode(bytes)}';
  } catch (error, stackTrace) {
    _log.warning('Failed to read the picked image', error, stackTrace);

    return null;
  }
}

enum _Tab { file, url }

class _ImageMenu extends StatefulWidget {
  final ImageStore? store;
  final ImageFilePicker? pickFile;
  final Future<void> Function(String url) onInsert;
  final VoidCallback onDismiss;

  const _ImageMenu({
    required this.store,
    required this.pickFile,
    required this.onInsert,
    required this.onDismiss,
  });

  @override
  State<_ImageMenu> createState() => _ImageMenuState();
}

class _ImageMenuState extends State<_ImageMenu> {
  final _url = TextEditingController();

  _Tab _tab = _Tab.file;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await widget.pickFile?.call();

    if (file == null) {
      return;
    }

    if (mounted) {
      setState(() => _busy = true);
    }

    final id = await widget.store?.call(file);

    // No attachment: the picture rides along in the document until a save
    // stores it, which is also what an insert made offline does.
    final url = id != null ? attachmentImageUrl(id) : await inlineImageOf(file);

    if (url == null) {
      if (mounted) {
        setState(() => _busy = false);
      }

      return;
    }

    // Never guarded on `mounted`: the native file dialog takes the focus away,
    // and the card is often gone by the time it comes back. The picture still
    // has to land — the insert needs the document, not this widget.
    await widget.onInsert(url);
  }

  bool get _urlReady => Uri.tryParse(_url.text.trim())?.hasScheme ?? false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.pickFile != null) ...[
          _Tabs(current: _tab, onChanged: (tab) => setState(() => _tab = tab)),
          const SizedBox(height: 12),
        ],
        if (widget.pickFile != null && _tab == _Tab.file)
          _picker()
        else
          _address(),
      ],
    );
  }

  Widget _picker() {
    final theme = RichTextTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _busy ? null : _pick,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 104,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.strongBorder),
            ),
            child: Center(
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          FastEdgyIcons.of(context)[FastEdgyGlyph.image],
                          size: 22,
                          color: theme.mutedText,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('Choose an image'),
                          style: theme.fieldText.copyWith(
                            color: theme.mutedText,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: RichTextControls.of(context).button(
            context,
            RichTextButtonSpec(
              label: t('Cancel'),
              kind: RichTextButtonKind.quiet,
              onTap: widget.onDismiss,
            ),
          ),
        ),
      ],
    );
  }

  Widget _address() {
    final controls = RichTextControls.of(context);
    final theme = RichTextTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        controls.field(
          context,
          RichTextFieldSpec(
            label: t('Address'),
            placeholder: t('Paste an image address'),
            controller: _url,
            autofocus: true,
            leading: Icon(
              FastEdgyIcons.of(context)[FastEdgyGlyph.link],
              size: 14,
              color: theme.mutedText,
            ),
            onChanged: (_) => setState(() {}),
            onSubmit: () =>
                _urlReady ? widget.onInsert(_url.text.trim()) : null,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            controls.button(
              context,
              RichTextButtonSpec(
                label: t('Cancel'),
                kind: RichTextButtonKind.quiet,
                onTap: widget.onDismiss,
              ),
            ),
            const SizedBox(width: 8),
            controls.button(
              context,
              RichTextButtonSpec(
                label: t('Insert'),
                kind: RichTextButtonKind.primary,
                onTap: _urlReady
                    ? () => widget.onInsert(_url.text.trim())
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  final _Tab current;
  final ValueChanged<_Tab> onChanged;

  const _Tabs({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TabLabel(
          label: t('File'),
          selected: current == _Tab.file,
          onTap: () => onChanged(_Tab.file),
        ),
        const SizedBox(width: 16),
        _TabLabel(
          label: t('Address'),
          selected: current == _Tab.url,
          onTap: () => onChanged(_Tab.url),
        ),
      ],
    );
  }
}

class _TabLabel extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? theme.ink : const Color(0x00000000),
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: theme.fieldText.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? theme.ink : theme.mutedText,
          ),
        ),
      ),
    );
  }
}
