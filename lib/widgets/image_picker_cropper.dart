import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/image_media_service.dart';
import '../utils/app_theme.dart';

class ImagePickerHelper {
  /// Opens a bottom sheet letting the user choose Camera or Gallery,
  /// optionally launches our interactive Crop & Rotate dialog, and returns
  /// the saved persistent image path inside AppDocuments/media/.
  static Future<String?> pickAndCropImage(
    BuildContext context, {
    required String prefix,
    String title = 'Pilih & Sesuaikan Gambar',
    bool saveAsPng = false,
  }) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.primaryGreenSoft,
                    child: Icon(Icons.photo_library_rounded, color: AppTheme.primaryGreen),
                  ),
                  title: const Text('Pilih dari Galeri / File'),
                  subtitle: const Text('Unggah foto PNG atau JPG dari perangkat'),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade50,
                    child: const Icon(Icons.camera_alt_rounded, color: AppTheme.accentBlue),
                  ),
                  title: const Text('Ambil Foto dari Kamera'),
                  subtitle: const Text('Gunakan kamera belakang/depan secara langsung'),
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null || !context.mounted) return null;

    String? rawPath;
    if (source == 'gallery') {
      rawPath = await ImageMediaService.pickImageFromGallery();
    } else if (source == 'camera') {
      rawPath = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const CameraPhotoCaptureScreen()),
      );
    }

    if (rawPath == null || !context.mounted) return null;

    return await openCropDialog(
      context,
      sourcePath: rawPath,
      prefix: prefix,
      saveAsPng: saveAsPng,
    );
  }

  static Future<String?> openCropDialog(
    BuildContext context, {
    required String sourcePath,
    required String prefix,
    bool saveAsPng = false,
  }) async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImageCropDialog(
        sourcePath: sourcePath,
        prefix: prefix,
        saveAsPng: saveAsPng,
      ),
    );
  }
}

class CameraPhotoCaptureScreen extends StatefulWidget {
  const CameraPhotoCaptureScreen({super.key});

  @override
  State<CameraPhotoCaptureScreen> createState() => _CameraPhotoCaptureScreenState();
}

class _CameraPhotoCaptureScreenState extends State<CameraPhotoCaptureScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIdx = 0;
  bool _ready = false;
  String? _error;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _error = 'Tidak ada kamera terdeteksi di perangkat ini.');
        return;
      }
      await _startController(_cameras[_selectedCameraIdx]);
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal membuka kamera: $e');
    }
  }

  Future<void> _startController(CameraDescription cam) async {
    await _controller?.dispose();
    final ctrl = CameraController(cam, ResolutionPreset.high, enableAudio: false);
    _controller = ctrl;
    try {
      await ctrl.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Kamera tidak dapat dimulai: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_capturing || _controller == null || !_controller!.value.isInitialized) return;
    setState(() => _capturing = true);
    try {
      final file = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.pop(context, file.path);
    } catch (e) {
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengambil foto: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Ambil Foto'),
        actions: [
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch_rounded),
              onPressed: () {
                _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
                setState(() => _ready = false);
                _startController(_cameras[_selectedCameraIdx]);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : (!_ready || _controller == null
                      ? const CircularProgressIndicator(color: Colors.white)
                      : CameraPreview(_controller!)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: (_ready && !_capturing) ? _capture : null,
                    icon: _capturing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt_rounded),
                    label: Text(_capturing ? 'Memproses...' : 'AMBIL FOTO'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImageCropDialog extends StatefulWidget {
  final String sourcePath;
  final String prefix;
  final bool saveAsPng;

  const ImageCropDialog({
    super.key,
    required this.sourcePath,
    required this.prefix,
    this.saveAsPng = false,
  });

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  // Normalized crop margins inside preview (0..1)
  double _marginH = 0.05;
  double _marginV = 0.05;
  int _quarterTurns = 0;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await ImageMediaService.cropAndSaveImage(
      sourcePath: widget.sourcePath,
      prefix: widget.prefix,
      normLeft: _marginH,
      normTop: _marginV,
      normWidth: 1.0 - (_marginH * 2),
      normHeight: 1.0 - (_marginV * 2),
      rotationQuarterTurns: _quarterTurns,
      saveAsPng: widget.saveAsPng,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Crop & Sesuaikan Gambar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.rotate_right_rounded),
                    tooltip: 'Putar 90°',
                    onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final h = constraints.maxHeight;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          RotatedBox(
                            quarterTurns: _quarterTurns,
                            child: Image.file(
                              File(widget.sourcePath),
                              fit: BoxFit.contain,
                            ),
                          ),
                          Positioned(
                            left: w * _marginH,
                            top: h * _marginV,
                            right: w * _marginH,
                            bottom: h * _marginV,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.primaryGreenLight, width: 2.5),
                                color: AppTheme.primaryGreenLight.withValues(alpha: 0.08),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Potong Sisi:', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _marginH,
                      min: 0.0,
                      max: 0.35,
                      onChanged: (v) => setState(() {
                        _marginH = v;
                        _marginV = v;
                      }),
                    ),
                  ),
                  Text('${((1 - _marginH * 2) * 100).toInt()}%', style: const TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? 'Menyimpan...' : 'Gunakan Gambar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
