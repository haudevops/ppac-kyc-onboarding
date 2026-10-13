import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/frame_cropper.dart';

import 'capture_overlay.dart';
import 'capture_preview_page.dart';

/// Full-screen custom camera with a guide overlay:
///  * documents: back camera + rounded-rectangle mask with corner brackets (ID-1 / passport ratio);
///  * selfie: front camera + oval face mask.
/// Document photos taken with the camera are cropped to the guide frame (plus a small margin);
/// selfies and gallery picks are kept whole.
/// Returns the path of the accepted (uncompressed) photo, or null if cancelled.
/// A gallery fallback is offered (useful on the iOS simulator, which has no camera).
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key, required this.mode, required this.title});

  final CaptureMode mode;
  final String title;

  static Future<String?> open(BuildContext context, {required CaptureMode mode, required String title}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => CameraCapturePage(mode: mode, title: title)),
    );
  }

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = false;
  bool _busy = false;
  String? _error;
  FlashMode _flashMode = FlashMode.off;

  /// Screen size and guide frame from the last layout - used to crop the captured photo.
  Size? _screenSize;
  Rect? _frame;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  /// The camera must be released when the app goes to background and re-acquired after.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (controller == null) return;
      _controller = null;
      controller.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && controller == null && _error == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setError('No camera is available on this device. You can choose a photo from your gallery instead.');
        return;
      }
      final wanted = widget.mode.isSelfie ? CameraLensDirection.front : CameraLensDirection.back;
      final description = cameras.firstWhere((c) => c.lensDirection == wanted, orElse: () => cameras.first);

      final controller = CameraController(
        description,
        // Documents get more pixels: only the framed part is kept, and it must stay readable.
        widget.mode.isSelfie ? ResolutionPreset.high : ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
        await controller.setFlashMode(_flashMode);
      } on CameraException {
        // Not supported on every device - not fatal.
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } on CameraException catch (e) {
      _setError(_describe(e));
    } finally {
      _initializing = false;
    }
  }

  void _setError(String message) {
    if (mounted) setState(() => _error = message);
  }

  String _describe(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Camera access is needed to capture your ${widget.mode.isSelfie ? 'selfie' : 'document'}. '
            'Please enable it in Settings, or choose a photo from your gallery.';
      default:
        return 'The camera could not be started (${e.code}).';
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || controller.value.isTakingPicture || _busy) return;

    setState(() => _busy = true);
    try {
      await HapticFeedback.mediumImpact();
      final file = await controller.takePicture();
      await controller.pausePreview();
      final path = await _cropToFrame(file.path);
      final accepted = await _review(path);
      if (!accepted && mounted && _controller == controller) await controller.resumePreview();
    } on CameraException catch (e) {
      _setError(_describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Keeps only the part of a document photo inside the guide frame. Falls back to the full
  /// photo if cropping fails, so the user is never blocked.
  Future<String> _cropToFrame(String path) async {
    final frame = _frame;
    final screen = _screenSize;
    if (widget.mode.isSelfie || frame == null || screen == null) return path;
    final target = '${path.substring(0, path.lastIndexOf('.'))}_framed.jpg';
    try {
      await FrameCropper.cropToFrame(sourcePath: path, targetPath: target, frame: frame, screen: screen);
      unawaited(_deleteQuietly(path));
      return target;
    } on Object {
      return path;
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
      if (picked == null || !mounted) return;
      await _review(picked.path);
    } on PlatformException catch (e) {
      _setError('Could not open the gallery (${e.code}).');
    }
  }

  /// Shows the preview; pops this page with the path if the user accepts it.
  Future<bool> _review(String path) async {
    if (!mounted) return false;
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CapturePreviewPage(imagePath: path, mode: widget.mode)),
    );
    if (!mounted) return false;
    if (accepted ?? false) {
      Navigator.of(context).pop(path);
      return true;
    }
    unawaited(_deleteQuietly(path));
    return false;
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // ignore
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await controller.setFlashMode(next);
      setState(() => _flashMode = next);
    } on CameraException {
      // device without flash
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final guideColor = Theme.of(context).colorScheme.primary;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final hole = CaptureOverlayGeometry.holeFor(widget.mode, size);
            _screenSize = size;
            _frame = hole;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (controller != null && controller.value.isInitialized)
                  _CameraPreviewCover(controller: controller)
                else if (_error == null)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
                CustomPaint(painter: CaptureOverlayPainter(mode: widget.mode, guideColor: guideColor)),
                Positioned(
                  left: 24,
                  right: 24,
                  top: hole.bottom + 20,
                  child: Text(
                    _error ?? widget.mode.instruction,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                _TopBar(
                  title: widget.title,
                  showFlash: !widget.mode.isSelfie && controller != null,
                  flashOn: _flashMode == FlashMode.torch,
                  onFlash: _toggleFlash,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    minimum: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RoundIconButton(icon: Icons.photo_library_outlined, label: 'Gallery', onTap: _pickFromGallery),
                        _ShutterButton(enabled: controller != null && !_busy, busy: _busy, onTap: _capture),
                        const SizedBox(width: 64),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Fills the screen with the preview (like BoxFit.cover) without distortion.
class _CameraPreviewCover extends StatelessWidget {
  const _CameraPreviewCover({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    // controller.value.aspectRatio is width/height in landscape; in portrait the preview is
    // `width` wide and `width * aspectRatio` tall.
    final width = MediaQuery.sizeOf(context).width;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width,
          height: width * controller.value.aspectRatio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.showFlash, required this.flashOn, required this.onFlash});

  final String title;
  final bool showFlash;
  final bool flashOn;
  final VoidCallback onFlash;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Cancel',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 48,
                child: showFlash
                    ? IconButton(
                        icon: Icon(flashOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
                        tooltip: 'Torch',
                        onPressed: onFlash,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.busy, required this.onTap});

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Take photo',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          padding: const EdgeInsets.all(5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? Colors.white : Colors.white38,
            ),
            child: busy ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()) : null,
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(onPressed: onTap, icon: Icon(icon)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
