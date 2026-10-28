import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_fastedgy/flutter_fastedgy.dart';
import 'package:flutter_test/flutter_test.dart';

class _Recorder extends BinaryMessenger {
  final sent = <String, ByteData?>{};

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    sent[channel] = message;
    return null;
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {}

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {}
}

void main() {
  const codec = JSONMethodCodec();

  String sentText(_Recorder recorder, MethodChannel channel) {
    final call = codec.decodeMethodCall(recorder.sent[channel.name]);

    return (call.arguments as Map)['text'] as String;
  }

  test('the keyboard gets half an emoji as a replacement character', () {
    final recorder = _Recorder();

    TextInputMessenger(recorder).send(
      SystemChannels.textInput.name,
      codec.encodeMethodCall(
        const MethodCall('TextInput.setEditingState', {
          'text': 'Salut \uD83D et \uDE00 😀',
          'selectionBase': 6,
        }),
      ),
    );

    expect(
      sentText(recorder, SystemChannels.textInput),
      'Salut \uFFFD et \uFFFD 😀',
    );
  });

  test('the clipboard gets half an emoji as a replacement character', () {
    final recorder = _Recorder();

    TextInputMessenger(recorder).send(
      SystemChannels.platform.name,
      codec.encodeMethodCall(
        const MethodCall('Clipboard.setData', {'text': 'Bravo \uD83D'}),
      ),
    );

    expect(sentText(recorder, SystemChannels.platform), 'Bravo \uFFFD');
  });

  test('the other channels get their message as it is', () {
    final recorder = _Recorder();
    final message = ByteData(4);

    TextInputMessenger(recorder).send('flutter/navigation', message);

    expect(recorder.sent['flutter/navigation'], same(message));
  });

  testWidgets('a pointer finds nothing to hit in a view not laid out yet', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final viewId = tester.view.viewId;
    final waiting = RenderView(
      view: tester.view,
      child: RenderConstrainedBox(
        additionalConstraints: const BoxConstraints(),
      ),
    );

    expect(FastEdgyBinding.awaitsLayout([waiting], viewId), isTrue);
    expect(
      FastEdgyBinding.awaitsLayout(tester.binding.renderViews, viewId),
      isFalse,
    );
  });
}
