/// Compile-time feature switches (`--dart-define=KEY=value`).
///
/// | Define | Default | Effect |
/// |--------|---------|--------|
/// | `USE_SERVER_PURCHASE_PREVIEW` | `true` | Wizard debounces `POST …/preview-lines` for line totals (SSOT). Set `false` to force local [lineMoney] only. |
/// | `USE_STRICT_SQL_REPORTS` | `false` | Reserved: when wired, prefer strict SQL paths / fail closed on ambiguous report aggregates. |
/// | `DEPRECATE_LEGACY_ENTRY_API` | `false` | Reserved: when wired, hide legacy entry endpoints in clients and log server-side deprecation. |
const bool kUseServerTradePurchasePreview = bool.fromEnvironment(
  'USE_SERVER_PURCHASE_PREVIEW',
  defaultValue: true,
);

/// Placeholder for future rollout (server + admin must agree before enforcing).
const bool kUseStrictSqlReports = bool.fromEnvironment(
  'USE_STRICT_SQL_REPORTS',
  defaultValue: false,
);

/// Placeholder for legacy `/entries` and related clients.
const bool kDeprecateLegacyEntryApi = bool.fromEnvironment(
  'DEPRECATE_LEGACY_ENTRY_API',
  defaultValue: false,
);

/// UI feature toggles for client-specific builds.
class FeatureFlags {
  static const bool showVoiceTab = false;
  static const bool showMaintenanceFeeCard = false;
  static const bool showAnalyticsTab = true;
}
