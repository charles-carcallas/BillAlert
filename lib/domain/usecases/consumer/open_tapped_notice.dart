import '../../../core/result/result.dart';
import '../../entities/bill.dart';
import '../../entities/consumer.dart';
import '../../notifications/phone_alerts.dart';
import '../../repositories/bill_repository.dart';
import '../../repositories/consumer_repository.dart';
import '../../value_objects/ids.dart';

/// Where a tapped notification should land.
sealed class TappedNoticeDestination {
  const TappedNoticeDestination();
}

/// The bill the notification was about, confirmed as the signed-in
/// household's own.
final class ShowBill extends TappedNoticeDestination {
  final Bill bill;

  const ShowBill(this.bill);
}

/// The Inbox, pointing at [highlight] if there is one, and saying
/// [explanation] if the bill could not be opened.
final class ShowInbox extends TappedNoticeDestination {
  final NotificationId? highlight;
  final String? explanation;

  const ShowInbox({this.highlight, this.explanation});
}

/// Phase 1: "open the app at the related bill or notice when a push
/// notification is selected, after verifying the notification belongs to the
/// authenticated account."
///
/// A notification can outlive the session it was shown in: shown to one
/// household, tapped after a different one has signed in on the same phone.
/// So the payload is not trusted to mean "yours". The bill opens only if it
/// can be read AND it belongs to the household signed in now. A notice is
/// pointed at in the Inbox, which lists only that household's own rows, and
/// the Inbox says so when the notice is not among them.
///
/// Every refusal lands in the Inbox with a sentence, never on a blank screen
/// or an error.
final class OpenTappedNotice {
  static const String notOnThisAccount =
      "That notification is about a bill that isn't on this account.";

  static const String couldNotOpen =
      "That bill couldn't be opened right now. It's in your History once "
      "you're back online.";

  final ConsumerRepository consumers;
  final BillRepository bills;

  const OpenTappedNotice({required this.consumers, required this.bills});

  Future<TappedNoticeDestination> call(String? payload) async {
    switch (NoticeTarget.decode(payload)) {
      case InboxNoticeTarget(:final NotificationId? notice):
        return ShowInbox(highlight: notice);
      case BillNoticeTarget(:final BillId bill):
        return _openBill(bill);
    }
  }

  Future<TappedNoticeDestination> _openBill(BillId id) async {
    final Consumer? household;
    switch (await consumers.signedInConsumer()) {
      case Err():
        return const ShowInbox(explanation: couldNotOpen);
      case Ok(:final value):
        household = value;
    }
    if (household == null) {
      return const ShowInbox(explanation: notOnThisAccount);
    }

    final Bill? bill;
    switch (await bills.byId(id)) {
      case Err():
        return const ShowInbox(explanation: couldNotOpen);
      case Ok(:final value):
        bill = value;
    }

    // Row-level security already hides another household's bill, so "not
    // found" is the usual answer for one. The comparison is the check the
    // requirement asks for, made here rather than assumed of the server.
    if (bill == null || bill.consumerId.value != household.id.value) {
      return const ShowInbox(explanation: notOnThisAccount);
    }
    return ShowBill(bill);
  }
}
