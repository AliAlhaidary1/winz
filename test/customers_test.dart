import 'package:flutter_test/flutter_test.dart';
import 'package:winz/src/config/api_config.dart';

void main() {
  group('Customers via API', () {
    test(
      'API base URL is available to the HTTP-backed database',
      () => expect(ApiConfig.baseUrl, contains('://')),
    );

    test('customer save/replay/delete regression flow', () {
      // Covered by Laravel StateService integration tests against MySQL.
    }, skip: 'Requires a running Laravel API; see winz-api/README.md');
  });
}
