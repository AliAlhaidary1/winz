import '../data/database.dart';
import '../utils/format.dart';
import '../utils/timezone.dart';

/// Draw period status lifecycle per spec section 4
class DrawStatus {
  static const scheduled = 'SCHEDULED';
  static const open = 'OPEN';
  static const salesClosed = 'SALES_CLOSED';
  static const drawing = 'DRAWING';
  static const resultPending = 'RESULT_PENDING';
  static const resultPublished = 'RESULT_PUBLISHED';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';
  static const postponed = 'POSTPONED';
  static const suspended = 'SUSPENDED';

  static const all = [
    scheduled,
    open,
    salesClosed,
    drawing,
    resultPending,
    resultPublished,
    completed,
    cancelled,
    postponed,
    suspended,
  ];

  /// Legacy mapping from old draws.status
  static String fromLegacy(String? legacy) {
    if (legacy == 'open') return open;
    if (legacy == 'closed') return resultPublished;
    return scheduled;
  }
}

class DrawPeriodService {
  final AppDatabase db;
  DrawPeriodService(this.db);

  // ---------- Config ----------

  Future<Map<String, String>> getConfigMap() async {
    final rows = await db.getAppConfig();
    return {for (var r in rows) r['key'] as String: r['value'] as String};
  }

  Future<String> getTimezone() async {
    final cfg = await getConfigMap();
    return cfg['draw_timezone'] ?? cfg['timezone'] ?? 'America/New_York';
  }

  Future<void> setTimezone(String tz) async {
    await db.upsertConfig('draw_timezone', tz, 'local');
    await _audit(
      'SET_TIMEZONE',
      null,
      null,
      tz,
      reason: 'Timezone changed to $tz',
    );
  }

  Future<Map<String, dynamic>> getDrawConfig(String drawType) async {
    // drawType = MIDDAY or EVENING
    final cfg = await getConfigMap();
    final prefix = drawType.toLowerCase(); // midday / evening
    final salesClose =
        cfg['${prefix}_sales_close'] ??
        (drawType == 'MIDDAY' ? '14:15' : '22:20');
    final drawTime =
        cfg['${prefix}_draw_time'] ??
        (drawType == 'MIDDAY' ? '14:30' : '22:30');
    final enabledStr = cfg['${prefix}_enabled'] ?? '1';
    final resultMode =
        cfg['${prefix}_result_mode'] ?? cfg['result_mode'] ?? 'manual';
    final autoOpen = cfg['${prefix}_auto_open'] ?? cfg['auto_open_next'] ?? '1';
    final tz = await getTimezone();
    return {
      'drawType': drawType,
      'drawName': drawType[0] + drawType.substring(1).toLowerCase(),
      'salesClose': salesClose,
      'drawTime': drawTime,
      'enabled':
          enabledStr == '1' ||
          enabledStr.toLowerCase() == 'true' ||
          enabledStr.toLowerCase() == 'on',
      'timezone': tz,
      'resultMode': resultMode,
      'autoOpenNext': autoOpen == '1',
    };
  }

  Future<List<Map<String, dynamic>>> getAllDrawConfigs() async {
    final midday = await getDrawConfig('MIDDAY');
    final evening = await getDrawConfig('EVENING');
    return [midday, evening];
  }

  Future<void> updateDrawConfig({
    required String drawType,
    String? salesClose,
    String? drawTime,
    bool? enabled,
    String? resultMode,
    bool? autoOpenNext,
    String? timezone,
    String? user,
    String? reason,
  }) async {
    final cfg = await getConfigMap();
    final prefix = drawType.toLowerCase();
    String? oldSales = cfg['${prefix}_sales_close'];
    String? oldDraw = cfg['${prefix}_draw_time'];
    String? oldEnabled = cfg['${prefix}_enabled'];
    if (salesClose != null) {
      _validateTimeFormat(salesClose);
      await db.upsertConfig('${prefix}_sales_close', salesClose, 'local');
      await _audit(
        'CONFIG_CHANGE',
        null,
        oldSales,
        salesClose,
        reason: reason ?? 'Sales close $drawType: $oldSales -> $salesClose',
        user: user,
      );
    }
    if (drawTime != null) {
      _validateTimeFormat(drawTime);
      await db.upsertConfig('${prefix}_draw_time', drawTime, 'local');
      await _audit(
        'CONFIG_CHANGE',
        null,
        oldDraw,
        drawTime,
        reason: reason ?? 'Draw time $drawType: $oldDraw -> $drawTime',
        user: user,
      );
    }
    if (enabled != null) {
      await db.upsertConfig('${prefix}_enabled', enabled ? '1' : '0', 'local');
      await _audit(
        'CONFIG_CHANGE',
        null,
        oldEnabled,
        enabled ? '1' : '0',
        reason:
            reason ?? 'Enabled $drawType: $oldEnabled -> ${enabled ? 1 : 0}',
        user: user,
      );
    }
    if (resultMode != null) {
      await db.upsertConfig('${prefix}_result_mode', resultMode, 'local');
      await _audit(
        'CONFIG_CHANGE',
        null,
        cfg['${prefix}_result_mode'],
        resultMode,
        reason: 'Result mode $drawType -> $resultMode',
        user: user,
      );
    }
    if (autoOpenNext != null) {
      await db.upsertConfig(
        '${prefix}_auto_open',
        autoOpenNext ? '1' : '0',
        'local',
      );
    }
    if (timezone != null) {
      await setTimezone(timezone);
    }
    // Regenerate future periods if times changed
    if (salesClose != null || drawTime != null || enabled != null) {
      await ensureDailyPeriods(daysAhead: 14);
    }
  }

  void _validateTimeFormat(String t) {
    if (!RegExp(
      r'^\d{1,2}:\d{2}(\s*[AP]M)?$',
      caseSensitive: false,
    ).hasMatch(t.trim())) {
      throw Exception(
        'Invalid time format: $t (expected HH:MM or HH:MM AM/PM)',
      );
    }
  }

  // ---------- Period generation ----------

  /// Parse HH:MM [or HH:MM AM/PM] into hour/minute 24h
  List<int> _parseHM(String s) {
    s = s.trim().toUpperCase();
    bool isPM = s.contains('PM');
    bool isAM = s.contains('AM');
    s = s.replaceAll(RegExp(r'\s*[AP]M'), '').trim();
    final parts = s.split(':');
    int h = int.parse(parts[0]);
    int m = int.parse(parts[1]);
    if (isPM && h < 12) h += 12;
    if (isAM && h == 12) h = 0;
    return [h, m];
  }

  /// Build an absolute epoch for a date + wall-clock time in the configured
  /// timezone. [tz] is the `draw_timezone` value from app config.
  int _epochForDate(DateTime date, String timeStr, String tz) {
    final hm = _parseHM(timeStr);
    return MarketTimezone.epochForWallTime(date, hm[0], hm[1], tz);
  }

  String _periodId(DateTime date, String drawType) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d-${drawType.toUpperCase()}';
  }

  Future<void> ensureDailyPeriods({int daysAhead = 14}) async {
    final now = DateTime.now();
    final configs = await getAllDrawConfigs();
    for (int i = 0; i < daysAhead; i++) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: i));
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      for (final cfg in configs) {
        final drawType = cfg['drawType'] as String;
        if (cfg['enabled'] != true) continue;
        final salesCloseStr = cfg['salesClose'] as String;
        final drawTimeStr = cfg['drawTime'] as String;
        final tz = cfg['timezone'] as String;
        final id = _periodId(date, drawType);
        final salesCloseEpoch = _epochForDate(date, salesCloseStr, tz);
        final drawEpoch = _epochForDate(date, drawTimeStr, tz);
        // sales open = previous period's result published OR start of day 00:00, simplified as 00:00
        final salesOpenEpoch = MarketTimezone.epochForWallTime(date, 0, 0, tz);
        // Try insert, ignore if exists but update times if changed
        final existing = await db.getPeriodById(id);
        if (existing == null) {
          await db.insertPeriod({
            'id': id,
            'drawType': drawType,
            'drawDate': dateStr,
            'salesOpenTime': salesOpenEpoch,
            'salesCloseTime': salesCloseEpoch,
            'drawTime': drawEpoch,
            'status': DrawStatus.scheduled,
            'result': null,
            'resultPublishedAt': null,
            'publishedBy': null,
            'resultSource': null,
            'timezone': tz,
          });
        } else {
          // إذا غيّر الوقت وقد كان مغلقاً — أعد فتحه من اليوم نفسه كما طلب العميل
          final hasResult =
              (existing['result3'] != null &&
                  (existing['result3'] as String).isNotEmpty) ||
              (existing['result4'] != null &&
                  (existing['result4'] as String).isNotEmpty) ||
              (existing['result'] != null &&
                  (existing['result'] as String).isNotEmpty);
          final isTodayOrFuture =
              dateStr.compareTo(
                '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
              ) >=
              0;
          // حدّث الوقت دائماً إذا لم يُنشر فائز بعد ويوم اليوم أو بعده — يعيد فتح الفترة المغلقة
          if (!hasResult && isTodayOrFuture) {
            await db.updatePeriodTimes(
              id,
              salesOpenEpoch,
              salesCloseEpoch,
              drawEpoch,
            );
          } else if (existing['status'] == DrawStatus.scheduled ||
              existing['status'] == DrawStatus.open) {
            await db.updatePeriodTimes(
              id,
              salesOpenEpoch,
              salesCloseEpoch,
              drawEpoch,
            );
          }
        }
      }
    }
    // After ensuring, auto-transition statuses based on current time
    await refreshPeriodStatuses();
  }

  Future<void> refreshPeriodStatuses() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final periods = await db.getAllPeriods();
    for (final p in periods) {
      final status = p['status'] as String;
      final salesOpen = p['salesOpenTime'] as int;
      final salesClose = p['salesCloseTime'] as int;
      final drawTime = p['drawTime'] as int;
      final result = p['result'] as String?;
      final r3 = p['result3'] as String?;
      final r4 = p['result4'] as String?;
      final hasResult =
          (result != null && result.isNotEmpty) ||
          (r3 != null && r3.isNotEmpty) ||
          (r4 != null && r4.isNotEmpty);
      if (status == DrawStatus.cancelled ||
          status == DrawStatus.postponed ||
          status == DrawStatus.suspended) {
        continue;
      }
      // إذا يوجد فائز بالفعل — لا تعيد فتحه، فقط ترقية إلى منشور/مكتمل
      if (hasResult) {
        if (status == DrawStatus.resultPending ||
            status == DrawStatus.salesClosed ||
            status == DrawStatus.open ||
            status == DrawStatus.scheduled ||
            status == DrawStatus.drawing) {
          await db.updatePeriodStatus(
            p['id'] as String,
            DrawStatus.resultPublished,
          );
        } else if (status == DrawStatus.resultPublished) {
          await db.updatePeriodStatus(p['id'] as String, DrawStatus.completed);
        }
        continue;
      }
      // بدون فائز — احسب الحالة المطلوبة من الوقت (يسمح بإعادة الفتح كما طلب العميل)
      String desired;
      if (now < salesOpen) {
        desired = DrawStatus.scheduled;
      } else if (now < salesClose) {
        desired = DrawStatus.open;
      } else if (now < drawTime) {
        desired = DrawStatus.salesClosed;
      } else {
        desired = DrawStatus.resultPending;
      }
      // ترقية تدريجية عبر drawing إذا لزم الأمر
      if (desired == DrawStatus.resultPending &&
          status == DrawStatus.salesClosed) {
        // سيمر عبر drawing أولاً لكن نسمح بالقفز مباشرة
        desired = DrawStatus.resultPending;
      }
      if (desired != status) {
        // السماح بإعادة الفتح: SALES_CLOSED/RESULT_PENDING → OPEN إذا الوقت عاد قبل salesClose
        await db.updatePeriodStatus(p['id'] as String, desired);
      }
    }
  }

  Future<Map<String, dynamic>?> getCurrentPeriod() async {
    await refreshPeriodStatuses();
    final now = DateTime.now().millisecondsSinceEpoch;
    final periods = await db.getAllPeriods();
    // Current = first OPEN period ordered by drawTime
    periods.sort(
      (a, b) =>
          asInt(a['salesCloseTime']).compareTo(asInt(b['salesCloseTime'])),
    );
    for (final p in periods) {
      if (p['status'] == DrawStatus.open) return p;
    }
    // Fallback: next upcoming scheduled
    for (final p in periods) {
      if (p['status'] == DrawStatus.scheduled &&
          asInt(p['salesCloseTime']) > now)
        return p;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getNextPeriod() async {
    await refreshPeriodStatuses();
    final periods = await db.getAllPeriods();
    periods.sort(
      (a, b) => asInt(a['drawTime']).compareTo(asInt(b['drawTime'])),
    );
    bool foundCurrent = false;
    for (final p in periods) {
      if (foundCurrent &&
          (p['status'] == DrawStatus.scheduled ||
              p['status'] == DrawStatus.open))
        return p;
      if (p['status'] == DrawStatus.open) foundCurrent = true;
    }
    // If no open, next scheduled after now
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in periods) {
      if (asInt(p['drawTime']) > now &&
          (p['status'] == DrawStatus.scheduled ||
              p['status'] == DrawStatus.open))
        return p;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getPeriodsForDate(DateTime date) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return db.getPeriodsByDate(dateStr);
  }

  // ---------- Sales validation ----------

  Future<bool> isPeriodOpen(String periodId) async {
    await refreshPeriodStatuses();
    final p = await db.getPeriodById(periodId);
    if (p == null) return false;
    return p['status'] == DrawStatus.open;
  }

  Future<void> validateSaleForPeriods(List<String> periodIds) async {
    await refreshPeriodStatuses();
    for (final pid in periodIds) {
      final p = await db.getPeriodById(pid);
      if (p == null) throw Exception('Period $pid not found');
      if (p['status'] != DrawStatus.open) {
        final name = p['drawType'];
        final date = p['drawDate'];
        throw Exception(
          '$name $date is not open for sales (status: ${p['status']})',
        );
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= asInt(p['salesCloseTime'])) {
        throw Exception('Sales closed for $pid — cutoff reached');
      }
    }
  }

  Future<Map<String, dynamic>> getValidationForBoth(DateTime date) async {
    final middayId = _periodId(date, 'MIDDAY');
    final eveningId = _periodId(date, 'EVENING');
    final midday = await db.getPeriodById(middayId);
    final evening = await db.getPeriodById(eveningId);
    return {
      'midday': midday,
      'evening': evening,
      'middayOpen': midday != null && midday['status'] == DrawStatus.open,
      'eveningOpen': evening != null && evening['status'] == DrawStatus.open,
      'bothAvailable':
          (midday != null && midday['status'] == DrawStatus.open) &&
          (evening != null && evening['status'] == DrawStatus.open),
    };
  }

  // ---------- Result handling ----------

  Future<void> publishResult({
    required String periodId,
    required String winningNumber,
    required String publishedBy,
    String resultSource = 'manual',
    bool isCorrection = false,
  }) async {
    final p = await db.getPeriodById(periodId);
    if (p == null) throw Exception('Period not found: $periodId');
    // Validate
    if (p['status'] == DrawStatus.cancelled)
      throw Exception('Cannot publish result for cancelled period');
    // Validate number format
    final digits = winningNumber.trim().replaceAll(',', '').replaceAll(' ', '');
    if (!RegExp(r'^[0-9]+$').hasMatch(digits))
      throw Exception('Result must be digits 0-9');
    if (digits.length < 3 || digits.length > 4)
      throw Exception('Result must be 3 or 4 digits (got $digits)');
    // Check already published
    final existing = p['result'] as String?;
    if (existing != null && existing.isNotEmpty && !isCorrection) {
      throw Exception(
        'Result already published for $periodId: $existing — use correction flow',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.publishPeriodResult(
      periodId,
      winningNumber,
      now,
      publishedBy,
      resultSource,
    );
    await _audit(
      isCorrection ? 'RESULT_CORRECTED' : 'RESULT_PUBLISHED',
      periodId,
      existing,
      winningNumber,
      user: publishedBy,
    );
    // Also update legacy draws for backward compat (if any draw matches period)
    await _syncLegacyDraws(periodId, winningNumber);
  }

  // --- Dual winners (3-digit & 4-digit) ---
  Future<void> publishResult3({
    required String periodId,
    required String winningNumber,
    required String publishedBy,
    String resultSource = 'manual',
    bool isCorrection = false,
  }) async {
    final p = await db.getPeriodById(periodId);
    if (p == null) throw Exception('Period not found: $periodId');
    if (p['status'] == DrawStatus.cancelled)
      throw Exception('Cannot publish result for cancelled period');
    final digits = winningNumber.trim().replaceAll(',', '').replaceAll(' ', '');
    if (!RegExp(r'^[0-9]{3}$').hasMatch(digits))
      throw Exception('Result3 must be exactly 3 digits (0-9)');
    final existing = p['result3'] as String?;
    if (existing != null && existing.isNotEmpty && !isCorrection) {
      throw Exception(
        'Result 3-digit already published for $periodId: $existing — use correction',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.publishPeriodResult3(
      periodId,
      digits,
      now,
      publishedBy,
      resultSource,
    );
    await _audit(
      isCorrection ? 'RESULT3_CORRECTED' : 'RESULT3_PUBLISHED',
      periodId,
      existing,
      digits,
      user: publishedBy,
    );
    await _syncLegacyDraws(periodId, digits);
  }

  Future<void> publishResult4({
    required String periodId,
    required String winningNumber,
    required String publishedBy,
    String resultSource = 'manual',
    bool isCorrection = false,
  }) async {
    final p = await db.getPeriodById(periodId);
    if (p == null) throw Exception('Period not found: $periodId');
    if (p['status'] == DrawStatus.cancelled)
      throw Exception('Cannot publish result for cancelled period');
    final digits = winningNumber.trim().replaceAll(',', '').replaceAll(' ', '');
    if (!RegExp(r'^[0-9]{4}$').hasMatch(digits))
      throw Exception('Result4 must be exactly 4 digits (0-9)');
    final existing = p['result4'] as String?;
    if (existing != null && existing.isNotEmpty && !isCorrection) {
      throw Exception(
        'Result 4-digit already published for $periodId: $existing — use correction',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.publishPeriodResult4(
      periodId,
      digits,
      now,
      publishedBy,
      resultSource,
    );
    await _audit(
      isCorrection ? 'RESULT4_CORRECTED' : 'RESULT4_PUBLISHED',
      periodId,
      existing,
      digits,
      user: publishedBy,
    );
    await _syncLegacyDraws(periodId, digits);
  }

  Future<void> _syncLegacyDraws(String periodId, String winningNumber) async {
    // periodId like 2026-09-01-MIDDAY, need to find draws with same date and period
    try {
      final draws = await db.getAllDraws();
      for (final d in draws) {
        final name = d['name'] as String;
        if (periodId.contains('MIDDAY') &&
                name.toLowerCase().contains('midday') ||
            name.toLowerCase().contains('morning')) {
          // check date match via drawTime day
          final dt = DateTime.fromMillisecondsSinceEpoch(asInt(d['drawTime']));
          final dateStr =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          if (periodId.startsWith(dateStr)) {
            // winningNumbers is stored as comma-joined digits.
            final comma = winningNumber.split('').join(',');
            await db.updateDrawResult(d['id'] as String, comma);
          }
        }
        if (periodId.contains('EVENING') &&
            name.toLowerCase().contains('evening')) {
          final dt = DateTime.fromMillisecondsSinceEpoch(asInt(d['drawTime']));
          final dateStr =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          if (periodId.startsWith(dateStr)) {
            final comma = winningNumber.split('').join(',');
            await db.updateDrawResult(d['id'] as String, comma);
          }
        }
      }
    } catch (_) {}
  }

  // ---------- Admin overrides ----------

  Future<void> overrideStatus(
    String periodId,
    String newStatus, {
    String? user,
    String? reason,
  }) async {
    if (!DrawStatus.all.contains(newStatus))
      throw Exception('Invalid status: $newStatus');
    final p = await db.getPeriodById(periodId);
    if (p == null) throw Exception('Period not found');
    final old = p['status'] as String;
    await db.updatePeriodStatus(periodId, newStatus);
    await _audit(
      'STATUS_OVERRIDE',
      periodId,
      old,
      newStatus,
      user: user,
      reason: reason,
    );
  }

  Future<void> suspendSales(String periodId, {String? user, String? reason}) =>
      overrideStatus(
        periodId,
        DrawStatus.suspended,
        user: user,
        reason: reason,
      );
  Future<void> reopenSales(String periodId, {String? user, String? reason}) =>
      overrideStatus(periodId, DrawStatus.open, user: user, reason: reason);
  Future<void> cancelDraw(String periodId, {String? user, String? reason}) =>
      overrideStatus(
        periodId,
        DrawStatus.cancelled,
        user: user,
        reason: reason,
      );
  Future<void> postponeDraw(String periodId, {String? user, String? reason}) =>
      overrideStatus(
        periodId,
        DrawStatus.postponed,
        user: user,
        reason: reason,
      );

  // ---------- Countdown ----------

  Future<Map<String, dynamic>?> getCountdownForPeriod(String periodId) async {
    final p = await db.getPeriodById(periodId);
    if (p == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final close = p['salesCloseTime'] as int;
    final status = p['status'] as String;
    if (status != DrawStatus.open) {
      return {'status': status, 'remainingMs': 0, 'display': status};
    }
    final rem = close - now;
    if (rem <= 0)
      return {
        'status': DrawStatus.salesClosed,
        'remainingMs': 0,
        'display': 'SALES CLOSED',
      };
    final d = Duration(milliseconds: rem);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return {'status': status, 'remainingMs': rem, 'display': '$h:$m:$s'};
  }

  // ---------- Audit ----------

  Future<void> _audit(
    String action,
    String? periodId,
    dynamic oldVal,
    dynamic newVal, {
    String? user,
    String? reason,
  }) async {
    await db.insertAuditLog({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'user': user ?? 'system',
      'action': action,
      'periodId': periodId,
      'oldValue': oldVal?.toString(),
      'newValue': newVal?.toString(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'reason': reason,
    });
  }

  Future<List<Map<String, dynamic>>> getAuditLogs({String? periodId}) async {
    return db.getAuditLogs(periodId: periodId);
  }
}
