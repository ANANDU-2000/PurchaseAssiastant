import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/auth/jwt_access_token.dart';

void main() {
  test('expired JWT is detected', () {
    // exp = 1 (1970) — always expired
    const token =
        'eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjF9.signature';
    expect(isAccessTokenExpiredOrNearExpiry(token), isTrue);
  });

  test('malformed JWT does not force refresh', () {
    expect(isAccessTokenExpiredOrNearExpiry('not-a-jwt'), isFalse);
  });
}
