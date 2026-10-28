/// Area defaults. Posted due dates and closed trip deadlines remain fixed.
class BillingSchedule {
  const BillingSchedule({
    this.dueDay = 28,
    this.cutoffDay = 28,
    this.cutoffMinutes = 720,
    this.version,
    this.effectiveMonth,
  });
  final int dueDay, cutoffDay, cutoffMinutes;
  final String? version, effectiveMonth;
  factory BillingSchedule.fromJson(Map<String, dynamic> json) =>
      BillingSchedule(
        dueDay: json['due_day'] as int,
        cutoffDay: json['cutoff_day'] as int,
        cutoffMinutes: json['cutoff_minutes'] as int,
        version: json['version'] as String?,
        effectiveMonth: json['effective_month'] as String,
      );
  String get cutoffTime {
    final hour = cutoffMinutes ~/ 60;
    return '${hour % 12 == 0 ? 12 : hour % 12}:${(cutoffMinutes % 60).toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
  }

  String get cutoffLabel => 'Day $cutoffDay, $cutoffTime PH time';
  static String formatPhInstant(DateTime instant) {
    final ph = instant.toUtc().add(const Duration(hours: 8));
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final clock = BillingSchedule(
      cutoffMinutes: ph.hour * 60 + ph.minute,
    ).cutoffTime;
    return '${ph.day} ${months[ph.month - 1]} ${ph.year}, $clock';
  }
}
