import 'package:flutter_fastedgy/src/app_info/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a debug build marks its version as a dev pre-release', () {
    expect(devVersion('4.0.0'), '4.0.0-dev');
  });

  test('a version already marked dev is not marked twice', () {
    expect(devVersion('4.0.0-dev'), '4.0.0-dev');
  });
}
