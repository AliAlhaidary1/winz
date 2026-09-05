import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});
  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  late final MobileScannerController _controller;
  bool _handled = false;
  String? _lastScanned;
  bool _torchOn = false;
  final TextEditingController _manualCtrl = TextEditingController();

  @override
  void initState(){
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
      // detect all formats including QR and Code128 (barcode printed is QR)
    );
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _cleanBarcode(String raw){
    raw = raw.trim();
    // remove line breaks
    raw = raw.replaceAll(RegExp(r'[\r\n]'), '').trim();
    // If QR was generated as "000001" it's fine. If it contains extra text like "ID:000001" extract token
    if(raw.contains(' ') || raw.contains(':') || raw.contains('\n') || raw.contains('|')){
      // split by non-alphanumeric
      final parts = raw.split(RegExp(r'[^A-Za-z0-9]+')).where((p)=> p.isNotEmpty).toList();
      if(parts.isNotEmpty){
        // Prefer numeric token length 4-8 (ticket id 6 digits) or serial 8 digits
        final numeric = parts.where((p)=> RegExp(r'^\d{4,10}$').hasMatch(p)).toList();
        if(numeric.isNotEmpty) return numeric.last;
        // otherwise last alphanumeric token
        return parts.last;
      }
    }
    return raw;
  }

  void _onDetect(BarcodeCapture capture){
    if(_handled) return;
    final barcodes = capture.barcodes;
    if(barcodes.isEmpty) return;
    // Iterate to find first valid rawValue
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
    // stop scanner before pop to avoid duplicate callbacks
    _controller.stop();
    Future.delayed(const Duration(milliseconds: 150), (){
      if(mounted) Navigator.pop(context, cleaned);
    });
  }

  void _submitManual(){
    final v = _manualCtrl.text.trim();
    if(v.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل رقم التذكرة / الباركود')));
      return;
    }
    Navigator.pop(context, _cleanBarcode(v));
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
            onPressed: () async {
              await _controller.toggleTorch();
              setState(()=> _torchOn = !_torchOn);
            }
          ),
          IconButton(icon: const Icon(Icons.flip_camera_ios), tooltip: 'Switch camera', onPressed: ()=> _controller.switchCamera()),
        ],
      ),
      body: Column(children: [
        Expanded(child: Stack(children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (ctx, err, w){
              return Center(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.videocam_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 8),
                  Text('Camera error: ${err.errorCode} - ${err.errorDetails?.message ?? ''}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  const SizedBox(height: 4),
                  const Text('يمكنك إدخال رقم التذكرة يدويا بالأسفل', style: TextStyle(fontSize: 11, color: Colors.black45)),
                ]),
              ));
            },
          ),
          // Dim overlay with cutout
          ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.45), BlendMode.srcOut),
            child: Stack(children: [
              Container(decoration: const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut)),
              Align(alignment: Alignment.center, child: Container(width: 270, height: 270, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)))),
            ]),
          ),
          Center(child: Container(width: 270, height: 270, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(16)))),
          // Scanning line animation hint (static)
          Center(child: Container(width: 270, height: 2, color: const Color(0xFF0B8A3E).withValues(alpha: 0.9))),
          Align(alignment: Alignment.bottomCenter, child: Container(margin: const EdgeInsets.fromLTRB(16,0,16,12), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('ضع الباركود / QR داخل الإطار — سيتم التعرف تلقائيا', style: TextStyle(color: Colors.white, fontSize: 11), textAlign: TextAlign.center),
            if(_lastScanned != null) Padding(padding: const EdgeInsets.only(top:4), child: Text('Detected: $_lastScanned', style: const TextStyle(color: Colors.greenAccent, fontSize: 10))),
          ]))),
        ])),
        // Manual fallback
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12,10,12,12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('أو أدخل رقم التذكرة / السيريال / الباركود يدويا:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(
                controller: _manualCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'مثلاً 000001 أو 00000001',
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
                label: const Text('بحث', style: TextStyle(fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('التذكرة تُطبع بـ QR + ID رقمي (000001)، يمكنك نسخ أي منهما.', style: TextStyle(fontSize: 9, color: Colors.black45)),
          ]),
        ),
      ]),
    );
  }
}
