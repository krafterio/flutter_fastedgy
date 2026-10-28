/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The [WidgetsFlutterBinding] of a FastEdgy application, created in place of
/// it at the start of `main`.
///
/// What it adds:
/// - the text handed to the system keyboard and to the clipboard is always
///   valid UTF-16. iOS decodes it as JSON and stops the app on half a
///   surrogate pair (an emoji cut in two), a native crash no Dart code can
///   catch;
/// - a pointer that comes before its view was first laid out (the mouse over a
///   desktop window as the app starts) hits nothing, where the framework would
///   read the size the root does not have yet.
class FastEdgyBinding extends WidgetsFlutterBinding {
  static FastEdgyBinding? _instance;

  static WidgetsBinding ensureInitialized() => _instance ??= FastEdgyBinding();

  @override
  BinaryMessenger createBinaryMessenger() =>
      TextInputMessenger(super.createBinaryMessenger());

  @override
  void hitTestInView(HitTestResult result, Offset position, int viewId) {
    if (awaitsLayout(renderViews, viewId)) {
      return;
    }

    super.hitTestInView(result, position, viewId);
  }

  /// Whether the root of the view [viewId] among [views] was never laid out.
  @visibleForTesting
  static bool awaitsLayout(Iterable<RenderView> views, int viewId) => views.any(
    (view) => view.flutterView.viewId == viewId && view.child?.hasSize == false,
  );
}

/// Hands every message on to [messenger], those of the text input and of the
/// platform (the clipboard) with half a surrogate pair put as U+FFFD: one code
/// unit for one, the offsets the keyboard reports back stay right.
class TextInputMessenger extends BinaryMessenger {
  const TextInputMessenger(this.messenger);

  final BinaryMessenger messenger;

  static const _codec = JSONMethodCodec();
  static final _channels = {
    SystemChannels.textInput.name,
    SystemChannels.platform.name,
  };
  static final _halfPair = RegExp(
    r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]',
  );

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (message == null || !_channels.contains(channel)) {
      return messenger.send(channel, message);
    }

    final call = _codec.decodeMethodCall(message);

    return messenger.send(
      channel,
      _codec.encodeMethodCall(MethodCall(call.method, _whole(call.arguments))),
    );
  }

  static Object? _whole(Object? value) => switch (value) {
    String() => value.replaceAll(_halfPair, '\uFFFD'),
    List() => [for (final item in value) _whole(item)],
    Map() => {
      for (final entry in value.entries) entry.key: _whole(entry.value),
    },
    _ => value,
  };

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      messenger.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) =>
      // ignore: deprecated_member_use
      messenger.handlePlatformMessage(channel, data, callback);
}
