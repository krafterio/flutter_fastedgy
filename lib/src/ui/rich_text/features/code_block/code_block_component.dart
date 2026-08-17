/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_fastedgy/flutter_fastedgy.dart' show t;
import 'package:provider/provider.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/vue.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../rich_text_controls.dart';
import '../../../icons.dart';
import '../../rich_text_theme.dart';
import 'code_block_theme.dart';

class CodeBlockKeys {
  const CodeBlockKeys._();

  static const String type = 'code';
  static const String delta = blockComponentDelta;

  /// Language id from [codeBlockLanguages]; absent means auto-detection.
  static const String language = 'language';
}

Node codeBlockNode({Delta? delta, String? language}) {
  return Node(
    type: CodeBlockKeys.type,
    attributes: {
      CodeBlockKeys.delta: (delta ?? Delta()).toJson(),
      CodeBlockKeys.language: ?language,
    },
  );
}

/// Manually selectable languages, id → display name. Auto-detection picks
/// among these same ids.
const codeBlockLanguages = {
  'python': 'Python',
  'javascript': 'JavaScript',
  'dart': 'Dart',
  'vue': 'Vue',
};

/// The extra grammars are registered because vue/xml embed them as
/// sub-languages (a script tag highlights its JS…); they are not offered in
/// the selector nor considered by auto-detection.
final _highlighter = Highlight()
  ..registerLanguages({
    'python': langPython,
    'javascript': langJavascript,
    'dart': langDart,
    'vue': langVue,
    'typescript': langTypescript,
    'xml': langXml,
    'css': langCss,
  });

class CodeBlockComponentBuilder extends BlockComponentBuilder {
  CodeBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CodeBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.delta != null;
}

/// Code block: grey card, language selector (auto-detected by
/// default) and copy button in the header, syntax-highlighted mono text.
class CodeBlockComponentWidget extends BlockComponentStatefulWidget {
  const CodeBlockComponentWidget({
    required super.node,
    super.key,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<CodeBlockComponentWidget> createState() =>
      _CodeBlockComponentWidgetState();
}

class _CodeBlockComponentWidgetState extends State<CodeBlockComponentWidget>
    with SelectableMixin, DefaultSelectableMixin, BlockComponentConfigurable {
  @override
  final forwardKey = GlobalKey(debugLabel: 'code_block_rich_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: CodeBlockKeys.type,
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late final editorState = Provider.of<EditorState>(context, listen: false);

  bool _copied = false;

  String? get _language => node.attributes[CodeBlockKeys.language] as String?;

  HighlightResult? _highlightCode(String code) {
    if (code.isEmpty) return null;
    final language = _language;
    if (language != null && codeBlockLanguages.containsKey(language)) {
      return _highlighter.highlight(code: code, language: language);
    }
    return _highlighter.highlightAuto(code, codeBlockLanguages.keys.toList());
  }

  void _setLanguage(String? language) {
    final transaction = editorState.transaction
      ..updateNode(node, {CodeBlockKeys.language: language});
    editorState.apply(transaction);
  }

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(text: node.delta?.toPlainText() ?? ''),
    );
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _highlightCode(node.delta?.toPlainText() ?? '');
    final theme = RichTextTheme.of(context);
    final code = CodeBlockTheme.of(context);
    final controls = RichTextControls.of(context);
    final icons = FastEdgyIcons.of(context);

    Widget child = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.subtleSurface,
        borderRadius: theme.blockRadius,
        border: Border.all(color: theme.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Row(
              children: [
                _LanguageSelector(
                  language: _language,
                  detected: result?.language,
                  onSelect: _setLanguage,
                ),
                const Spacer(),
                controls.tappable(
                  context,
                  RichTextTapSpec(
                    onTap: _copy,
                    radius: theme.chipRadius,
                    tooltip: t('Copy'),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _copied
                            ? icons[FastEdgyGlyph.copied]
                            : icons[FastEdgyGlyph.copy],
                        size: 13,
                        color: _copied ? theme.ink : theme.mutedText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: AppFlowyRichText(
              key: forwardKey,
              delegate: this,
              node: widget.node,
              editorState: editorState,
              placeholderText: t('Code'),
              textSpanDecorator: (textSpan) {
                if (result == null) return textSpan.updateTextStyle(code.text);
                final renderer = TextSpanRenderer(code.text, code.syntax);
                result.render(renderer);
                return renderer.span ?? textSpan.updateTextStyle(code.text);
              },
              placeholderTextSpanDecorator: (textSpan) => textSpan
                  .updateTextStyle(code.text.copyWith(color: theme.mutedText)),
              textDirection: TextDirection.ltr,
              cursorColor: editorState.editorStyle.cursorColor,
              // Not the editor's own: that tint is a hair off this card, and
              // selected code read as unselected code.
              selectionColor: theme.selectionOnSurface,
              cursorWidth: editorState.editorStyle.cursorWidth,
            ),
          ),
        ],
      ),
    );

    child = Container(key: blockComponentKey, padding: padding, child: child);

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }
}

class _LanguageSelector extends StatelessWidget {
  final String? language;
  final String? detected;
  final ValueChanged<String?> onSelect;

  const _LanguageSelector({
    required this.language,
    required this.detected,
    required this.onSelect,
  });

  /// The chosen language, or what auto-detection made of the code. Both read as
  /// one label so the header never grows a second control.
  String get _label {
    final language = this.language;

    if (language != null) {
      return codeBlockLanguages[language] ?? language;
    }

    final detectedName = codeBlockLanguages[detected];

    return detectedName == null ? t('Auto') : '${t('Auto')} · $detectedName';
  }

  @override
  Widget build(BuildContext context) {
    return RichTextControls.of(context).picker(
      context,
      RichTextPickerSpec(
        label: _label,
        selected: language,
        onSelect: onSelect,
        options: [
          RichTextPickerOption(value: null, label: t('Auto')),
          for (final entry in codeBlockLanguages.entries)
            RichTextPickerOption(value: entry.key, label: entry.value),
        ],
      ),
    );
  }
}
