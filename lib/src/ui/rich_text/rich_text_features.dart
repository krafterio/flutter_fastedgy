/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'features/code_block/code_block_feature.dart';
import 'features/image/image_feature.dart';
import 'features/link/link_feature.dart';
import 'features/mention/mention_feature.dart';
import 'features/paragraph_feature.dart';
import 'features/table/table_feature.dart';
import 'features/todo_list_feature.dart';
import 'rich_text_feature.dart';

/// What a document page offers unless its caller says otherwise. Add a content
/// feature here and it reaches the editor, the "/" menu and the markdown round
/// trip at once.
///
/// [MentionFeature] comes after [LinkFeature]: both ride on the `href`
/// attribute, and the last feature to dress a run is the one that owns it. What
/// there is to mention is the application's to register at boot — an editor
/// mounted with none simply arms no trigger.
///
/// Every glyph here is Material's and the table wears the fallback theme: what
/// a feature carries is fixed when it is declared, so an application with an
/// icon set of its own lists its own features rather than overriding these.
const RichTextFeatures defaultRichTextFeatures = RichTextFeatures([
  ParagraphFeature(),
  TodoListFeature(),
  CodeBlockFeature(),
  TableFeature(),
  ImageFeature(),
  LinkFeature(),
  MentionFeature(),
]);
