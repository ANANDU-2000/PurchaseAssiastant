import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/auth/session_permissions.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/errors/barcode_operation_errors.dart';
import '../barcode_scan_controller.dart';
import '../barcode_scan_session.dart';
import '../services/assign_barcode_helper.dart';
import '../services/barcode_camera_controller.dart';
import 'barcode_mobile_result_sheet.dart';
import 'barcode_scan_page_actions.dart';
import 'barcode_scan_result_panel.dart';
import 'barcode_scan_web_stub.dart'
    if (dart.library.html) 'barcode_scan_web.dart';
import 'barcode_scan_workspace.dart';

/// Warehouse barcode scan — thin scaffold wiring camera + scan controllers.
class BarcodeScanPage extends ConsumerStatefulWidget {
  const BarcodeScanPage({super.key});

  @override
  ConsumerState<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends ConsumerState<BarcodeScanPage>
    with WidgetsBindingObserver {
  late final BarcodeScanController _scan;
  late final BarcodeCameraController _camera;
  final _resultActionFocus = FocusNode(debugLabel: 'barcodeResultActions');
  bool _boundBiz = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scan = BarcodeScanController(
      lookupFn: ({required String businessId, required String code}) =>
          ref.read(hexaApiProvider).barcodeStockLookup(
                businessId: businessId,
                code: code,
              ),
      stockSearchFn: ({required String businessId, required String q}) =>
          ref.read(hexaApiProvider).listStock(
                businessId: businessId,
                q: q,
                perPage: 8,
                page: 1,
              ),
      assignFn: ({
        required String businessId,
        required String itemId,
        required String barcode,
      }) =>
          assignBarcodeToItem(
            api: ref.read(hexaApiProvider),
            businessId: businessId,
            itemId: itemId,
            barcode: barcode,
          ),
    );
    _camera = BarcodeCameraController(onCodeDetected: _onCode);
    _scan.manualCtrl.addListener(_scan.onManualChanged);
    unawaited(_scan.loadPrefs());
    unawaited(_scan.loadRecent());
    unawaited(_camera.bootstrap());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_boundBiz) return;
    final bid = ref.read(sessionProvider)?.primaryBusiness.id;
    if (bid == null) return;
    _boundBiz = true;
    _scan.bindBusinessId(bid);
  }

  BarcodeScanPageActions get _actions => BarcodeScanPageActions(
        context: context,
        ref: ref,
        scan: _scan,
        camera: _camera,
        onReadyForNext: _dismissResult,
        onRetryLookup: _runLookup,
      );

  void _onCode(String code) {
    if (!_scan.acceptsCameraDetect) return;
    if (!_scan.acceptDecode(code)) {
      _showRejectIfAny();
      return;
    }
    if (!_scan.debouncePass(code)) return;
    _scan.onDecoded(code);
    unawaited(_runLookup(code));
  }

  void _showRejectIfAny() {
    final msg = _scan.lastRejectMessage;
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(
          label: 'Manual',
          onPressed: () => _scan.manualFocus.requestFocus(),
        ),
      ),
    );
    _scan.clearRejectMessage();
  }

  Future<void> _runLookup(String raw) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    _scan.bindBusinessId(bid);
    await _scan.lookup(raw, businessId: bid);
    if (!mounted) return;
    final snap = _scan.session.current;
    if (snap == null) return;

    final item = snap.item;
    final id = item?['id']?.toString();
    final name = item?['name']?.toString() ?? snap.code;
    if (snap.outcome == BarcodeScanOutcome.found &&
        item != null &&
        id != null &&
        id.isNotEmpty) {
      if (await _actions.handleReturnQuery(item: item, id: id, name: name)) {
        return;
      }
    }

    if (MediaQuery.sizeOf(context).width >= kDesktopMin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resultActionFocus.requestFocus();
      });
      return;
    }

    if (snap.phase == BarcodeScanPhase.result ||
        snap.phase == BarcodeScanPhase.error) {
      await showBarcodeMobileResultSheet(
        context: context,
        scan: _scan,
        panel: _buildPanel(dense: true),
      );
      await _camera.ensureRunning();
    }
  }

  BarcodeScanResultPanel _buildPanel({required bool dense}) {
    final session = ref.read(sessionProvider);
    final canEdit = session != null && !sessionIsStockReadOnly(session);
    final canPurchase = session != null &&
        (sessionCanPurchaseCreate(session) || sessionCanPurchaseEdit(session));
    final canPrint = session != null && sessionCanBarcodePrint(session);
    final a = _actions;
    return barcodeResultPanelFromScan(
      scan: _scan,
      canStockEdit: canEdit,
      canAddToPurchase: canPurchase,
      canPrint: canPrint,
      dense: dense,
      onAddToPurchase: a.addPurchase,
      onEdit: a.edit,
      onStock: a.stock,
      onHistory: a.history,
      onPrint: a.printLabel,
      onCreateItem: canEdit ? a.createItem : null,
      onAssign: canEdit ? a.assign : null,
      onRetry: a.retry,
      onDismiss: () {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _camera.onAppResumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resultActionFocus.dispose();
    _scan.manualCtrl.removeListener(_scan.onManualChanged);
    _scan.abandonInFlight();
    _camera.dispose();
    _scan.dispose();
    super.dispose();
  }

  Future<void> _scanFromImage() async {
    if (_scan.lookingUp) return;
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      var code = await _camera.analyzeImagePath(file.path);
      if ((code == null || code.isEmpty) && kIsWeb) {
        code = await decodeBarcodeFromImageBytes(await file.readAsBytes());
      }
      if (code != null &&
          code.isNotEmpty &&
          _scan.acceptDecode(code)) {
        _scan.onDecoded(code);
        await _runLookup(code);
      } else if (mounted) {
        final msg = barcodeMessageForUser(
          barcodePhotoUnreadableError(),
          ctx: BarcodeOperationContext.scanner,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            action: SnackBarAction(
              label: 'Manual',
              onPressed: () => _scan.manualFocus.requestFocus(),
            ),
          ),
        );
      }
    } catch (e, st) {
      developer.log('Error in scanFromImage', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              barcodeMessageForUser(
                e,
                ctx: BarcodeOperationContext.scanner,
              ),
            ),
          ),
        );
      }
    }
  }

  void _dismissResult() {
    _scan.readyForNext();
    unawaited(_camera.ensureRunning());
  }

  @override
  Widget build(BuildContext context) {
    return BarcodeScanWorkspace(
      scan: _scan,
      camera: _camera,
      resultActionFocus: _resultActionFocus,
      actions: _actions,
      onLookup: _runLookup,
      onUploadPhoto: () => unawaited(_scanFromImage()),
      onDismissResult: _dismissResult,
    );
  }
}
