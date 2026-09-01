import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});
  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        backgroundColor: const Color(0xFF0B8A3E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), onPressed: ()=> _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.flip_camera_ios), onPressed: ()=> _controller.switchCamera()),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if(_handled) return;
            final barcodes = capture.barcodes;
            if(barcodes.isEmpty) return;
            final raw = barcodes.first.rawValue;
            if(raw==null || raw.isEmpty) return;
            _handled = true;
            Navigator.pop(context, raw);
          },
        ),
        Align(alignment: Alignment.bottomCenter, child: Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)), child: const Text('ضع الباركود داخل الإطار — سيتم البحث تلقائيا', style: TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.center))),
        Center(child: Container(width: 260, height: 260, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(16)))),
      ]),
    );
  }
}
