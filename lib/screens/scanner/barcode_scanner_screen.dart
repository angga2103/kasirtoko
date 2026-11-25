import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/barcode_scan_guard.dart';
import '../../services/hardware_bridge.dart';
import '../../utils/app_theme.dart';

class ContinuousScanEventResult {
  final bool found;
  final String title;
  final String subtitle;

  ContinuousScanEventResult({
    required this.found,
    required this.title,
    this.subtitle = '',
  });
}

class BarcodeScannerScreen extends StatefulWidget {
  final String title;
  final String helperText;
  final bool continuousMode;

  /// Required when [continuousMode] is true. Returns feedback to display on overlay.
  final Future<ContinuousScanEventResult> Function(String barcode)? onBarcodeScanned;

  const BarcodeScannerScreen({
    super.key,
    this.title = 'Scan Barcode',
    this.helperText = 'Arahkan kamera ke barcode atau QR Code',
    this.continuousMode = false,
    this.onBarcodeScanned,
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  late final MobileScannerController _controller;
  final BarcodeScanGuard _scanGuard = BarcodeScanGuard();
  final TextEditingController _manualCtrl = TextEditingController();

  Timer? _rearmTimer;
  bool _hasPoppedSingleShot = false;
  bool _torchOn = false;
  String _statusMessage = 'Siap memindai...';
  bool? _lastSuccess;
  final List<String> _recentLog = [];

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 150,
      facing: CameraFacing.back,
    );

    if (widget.continuousMode) {
      _rearmTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        final before = _scanGuard.lockedCodes.length;
        _scanGuard.tickRearm();
        final after = _scanGuard.lockedCodes.length;
        if (before > 0 && after == 0 && mounted) {
          setState(() {
            _statusMessage = 'Siap memindai barcode berikutnya...';
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _rearmTimer?.cancel();
    _controller.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    final codes = capture.barcodes
        .map((b) => b.rawValue ?? b.displayValue ?? '')
        .where((s) => s.trim().isNotEmpty)
        .toList();

    if (codes.isEmpty) return;

    if (!widget.continuousMode) {
      if (_hasPoppedSingleShot) return;
      _hasPoppedSingleShot = true;
      final code = codes.first.trim();
      await HardwareBridge.playBeep();
      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.pop(context, code);
      }
      return;
    }

    // Continuous POS Mode with Anti-Double-Scan (cooldown + re-arm)
    final accepted = _scanGuard.evaluateFrame(codes);
    if (accepted.isEmpty) return;

    for (final code in accepted) {
      await _processContinuousCode(code);
    }
  }

  Future<void> _processContinuousCode(String code) async {
    if (widget.onBarcodeScanned == null) return;
    final res = await widget.onBarcodeScanned!(code);
    await HardwareBridge.playBeep();
    HapticFeedback.mediumImpact();

    if (!mounted) return;
    setState(() {
      _lastSuccess = res.found;
      _statusMessage = res.found
          ? '✓ ${res.title} ${res.subtitle}'.trim()
          : '✗ Barcode $code tidak ditemukan';
      _recentLog.insert(0, '${res.found ? "+" : "!"} $code — ${res.title}');
      if (_recentLog.length > 5) _recentLog.removeLast();
    });
  }

  void _showManualEntry() {
    _manualCtrl.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Input Barcode Manual'),
        content: TextField(
          controller: _manualCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Kode Barcode / SKU',
            hintText: 'Contoh: 8992345001',
            prefixIcon: Icon(Icons.qr_code_rounded),
          ),
          onSubmitted: (val) => _submitManual(ctx, val),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => _submitManual(ctx, _manualCtrl.text),
            child: const Text('Proses'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitManual(BuildContext dialogCtx, String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    Navigator.pop(dialogCtx);

    if (!widget.continuousMode) {
      Navigator.pop(context, code);
    } else {
      await _processContinuousCode(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = widget.continuousMode && _scanGuard.lockedCodes.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded),
            tooltip: 'Lampu Flash',
            onPressed: () async {
              await _controller.toggleTorch();
              if (mounted) setState(() => _torchOn = !_torchOn);
            },
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded),
            tooltip: 'Ganti Kamera',
            onPressed: () => _controller.switchCamera(),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_rounded),
            tooltip: 'Input Manual',
            onPressed: _showManualEntry,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleCapture,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.no_photography_rounded, color: Colors.white54, size: 54),
                      const SizedBox(height: 12),
                      Text(
                        'Kamera tidak tersedia (${error.errorCode.name}).\nGunakan Input Manual di bawah.',
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _showManualEntry,
                        icon: const Icon(Icons.keyboard_rounded),
                        label: const Text('Ketik Barcode Manual'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Scan Reticle Overlay
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 260,
                  height: 170,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isLocked
                          ? AppTheme.accentOrange
                          : (_lastSuccess == true ? AppTheme.success : AppTheme.primaryGreenLight),
                      width: 3,
                    ),
                    color: Colors.transparent,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isLocked
                        ? 'Tahan sebentar • Jauhkan barcode agar bisa scan ulang'
                        : widget.helperText,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // Bottom Feedback Panel
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _lastSuccess == false
                        ? AppTheme.accentRed
                        : (_lastSuccess == true ? AppTheme.success : Colors.white24),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _lastSuccess == false
                              ? Icons.error_outline
                              : (_lastSuccess == true ? Icons.check_circle_rounded : Icons.qr_code_scanner_rounded),
                          color: _lastSuccess == false
                              ? AppTheme.accentRed
                              : (_lastSuccess == true ? AppTheme.success : Colors.white70),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        if (widget.continuousMode)
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Selesai', style: TextStyle(color: AppTheme.primaryGreenLight)),
                          ),
                      ],
                    ),
                    if (_recentLog.isNotEmpty) ...[
                      const Divider(color: Colors.white12, height: 14),
                      ..._recentLog.take(3).map(
                            (e) => Text(
                              e,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
