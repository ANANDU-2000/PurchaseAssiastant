import '../calc_engine.dart' show lineMoney;
import '../catalog/item_trade_history.dart' show tradeLineToCalc;
import '../models/trade_purchase_models.dart';

/// Trade-only estimated gross margin for a line (selling - landed cost). Uses
/// the same [lineMoney] as dashboards when [sellingCost] is missing, profit is 0.
double estimatedTradeLineProfit(TradePurchaseLine ln) {
  final sell = ln.sellingCost;
  if (sell == null || sell <= 0) return 0.0;
  final cost = lineMoney(tradeLineToCalc(ln));
  final kpu = ln.kgPerUnit;
  final lcpk = ln.landingCostPerKg;
  if (kpu != null && lcpk != null && kpu > 0 && lcpk > 0) {
    // Selling stored as Rs/kg, qty in bags: revenue = sell * kg = sell * (qty * kpu).
    return (sell * ln.qty * kpu) - cost;
  }
  return (sell * ln.qty) - cost;
}
