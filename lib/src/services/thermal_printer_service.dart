import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../data/database.dart';
import '../utils/format.dart';

const kPrinter58 = 'thermal_58mm';
const kPrinter80 = 'thermal_80mm';

class DiscoveredPrinter {
  final String id;
  final String name;
  final String kind; // bluetooth | system
  const DiscoveredPrinter({
    required this.id,
    required this.name,
    required this.kind,
  });
  bool get isBluetooth => kind == 'bluetooth';
}

class PrinterDiscoveryResult {
  final List<DiscoveredPrinter> printers;
  final String? warning;
  const PrinterDiscoveryResult(this.printers, {this.warning});
}

class PrintJobResult {
  final bool ok;
  final String? error;
  const PrintJobResult.success() : ok = true, error = null;
  const PrintJobResult.fail(this.error) : ok = false;
}

final _macRe = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
bool looksLikeMac(String? id) => id != null && _macRe.hasMatch(id.trim());

String? _connectedMac;

String normalizePrinterType(String? printerType) {
  final v = (printerType ?? '').trim().toLowerCase();
  if (v.contains('80')) return kPrinter80;
  return kPrinter58;
}

bool is80mmPrinter(String? printerType) =>
    normalizePrinterType(printerType) == kPrinter80;

PaperSize paperSizeForType(String? printerType) =>
    is80mmPrinter(printerType) ? PaperSize.mm80 : PaperSize.mm58;

String _betLabel(String raw) {
  final n = raw
      .trim()
      .toLowerCase()
      .replaceAll('-', '/')
      .replaceAll('_', '/')
      .replaceAll(' ', '');
  if (n == 'all' ||
      n == 'all/box' ||
      n == 'all/straight' ||
      (n.contains('straight') && n.contains('box')) ||
      n == 'straightbox' ||
      n == 'str/box' ||
      n == 'strbox')
    return 'ST/BOX';
  if (n == 'straight') return 'ST';
  if (n == 'box') return 'BOX';
  if (n.contains('combo')) return 'COMBO';
  return raw;
}

String _ascii(String input) {
  return input
      .replaceAll('•', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('’', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"');
}

String _padLine(String left, String right, int width) {
  final l = _ascii(left);
  final r = _ascii(right);
  final space = width - l.length - r.length;
  if (space < 1) {
    final keep = width - r.length - 1;
    if (keep < 4)
      return (l + r).length <= width ? l + r : (l + r).substring(0, width);
    return '${l.substring(0, keep)} $r';
  }
  return l + ' ' * space + r;
}

Future<void> _ensureBluetoothPermission() async {
  if (kIsWeb) return;
  if (Platform.isAndroid) {
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request();
  } else if (Platform.isIOS) {
    await Permission.bluetooth.request();
  }
}

Future<PrinterDiscoveryResult> discoverPrinters() async {
  final out = <DiscoveredPrinter>[];
  String? warning;

  try {
    await _ensureBluetoothPermission();
    final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!granted && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      warning = 'Allow Bluetooth permission to discover the printer';
    }
    bool btOn = true;
    try {
      btOn = await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      btOn = true;
    }
    if (!btOn) {
      warning = 'Bluetooth is off — turn it on and pair the printer in device settings';
    } else {
      final list = await PrintBluetoothThermal.pairedBluetooths;
      for (final b in list) {
        final mac = b.macAdress.trim();
        if (mac.isEmpty) continue;
        out.add(
          DiscoveredPrinter(
            id: mac,
            name: b.name.trim().isEmpty ? mac : b.name.trim(),
            kind: 'bluetooth',
          ),
        );
      }
    }
  } catch (e) {
    warning = 'Could not read Bluetooth devices: $e';
  }

  try {
    final info = await Printing.info();
    if (info.canListPrinters) {
      for (final p in await Printing.listPrinters()) {
        out.add(DiscoveredPrinter(id: p.url, name: p.name, kind: 'system'));
      }
    }
  } catch (_) {}

  if (out.isEmpty && warning == null) {
    warning = 'No printers found. Pair the thermal printer in device Bluetooth settings, then tap Discover.';
  }
  return PrinterDiscoveryResult(out, warning: warning);
}

Future<bool> _connectBluetooth(String mac) async {
  final already = await PrintBluetoothThermal.connectionStatus;
  if (already && _connectedMac == mac) return true;
  if (already) {
    await PrintBluetoothThermal.disconnect;
    _connectedMac = null;
    await Future.delayed(const Duration(milliseconds: 250));
  }
  final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
  if (ok) {
    _connectedMac = mac;
    await Future.delayed(const Duration(milliseconds: 350));
  }
  return ok;
}

Future<bool> _writeBluetooth(List<int> bytes) async {
  if (bytes.isEmpty) return false;
  if (bytes.length <= 4096) {
    return PrintBluetoothThermal.writeBytes(bytes);
  }
  const chunk = 1024;
  for (var i = 0; i < bytes.length; i += chunk) {
    final end = i + chunk > bytes.length ? bytes.length : i + chunk;
    final ok = await PrintBluetoothThermal.writeBytes(bytes.sublist(i, end));
    if (!ok) return false;
    if (end < bytes.length) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }
  return true;
}

Future<Generator> _generator(String printerType) async {
  final paper = paperSizeForType(printerType);
  final profile = await CapabilityProfile.load();
  return Generator(paper, profile);
}

int _charsPerLine(String printerType) => is80mmPrinter(printerType) ? 48 : 32;

Future<List<int>> buildTicketEscPos({
  required Map<String, dynamic> ticket,
  required List<Map<String, dynamic>> lines,
  required String company,
  required String footer,
  required String printerType,
}) async {
  final type = normalizePrinterType(printerType);
  final mm80 = is80mmPrinter(type);
  final g = await _generator(type);
  final width = _charsPerLine(type);
  final customerRaw = ticket['customerName'];
  final customerName = (customerRaw is String && customerRaw.trim().isNotEmpty)
      ? customerRaw.trim()
      : 'Cash Customer';
  final bytes = <int>[];
  bytes.addAll(g.reset());
  bytes.addAll(g.setGlobalCodeTable('CP1252'));

  final bodySize = mm80 ? PosTextSize.size2 : PosTextSize.size1;
  bytes.addAll(
    g.text(
      'INVOICE REPORT',
      styles: PosStyles(
        align: PosAlign.center,
        bold: true,
        height: bodySize,
        width: PosTextSize.size1,
      ),
    ),
  );
  bytes.addAll(g.hr(ch: '='));
  // رقم الفاتورة والتاريخ مباشرة تحت SALES REPORT
  final idEarly = '${ticket['barcode'] ?? ticket['id']}';
  bytes.addAll(
    g.text(
      'Ticket: ${_ascii(idEarly)}',
      styles: PosStyles(bold: true, height: bodySize, width: PosTextSize.size1),
    ),
  );
  bytes.addAll(
    g.text(
      'Date: ${fmtDate(ticket['createdAt'] is int ? ticket['createdAt'] as int : DateTime.now().millisecondsSinceEpoch)}',
      styles: PosStyles(bold: true, height: bodySize, width: PosTextSize.size1),
    ),
  );
  bytes.addAll(
    g.text(
      'Op: ${_ascii('${ticket['operatorName'] ?? ''}')}',
      styles: PosStyles(bold: true, height: bodySize, width: PosTextSize.size1),
    ),
  );
  bytes.addAll(
    g.text(
      'Customer: ${_ascii(customerName)}',
      styles: PosStyles(bold: true, height: bodySize, width: PosTextSize.size1),
    ),
  );
  bytes.addAll(g.hr(ch: '-'));
  final total = fmtMoney(ticket['total'] ?? ticket['amount']);

  void playLine(String numbers, String bet, String amount) {
    final nums = numbers.replaceAll(',', ' ');
    final lineWidth = mm80 ? width ~/ 2 : width;
    bytes.addAll(
      g.text(
        _padLine(nums, '$bet  $amount', lineWidth),
        styles: PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: mm80 ? PosTextSize.size2 : PosTextSize.size1,
        ),
      ),
    );
  }

  String classify(Map<String, dynamic> l) {
    final pid = (l['periodId'] ?? '').toString().toUpperCase();
    if (pid.contains('MIDDAY') ||
        pid.contains('MORNING') ||
        pid.contains('MID_'))
      return 'MIDDAY';
    if (pid.contains('EVENING') || pid.contains('EVE') || pid.contains('NIGHT'))
      return 'EVENING';
    final dn = (l['drawName'] ?? '').toString().toUpperCase();
    if (dn.contains('MIDDAY') || dn.contains('MORNING')) return 'MIDDAY';
    if (dn.contains('EVENING')) return 'EVENING';
    final dt = (l['drawType'] ?? '').toString().toUpperCase();
    if (dt.contains('MIDDAY') || dt.contains('MORNING') || dt.contains('MID'))
      return 'MIDDAY';
    if (dt.contains('EVENING') || dt.contains('EVE')) return 'EVENING';
    return '';
  }

  if (lines.isEmpty) {
    final dn = (ticket['drawName'] ?? '').toString().toUpperCase();
    String? header;
    if (dn.contains('MIDDAY') || dn.contains('MORNING'))
      header = 'MIDDAY';
    else if (dn.contains('EVENING'))
      header = 'EVENING';
    if (header != null)
      bytes.addAll(g.text(header, styles: const PosStyles(bold: true)));
    playLine(
      '${ticket['numbers'] ?? ''}',
      _betLabel('${ticket['betType'] ?? ''}'),
      fmtMoney(ticket['amount'] ?? 0),
    );
  } else {
    final mid = lines.where((l) => classify(l) == 'MIDDAY').toList();
    final eve = lines.where((l) => classify(l) == 'EVENING').toList();
    final other = lines.where((l) => classify(l) == '').toList();
    final hasMid = mid.isNotEmpty;
    final hasEve = eve.isNotEmpty;
    final hasOther = other.isNotEmpty;
    if (!hasMid && !hasEve) {
      for (final l in lines) {
        playLine(
          '${l['numbers']}',
          _betLabel('${l['betType']}'),
          fmtMoney(l['amount']),
        );
      }
    } else {
      if (hasMid) {
        bytes.addAll(g.text('MIDDAY', styles: const PosStyles(bold: true)));
        for (final l in mid) {
          playLine(
            '${l['numbers']}',
            _betLabel('${l['betType']}'),
            fmtMoney(l['amount']),
          );
        }
      }
      if (hasMid && hasEve) bytes.addAll(g.hr(ch: '-'));
      if (hasEve) {
        bytes.addAll(g.text('EVENING', styles: const PosStyles(bold: true)));
        for (final l in eve) {
          playLine(
            '${l['numbers']}',
            _betLabel('${l['betType']}'),
            fmtMoney(l['amount']),
          );
        }
      }
      if (hasOther) {
        if (hasMid || hasEve) bytes.addAll(g.hr(ch: '-'));
        for (final l in other) {
          playLine(
            '${l['numbers']}',
            _betLabel('${l['betType']}'),
            fmtMoney(l['amount']),
          );
        }
      }
    }
  }

  bytes.addAll(g.hr());
  bytes.addAll(
    g.text(
      _padLine('TOTAL', total, mm80 ? width ~/ 2 : width),
      styles: PosStyles(
        bold: true,
        height: PosTextSize.size2,
        width: mm80 ? PosTextSize.size2 : PosTextSize.size1,
      ),
    ),
  );

  final status = '${ticket['status'] ?? ''}';
  if (status == 'winning' || status == 'paid') {
    final prize = fmtMoney(ticket['prizeAmount'] ?? 0);
    bytes.addAll(
      g.text(
        status == 'paid' ? 'PAID - Prize $prize' : 'WINNER - Prize $prize',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
  }

  final id = idEarly;
  bytes.addAll(g.feed(1));
  bytes.addAll(
    g.qrcode(
      id,
      align: PosAlign.center,
      size: mm80 ? QRSize.size6 : QRSize.size5,
      cor: QRCorrection.M,
    ),
  );
  bytes.addAll(
    g.text(
      _ascii(id),
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ),
  );
  bytes.addAll(g.hr());
  final foot = footer.trim();
  if (foot.isNotEmpty) {
    bytes.addAll(
      g.text(_ascii(foot), styles: const PosStyles(align: PosAlign.center)),
    );
  }
  bytes.addAll(
    g.text('--- CUT HERE ---', styles: const PosStyles(align: PosAlign.center)),
  );
  bytes.addAll(g.feed(2));
  bytes.addAll(g.cut());
  return bytes;
}

Future<List<int>> buildReportEscPos({
  required String printerType,
  required String company,
  required String rangeLabel,
  required List<({String title, List<String> rows})> sections,
  required String generated,
}) async {
  final type = normalizePrinterType(printerType);
  final g = await _generator(type);
  final bytes = <int>[];
  bytes.addAll(g.reset());
  bytes.addAll(g.setGlobalCodeTable('CP1252'));
  bytes.addAll(
    g.text(
      'INVOICE REPORT',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size1,
        width: PosTextSize.size1,
      ),
    ),
  );
  bytes.addAll(
    g.text(_ascii(rangeLabel), styles: const PosStyles(align: PosAlign.center)),
  );
  bytes.addAll(g.hr(ch: '='));
  for (final section in sections) {
    bytes.addAll(
      g.text(_ascii(section.title), styles: const PosStyles(bold: true)),
    );
    for (final row in section.rows) {
      bytes.addAll(g.text(_ascii(row)));
    }
    bytes.addAll(g.feed(1));
  }
  bytes.addAll(g.hr());
  bytes.addAll(
    g.text(_ascii(generated), styles: const PosStyles(align: PosAlign.center)),
  );
  bytes.addAll(
    g.text('--- CUT HERE ---', styles: const PosStyles(align: PosAlign.center)),
  );
  bytes.addAll(g.feed(2));
  bytes.addAll(g.cut());
  return bytes;
}

Future<List<int>> _pdfToEscPos(Uint8List pdfBytes, String printerType) async {
  final paper = paperSizeForType(printerType);
  final g = await _generator(printerType);
  final bytes = <int>[];
  bytes.addAll(g.reset());

  final targetW = paper.width;
  var pages = 0;
  await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
    pages++;
    final png = await page.toPng();
    var image = img.decodePng(png);
    if (image == null) continue;
    image = _fitThermalImage(image, targetW);
    const sliceH = 240;
    var y = 0;
    while (y < image.height) {
      final h = (y + sliceH > image.height) ? image.height - y : sliceH;
      final slice = img.copyCrop(
        image,
        x: 0,
        y: y,
        width: image.width,
        height: h,
      );
      bytes.addAll(g.imageRaster(slice, align: PosAlign.center));
      y += h;
    }
  }
  if (pages == 0) {
    throw StateError('Could not convert the ticket image for the printer');
  }
  bytes.addAll(g.feed(2));
  bytes.addAll(g.cut());
  return bytes;
}

img.Image _fitThermalImage(img.Image src, int targetW) {
  var image = src;
  if (image.width != targetW) {
    final h = (image.height * targetW / image.width).round().clamp(1, 8000);
    image = img.copyResize(
      image,
      width: targetW,
      height: h,
      interpolation: img.Interpolation.linear,
    );
  }
  image = img.grayscale(image);
  image = img.adjustColor(image, contrast: 1.35);
  image = _trimWhite(image);
  if (image.width != targetW) {
    final canvas = img.Image(width: targetW, height: image.height);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(
      canvas,
      image,
      dstX: ((targetW - image.width) / 2).round(),
    );
    image = canvas;
  }
  return image;
}

img.Image _trimWhite(img.Image src) {
  bool rowEmpty(int y) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      if (p.r < 245 || p.g < 245 || p.b < 245) return false;
    }
    return true;
  }

  var top = 0;
  var bottom = src.height - 1;
  while (top < bottom && rowEmpty(top)) {
    top++;
  }
  while (bottom > top && rowEmpty(bottom)) {
    bottom--;
  }
  final keepTop = top > 4 ? top - 4 : 0;
  final keepBottom = bottom + 4 < src.height - 1 ? bottom + 4 : src.height - 1;
  final h = keepBottom - keepTop + 1;
  if (h <= 0 || h >= src.height) return src;
  return img.copyCrop(src, x: 0, y: keepTop, width: src.width, height: h);
}

Future<PrintJobResult> printPdfBytes({
  required AppDatabase db,
  required Uint8List pdfBytes,
  required PdfPageFormat format,
  required String jobName,
  List<int>? bluetoothBytes,
}) async {
  final cfg = await db.getAppConfig();
  final map = {for (var c in cfg) c['key'] as String: c['value'] as String};
  final url = (map['default_printer_url'] ?? '').trim();
  final name = (map['default_printer_name'] ?? '').trim();
  final kind =
      (map['default_printer_kind'] ??
              (looksLikeMac(url) ? 'bluetooth' : 'system'))
          .trim();
  final printerType = normalizePrinterType(map['printer_type']);
  if (url.isEmpty) {
    return const PrintJobResult.fail(
      'No default printer selected in General Settings',
    );
  }

  final useBt = kind == 'bluetooth' || looksLikeMac(url);
  if (useBt) {
    try {
      await _ensureBluetoothPermission();
      final connected = await _connectBluetooth(url);
      if (!connected) {
        return PrintJobResult.fail(
          'Could not connect to printer ${name.isEmpty ? url : name}. Make sure it is paired and powered on.',
        );
      }
      final ticket =
          bluetoothBytes ?? await _pdfToEscPos(pdfBytes, printerType);
      var ok = await _writeBluetooth(ticket);
      if (!ok) {
        await PrintBluetoothThermal.disconnect;
        _connectedMac = null;
        final again = await _connectBluetooth(url);
        if (again) ok = await _writeBluetooth(ticket);
      }
      if (ok) return const PrintJobResult.success();
      return const PrintJobResult.fail('Failed to send data to the printer');
    } catch (e) {
      return PrintJobResult.fail('Bluetooth print error: $e');
    }
  }

  try {
    final printers = await Printing.listPrinters();
    Printer? target;
    for (final p in printers) {
      if (p.url == url) {
        target = p;
        break;
      }
    }
    if (target == null && name.isNotEmpty) {
      for (final p in printers) {
        if (p.name == name) {
          target = p;
          break;
        }
      }
    }
    if (target == null) {
      return const PrintJobResult.fail(
        'Default printer is not available on this device',
      );
    }
    final ok = await Printing.directPrintPdf(
      printer: target,
      onLayout: (_) async => pdfBytes,
      name: jobName,
      format: format,
    );
    return ok
        ? const PrintJobResult.success()
        : const PrintJobResult.fail('Direct print failed');
  } catch (e) {
    return PrintJobResult.fail('System printer error: $e');
  }
}

Future<void> saveDefaultPrinter(AppDatabase db, DiscoveredPrinter p) async {
  await db.upsertConfig('default_printer_url', p.id, 'local');
  await db.upsertConfig('default_printer_name', p.name, 'local');
  await db.upsertConfig('default_printer_kind', p.kind, 'local');
}

Future<void> clearDefaultPrinter(AppDatabase db) async {
  await db.upsertConfig('default_printer_url', '', 'local');
  await db.upsertConfig('default_printer_name', '', 'local');
  await db.upsertConfig('default_printer_kind', '', 'local');
}

Future<void> savePrinterPaperSize(AppDatabase db, String printerType) async {
  await db.upsertConfig(
    'printer_type',
    normalizePrinterType(printerType),
    'local',
  );
}
