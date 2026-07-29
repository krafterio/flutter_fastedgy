/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t, getLogger;
import 'package:url_launcher/url_launcher.dart';

import '../../rich_text_controls.dart';
import '../../../icons.dart';
import '../../rich_text_popover.dart';
import '../../rich_text_theme.dart';

final _log = getLogger('link_menu');

/// Whether [text] is something we can turn into a link. Anything with a host
/// counts, scheme included or not — a pasted `kascade.io/x` is a link too.
bool isLinkable(String text) {
  final trimmed = text.trim();

  if (trimmed.isEmpty || trimmed.contains(' ')) {
    return false;
  }

  final uri = Uri.tryParse(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );

  return uri != null && uri.host.contains('.');
}

/// What a bare `kascade.io/x` is stored as.
String normalizeLink(String text) {
  final trimmed = text.trim();

  return trimmed.contains('://') ? trimmed : 'https://$trimmed';
}

/// Opens the link card under the selection, editing [selection]'s href.
///
/// The package ships one of these but keeps both the menu and its placement
/// under `src/`, out of reach — hence our own, on the app's design system.
void showLinkEditor(
  BuildContext context,
  EditorState editorState,
  Selection selection,
) {
  final link = editorState.getDeltaAttributeValueInSelection<String>(
    AppFlowyRichTextKeys.href,
    selection,
  );
  final node = editorState.getNodeAtPath(selection.end.path);

  if (node == null) {
    return;
  }

  final normalized = selection.normalized;
  final index = normalized.startIndex;
  final length = normalized.length;
  final text = editorState.getTextInSelection(normalized).join();

  Future<void> write(String? href, {String? label}) async {
    if (label != null && label != text) {
      // Carries the run's own formatting over: replaceText takes the attributes
      // it is given as the whole set, so linking bold text would unbolden it.
      final transaction = editorState.transaction
        ..replaceText(
          node,
          index,
          length,
          label,
          attributes: {
            ..._attributesAt(node, index, length),
            AppFlowyRichTextKeys.href: ?href,
          },
        );
      await editorState.apply(transaction);
    } else {
      await editorState.formatDelta(normalized, {
        AppFlowyRichTextKeys.href: href,
      });
    }
  }

  showRichTextPopover(
    context,
    editorState,
    selection,
    builder: (context, dismiss) {
      Future<void> apply(String? href, {String? label}) async {
        await write(href, label: label);
        dismiss();
      }

      return _LinkMenu(
        icons: FastEdgyIcons.of(context),
        text: text,
        link: link,
        onSubmit: (label, href) => apply(normalizeLink(href), label: label),
        onRemove: () => apply(null),
        onOpen: () => openLink(link),
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: link ?? ''));
          dismiss();
        },
        onDismiss: dismiss,
      );
    },
  );
}

/// The formatting already carried by the selected run.
Attributes _attributesAt(Node node, int index, int length) {
  final sliced = node.delta?.slice(index, index + length);

  return sliced == null || sliced.isEmpty
      ? const {}
      : (sliced.first.attributes ?? const {});
}

/// Opens [link] in the browser.
Future<void> openLink(String? link) async {
  final uri = Uri.tryParse(link ?? '');

  if (uri == null) {
    return;
  }

  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (error, stackTrace) {
    _log.warning('Failed to open the link', error, stackTrace);
  }
}

class _LinkMenu extends StatefulWidget {
  final FastEdgyIcons icons;

  /// The selected text, which the card lets you rewrite along with the link.
  final String text;
  final String? link;
  final void Function(String label, String link) onSubmit;
  final VoidCallback onRemove;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onDismiss;

  const _LinkMenu({
    required this.icons,
    required this.text,
    required this.link,
    required this.onSubmit,
    required this.onRemove,
    required this.onOpen,
    required this.onCopy,
    required this.onDismiss,
  });

  @override
  State<_LinkMenu> createState() => _LinkMenuState();
}

class _LinkMenuState extends State<_LinkMenu> {
  late final _label = TextEditingController(text: widget.text);

  /// Selecting a URL and pressing the link button means linking it to itself —
  /// far more common than wanting an empty field there.
  late final _link = TextEditingController(
    text: widget.link ?? (isLinkable(widget.text) ? widget.text : ''),
  );

  late bool _valid = _isValid;

  bool get _isValid => isLinkable(_link.text) && _label.text.trim().isNotEmpty;

  @override
  void dispose() {
    _label.dispose();
    _link.dispose();
    super.dispose();
  }

  void _submit() {
    if (_valid) {
      widget.onSubmit(_label.text, _link.text);
    }
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    bool autofocus = false,
  }) {
    final theme = RichTextTheme.of(context);

    return RichTextControls.of(context).field(
      context,
      RichTextFieldSpec(
        label: label,
        placeholder: hint,
        controller: controller,
        autofocus: autofocus,
        leading: icon == null
            ? null
            : Icon(icon, size: 14, color: theme.mutedText),
        onChanged: (_) => setState(() => _valid = _isValid),
        onSubmit: _submit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.link != null;

    // The chrome, the placement and Escape belong to the card that carries
    // this: only what a link needs is built here.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          editing ? t('Edit link') : t('Add a link'),
          style: RichTextTheme.of(
            context,
          ).fieldText.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.enter): _submit},
          child: Column(
            children: [
              _field(
                label: t('Title'),
                controller: _label,
                hint: t('The text to show'),
                icon: widget.icons[FastEdgyGlyph.title],
              ),
              const SizedBox(height: 10),
              _field(
                label: t('Link'),
                controller: _link,
                hint: t('Paste or type a link'),
                icon: widget.icons[FastEdgyGlyph.link],
                // The title comes from the selection: the link is what is
                // left to fill in.
                autofocus: true,
              ),
            ],
          ),
        ),
        if (editing) ...[
          const SizedBox(height: 10),
          // Wrapped rather than in a row: a card is as wide as every other
          // card, and what an application draws these with is its own —
          // three labels in its own font are not owed to fit on one line.
          Wrap(
            children: [
              _LinkAction(
                icon: widget.icons[FastEdgyGlyph.openExternal],
                label: t('Open'),
                onTap: widget.onOpen,
              ),
              _LinkAction(
                icon: widget.icons[FastEdgyGlyph.copy],
                label: t('Copy'),
                onTap: widget.onCopy,
              ),
              _LinkAction(
                icon: widget.icons[FastEdgyGlyph.unlink],
                label: t('Remove'),
                onTap: widget.onRemove,
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            RichTextControls.of(context).button(
              context,
              RichTextButtonSpec(
                label: t('Cancel'),
                kind: RichTextButtonKind.quiet,
                onTap: widget.onDismiss,
              ),
            ),
            RichTextControls.of(context).button(
              context,
              RichTextButtonSpec(
                label: editing ? t('Save') : t('Add'),
                kind: RichTextButtonKind.primary,
                onTap: _valid ? _submit : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LinkAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LinkAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichTextTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: RichTextControls.of(context).tappable(
        context,
        RichTextTapSpec(
          onTap: onTap,
          radius: theme.chipRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: theme.mutedText),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: theme.codeText.copyWith(
                    fontFamily: theme.fieldText.fontFamily,
                    color: theme.mutedText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
