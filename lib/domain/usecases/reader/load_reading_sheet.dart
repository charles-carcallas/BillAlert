import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/bill.dart';
import '../../entities/consumer.dart';
import '../../outbox/outbox_entry.dart';
import '../../outbox/outbox_operation.dart';
import '../../repositories/bill_repository.dart';
import '../../repositories/consumer_repository.dart';
import '../../repositories/outbox_repository.dart';
import '../../value_objects/cycle_label.dart';
import '../../value_objects/ids.dart';
import '../../value_objects/kwh.dart';
import '../../value_objects/ph_date.dart';

/// Where one household's reading for the cycle stands.
enum SheetRowState {
  /// On the server: the figures are the ones the bill was made from.
  synced,

  /// Recorded on this phone and still in the outbox.
  waitingToSync,

  /// The server has it, but this phone could not fetch the figures.
  recordedFiguresUnavailable,

  /// Nobody has read this meter yet this cycle.
  notRead,
}

/// One line of the reading sheet the reader hands to BOHECO.
final class ReadingSheetRow {
  final Consumer household;
  final SheetRowState state;
  final Kwh? previousReading;
  final Kwh? currentReading;
  final PhDate? readingDate;

  const ReadingSheetRow({
    required this.household,
    required this.state,
    this.previousReading,
    this.currentReading,
    this.readingDate,
  });

  bool get isRead => state != SheetRowState.notRead;

  /// Present minus previous, when both are known. Readings only; no money.
  Kwh? get consumption => previousReading == null || currentReading == null
      ? null
      : currentReading! - previousReading!;
}

/// The month's readings for one area, in the order the sheet is written.
final class ReadingSheet {
  final CycleLabel cycle;
  final List<ReadingSheetRow> rows;

  /// Set when the server's readings could not be fetched. The sheet still
  /// lists every household and anything waiting on this phone.
  final AppFailure? serverFailure;

  const ReadingSheet({
    required this.cycle,
    required this.rows,
    this.serverFailure,
  });

  int get readCount => rows.where((ReadingSheetRow r) => r.isRead).length;
  int get notReadCount => rows.length - readCount;

  /// Summed in hundredths rather than with a `+` on [Kwh]: consumption stays
  /// the domain's one reading arithmetic, and this is only a column total.
  Kwh get totalConsumption => Kwh.fromHundredths(
    rows.fold(
      0,
      (int sum, ReadingSheetRow row) =>
          sum + (row.consumption?.hundredths ?? 0),
    ),
  );
}

/// Step 2 of the reader's month: the list that goes onto BOHECO's paper.
///
/// Every active household in the area appears once, so a meter nobody read is
/// visible on the sheet rather than silently missing from it. The figures
/// come from three places, most authoritative first:
///
/// 1. the server's bills for the cycle, which carry the reading they were
///    made from;
/// 2. readings still in this phone's outbox, whose previous reading is the
///    one saved with the household;
/// 3. otherwise, "not read".
///
/// With no signal, (1) is unavailable. Households the saved roster already
/// knows were read then say so without figures, and the failure is returned
/// alongside so the screen can explain the gap.
final class LoadReadingSheet {
  final ConsumerRepository consumers;
  final BillRepository bills;
  final OutboxRepository outbox;

  const LoadReadingSheet({
    required this.consumers,
    required this.bills,
    required this.outbox,
  });

  Future<Result<ReadingSheet>> call({
    required AreaId areaId,
    required CycleLabel cycle,
  }) async {
    final List<Consumer> households;
    switch (await consumers.areaRoster(areaId)) {
      case Err(:final failure):
        return Err<ReadingSheet>(failure);
      case Ok(:final value):
        households = value.where((Consumer c) => c.isActive).toList();
    }

    final Map<ConsumerId, Bill> billed = <ConsumerId, Bill>{};
    AppFailure? serverFailure;
    switch (await bills.readingsForCycle(areaId, cycle)) {
      case Err(:final failure):
        serverFailure = failure;
      case Ok(:final value):
        for (final Bill bill in value) {
          billed[bill.consumerId] = bill;
        }
    }

    final Map<ConsumerId, OutboxEntry> queued = <ConsumerId, OutboxEntry>{};
    if (await outbox.all() case Ok(:final value)) {
      for (final OutboxEntry entry in value) {
        final OutboxOperation op = entry.operation;
        if (op is RecordReadingOperation &&
            op.cycleLabel == cycle &&
            (entry.status == OutboxStatus.pending ||
                entry.status == OutboxStatus.syncing)) {
          queued[op.consumerId] = entry;
        }
      }
    }

    final List<ReadingSheetRow> rows = households.map((Consumer household) {
      final Bill? bill = billed[household.id];
      if (bill != null) {
        return ReadingSheetRow(
          household: household,
          state: SheetRowState.synced,
          previousReading: bill.previousReading,
          currentReading: bill.currentReading,
          readingDate: bill.readingDate,
        );
      }
      final OutboxEntry? entry = queued[household.id];
      if (entry != null) {
        final op = entry.operation as RecordReadingOperation;
        return ReadingSheetRow(
          household: household,
          state: SheetRowState.waitingToSync,
          previousReading: household.previousReading,
          currentReading: op.currentReading,
          readingDate: PhDate.at(op.capturedAt),
        );
      }
      if (serverFailure != null && household.hasBeenReadFor(cycle)) {
        return ReadingSheetRow(
          household: household,
          state: SheetRowState.recordedFiguresUnavailable,
        );
      }
      return ReadingSheetRow(
        household: household,
        state: SheetRowState.notRead,
      );
    }).toList()..sort(_sheetOrder);

    return Ok<ReadingSheet>(
      ReadingSheet(cycle: cycle, rows: rows, serverFailure: serverFailure),
    );
  }

  /// Purok by purok, then by account number: the order a reader walks and
  /// the order a clerk looks a household up in.
  static int _sheetOrder(ReadingSheetRow a, ReadingSheetRow b) {
    final int byPurok = (a.household.purok ?? '\u{10FFFF}').compareTo(
      b.household.purok ?? '\u{10FFFF}',
    );
    if (byPurok != 0) return byPurok;
    return a.household.consumerNo.value.compareTo(b.household.consumerNo.value);
  }
}
