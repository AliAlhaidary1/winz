import 'package:flutter_test/flutter_test.dart';
import 'package:winz/src/config/api_config.dart';

void main() {
  group('Winz API client', () {
    test('base URL is configured in one place', () {
      expect(ApiConfig.baseUrl, isNotEmpty);
      expect(ApiConfig.baseUrl, endsWith('/api'));
    });

    test('business-logic regression suite', () {
      // The previous local-SQLite regression suite was removed: all betting,
      // prize, payout and reporting rules now live in the Laravel backend
      // (winz-api/app/Services/StateService.php). Run those tests against a
      // running API instance before deploying.
    }, skip: 'Requires a running Laravel API; see winz-api/README.md');
  });
}
