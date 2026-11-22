import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../services/thermal_printer_service.dart';
import '../../utils/responsive.dart';

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});
  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  List<Map<String, dynamic>> _configs = [];
  bool _loading = true;
  String _search = '';
  List<DiscoveredPrinter> _printers = [];
  bool _loadingPrinters = false;
  String? _defaultPrinterUrl;
  String? _defaultPrinterName;
  String? _defaultPrinterKind;
  String? _discoverHint;
  double _clientRate = 20;
  String _paperSize = kPrinter58;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final c = await db.getAppConfig();
    if (!mounted) return;
    final rate = await db.getClientCommissionRate();
    setState(() {
      _clientRate = rate;
      final typeRow = c.where((e) => e['key'] == 'printer_type').toList();
      _paperSize = normalizePrinterType(
        typeRow.isEmpty ? null : typeRow.first['value'] as String,
      );
      _configs = c.where((e) {
        final k = e['key'] as String;
        return !k.contains('numbers') &&
            !k.contains('win4') &&
            !k.contains('straight') &&
            !k.contains('box') &&
            !k.contains('midday') &&
            !k.contains('evening') &&
            !k.contains('draw_') &&
            !k.contains('backup') &&
            k != 'winning_time_restricted' &&
            k != 'ticket_seq' &&
            k != 'serial_seq' &&
            k != 'default_printer_url' &&
            k != 'default_printer_name' &&
            k != 'default_printer_kind' &&
            k != 'client_commission_rate' &&
            k != 'printer_type' &&
            k != 'printer_connection';
      }).toList();
      _loading = false;
    });
    try {
      final urlRow = c.where((e) => e['key'] == 'default_printer_url').toList();
      final nameRow = c
          .where((e) => e['key'] == 'default_printer_name')
          .toList();
      final kindRow = c
          .where((e) => e['key'] == 'default_printer_kind')
          .toList();
      if (mounted)
        setState(() {
          _defaultPrinterUrl = urlRow.isNotEmpty
              ? urlRow.first['value'] as String
              : null;
          _defaultPrinterName = nameRow.isNotEmpty
              ? nameRow.first['value'] as String
              : null;
          _defaultPrinterKind = kindRow.isNotEmpty
              ? kindRow.first['value'] as String
              : null;
          if (_defaultPrinterUrl != null && _defaultPrinterUrl!.isEmpty)
            _defaultPrinterUrl = null;
          if (_defaultPrinterName != null && _defaultPrinterName!.isEmpty)
            _defaultPrinterName = null;
          if (_defaultPrinterKind != null && _defaultPrinterKind!.isEmpty)
            _defaultPrinterKind = null;
        });
    } catch (_) {}
  }

  Future<void> _discoverPrinters() async {
    setState(() {
      _loadingPrinters = true;
      _discoverHint = null;
    });
    try {
      final result = await discoverPrinters();
      if (mounted)
        setState(() {
          _printers = result.printers;
          _discoverHint = result.warning;
        });
      if (result.printers.isEmpty && mounted && result.warning != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.warning!)));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Printer discovery error: $e')));
    }
    if (mounted) setState(() => _loadingPrinters = false);
  }

  Future<void> _setDefaultPrinter(DiscoveredPrinter p) async {
    final db = context.read<AppDatabase>();
    await saveDefaultPrinter(db, p);
    setState(() {
      _defaultPrinterUrl = p.id;
      _defaultPrinterName = p.name;
      _defaultPrinterKind = p.kind;
    });
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Default printer saved: ${p.name} — printing is direct from the app',
          ),
          backgroundColor: const Color(0xFF0B8A3E),
        ),
      );
  }

  Future<void> _clearDefaultPrinter() async {
    final db = context.read<AppDatabase>();
    await clearDefaultPrinter(db);
    setState(() {
      _defaultPrinterUrl = null;
      _defaultPrinterName = null;
      _defaultPrinterKind = null;
    });
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Default printer removed')));
  }

  Future<void> _setPaperSize(String value) async {
    final next = normalizePrinterType(value);
    if (next == _paperSize) return;
    final db = context.read<AppDatabase>();
    await savePrinterPaperSize(db, next);
    if (!mounted) return;
    setState(() => _paperSize = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Default paper width saved: ${is80mmPrinter(next) ? '80mm' : '58mm'}',
        ),
        backgroundColor: const Color(0xFF0B8A3E),
      ),
    );
  }

  String _desc(String k) {
    switch (k) {
      case 'currency':
        return 'Currency (USD)';
      case 'language':
        return 'Language';
      case 'company_name':
        return 'Company name on ticket';
      case 'ticket_footer':
        return 'Ticket footer text';
      case 'printer_type':
        return 'Printer type 58/80mm';
      case 'printer_connection':
        return 'Printer connection Bluetooth/USB';
      case 'client_commission_rate':
        return 'Customer percent of total sales';
      default:
        return k;
    }
  }

  Future<void> _edit(String key, String current, String scope) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          key,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: key,
            border: const OutlineInputBorder(),
            isDense: true,
            helperText: 'Scope: $scope',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B8A3E),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final value = ctrl.text.trim();
    // Numeric settings must never be stored empty — downstream parsing breaks.
    if (value.isEmpty && num.tryParse(current) != null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a numeric value'),
            backgroundColor: Colors.red,
          ),
        );
      return;
    }
    if (!mounted) return;
    await context.read<AppDatabase>().upsertConfig(key, value, scope);
    await _load();
  }

  Future<void> _editClientRate() async {
    final ctrl = TextEditingController(
      text: _clientRate == _clientRate.roundToDouble()
          ? _clientRate.toStringAsFixed(0)
          : _clientRate.toString(),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(
          'Customer percent',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calculated from full sales. Default is 20%.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Rate %',
                hintText: '20',
                suffixText: '%',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B8A3E),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
    if (v == null || v < 0 || v > 100) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a valid rate between 0 and 100'),
            backgroundColor: Colors.red,
          ),
        );
      return;
    }
    if (!mounted) return;
    await context.read<AppDatabase>().setClientCommissionRate(v);
    await _load();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Customer rate saved: ${v == v.roundToDouble() ? v.toStringAsFixed(0) : v}%',
          ),
          backgroundColor: const Color(0xFF0B8A3E),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0B8A3E);
    final filtered = _search.isEmpty
        ? _configs
        : _configs
              .where(
                (e) => (e['key'] as String).toLowerCase().contains(
                  _search.toLowerCase(),
                ),
              )
              .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: const Text('General Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: green))
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: green.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.print,
                              color: green,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Printer',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (_defaultPrinterName != null)
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Default: $_defaultPrinterName',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: green,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _defaultPrinterUrl == null
                            ? 'No default printer selected. Pair the printer in device Bluetooth settings, then tap Discover.'
                            : 'Default printer: $_defaultPrinterName${_defaultPrinterKind != null ? ' • $_defaultPrinterKind' : ''}\n$_defaultPrinterUrl',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Printing is done from inside the app on the selected default printer.',
                        style: TextStyle(fontSize: 10, color: Colors.black87),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Paper width',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Default is 58mm. Switch to 80mm only if your printer uses 80mm rolls.',
                        style: TextStyle(fontSize: 10, color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: kPrinter58,
                            label: Text('58mm'),
                            icon: Icon(Icons.receipt_long, size: 16),
                          ),
                          ButtonSegment(
                            value: kPrinter80,
                            label: Text('80mm'),
                            icon: Icon(Icons.receipt, size: 16),
                          ),
                        ],
                        selected: {_paperSize},
                        onSelectionChanged: (v) => _setPaperSize(v.first),
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (s) => s.contains(WidgetState.selected)
                                ? Colors.white
                                : green,
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (s) => s.contains(WidgetState.selected)
                                ? green
                                : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _defaultPrinterUrl == null
                            ? 'Choose a printer below, then print uses ${_paperSize == kPrinter80 ? '80mm' : '58mm'}.'
                            : 'Tickets print on ${_defaultPrinterName ?? 'the default printer'} at ${_paperSize == kPrinter80 ? '80mm' : '58mm'}.',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black54,
                        ),
                      ),
                      if (_discoverHint != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _discoverHint!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: _loadingPrinters
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.search, size: 16),
                              label: Text(
                                _loadingPrinters
                                    ? 'Searching...'
                                    : 'Discover printers',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _loadingPrinters
                                  ? null
                                  : _discoverPrinters,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.clear, size: 16),
                            label: const Text(
                              'Clear',
                              style: TextStyle(fontSize: 11),
                            ),
                            onPressed: _defaultPrinterUrl == null
                                ? null
                                : _clearDefaultPrinter,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      if (_printers.isNotEmpty) ...[
                        const Divider(height: 16),
                        const Text(
                          'Choose a default printer (paired Bluetooth devices):',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ..._printers.map(
                          (p) => Card(
                            color: p.id == _defaultPrinterUrl
                                ? green.withValues(alpha: 0.07)
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: p.id == _defaultPrinterUrl
                                    ? green
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: RadioListTile<String>(
                              value: p.id,
                              groupValue: _defaultPrinterUrl,
                              onChanged: (v) => _setDefaultPrinter(p),
                              title: Text(
                                p.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${p.kind == 'bluetooth' ? 'Bluetooth' : 'System'} • ${p.id}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.black54,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              secondary: Icon(
                                p.isBluetooth ? Icons.bluetooth : Icons.print,
                                size: 18,
                                color: p.id == _defaultPrinterUrl
                                    ? green
                                    : Colors.blueGrey,
                              ),
                              dense: true,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.percent,
                          color: Colors.blue,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Customer percent',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Taken from full sales. Default is 20%.',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_clientRate == _clientRate.roundToDouble() ? _clientRate.toStringAsFixed(0) : _clientRate}%',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18, color: green),
                        tooltip: 'Edit customer rate',
                        onPressed: _editClientRate,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                ...filtered.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.withValues(alpha: 0.1),
                          child: Icon(
                            e['key'].toString().contains('printer')
                                ? Icons.print
                                : Icons.settings,
                            color: Colors.blue,
                            size: 16,
                          ),
                        ),
                        title: Text(
                          e['key'],
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${e['value']}\n${_desc(e['key'])}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, size: 16, color: green),
                          onPressed: () =>
                              _edit(e['key'], e['value'], e['scope']),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
