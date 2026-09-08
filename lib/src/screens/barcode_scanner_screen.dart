import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});
  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _handled = false;
  String? _lastScanned;
  bool _torchOn = false;
  bool _ready = false;
  bool _requesting = true;
  bool _inFlight = false;
  bool _permanentlyDenied = false;
  bool _starting = false;
  String? _statusMessage;
  final TextEditingController _manualCtrl = TextEditingController();

  MobileScannerController _createController() {
    return MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
      cameraResolution: const Size(1280, 720),
      useNewCameraSelector: true,
      formats: const [
        BarcodeFormat.qrCode,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.codabar,
      ],
    );
  }

  @override
  void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = _createController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureCameraReady();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    if (state == AppLifecycleState.resumed) {
      if (_ready) {
        _startCamera();
      } else if (!_requesting) {
        _ensureCameraReady();
      }
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_ready) c.stop().catchError((_) {});
    }
  }

  Future<void> _ensureCameraReady() async {
    if (!mounted || _inFlight) return;
    _inFlight = true;
    setState(() {
      _requesting = true;
      _statusMessage = null;
      _permanentlyDenied = false;
    });

    try {
      if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
        if (!mounted) return;
        setState(() {
          _requesting = false;
          _ready = false;
          _statusMessage = 'Camera scanning is not available on this device. Enter the ticket ID below.';
        });
        return;
      }

      // Always request — if already granted the system returns immediately.
      // Checking status first can skip the dialog on some Samsung phones.
      var status = await Permission.camera.request();
      if (!mounted) return;

      if (!(status.isGranted || status.isLimited) && status.isDenied) {
        status = await Permission.camera.request();
        if (!mounted) return;
      }

      if (status.isGranted || status.isLimited) {
        setState(() {
          _ready = true;
          _requesting = false;
          _permanentlyDenied = false;
          _statusMessage = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startCamera();
        });
        return;
      }

      final blocked = status.isPermanentlyDenied || status.isRestricted;
      setState(() {
        _ready = false;
        _requesting = false;
        _permanentlyDenied = blocked;
        _statusMessage = blocked
          ? 'Camera permission is blocked. Open Settings, allow Camera, then return here.'
          : 'Camera permission is required to scan tickets. Tap Allow Camera to continue.';
      });
      if (blocked) {
        await openAppSettings();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _requesting = false;
        _statusMessage = 'Could not start the camera. Enter the ticket ID below.';
      });
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _startCamera({bool retried = false}) async {
    final c = _controller;
    if (!mounted || c == null || _starting || _handled) return;
    _starting = true;
    try {
      await c.start();
      if (mounted) setState(() => _statusMessage = null);
    } catch (e) {
      if (!retried && mounted) {
        await Future.delayed(const Duration(milliseconds: 350));
        await _recycleController();
        _starting = false;
        await _startCamera(retried: true);
        return;
      }
      if (!mounted) return;
      setState(() {
        _ready = false;
        _statusMessage = 'Could not start the camera on this phone. Enter the ticket ID below.';
      });
    } finally {
      _starting = false;
    }
  }

  Future<void> _recycleController() async {
    final old = _controller;
    _controller = _createController();
    if (mounted) setState(() {});
    try { await old?.stop(); } catch (_) {}
    try { old?.dispose(); } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualCtrl.dispose();
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  String _cleanBarcode(String raw){
    raw = raw.trim().replaceAll(RegExp(r'[\r\n]'), '').trim();
    if(raw.contains(' ') || raw.contains(':') || raw.contains('|')){
      final parts = raw.split(RegExp(r'[^A-Za-z0-9]+')).where((p)=> p.isNotEmpty).toList();
      if(parts.isNotEmpty){
        final numeric = parts.where((p)=> RegExp(r'^\d{4,10}$').hasMatch(p)).toList();
        if(numeric.isNotEmpty) return numeric.last;
        return parts.last;
      }
    }
    return raw;
  }

  void _onDetect(BarcodeCapture capture){
    if(_handled) return;
    final barcodes = capture.barcodes;
    if(barcodes.isEmpty) return;
    String? raw;
    for(final b in barcodes){
      if(b.rawValue != null && b.rawValue!.trim().isNotEmpty){
        raw = b.rawValue;
        break;
      }
      if(b.displayValue != null && b.displayValue!.trim().isNotEmpty){
        raw = b.displayValue;
        break;
      }
    }
    if(raw==null || raw.trim().isEmpty) return;
    final cleaned = _cleanBarcode(raw);
    if(cleaned.isEmpty) return;
    setState(()=> _lastScanned = cleaned);
    HapticFeedback.mediumImpact();
    _handled = true;
    _controller?.stop().catchError((_) {});
    Future.delayed(const Duration(milliseconds: 150), (){
      if(mounted) Navigator.pop(context, cleaned);
    });
  }

  void _submitManual(){
    final v = _manualCtrl.text.trim();
    if(v.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a ticket ID, serial, or barcode')));
      return;
    }
    Navigator.pop(context, _cleanBarcode(v));
  }

  Widget _errorView(MobileScannerException error) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.videocam_off, size: 48, color: Colors.grey),
        const SizedBox(height: 10),
        const Text('Camera failed to start on this phone.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 6),
        Text('${error.errorCode.name}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black38, fontSize: 11)),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0B8A3E), foregroundColor: Colors.white),
          onPressed: () async {
            await _recycleController();
            if (mounted) {
              setState(() => _ready = true);
              await _startCamera();
            }
          },
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Retry camera'),
        ),
      ]),
    ));
  }

  Widget _cameraBody(){
    final c = _controller;
    if(_requesting){
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: Color(0xFF0B8A3E)),
        SizedBox(height: 12),
        Text('Requesting camera permission…', style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]));
    }
    if(_ready && c != null){
      return Stack(children: [
        MobileScanner(
          controller: c,
          onDetect: _onDetect,
          errorBuilder: (context, error, _) => _errorView(error),
          overlayBuilder: (context, constraints) => CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _ScanFramePainter(),
          ),
        ),
        Align(alignment: Alignment.bottomCenter, child: Container(
          margin: const EdgeInsets.fromLTRB(16,0,16,12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Align the QR / barcode inside the frame — it scans automatically', style: TextStyle(color: Colors.white, fontSize: 11), textAlign: TextAlign.center),
            if(_lastScanned != null) Padding(padding: const EdgeInsets.only(top:4), child: Text('Detected: $_lastScanned', style: const TextStyle(color: Colors.greenAccent, fontSize: 10))),
          ]),
        )),
      ]);
    }
    return Center(child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.videocam_off, size: 48, color: Colors.grey),
        const SizedBox(height: 10),
        Text(_statusMessage ?? 'Camera is not available.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0B8A3E), foregroundColor: Colors.white),
          onPressed: _ensureCameraReady,
          icon: const Icon(Icons.camera_alt, size: 16),
          label: const Text('Allow Camera'),
        ),
        if(_permanentlyDenied) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await openAppSettings();
            },
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('Open Settings'),
          ),
        ],
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        backgroundColor: const Color(0xFF0B8A3E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_torchOn ? Icons.flash_off : Icons.flash_on),
            tooltip: 'Torch',
            onPressed: !_ready ? null : () async {
              try {
                await _controller?.toggleTorch();
                if(mounted) setState(()=> _torchOn = !_torchOn);
              } catch (_) {}
            }
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            tooltip: 'Switch camera',
            onPressed: !_ready ? null : () async {
              try { await _controller?.switchCamera(); } catch (_) {}
            },
          ),
        ],
      ),
      body: Column(children: [
        Expanded(child: _cameraBody()),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12,10,12,12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Or enter ticket ID / serial / barcode:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(
                controller: _manualCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'e.g. 000001 or 00000001',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.confirmation_number, size: 18),
                  suffixIcon: IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: ()=> _manualCtrl.clear()),
                ),
                onSubmitted: (_)=> _submitManual(),
              )),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0B8A3E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
                onPressed: _submitManual,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Search', style: TextStyle(fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('Tickets print a QR code plus a numeric ID (000001). Either value works.', style: TextStyle(fontSize: 9, color: Colors.black45)),
          ]),
        ),
      ]),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 260,
      height: 260,
    );
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)), border);
    final line = Paint()
      ..color = const Color(0xFF0B8A3E)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(rect.left + 16, rect.center.dy), Offset(rect.right - 16, rect.center.dy), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
