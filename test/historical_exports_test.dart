/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What each historical entry point exported before Material and Cupertino
/// went on demand (60c16d9): an application that changes nothing still gets
/// all of it, through the same entry point.
const _exported = {
  'flutter_fastedgy.dart': [
    'package:dio/dio.dart',
    'package:easy_localization/easy_localization.dart',
    'package:flutter/widgets.dart',
    'package:logging/logging.dart',
    'src/api/api.dart',
    'src/app_info/app_info.dart',
    'src/auth/auth.dart',
    'src/bus/bus.dart',
    'src/bus/events.dart',
    'src/container/container.dart',
    'src/fetcher/fetcher.dart',
    'src/i18n/i18n.dart',
    'src/image/image.dart',
    'src/initializer.dart',
    'src/logging/logging.dart',
    'src/metadata/metadata.dart',
    'src/offline/offline.dart',
    'src/realtime/origin.dart',
    'src/realtime/realtime_events.dart',
    'src/realtime/realtime_socket.dart',
    'src/realtime/resource_relay.dart',
    'src/realtime/resource_watch.dart',
    'src/storage/storage.dart',
    'src/sync/sync_status.dart',
  ],
  'ui.dart': [
    'src/ui/document/document_cover.dart',
    'src/ui/document/document_editor.dart',
    'src/ui/document/document_gutter.dart',
    'src/ui/document/document_layout.dart',
    'src/ui/document/document_viewer.dart',
    'src/ui/icons.dart',
    'src/ui/image/fullscreen_image_viewer.dart',
    'src/ui/interaction.dart',
    'src/ui/responsive.dart',
    'src/ui/rich_text/features/code_block/code_block_component.dart',
    'src/ui/rich_text/features/code_block/code_block_feature.dart',
    'src/ui/rich_text/features/code_block/code_block_shortcuts.dart',
    'src/ui/rich_text/features/code_block/code_block_theme.dart',
    'src/ui/rich_text/features/image/image_component.dart',
    'src/ui/rich_text/features/image/image_feature.dart',
    'src/ui/rich_text/features/image/image_markdown.dart',
    'src/ui/rich_text/features/image/image_menu.dart',
    'src/ui/rich_text/features/image/image_source.dart',
    'src/ui/rich_text/features/image/image_store.dart',
    'src/ui/rich_text/features/image/image_sync.dart',
    'src/ui/rich_text/features/link/link_feature.dart',
    'src/ui/rich_text/features/link/link_gestures.dart',
    'src/ui/rich_text/features/link/link_markdown.dart',
    'src/ui/rich_text/features/link/link_menu.dart',
    'src/ui/rich_text/features/mention/mention_address.dart',
    'src/ui/rich_text/features/mention/mention_controller.dart',
    'src/ui/rich_text/features/mention/mention_feature.dart',
    'src/ui/rich_text/features/mention/mention_markdown.dart',
    'src/ui/rich_text/features/mention/mention_menu.dart',
    'src/ui/rich_text/features/mention/mention_options.dart',
    'src/ui/rich_text/features/mention/mention_popover.dart',
    'src/ui/rich_text/features/mention/mention_preview.dart',
    'src/ui/rich_text/features/mention/mention_source.dart',
    'src/ui/rich_text/features/mention/mention_span.dart',
    'src/ui/rich_text/features/paragraph_feature.dart',
    'src/ui/rich_text/features/plus_underline_feature.dart',
    'src/ui/rich_text/features/table/table_component.dart',
    'src/ui/rich_text/features/table/table_feature.dart',
    'src/ui/rich_text/features/table/table_handle.dart',
    'src/ui/rich_text/features/table/table_markdown.dart',
    'src/ui/rich_text/features/todo_list_feature.dart',
    'src/ui/rich_text/rich_text_action.dart',
    'src/ui/rich_text/rich_text_action_bar.dart',
    'src/ui/rich_text/rich_text_blank.dart',
    'src/ui/rich_text/rich_text_blocks.dart',
    'src/ui/rich_text/rich_text_clipboard.dart',
    'src/ui/rich_text/rich_text_clipboard_menu.dart',
    'src/ui/rich_text/rich_text_codec.dart',
    'src/ui/rich_text/rich_text_controls.dart',
    'src/ui/rich_text/rich_text_diff.dart',
    'src/ui/rich_text/rich_text_editor.dart',
    'src/ui/rich_text/rich_text_feature.dart',
    'src/ui/rich_text/rich_text_features.dart',
    'src/ui/rich_text/rich_text_focus.dart',
    'src/ui/rich_text/rich_text_markdown.dart',
    'src/ui/rich_text/rich_text_menu.dart',
    'src/ui/rich_text/rich_text_nesting.dart',
    'src/ui/rich_text/rich_text_paste.dart',
    'src/ui/rich_text/rich_text_plain.dart',
    'src/ui/rich_text/rich_text_popover.dart',
    'src/ui/rich_text/rich_text_shortcuts.dart',
    'src/ui/rich_text/rich_text_style.dart',
    'src/ui/rich_text/rich_text_theme.dart',
    'src/ui/rich_text/rich_text_toolbar.dart',
    'src/ui/rich_text/rich_text_toolbar_theme.dart',
    'src/ui/rich_text/rich_text_touch_menu.dart',
    'src/ui/rich_text/rich_text_viewer.dart',
    'src/ui/theme/animated_theme.dart',
    'src/ui/theme/breakpoints.dart',
    'src/ui/theme/color_scheme.dart',
    'src/ui/theme/component_theme.dart',
    'src/ui/theme/scaling.dart',
    'src/ui/theme/theme.dart',
    'src/ui/theme/theme_data.dart',
    'src/ui/theme/typography.dart',
  ],
  'testing.dart': ['src/fetcher/mock_transport.dart'],
  'workspace.dart': [
    'src/workspace/workspace_prefix_interceptor.dart',
    'src/workspace/workspace_provider.dart',
  ],
};

final _export = RegExp(r"""^\s*export\s+['"]([^'"]+)['"]""", multiLine: true);

/// What [entryPoint] exports, through the libraries of the package it
/// exports in turn: their paths under `lib/`, and the URIs of other packages.
Set<String> _exportedBy(String entryPoint) {
  final seen = <String>{};
  final pending = [entryPoint];

  while (pending.isNotEmpty) {
    final path = pending.removeLast();

    if (!seen.add(path) || path.startsWith('package:')) {
      continue;
    }

    for (final match in _export.allMatches(
      File('lib/$path').readAsStringSync(),
    )) {
      final uri = match.group(1)!;

      pending.add(
        uri.startsWith('package:') ? uri : Uri.parse(path).resolve(uri).path,
      );
    }
  }

  return seen;
}

void main() {
  for (final MapEntry(key: entryPoint, value: exported) in _exported.entries) {
    test('$entryPoint exports what it exported', () {
      final now = _exportedBy(entryPoint);

      expect([
        for (final uri in exported)
          if (!now.contains(
            uri.startsWith('package:')
                ? uri
                : Uri.parse(entryPoint).resolve(uri).path,
          ))
            uri,
      ], isEmpty);
    });
  }
}
