/// Anti-double-scan state machine for real-time barcode scanning.
///
/// Guarantees:
/// - Holding a single barcode continuously in front of the camera only emits ONCE.
/// - Brief detection frame drops (< [rearmAbsenceDuration]) do NOT trigger re-scan.
/// - Pulling the barcode out of the detection zone for >= [rearmAbsenceDuration]
///   plus >= [minCooldownDuration] cleanly re-arms that barcode so scanning it
///   again adds +1 quantity.
/// - Scanning a different barcode while another barcode is active/locked succeeds
///   immediately without waiting.
class BarcodeScanGuard {
  final Duration rearmAbsenceDuration;
  final Duration minCooldownDuration;

  final Set<String> _activeLocks = {};
  final Map<String, DateTime> _lastSeenAt = {};
  final Map<String, DateTime> _lastTriggeredAt = {};

  BarcodeScanGuard({
    this.rearmAbsenceDuration = const Duration(milliseconds: 900),
    this.minCooldownDuration = const Duration(milliseconds: 1000),
  });

  Set<String> get lockedCodes => Set.unmodifiable(_activeLocks);

  /// Evaluates barcodes present in the current camera frame and returns only
  /// newly accepted barcodes that passed anti-double-scan checks.
  List<String> evaluateFrame(List<String> barcodesInFrame, {DateTime? now}) {
    final ts = now ?? DateTime.now();
    tickRearm(now: ts);

    final accepted = <String>[];
    final uniqueInFrame = <String>{};

    for (final raw in barcodesInFrame) {
      final code = raw.trim();
      if (code.isEmpty || !uniqueInFrame.add(code)) continue;

      // Refresh presence heartbeat while barcode stays visible in frame
      _lastSeenAt[code] = ts;

      if (_activeLocks.contains(code)) {
        // Still locked while held in front of camera
        continue;
      }

      // Check per-code minimum cooldown just in case of instantaneous flicker
      final lastTrig = _lastTriggeredAt[code];
      if (lastTrig != null && ts.difference(lastTrig) < minCooldownDuration) {
        _activeLocks.add(code);
        continue;
      }

      _activeLocks.add(code);
      _lastTriggeredAt[code] = ts;
      accepted.add(code);
    }

    return accepted;
  }

  /// Releases any locked barcode that has left the detection zone for longer than
  /// [rearmAbsenceDuration] and past [minCooldownDuration].
  void tickRearm({DateTime? now}) {
    final ts = now ?? DateTime.now();
    final toRelease = <String>[];

    for (final code in _activeLocks) {
      final lastSeen = _lastSeenAt[code];
      final lastTrig = _lastTriggeredAt[code];
      final absentLongEnough =
          lastSeen == null || ts.difference(lastSeen) >= rearmAbsenceDuration;
      final cooledDown =
          lastTrig == null || ts.difference(lastTrig) >= minCooldownDuration;
      if (absentLongEnough && cooledDown) {
        toRelease.add(code);
      }
    }

    for (final code in toRelease) {
      _activeLocks.remove(code);
    }
  }

  void reset() {
    _activeLocks.clear();
    _lastSeenAt.clear();
    _lastTriggeredAt.clear();
  }
}
