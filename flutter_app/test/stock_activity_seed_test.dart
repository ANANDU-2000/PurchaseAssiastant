import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/stock_list_providers.dart';

void main() {
  test('auditRowsFromShellBundle reads audit_recent maps', () {
    final rows = auditRowsFromShellBundle({
      'audit_recent': [
        {'id': '1', 'item_name': 'Rice', 'updated_at': '2026-08-08T10:00:00Z'},
        'skip-me',
        {'id': '2', 'item_name': 'Oil'},
      ],
    });
    expect(rows.length, 2);
    expect(rows.first['id'], '1');
  });

  test('auditRowsFromShellBundle empty / missing', () {
    expect(auditRowsFromShellBundle(null), isEmpty);
    expect(auditRowsFromShellBundle(const {}), isEmpty);
    expect(auditRowsFromShellBundle(const {'audit_recent': <dynamic>[]}), isEmpty);
  });
}
