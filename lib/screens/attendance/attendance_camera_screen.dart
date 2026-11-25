import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import '../../models/attendance.dart';
import '../../providers/auth_provider.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/liveness_service.dart';
import '../../services/image_watermark_service.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/app_theme.dart';

class AttendanceCameraScreen extends StatefulWidget {
  const AttendanceCameraScreen({super.key});

  @override
  State<AttendanceCameraScreen> createState() => _AttendanceCameraScreenState();
}

class _AttendanceCameraScreenState extends State<AttendanceCameraScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;

  late final LivenessService _livenessService;
  late final LivenessChallenge _currentChallenge;
  late final String _challengeToken;

  String _attendanceType = 'masuk'; // 'masuk' or 'pulang'
  String _livenessFeedback = 'Posisikan wajah Anda tepat di lingkaran kamera';
  bool _isLivenessPassed = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _livenessService = LivenessService();
    _currentChallenge = LivenessService.generateRandomChallenge();
    _challengeToken = LivenessService.generateRandomToken();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      // Select front camera if available
      final frontCamera = _cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });

      // Start streaming frames for Google ML Kit face liveness detection
      _cameraController!.startImageStream((CameraImage image) {
        if (_isProcessingFrame || _isLivenessPassed || _isCapturing) return;
        _processCameraFrame(image);
      });
    } catch (_) {
      // Graceful fallback for emulators or machines without camera hardware
    }
  }

  Future<void> _processCameraFrame(CameraImage image) async {
    _isProcessingFrame = true;

    try {
      // Build ML Kit InputImage from CameraImage
      final camera = _cameraController!.description;
      final sensorOrientation = camera.sensorOrientation;

      final inputImage = InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(sensorOrientation) ??
              InputImageRotation.rotation0deg,
          format: InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _livenessService.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        final result = _livenessService.verifyFaceChallenge(face, _currentChallenge);

        if (mounted) {
          setState(() {
            _livenessFeedback = result.message;
            if (result.isSuccess) {
              _isLivenessPassed = true;
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _livenessFeedback = 'Wajah tidak terdeteksi, hadap ke kamera';
          });
        }
      }
    } catch (_) {
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _takeAttendancePicture() async {
    if (_isCapturing) return;
    if (_isCameraInitialized && !_isLivenessPassed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harap selesaikan verifikasi Liveness wajah terlebih dahulu.'),
          backgroundColor: AppTheme.accentOrange,
        ),
      );
      return;
    }
    setState(() => _isCapturing = true);

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final attProv = Provider.of<AttendanceProvider>(context, listen: false);
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final user = auth.currentUser;

      String rawPath = '';

      if (_cameraController != null && _cameraController!.value.isInitialized) {
        final xFile = await _cameraController!.takePicture();
        rawPath = xFile.path;
      } else {
        // Fallback for devices/emulators without camera hardware: generate a valid decodable JPG
        final tempDir = Directory.systemTemp;
        final dummyFile = File('${tempDir.path}/absensi_fallback_${DateTime.now().millisecondsSinceEpoch}.jpg');
        final canvas = img.Image(width: 480, height: 640);
        img.fill(canvas, color: img.ColorRgb8(28, 38, 56));
        img.fillCircle(canvas, x: 240, y: 260, radius: 90, color: img.ColorRgb8(64, 84, 114));
        await dummyFile.writeAsBytes(img.encodeJpg(canvas, quality: 85));
        rawPath = dummyFile.path;
      }

      // Stamp anti-tamper watermark & cryptographic hash
      final watermarkResult = await ImageWatermarkService.stampWatermark(
        sourceImagePath: rawPath,
        employeeId: user?.id ?? 1,
        employeeName: user?.name ?? 'Karyawan',
        attendanceType: _attendanceType,
        challengeToken: _challengeToken,
        shiftStartHour: settings.shiftStartHour,
      );

      final attendance = AttendanceModel(
        employeeId: user?.id ?? 1,
        employeeName: user?.name ?? 'Karyawan',
        timestamp: DateTime.now(),
        type: _attendanceType,
        status: watermarkResult.isLate ? 'terlambat' : 'tepat_waktu',
        lateMinutes: watermarkResult.lateMinutes,
        challengeCode: _challengeToken,
        validationHash: watermarkResult.validationHash,
        photoPath: watermarkResult.savedPath,
        isLivenessPassed: _isLivenessPassed,
      );

      await attProv.recordAttendance(attendance);

      await auth.logAction(
        'absensi_selfie',
        'Absensi $_attendanceType: ${user?.name} (${attendance.status.toUpperCase()}, Token: $_challengeToken)',
      );

      if (!mounted) return;

      // Show dialog with success & 1-tap WhatsApp Share to Owner
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.verified_rounded, color: AppTheme.primaryGreen),
                SizedBox(width: 8),
                Text('Absensi Berhasil!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nama: ${attendance.employeeName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Waktu: ${attendance.type.toUpperCase()} • ${attendance.status == "terlambat" ? "TERLAMBAT" : "TEPAT WAKTU"}'),
                Text('Kode Verifikasi: ${attendance.validationHash}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
                const SizedBox(height: 8),
                const Text(
                  'Foto selfie dengan watermark anti-pemalsuan AI telah berhasil disimpan.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text('Tutup'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.share_rounded),
                label: const Text('Kirim ke WA Owner'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await WhatsAppService.sendAttendanceToAdmin(
                    attendance: attendance,
                    ownerPhone: settings.ownerPhone,
                    storeName: settings.storeName,
                  );
                  if (mounted) Navigator.pop(context);
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal merekam absensi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _livenessService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final challengeText = LivenessService.getChallengeInstruction(_currentChallenge);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Absensi Selfie (Liveness Anti-AI)'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Shift In / Out Toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Absen Masuk'),
                      selected: _attendanceType == 'masuk',
                      selectedColor: AppTheme.primaryGreenLight,
                      onSelected: (val) {
                        if (val) setState(() => _attendanceType = 'masuk');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Absen Pulang'),
                      selected: _attendanceType == 'pulang',
                      selectedColor: AppTheme.primaryGreenLight,
                      onSelected: (val) {
                        if (val) setState(() => _attendanceType = 'pulang');
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Dynamic Challenge Badge (Anti-AI Token)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'TOKEN: $_challengeToken',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tantangan Gestur Hidup (Offline):',
                          style: TextStyle(fontSize: 10, color: Colors.white70),
                        ),
                        Text(
                          challengeText,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Camera Viewport
            Expanded(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isLivenessPassed ? AppTheme.primaryGreenLight : Colors.white24,
                      width: 2.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_isCameraInitialized && _cameraController != null)
                        CameraPreview(_cameraController!)
                      else
                        const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.face_retouching_natural_rounded, size: 64, color: Colors.white54),
                            SizedBox(height: 12),
                            Text('Kamera Sedang Dipersiapkan...', style: TextStyle(color: Colors.white70)),
                          ],
                        ),

                      // Oval Face Guide Overlay
                      Container(
                        width: 220,
                        height: 280,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(110),
                          border: Border.all(
                            color: _isLivenessPassed ? Colors.greenAccent : Colors.white54,
                            width: 2,
                          ),
                        ),
                      ),

                      // Feedback Banner at Bottom of Preview
                      Positioned(
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isLivenessPassed
                                ? Colors.green.withOpacity(0.85)
                                : Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isLivenessPassed ? Icons.check_circle : Icons.info_outline,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _livenessFeedback,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Shutter Button
            Padding(
              padding: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLivenessPassed ? AppTheme.primaryGreen : Colors.grey.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _isCapturing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_rounded, size: 24),
                  label: Text(
                    _isCapturing
                        ? 'MEMPROSES WATERMARK...'
                        : _isCameraInitialized
                            ? (_isLivenessPassed
                                ? 'AMBIL FOTO ABSENSI'
                                : 'SELESAIKAN VERIFIKASI WAJAH...')
                            : 'KAMERA TIDAK TERSEDIA (MODE UJI)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed: (_isCapturing || (_isCameraInitialized && !_isLivenessPassed))
                      ? null
                      : _takeAttendancePicture,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
