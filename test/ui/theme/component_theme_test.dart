/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_fastedgy/ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two unrelated packages declaring their own theme, as they would in the wild.
class _EditorTheme extends ComponentThemeData {
  final double gutter;

  const _EditorTheme(this.gutter);

  /// The resolution order every package follows.
  static _EditorTheme of(BuildContext context) =>
      ComponentTheme.maybeOf<_EditorTheme>(context) ??
      _EditorTheme.from(FastEdgyTheme.of(context));

  factory _EditorTheme.from(FastEdgyThemeData theme) =>
      _EditorTheme(theme.spacing * 4);

  @override
  bool operator ==(Object other) =>
      other is _EditorTheme && other.gutter == gutter;

  @override
  int get hashCode => gutter.hashCode;
}

class _ThreadTheme extends ComponentThemeData {
  final double gap;

  const _ThreadTheme(this.gap);

  @override
  bool operator ==(Object other) => other is _ThreadTheme && other.gap == gap;

  @override
  int get hashCode => gap.hashCode;
}

void main() {
  group('ComponentTheme', () {
    testWidgets('resolves by type, so two packages never collide', (
      tester,
    ) async {
      late _EditorTheme editor;
      late _ThreadTheme thread;

      await tester.pumpWidget(
        ComponentTheme<_EditorTheme>(
          data: const _EditorTheme(30),
          child: ComponentTheme<_ThreadTheme>(
            data: const _ThreadTheme(7),
            child: Builder(
              builder: (context) {
                editor = ComponentTheme.of<_EditorTheme>(context);
                thread = ComponentTheme.of<_ThreadTheme>(context);

                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(editor.gutter, 30);
      expect(thread.gap, 7);
    });

    testWidgets('is null where the application said nothing about it', (
      tester,
    ) async {
      late _ThreadTheme? thread;

      await tester.pumpWidget(
        ComponentTheme<_EditorTheme>(
          data: const _EditorTheme(30),
          child: Builder(
            builder: (context) {
              thread = ComponentTheme.maybeOf<_ThreadTheme>(context);

              return const SizedBox();
            },
          ),
        ),
      );

      expect(thread, isNull);
    });

    testWidgets('a subtree overrides for itself', (tester) async {
      late _EditorTheme outer;
      late _EditorTheme inner;

      await tester.pumpWidget(
        ComponentTheme<_EditorTheme>(
          data: const _EditorTheme(30),
          child: Column(
            children: [
              Builder(
                builder: (context) {
                  outer = _EditorTheme.of(context);

                  return const SizedBox();
                },
              ),
              ComponentTheme<_EditorTheme>(
                data: const _EditorTheme(8),
                child: Builder(
                  builder: (context) {
                    inner = _EditorTheme.of(context);

                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      );

      expect(outer.gutter, 30);
      expect(inner.gutter, 8, reason: 'a denser editor inside a panel');
    });

    testWidgets('derives from the tokens when nothing was overridden', (
      tester,
    ) async {
      late _EditorTheme derived;

      await tester.pumpWidget(
        FastEdgyTheme(
          data: FastEdgyThemeData.fallback.copyWith(spacing: 10.0),
          child: Builder(
            builder: (context) {
              derived = _EditorTheme.of(context);

              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        derived.gutter,
        40.0,
        reason: 'overriding one token makes every derived theme follow',
      );
    });

    testWidgets('travels into an overlay with everything else', (tester) async {
      late BuildContext anchor;
      late OverlayState overlay;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) {
                  overlay = Overlay.of(context);

                  return ComponentTheme<_EditorTheme>(
                    data: const _EditorTheme(30),
                    child: Builder(
                      builder: (context) {
                        anchor = context;

                        return const SizedBox();
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );

      final captured = InheritedTheme.capture(
        from: anchor,
        to: overlay.context,
      );

      _EditorTheme? floating;

      overlay.insert(
        OverlayEntry(
          builder: (context) => captured.wrap(
            Builder(
              builder: (context) {
                floating = ComponentTheme.maybeOf<_EditorTheme>(context);

                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(floating?.gutter, 30);
    });
  });
}
