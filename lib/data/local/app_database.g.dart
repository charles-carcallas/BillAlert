// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedConsumersTable extends CachedConsumers
    with TableInfo<$CachedConsumersTable, CachedConsumerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedConsumersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _consumerNoMeta = const VerificationMeta(
    'consumerNo',
  );
  @override
  late final GeneratedColumn<String> consumerNo = GeneratedColumn<String>(
    'consumer_no',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contactNumberMeta = const VerificationMeta(
    'contactNumber',
  );
  @override
  late final GeneratedColumn<String> contactNumber = GeneratedColumn<String>(
    'contact_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _meterSerialNoMeta = const VerificationMeta(
    'meterSerialNo',
  );
  @override
  late final GeneratedColumn<String> meterSerialNo = GeneratedColumn<String>(
    'meter_serial_no',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _areaIdMeta = const VerificationMeta('areaId');
  @override
  late final GeneratedColumn<String> areaId = GeneratedColumn<String>(
    'area_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _purokMeta = const VerificationMeta('purok');
  @override
  late final GeneratedColumn<String> purok = GeneratedColumn<String>(
    'purok',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accountStatusMeta = const VerificationMeta(
    'accountStatus',
  );
  @override
  late final GeneratedColumn<String> accountStatus = GeneratedColumn<String>(
    'account_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previousReadingHundredthsMeta =
      const VerificationMeta('previousReadingHundredths');
  @override
  late final GeneratedColumn<int> previousReadingHundredths =
      GeneratedColumn<int>(
        'previous_reading_hundredths',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _previousReadingDateMeta =
      const VerificationMeta('previousReadingDate');
  @override
  late final GeneratedColumn<String> previousReadingDate =
      GeneratedColumn<String>(
        'previous_reading_date',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastReadCycleMeta = const VerificationMeta(
    'lastReadCycle',
  );
  @override
  late final GeneratedColumn<String> lastReadCycle = GeneratedColumn<String>(
    'last_read_cycle',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    consumerNo,
    firstName,
    lastName,
    contactNumber,
    meterSerialNo,
    areaId,
    purok,
    accountStatus,
    previousReadingHundredths,
    previousReadingDate,
    lastReadCycle,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_consumers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedConsumerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('consumer_no')) {
      context.handle(
        _consumerNoMeta,
        consumerNo.isAcceptableOrUnknown(data['consumer_no']!, _consumerNoMeta),
      );
    } else if (isInserting) {
      context.missing(_consumerNoMeta);
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    } else if (isInserting) {
      context.missing(_firstNameMeta);
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    } else if (isInserting) {
      context.missing(_lastNameMeta);
    }
    if (data.containsKey('contact_number')) {
      context.handle(
        _contactNumberMeta,
        contactNumber.isAcceptableOrUnknown(
          data['contact_number']!,
          _contactNumberMeta,
        ),
      );
    }
    if (data.containsKey('meter_serial_no')) {
      context.handle(
        _meterSerialNoMeta,
        meterSerialNo.isAcceptableOrUnknown(
          data['meter_serial_no']!,
          _meterSerialNoMeta,
        ),
      );
    }
    if (data.containsKey('area_id')) {
      context.handle(
        _areaIdMeta,
        areaId.isAcceptableOrUnknown(data['area_id']!, _areaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_areaIdMeta);
    }
    if (data.containsKey('purok')) {
      context.handle(
        _purokMeta,
        purok.isAcceptableOrUnknown(data['purok']!, _purokMeta),
      );
    }
    if (data.containsKey('account_status')) {
      context.handle(
        _accountStatusMeta,
        accountStatus.isAcceptableOrUnknown(
          data['account_status']!,
          _accountStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accountStatusMeta);
    }
    if (data.containsKey('previous_reading_hundredths')) {
      context.handle(
        _previousReadingHundredthsMeta,
        previousReadingHundredths.isAcceptableOrUnknown(
          data['previous_reading_hundredths']!,
          _previousReadingHundredthsMeta,
        ),
      );
    }
    if (data.containsKey('previous_reading_date')) {
      context.handle(
        _previousReadingDateMeta,
        previousReadingDate.isAcceptableOrUnknown(
          data['previous_reading_date']!,
          _previousReadingDateMeta,
        ),
      );
    }
    if (data.containsKey('last_read_cycle')) {
      context.handle(
        _lastReadCycleMeta,
        lastReadCycle.isAcceptableOrUnknown(
          data['last_read_cycle']!,
          _lastReadCycleMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedConsumerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedConsumerRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      consumerNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consumer_no'],
      )!,
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      )!,
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      )!,
      contactNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_number'],
      ),
      meterSerialNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meter_serial_no'],
      ),
      areaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area_id'],
      )!,
      purok: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purok'],
      ),
      accountStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_status'],
      )!,
      previousReadingHundredths: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}previous_reading_hundredths'],
      )!,
      previousReadingDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_reading_date'],
      ),
      lastReadCycle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_read_cycle'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $CachedConsumersTable createAlias(String alias) {
    return $CachedConsumersTable(attachedDatabase, alias);
  }
}

class CachedConsumerRow extends DataClass
    implements Insertable<CachedConsumerRow> {
  final String id;
  final String consumerNo;
  final String firstName;
  final String lastName;
  final String? contactNumber;
  final String? meterSerialNo;
  final String areaId;
  final String? purok;
  final String accountStatus;

  /// MTR-08, in hundredths of a kWh. See the note above.
  final int previousReadingHundredths;
  final String? previousReadingDate;

  /// 'YYYY-MM' in Philippine time. FR-23 checks against this.
  final String? lastReadCycle;
  final String? updatedAt;
  const CachedConsumerRow({
    required this.id,
    required this.consumerNo,
    required this.firstName,
    required this.lastName,
    this.contactNumber,
    this.meterSerialNo,
    required this.areaId,
    this.purok,
    required this.accountStatus,
    required this.previousReadingHundredths,
    this.previousReadingDate,
    this.lastReadCycle,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['consumer_no'] = Variable<String>(consumerNo);
    map['first_name'] = Variable<String>(firstName);
    map['last_name'] = Variable<String>(lastName);
    if (!nullToAbsent || contactNumber != null) {
      map['contact_number'] = Variable<String>(contactNumber);
    }
    if (!nullToAbsent || meterSerialNo != null) {
      map['meter_serial_no'] = Variable<String>(meterSerialNo);
    }
    map['area_id'] = Variable<String>(areaId);
    if (!nullToAbsent || purok != null) {
      map['purok'] = Variable<String>(purok);
    }
    map['account_status'] = Variable<String>(accountStatus);
    map['previous_reading_hundredths'] = Variable<int>(
      previousReadingHundredths,
    );
    if (!nullToAbsent || previousReadingDate != null) {
      map['previous_reading_date'] = Variable<String>(previousReadingDate);
    }
    if (!nullToAbsent || lastReadCycle != null) {
      map['last_read_cycle'] = Variable<String>(lastReadCycle);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<String>(updatedAt);
    }
    return map;
  }

  CachedConsumersCompanion toCompanion(bool nullToAbsent) {
    return CachedConsumersCompanion(
      id: Value(id),
      consumerNo: Value(consumerNo),
      firstName: Value(firstName),
      lastName: Value(lastName),
      contactNumber: contactNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(contactNumber),
      meterSerialNo: meterSerialNo == null && nullToAbsent
          ? const Value.absent()
          : Value(meterSerialNo),
      areaId: Value(areaId),
      purok: purok == null && nullToAbsent
          ? const Value.absent()
          : Value(purok),
      accountStatus: Value(accountStatus),
      previousReadingHundredths: Value(previousReadingHundredths),
      previousReadingDate: previousReadingDate == null && nullToAbsent
          ? const Value.absent()
          : Value(previousReadingDate),
      lastReadCycle: lastReadCycle == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadCycle),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory CachedConsumerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedConsumerRow(
      id: serializer.fromJson<String>(json['id']),
      consumerNo: serializer.fromJson<String>(json['consumerNo']),
      firstName: serializer.fromJson<String>(json['firstName']),
      lastName: serializer.fromJson<String>(json['lastName']),
      contactNumber: serializer.fromJson<String?>(json['contactNumber']),
      meterSerialNo: serializer.fromJson<String?>(json['meterSerialNo']),
      areaId: serializer.fromJson<String>(json['areaId']),
      purok: serializer.fromJson<String?>(json['purok']),
      accountStatus: serializer.fromJson<String>(json['accountStatus']),
      previousReadingHundredths: serializer.fromJson<int>(
        json['previousReadingHundredths'],
      ),
      previousReadingDate: serializer.fromJson<String?>(
        json['previousReadingDate'],
      ),
      lastReadCycle: serializer.fromJson<String?>(json['lastReadCycle']),
      updatedAt: serializer.fromJson<String?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'consumerNo': serializer.toJson<String>(consumerNo),
      'firstName': serializer.toJson<String>(firstName),
      'lastName': serializer.toJson<String>(lastName),
      'contactNumber': serializer.toJson<String?>(contactNumber),
      'meterSerialNo': serializer.toJson<String?>(meterSerialNo),
      'areaId': serializer.toJson<String>(areaId),
      'purok': serializer.toJson<String?>(purok),
      'accountStatus': serializer.toJson<String>(accountStatus),
      'previousReadingHundredths': serializer.toJson<int>(
        previousReadingHundredths,
      ),
      'previousReadingDate': serializer.toJson<String?>(previousReadingDate),
      'lastReadCycle': serializer.toJson<String?>(lastReadCycle),
      'updatedAt': serializer.toJson<String?>(updatedAt),
    };
  }

  CachedConsumerRow copyWith({
    String? id,
    String? consumerNo,
    String? firstName,
    String? lastName,
    Value<String?> contactNumber = const Value.absent(),
    Value<String?> meterSerialNo = const Value.absent(),
    String? areaId,
    Value<String?> purok = const Value.absent(),
    String? accountStatus,
    int? previousReadingHundredths,
    Value<String?> previousReadingDate = const Value.absent(),
    Value<String?> lastReadCycle = const Value.absent(),
    Value<String?> updatedAt = const Value.absent(),
  }) => CachedConsumerRow(
    id: id ?? this.id,
    consumerNo: consumerNo ?? this.consumerNo,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    contactNumber: contactNumber.present
        ? contactNumber.value
        : this.contactNumber,
    meterSerialNo: meterSerialNo.present
        ? meterSerialNo.value
        : this.meterSerialNo,
    areaId: areaId ?? this.areaId,
    purok: purok.present ? purok.value : this.purok,
    accountStatus: accountStatus ?? this.accountStatus,
    previousReadingHundredths:
        previousReadingHundredths ?? this.previousReadingHundredths,
    previousReadingDate: previousReadingDate.present
        ? previousReadingDate.value
        : this.previousReadingDate,
    lastReadCycle: lastReadCycle.present
        ? lastReadCycle.value
        : this.lastReadCycle,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  CachedConsumerRow copyWithCompanion(CachedConsumersCompanion data) {
    return CachedConsumerRow(
      id: data.id.present ? data.id.value : this.id,
      consumerNo: data.consumerNo.present
          ? data.consumerNo.value
          : this.consumerNo,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      contactNumber: data.contactNumber.present
          ? data.contactNumber.value
          : this.contactNumber,
      meterSerialNo: data.meterSerialNo.present
          ? data.meterSerialNo.value
          : this.meterSerialNo,
      areaId: data.areaId.present ? data.areaId.value : this.areaId,
      purok: data.purok.present ? data.purok.value : this.purok,
      accountStatus: data.accountStatus.present
          ? data.accountStatus.value
          : this.accountStatus,
      previousReadingHundredths: data.previousReadingHundredths.present
          ? data.previousReadingHundredths.value
          : this.previousReadingHundredths,
      previousReadingDate: data.previousReadingDate.present
          ? data.previousReadingDate.value
          : this.previousReadingDate,
      lastReadCycle: data.lastReadCycle.present
          ? data.lastReadCycle.value
          : this.lastReadCycle,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedConsumerRow(')
          ..write('id: $id, ')
          ..write('consumerNo: $consumerNo, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('contactNumber: $contactNumber, ')
          ..write('meterSerialNo: $meterSerialNo, ')
          ..write('areaId: $areaId, ')
          ..write('purok: $purok, ')
          ..write('accountStatus: $accountStatus, ')
          ..write('previousReadingHundredths: $previousReadingHundredths, ')
          ..write('previousReadingDate: $previousReadingDate, ')
          ..write('lastReadCycle: $lastReadCycle, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    consumerNo,
    firstName,
    lastName,
    contactNumber,
    meterSerialNo,
    areaId,
    purok,
    accountStatus,
    previousReadingHundredths,
    previousReadingDate,
    lastReadCycle,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedConsumerRow &&
          other.id == this.id &&
          other.consumerNo == this.consumerNo &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.contactNumber == this.contactNumber &&
          other.meterSerialNo == this.meterSerialNo &&
          other.areaId == this.areaId &&
          other.purok == this.purok &&
          other.accountStatus == this.accountStatus &&
          other.previousReadingHundredths == this.previousReadingHundredths &&
          other.previousReadingDate == this.previousReadingDate &&
          other.lastReadCycle == this.lastReadCycle &&
          other.updatedAt == this.updatedAt);
}

class CachedConsumersCompanion extends UpdateCompanion<CachedConsumerRow> {
  final Value<String> id;
  final Value<String> consumerNo;
  final Value<String> firstName;
  final Value<String> lastName;
  final Value<String?> contactNumber;
  final Value<String?> meterSerialNo;
  final Value<String> areaId;
  final Value<String?> purok;
  final Value<String> accountStatus;
  final Value<int> previousReadingHundredths;
  final Value<String?> previousReadingDate;
  final Value<String?> lastReadCycle;
  final Value<String?> updatedAt;
  final Value<int> rowid;
  const CachedConsumersCompanion({
    this.id = const Value.absent(),
    this.consumerNo = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.contactNumber = const Value.absent(),
    this.meterSerialNo = const Value.absent(),
    this.areaId = const Value.absent(),
    this.purok = const Value.absent(),
    this.accountStatus = const Value.absent(),
    this.previousReadingHundredths = const Value.absent(),
    this.previousReadingDate = const Value.absent(),
    this.lastReadCycle = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedConsumersCompanion.insert({
    required String id,
    required String consumerNo,
    required String firstName,
    required String lastName,
    this.contactNumber = const Value.absent(),
    this.meterSerialNo = const Value.absent(),
    required String areaId,
    this.purok = const Value.absent(),
    required String accountStatus,
    this.previousReadingHundredths = const Value.absent(),
    this.previousReadingDate = const Value.absent(),
    this.lastReadCycle = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       consumerNo = Value(consumerNo),
       firstName = Value(firstName),
       lastName = Value(lastName),
       areaId = Value(areaId),
       accountStatus = Value(accountStatus);
  static Insertable<CachedConsumerRow> custom({
    Expression<String>? id,
    Expression<String>? consumerNo,
    Expression<String>? firstName,
    Expression<String>? lastName,
    Expression<String>? contactNumber,
    Expression<String>? meterSerialNo,
    Expression<String>? areaId,
    Expression<String>? purok,
    Expression<String>? accountStatus,
    Expression<int>? previousReadingHundredths,
    Expression<String>? previousReadingDate,
    Expression<String>? lastReadCycle,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (consumerNo != null) 'consumer_no': consumerNo,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (contactNumber != null) 'contact_number': contactNumber,
      if (meterSerialNo != null) 'meter_serial_no': meterSerialNo,
      if (areaId != null) 'area_id': areaId,
      if (purok != null) 'purok': purok,
      if (accountStatus != null) 'account_status': accountStatus,
      if (previousReadingHundredths != null)
        'previous_reading_hundredths': previousReadingHundredths,
      if (previousReadingDate != null)
        'previous_reading_date': previousReadingDate,
      if (lastReadCycle != null) 'last_read_cycle': lastReadCycle,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedConsumersCompanion copyWith({
    Value<String>? id,
    Value<String>? consumerNo,
    Value<String>? firstName,
    Value<String>? lastName,
    Value<String?>? contactNumber,
    Value<String?>? meterSerialNo,
    Value<String>? areaId,
    Value<String?>? purok,
    Value<String>? accountStatus,
    Value<int>? previousReadingHundredths,
    Value<String?>? previousReadingDate,
    Value<String?>? lastReadCycle,
    Value<String?>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedConsumersCompanion(
      id: id ?? this.id,
      consumerNo: consumerNo ?? this.consumerNo,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      contactNumber: contactNumber ?? this.contactNumber,
      meterSerialNo: meterSerialNo ?? this.meterSerialNo,
      areaId: areaId ?? this.areaId,
      purok: purok ?? this.purok,
      accountStatus: accountStatus ?? this.accountStatus,
      previousReadingHundredths:
          previousReadingHundredths ?? this.previousReadingHundredths,
      previousReadingDate: previousReadingDate ?? this.previousReadingDate,
      lastReadCycle: lastReadCycle ?? this.lastReadCycle,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (consumerNo.present) {
      map['consumer_no'] = Variable<String>(consumerNo.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (contactNumber.present) {
      map['contact_number'] = Variable<String>(contactNumber.value);
    }
    if (meterSerialNo.present) {
      map['meter_serial_no'] = Variable<String>(meterSerialNo.value);
    }
    if (areaId.present) {
      map['area_id'] = Variable<String>(areaId.value);
    }
    if (purok.present) {
      map['purok'] = Variable<String>(purok.value);
    }
    if (accountStatus.present) {
      map['account_status'] = Variable<String>(accountStatus.value);
    }
    if (previousReadingHundredths.present) {
      map['previous_reading_hundredths'] = Variable<int>(
        previousReadingHundredths.value,
      );
    }
    if (previousReadingDate.present) {
      map['previous_reading_date'] = Variable<String>(
        previousReadingDate.value,
      );
    }
    if (lastReadCycle.present) {
      map['last_read_cycle'] = Variable<String>(lastReadCycle.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedConsumersCompanion(')
          ..write('id: $id, ')
          ..write('consumerNo: $consumerNo, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('contactNumber: $contactNumber, ')
          ..write('meterSerialNo: $meterSerialNo, ')
          ..write('areaId: $areaId, ')
          ..write('purok: $purok, ')
          ..write('accountStatus: $accountStatus, ')
          ..write('previousReadingHundredths: $previousReadingHundredths, ')
          ..write('previousReadingDate: $previousReadingDate, ')
          ..write('lastReadCycle: $lastReadCycle, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedBillsTable extends CachedBills
    with TableInfo<$CachedBillsTable, CachedBillRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedBillsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _billNoMeta = const VerificationMeta('billNo');
  @override
  late final GeneratedColumn<String> billNo = GeneratedColumn<String>(
    'bill_no',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _consumerIdMeta = const VerificationMeta(
    'consumerId',
  );
  @override
  late final GeneratedColumn<String> consumerId = GeneratedColumn<String>(
    'consumer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cycleLabelMeta = const VerificationMeta(
    'cycleLabel',
  );
  @override
  late final GeneratedColumn<String> cycleLabel = GeneratedColumn<String>(
    'cycle_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _consumptionHundredthsMeta =
      const VerificationMeta('consumptionHundredths');
  @override
  late final GeneratedColumn<int> consumptionHundredths = GeneratedColumn<int>(
    'consumption_hundredths',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountPaidCentavosMeta =
      const VerificationMeta('amountPaidCentavos');
  @override
  late final GeneratedColumn<int> amountPaidCentavos = GeneratedColumn<int>(
    'amount_paid_centavos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalAmountCentavosMeta =
      const VerificationMeta('totalAmountCentavos');
  @override
  late final GeneratedColumn<int> totalAmountCentavos = GeneratedColumn<int>(
    'total_amount_centavos',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _generatedAtMeta = const VerificationMeta(
    'generatedAt',
  );
  @override
  late final GeneratedColumn<String> generatedAt = GeneratedColumn<String>(
    'generated_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    billNo,
    consumerId,
    cycleLabel,
    consumptionHundredths,
    amountPaidCentavos,
    totalAmountCentavos,
    dueDate,
    generatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_bills';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedBillRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('bill_no')) {
      context.handle(
        _billNoMeta,
        billNo.isAcceptableOrUnknown(data['bill_no']!, _billNoMeta),
      );
    } else if (isInserting) {
      context.missing(_billNoMeta);
    }
    if (data.containsKey('consumer_id')) {
      context.handle(
        _consumerIdMeta,
        consumerId.isAcceptableOrUnknown(data['consumer_id']!, _consumerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_consumerIdMeta);
    }
    if (data.containsKey('cycle_label')) {
      context.handle(
        _cycleLabelMeta,
        cycleLabel.isAcceptableOrUnknown(data['cycle_label']!, _cycleLabelMeta),
      );
    } else if (isInserting) {
      context.missing(_cycleLabelMeta);
    }
    if (data.containsKey('consumption_hundredths')) {
      context.handle(
        _consumptionHundredthsMeta,
        consumptionHundredths.isAcceptableOrUnknown(
          data['consumption_hundredths']!,
          _consumptionHundredthsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_consumptionHundredthsMeta);
    }
    if (data.containsKey('amount_paid_centavos')) {
      context.handle(
        _amountPaidCentavosMeta,
        amountPaidCentavos.isAcceptableOrUnknown(
          data['amount_paid_centavos']!,
          _amountPaidCentavosMeta,
        ),
      );
    }
    if (data.containsKey('total_amount_centavos')) {
      context.handle(
        _totalAmountCentavosMeta,
        totalAmountCentavos.isAcceptableOrUnknown(
          data['total_amount_centavos']!,
          _totalAmountCentavosMeta,
        ),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('generated_at')) {
      context.handle(
        _generatedAtMeta,
        generatedAt.isAcceptableOrUnknown(
          data['generated_at']!,
          _generatedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedBillRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedBillRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      billNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bill_no'],
      )!,
      consumerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consumer_id'],
      )!,
      cycleLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cycle_label'],
      )!,
      consumptionHundredths: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}consumption_hundredths'],
      )!,
      amountPaidCentavos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paid_centavos'],
      )!,
      totalAmountCentavos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_amount_centavos'],
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_date'],
      ),
      generatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}generated_at'],
      ),
    );
  }

  @override
  $CachedBillsTable createAlias(String alias) {
    return $CachedBillsTable(attachedDatabase, alias);
  }
}

class CachedBillRow extends DataClass implements Insertable<CachedBillRow> {
  final String id;
  final String billNo;
  final String consumerId;
  final String cycleLabel;
  final int consumptionHundredths;
  final int amountPaidCentavos;

  /// NULL until the cooperative amount is posted (FR-21b). CON-07 still has
  /// to show the reading and the consumption during that seven-day window,
  /// which is why an unpriced bill is cached rather than skipped.
  final int? totalAmountCentavos;
  final String? dueDate;
  final String? generatedAt;
  const CachedBillRow({
    required this.id,
    required this.billNo,
    required this.consumerId,
    required this.cycleLabel,
    required this.consumptionHundredths,
    required this.amountPaidCentavos,
    this.totalAmountCentavos,
    this.dueDate,
    this.generatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['bill_no'] = Variable<String>(billNo);
    map['consumer_id'] = Variable<String>(consumerId);
    map['cycle_label'] = Variable<String>(cycleLabel);
    map['consumption_hundredths'] = Variable<int>(consumptionHundredths);
    map['amount_paid_centavos'] = Variable<int>(amountPaidCentavos);
    if (!nullToAbsent || totalAmountCentavos != null) {
      map['total_amount_centavos'] = Variable<int>(totalAmountCentavos);
    }
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<String>(dueDate);
    }
    if (!nullToAbsent || generatedAt != null) {
      map['generated_at'] = Variable<String>(generatedAt);
    }
    return map;
  }

  CachedBillsCompanion toCompanion(bool nullToAbsent) {
    return CachedBillsCompanion(
      id: Value(id),
      billNo: Value(billNo),
      consumerId: Value(consumerId),
      cycleLabel: Value(cycleLabel),
      consumptionHundredths: Value(consumptionHundredths),
      amountPaidCentavos: Value(amountPaidCentavos),
      totalAmountCentavos: totalAmountCentavos == null && nullToAbsent
          ? const Value.absent()
          : Value(totalAmountCentavos),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      generatedAt: generatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(generatedAt),
    );
  }

  factory CachedBillRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedBillRow(
      id: serializer.fromJson<String>(json['id']),
      billNo: serializer.fromJson<String>(json['billNo']),
      consumerId: serializer.fromJson<String>(json['consumerId']),
      cycleLabel: serializer.fromJson<String>(json['cycleLabel']),
      consumptionHundredths: serializer.fromJson<int>(
        json['consumptionHundredths'],
      ),
      amountPaidCentavos: serializer.fromJson<int>(json['amountPaidCentavos']),
      totalAmountCentavos: serializer.fromJson<int?>(
        json['totalAmountCentavos'],
      ),
      dueDate: serializer.fromJson<String?>(json['dueDate']),
      generatedAt: serializer.fromJson<String?>(json['generatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'billNo': serializer.toJson<String>(billNo),
      'consumerId': serializer.toJson<String>(consumerId),
      'cycleLabel': serializer.toJson<String>(cycleLabel),
      'consumptionHundredths': serializer.toJson<int>(consumptionHundredths),
      'amountPaidCentavos': serializer.toJson<int>(amountPaidCentavos),
      'totalAmountCentavos': serializer.toJson<int?>(totalAmountCentavos),
      'dueDate': serializer.toJson<String?>(dueDate),
      'generatedAt': serializer.toJson<String?>(generatedAt),
    };
  }

  CachedBillRow copyWith({
    String? id,
    String? billNo,
    String? consumerId,
    String? cycleLabel,
    int? consumptionHundredths,
    int? amountPaidCentavos,
    Value<int?> totalAmountCentavos = const Value.absent(),
    Value<String?> dueDate = const Value.absent(),
    Value<String?> generatedAt = const Value.absent(),
  }) => CachedBillRow(
    id: id ?? this.id,
    billNo: billNo ?? this.billNo,
    consumerId: consumerId ?? this.consumerId,
    cycleLabel: cycleLabel ?? this.cycleLabel,
    consumptionHundredths: consumptionHundredths ?? this.consumptionHundredths,
    amountPaidCentavos: amountPaidCentavos ?? this.amountPaidCentavos,
    totalAmountCentavos: totalAmountCentavos.present
        ? totalAmountCentavos.value
        : this.totalAmountCentavos,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    generatedAt: generatedAt.present ? generatedAt.value : this.generatedAt,
  );
  CachedBillRow copyWithCompanion(CachedBillsCompanion data) {
    return CachedBillRow(
      id: data.id.present ? data.id.value : this.id,
      billNo: data.billNo.present ? data.billNo.value : this.billNo,
      consumerId: data.consumerId.present
          ? data.consumerId.value
          : this.consumerId,
      cycleLabel: data.cycleLabel.present
          ? data.cycleLabel.value
          : this.cycleLabel,
      consumptionHundredths: data.consumptionHundredths.present
          ? data.consumptionHundredths.value
          : this.consumptionHundredths,
      amountPaidCentavos: data.amountPaidCentavos.present
          ? data.amountPaidCentavos.value
          : this.amountPaidCentavos,
      totalAmountCentavos: data.totalAmountCentavos.present
          ? data.totalAmountCentavos.value
          : this.totalAmountCentavos,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      generatedAt: data.generatedAt.present
          ? data.generatedAt.value
          : this.generatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedBillRow(')
          ..write('id: $id, ')
          ..write('billNo: $billNo, ')
          ..write('consumerId: $consumerId, ')
          ..write('cycleLabel: $cycleLabel, ')
          ..write('consumptionHundredths: $consumptionHundredths, ')
          ..write('amountPaidCentavos: $amountPaidCentavos, ')
          ..write('totalAmountCentavos: $totalAmountCentavos, ')
          ..write('dueDate: $dueDate, ')
          ..write('generatedAt: $generatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    billNo,
    consumerId,
    cycleLabel,
    consumptionHundredths,
    amountPaidCentavos,
    totalAmountCentavos,
    dueDate,
    generatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedBillRow &&
          other.id == this.id &&
          other.billNo == this.billNo &&
          other.consumerId == this.consumerId &&
          other.cycleLabel == this.cycleLabel &&
          other.consumptionHundredths == this.consumptionHundredths &&
          other.amountPaidCentavos == this.amountPaidCentavos &&
          other.totalAmountCentavos == this.totalAmountCentavos &&
          other.dueDate == this.dueDate &&
          other.generatedAt == this.generatedAt);
}

class CachedBillsCompanion extends UpdateCompanion<CachedBillRow> {
  final Value<String> id;
  final Value<String> billNo;
  final Value<String> consumerId;
  final Value<String> cycleLabel;
  final Value<int> consumptionHundredths;
  final Value<int> amountPaidCentavos;
  final Value<int?> totalAmountCentavos;
  final Value<String?> dueDate;
  final Value<String?> generatedAt;
  final Value<int> rowid;
  const CachedBillsCompanion({
    this.id = const Value.absent(),
    this.billNo = const Value.absent(),
    this.consumerId = const Value.absent(),
    this.cycleLabel = const Value.absent(),
    this.consumptionHundredths = const Value.absent(),
    this.amountPaidCentavos = const Value.absent(),
    this.totalAmountCentavos = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.generatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedBillsCompanion.insert({
    required String id,
    required String billNo,
    required String consumerId,
    required String cycleLabel,
    required int consumptionHundredths,
    this.amountPaidCentavos = const Value.absent(),
    this.totalAmountCentavos = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.generatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       billNo = Value(billNo),
       consumerId = Value(consumerId),
       cycleLabel = Value(cycleLabel),
       consumptionHundredths = Value(consumptionHundredths);
  static Insertable<CachedBillRow> custom({
    Expression<String>? id,
    Expression<String>? billNo,
    Expression<String>? consumerId,
    Expression<String>? cycleLabel,
    Expression<int>? consumptionHundredths,
    Expression<int>? amountPaidCentavos,
    Expression<int>? totalAmountCentavos,
    Expression<String>? dueDate,
    Expression<String>? generatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (billNo != null) 'bill_no': billNo,
      if (consumerId != null) 'consumer_id': consumerId,
      if (cycleLabel != null) 'cycle_label': cycleLabel,
      if (consumptionHundredths != null)
        'consumption_hundredths': consumptionHundredths,
      if (amountPaidCentavos != null)
        'amount_paid_centavos': amountPaidCentavos,
      if (totalAmountCentavos != null)
        'total_amount_centavos': totalAmountCentavos,
      if (dueDate != null) 'due_date': dueDate,
      if (generatedAt != null) 'generated_at': generatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedBillsCompanion copyWith({
    Value<String>? id,
    Value<String>? billNo,
    Value<String>? consumerId,
    Value<String>? cycleLabel,
    Value<int>? consumptionHundredths,
    Value<int>? amountPaidCentavos,
    Value<int?>? totalAmountCentavos,
    Value<String?>? dueDate,
    Value<String?>? generatedAt,
    Value<int>? rowid,
  }) {
    return CachedBillsCompanion(
      id: id ?? this.id,
      billNo: billNo ?? this.billNo,
      consumerId: consumerId ?? this.consumerId,
      cycleLabel: cycleLabel ?? this.cycleLabel,
      consumptionHundredths:
          consumptionHundredths ?? this.consumptionHundredths,
      amountPaidCentavos: amountPaidCentavos ?? this.amountPaidCentavos,
      totalAmountCentavos: totalAmountCentavos ?? this.totalAmountCentavos,
      dueDate: dueDate ?? this.dueDate,
      generatedAt: generatedAt ?? this.generatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (billNo.present) {
      map['bill_no'] = Variable<String>(billNo.value);
    }
    if (consumerId.present) {
      map['consumer_id'] = Variable<String>(consumerId.value);
    }
    if (cycleLabel.present) {
      map['cycle_label'] = Variable<String>(cycleLabel.value);
    }
    if (consumptionHundredths.present) {
      map['consumption_hundredths'] = Variable<int>(
        consumptionHundredths.value,
      );
    }
    if (amountPaidCentavos.present) {
      map['amount_paid_centavos'] = Variable<int>(amountPaidCentavos.value);
    }
    if (totalAmountCentavos.present) {
      map['total_amount_centavos'] = Variable<int>(totalAmountCentavos.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (generatedAt.present) {
      map['generated_at'] = Variable<String>(generatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedBillsCompanion(')
          ..write('id: $id, ')
          ..write('billNo: $billNo, ')
          ..write('consumerId: $consumerId, ')
          ..write('cycleLabel: $cycleLabel, ')
          ..write('consumptionHundredths: $consumptionHundredths, ')
          ..write('amountPaidCentavos: $amountPaidCentavos, ')
          ..write('totalAmountCentavos: $totalAmountCentavos, ')
          ..write('dueDate: $dueDate, ')
          ..write('generatedAt: $generatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPaymentsTable extends CachedPayments
    with TableInfo<$CachedPaymentsTable, CachedPaymentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _billIdMeta = const VerificationMeta('billId');
  @override
  late final GeneratedColumn<String> billId = GeneratedColumn<String>(
    'bill_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receiptNoMeta = const VerificationMeta(
    'receiptNo',
  );
  @override
  late final GeneratedColumn<String> receiptNo = GeneratedColumn<String>(
    'receipt_no',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountPaidCentavosMeta =
      const VerificationMeta('amountPaidCentavos');
  @override
  late final GeneratedColumn<int> amountPaidCentavos = GeneratedColumn<int>(
    'amount_paid_centavos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paidAtMeta = const VerificationMeta('paidAt');
  @override
  late final GeneratedColumn<String> paidAt = GeneratedColumn<String>(
    'paid_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    billId,
    receiptNo,
    amountPaidCentavos,
    paidAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPaymentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('bill_id')) {
      context.handle(
        _billIdMeta,
        billId.isAcceptableOrUnknown(data['bill_id']!, _billIdMeta),
      );
    }
    if (data.containsKey('receipt_no')) {
      context.handle(
        _receiptNoMeta,
        receiptNo.isAcceptableOrUnknown(data['receipt_no']!, _receiptNoMeta),
      );
    } else if (isInserting) {
      context.missing(_receiptNoMeta);
    }
    if (data.containsKey('amount_paid_centavos')) {
      context.handle(
        _amountPaidCentavosMeta,
        amountPaidCentavos.isAcceptableOrUnknown(
          data['amount_paid_centavos']!,
          _amountPaidCentavosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaidCentavosMeta);
    }
    if (data.containsKey('paid_at')) {
      context.handle(
        _paidAtMeta,
        paidAt.isAcceptableOrUnknown(data['paid_at']!, _paidAtMeta),
      );
    } else if (isInserting) {
      context.missing(_paidAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedPaymentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPaymentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      billId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bill_id'],
      ),
      receiptNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_no'],
      )!,
      amountPaidCentavos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paid_centavos'],
      )!,
      paidAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}paid_at'],
      )!,
    );
  }

  @override
  $CachedPaymentsTable createAlias(String alias) {
    return $CachedPaymentsTable(attachedDatabase, alias);
  }
}

class CachedPaymentRow extends DataClass
    implements Insertable<CachedPaymentRow> {
  final String id;
  final String? billId;
  final String receiptNo;
  final int amountPaidCentavos;
  final String paidAt;
  const CachedPaymentRow({
    required this.id,
    this.billId,
    required this.receiptNo,
    required this.amountPaidCentavos,
    required this.paidAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || billId != null) {
      map['bill_id'] = Variable<String>(billId);
    }
    map['receipt_no'] = Variable<String>(receiptNo);
    map['amount_paid_centavos'] = Variable<int>(amountPaidCentavos);
    map['paid_at'] = Variable<String>(paidAt);
    return map;
  }

  CachedPaymentsCompanion toCompanion(bool nullToAbsent) {
    return CachedPaymentsCompanion(
      id: Value(id),
      billId: billId == null && nullToAbsent
          ? const Value.absent()
          : Value(billId),
      receiptNo: Value(receiptNo),
      amountPaidCentavos: Value(amountPaidCentavos),
      paidAt: Value(paidAt),
    );
  }

  factory CachedPaymentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPaymentRow(
      id: serializer.fromJson<String>(json['id']),
      billId: serializer.fromJson<String?>(json['billId']),
      receiptNo: serializer.fromJson<String>(json['receiptNo']),
      amountPaidCentavos: serializer.fromJson<int>(json['amountPaidCentavos']),
      paidAt: serializer.fromJson<String>(json['paidAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'billId': serializer.toJson<String?>(billId),
      'receiptNo': serializer.toJson<String>(receiptNo),
      'amountPaidCentavos': serializer.toJson<int>(amountPaidCentavos),
      'paidAt': serializer.toJson<String>(paidAt),
    };
  }

  CachedPaymentRow copyWith({
    String? id,
    Value<String?> billId = const Value.absent(),
    String? receiptNo,
    int? amountPaidCentavos,
    String? paidAt,
  }) => CachedPaymentRow(
    id: id ?? this.id,
    billId: billId.present ? billId.value : this.billId,
    receiptNo: receiptNo ?? this.receiptNo,
    amountPaidCentavos: amountPaidCentavos ?? this.amountPaidCentavos,
    paidAt: paidAt ?? this.paidAt,
  );
  CachedPaymentRow copyWithCompanion(CachedPaymentsCompanion data) {
    return CachedPaymentRow(
      id: data.id.present ? data.id.value : this.id,
      billId: data.billId.present ? data.billId.value : this.billId,
      receiptNo: data.receiptNo.present ? data.receiptNo.value : this.receiptNo,
      amountPaidCentavos: data.amountPaidCentavos.present
          ? data.amountPaidCentavos.value
          : this.amountPaidCentavos,
      paidAt: data.paidAt.present ? data.paidAt.value : this.paidAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPaymentRow(')
          ..write('id: $id, ')
          ..write('billId: $billId, ')
          ..write('receiptNo: $receiptNo, ')
          ..write('amountPaidCentavos: $amountPaidCentavos, ')
          ..write('paidAt: $paidAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, billId, receiptNo, amountPaidCentavos, paidAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPaymentRow &&
          other.id == this.id &&
          other.billId == this.billId &&
          other.receiptNo == this.receiptNo &&
          other.amountPaidCentavos == this.amountPaidCentavos &&
          other.paidAt == this.paidAt);
}

class CachedPaymentsCompanion extends UpdateCompanion<CachedPaymentRow> {
  final Value<String> id;
  final Value<String?> billId;
  final Value<String> receiptNo;
  final Value<int> amountPaidCentavos;
  final Value<String> paidAt;
  final Value<int> rowid;
  const CachedPaymentsCompanion({
    this.id = const Value.absent(),
    this.billId = const Value.absent(),
    this.receiptNo = const Value.absent(),
    this.amountPaidCentavos = const Value.absent(),
    this.paidAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPaymentsCompanion.insert({
    required String id,
    this.billId = const Value.absent(),
    required String receiptNo,
    required int amountPaidCentavos,
    required String paidAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       receiptNo = Value(receiptNo),
       amountPaidCentavos = Value(amountPaidCentavos),
       paidAt = Value(paidAt);
  static Insertable<CachedPaymentRow> custom({
    Expression<String>? id,
    Expression<String>? billId,
    Expression<String>? receiptNo,
    Expression<int>? amountPaidCentavos,
    Expression<String>? paidAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (billId != null) 'bill_id': billId,
      if (receiptNo != null) 'receipt_no': receiptNo,
      if (amountPaidCentavos != null)
        'amount_paid_centavos': amountPaidCentavos,
      if (paidAt != null) 'paid_at': paidAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPaymentsCompanion copyWith({
    Value<String>? id,
    Value<String?>? billId,
    Value<String>? receiptNo,
    Value<int>? amountPaidCentavos,
    Value<String>? paidAt,
    Value<int>? rowid,
  }) {
    return CachedPaymentsCompanion(
      id: id ?? this.id,
      billId: billId ?? this.billId,
      receiptNo: receiptNo ?? this.receiptNo,
      amountPaidCentavos: amountPaidCentavos ?? this.amountPaidCentavos,
      paidAt: paidAt ?? this.paidAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (billId.present) {
      map['bill_id'] = Variable<String>(billId.value);
    }
    if (receiptNo.present) {
      map['receipt_no'] = Variable<String>(receiptNo.value);
    }
    if (amountPaidCentavos.present) {
      map['amount_paid_centavos'] = Variable<int>(amountPaidCentavos.value);
    }
    if (paidAt.present) {
      map['paid_at'] = Variable<String>(paidAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPaymentsCompanion(')
          ..write('id: $id, ')
          ..write('billId: $billId, ')
          ..write('receiptNo: $receiptNo, ')
          ..write('amountPaidCentavos: $amountPaidCentavos, ')
          ..write('paidAt: $paidAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedNotificationsTable extends CachedNotifications
    with TableInfo<$CachedNotificationsTable, CachedNotificationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedNotificationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notifTypeMeta = const VerificationMeta(
    'notifType',
  );
  @override
  late final GeneratedColumn<String> notifType = GeneratedColumn<String>(
    'notif_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
    'is_read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    notifType,
    channel,
    message,
    status,
    isRead,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_notifications';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedNotificationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('notif_type')) {
      context.handle(
        _notifTypeMeta,
        notifType.isAcceptableOrUnknown(data['notif_type']!, _notifTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_notifTypeMeta);
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    } else if (isInserting) {
      context.missing(_channelMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('is_read')) {
      context.handle(
        _isReadMeta,
        isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedNotificationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedNotificationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      notifType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notif_type'],
      )!,
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      isRead: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_read'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CachedNotificationsTable createAlias(String alias) {
    return $CachedNotificationsTable(attachedDatabase, alias);
  }
}

class CachedNotificationRow extends DataClass
    implements Insertable<CachedNotificationRow> {
  final String id;
  final String notifType;
  final String channel;
  final String message;
  final String status;
  final bool isRead;
  final String createdAt;
  const CachedNotificationRow({
    required this.id,
    required this.notifType,
    required this.channel,
    required this.message,
    required this.status,
    required this.isRead,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['notif_type'] = Variable<String>(notifType);
    map['channel'] = Variable<String>(channel);
    map['message'] = Variable<String>(message);
    map['status'] = Variable<String>(status);
    map['is_read'] = Variable<bool>(isRead);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  CachedNotificationsCompanion toCompanion(bool nullToAbsent) {
    return CachedNotificationsCompanion(
      id: Value(id),
      notifType: Value(notifType),
      channel: Value(channel),
      message: Value(message),
      status: Value(status),
      isRead: Value(isRead),
      createdAt: Value(createdAt),
    );
  }

  factory CachedNotificationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedNotificationRow(
      id: serializer.fromJson<String>(json['id']),
      notifType: serializer.fromJson<String>(json['notifType']),
      channel: serializer.fromJson<String>(json['channel']),
      message: serializer.fromJson<String>(json['message']),
      status: serializer.fromJson<String>(json['status']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'notifType': serializer.toJson<String>(notifType),
      'channel': serializer.toJson<String>(channel),
      'message': serializer.toJson<String>(message),
      'status': serializer.toJson<String>(status),
      'isRead': serializer.toJson<bool>(isRead),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  CachedNotificationRow copyWith({
    String? id,
    String? notifType,
    String? channel,
    String? message,
    String? status,
    bool? isRead,
    String? createdAt,
  }) => CachedNotificationRow(
    id: id ?? this.id,
    notifType: notifType ?? this.notifType,
    channel: channel ?? this.channel,
    message: message ?? this.message,
    status: status ?? this.status,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt ?? this.createdAt,
  );
  CachedNotificationRow copyWithCompanion(CachedNotificationsCompanion data) {
    return CachedNotificationRow(
      id: data.id.present ? data.id.value : this.id,
      notifType: data.notifType.present ? data.notifType.value : this.notifType,
      channel: data.channel.present ? data.channel.value : this.channel,
      message: data.message.present ? data.message.value : this.message,
      status: data.status.present ? data.status.value : this.status,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedNotificationRow(')
          ..write('id: $id, ')
          ..write('notifType: $notifType, ')
          ..write('channel: $channel, ')
          ..write('message: $message, ')
          ..write('status: $status, ')
          ..write('isRead: $isRead, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, notifType, channel, message, status, isRead, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedNotificationRow &&
          other.id == this.id &&
          other.notifType == this.notifType &&
          other.channel == this.channel &&
          other.message == this.message &&
          other.status == this.status &&
          other.isRead == this.isRead &&
          other.createdAt == this.createdAt);
}

class CachedNotificationsCompanion
    extends UpdateCompanion<CachedNotificationRow> {
  final Value<String> id;
  final Value<String> notifType;
  final Value<String> channel;
  final Value<String> message;
  final Value<String> status;
  final Value<bool> isRead;
  final Value<String> createdAt;
  final Value<int> rowid;
  const CachedNotificationsCompanion({
    this.id = const Value.absent(),
    this.notifType = const Value.absent(),
    this.channel = const Value.absent(),
    this.message = const Value.absent(),
    this.status = const Value.absent(),
    this.isRead = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedNotificationsCompanion.insert({
    required String id,
    required String notifType,
    required String channel,
    required String message,
    required String status,
    this.isRead = const Value.absent(),
    required String createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       notifType = Value(notifType),
       channel = Value(channel),
       message = Value(message),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<CachedNotificationRow> custom({
    Expression<String>? id,
    Expression<String>? notifType,
    Expression<String>? channel,
    Expression<String>? message,
    Expression<String>? status,
    Expression<bool>? isRead,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (notifType != null) 'notif_type': notifType,
      if (channel != null) 'channel': channel,
      if (message != null) 'message': message,
      if (status != null) 'status': status,
      if (isRead != null) 'is_read': isRead,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedNotificationsCompanion copyWith({
    Value<String>? id,
    Value<String>? notifType,
    Value<String>? channel,
    Value<String>? message,
    Value<String>? status,
    Value<bool>? isRead,
    Value<String>? createdAt,
    Value<int>? rowid,
  }) {
    return CachedNotificationsCompanion(
      id: id ?? this.id,
      notifType: notifType ?? this.notifType,
      channel: channel ?? this.channel,
      message: message ?? this.message,
      status: status ?? this.status,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (notifType.present) {
      map['notif_type'] = Variable<String>(notifType.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedNotificationsCompanion(')
          ..write('id: $id, ')
          ..write('notifType: $notifType, ')
          ..write('channel: $channel, ')
          ..write('message: $message, ')
          ..write('status: $status, ')
          ..write('isRead: $isRead, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CacheOwnerTable extends CacheOwner
    with TableInfo<$CacheOwnerTable, CacheOwnerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheOwnerTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaIdMeta = const VerificationMeta('areaId');
  @override
  late final GeneratedColumn<String> areaId = GeneratedColumn<String>(
    'area_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<String> cachedAt = GeneratedColumn<String>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, profileId, role, areaId, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_owner';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheOwnerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('area_id')) {
      context.handle(
        _areaIdMeta,
        areaId.isAcceptableOrUnknown(data['area_id']!, _areaIdMeta),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CacheOwnerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheOwnerRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      areaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area_id'],
      ),
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CacheOwnerTable createAlias(String alias) {
    return $CacheOwnerTable(attachedDatabase, alias);
  }
}

class CacheOwnerRow extends DataClass implements Insertable<CacheOwnerRow> {
  final int id;
  final String profileId;
  final String role;
  final String? areaId;
  final String cachedAt;
  const CacheOwnerRow({
    required this.id,
    required this.profileId,
    required this.role,
    this.areaId,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['role'] = Variable<String>(role);
    if (!nullToAbsent || areaId != null) {
      map['area_id'] = Variable<String>(areaId);
    }
    map['cached_at'] = Variable<String>(cachedAt);
    return map;
  }

  CacheOwnerCompanion toCompanion(bool nullToAbsent) {
    return CacheOwnerCompanion(
      id: Value(id),
      profileId: Value(profileId),
      role: Value(role),
      areaId: areaId == null && nullToAbsent
          ? const Value.absent()
          : Value(areaId),
      cachedAt: Value(cachedAt),
    );
  }

  factory CacheOwnerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheOwnerRow(
      id: serializer.fromJson<int>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      role: serializer.fromJson<String>(json['role']),
      areaId: serializer.fromJson<String?>(json['areaId']),
      cachedAt: serializer.fromJson<String>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'profileId': serializer.toJson<String>(profileId),
      'role': serializer.toJson<String>(role),
      'areaId': serializer.toJson<String?>(areaId),
      'cachedAt': serializer.toJson<String>(cachedAt),
    };
  }

  CacheOwnerRow copyWith({
    int? id,
    String? profileId,
    String? role,
    Value<String?> areaId = const Value.absent(),
    String? cachedAt,
  }) => CacheOwnerRow(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    role: role ?? this.role,
    areaId: areaId.present ? areaId.value : this.areaId,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CacheOwnerRow copyWithCompanion(CacheOwnerCompanion data) {
    return CacheOwnerRow(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      role: data.role.present ? data.role.value : this.role,
      areaId: data.areaId.present ? data.areaId.value : this.areaId,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheOwnerRow(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('role: $role, ')
          ..write('areaId: $areaId, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, profileId, role, areaId, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheOwnerRow &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.role == this.role &&
          other.areaId == this.areaId &&
          other.cachedAt == this.cachedAt);
}

class CacheOwnerCompanion extends UpdateCompanion<CacheOwnerRow> {
  final Value<int> id;
  final Value<String> profileId;
  final Value<String> role;
  final Value<String?> areaId;
  final Value<String> cachedAt;
  const CacheOwnerCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.role = const Value.absent(),
    this.areaId = const Value.absent(),
    this.cachedAt = const Value.absent(),
  });
  CacheOwnerCompanion.insert({
    this.id = const Value.absent(),
    required String profileId,
    required String role,
    this.areaId = const Value.absent(),
    required String cachedAt,
  }) : profileId = Value(profileId),
       role = Value(role),
       cachedAt = Value(cachedAt);
  static Insertable<CacheOwnerRow> custom({
    Expression<int>? id,
    Expression<String>? profileId,
    Expression<String>? role,
    Expression<String>? areaId,
    Expression<String>? cachedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (role != null) 'role': role,
      if (areaId != null) 'area_id': areaId,
      if (cachedAt != null) 'cached_at': cachedAt,
    });
  }

  CacheOwnerCompanion copyWith({
    Value<int>? id,
    Value<String>? profileId,
    Value<String>? role,
    Value<String?>? areaId,
    Value<String>? cachedAt,
  }) {
    return CacheOwnerCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      role: role ?? this.role,
      areaId: areaId ?? this.areaId,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (areaId.present) {
      map['area_id'] = Variable<String>(areaId.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<String>(cachedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheOwnerCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('role: $role, ')
          ..write('areaId: $areaId, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tableName_Meta = const VerificationMeta(
    'tableName_',
  );
  @override
  late final GeneratedColumn<String> tableName_ = GeneratedColumn<String>(
    'table_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastRefreshedAtMeta = const VerificationMeta(
    'lastRefreshedAt',
  );
  @override
  late final GeneratedColumn<String> lastRefreshedAt = GeneratedColumn<String>(
    'last_refreshed_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<String> lastAttemptAt = GeneratedColumn<String>(
    'last_attempt_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    tableName_,
    lastRefreshedAt,
    lastAttemptAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('table_name')) {
      context.handle(
        _tableName_Meta,
        tableName_.isAcceptableOrUnknown(data['table_name']!, _tableName_Meta),
      );
    } else if (isInserting) {
      context.missing(_tableName_Meta);
    }
    if (data.containsKey('last_refreshed_at')) {
      context.handle(
        _lastRefreshedAtMeta,
        lastRefreshedAt.isAcceptableOrUnknown(
          data['last_refreshed_at']!,
          _lastRefreshedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tableName_};
  @override
  SyncMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaRow(
      tableName_: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}table_name'],
      )!,
      lastRefreshedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_refreshed_at'],
      ),
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaRow extends DataClass implements Insertable<SyncMetaRow> {
  final String tableName_;
  final String? lastRefreshedAt;
  final String? lastAttemptAt;
  final String? lastError;
  const SyncMetaRow({
    required this.tableName_,
    this.lastRefreshedAt,
    this.lastAttemptAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['table_name'] = Variable<String>(tableName_);
    if (!nullToAbsent || lastRefreshedAt != null) {
      map['last_refreshed_at'] = Variable<String>(lastRefreshedAt);
    }
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<String>(lastAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(
      tableName_: Value(tableName_),
      lastRefreshedAt: lastRefreshedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRefreshedAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory SyncMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaRow(
      tableName_: serializer.fromJson<String>(json['tableName_']),
      lastRefreshedAt: serializer.fromJson<String?>(json['lastRefreshedAt']),
      lastAttemptAt: serializer.fromJson<String?>(json['lastAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tableName_': serializer.toJson<String>(tableName_),
      'lastRefreshedAt': serializer.toJson<String?>(lastRefreshedAt),
      'lastAttemptAt': serializer.toJson<String?>(lastAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  SyncMetaRow copyWith({
    String? tableName_,
    Value<String?> lastRefreshedAt = const Value.absent(),
    Value<String?> lastAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) => SyncMetaRow(
    tableName_: tableName_ ?? this.tableName_,
    lastRefreshedAt: lastRefreshedAt.present
        ? lastRefreshedAt.value
        : this.lastRefreshedAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  SyncMetaRow copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaRow(
      tableName_: data.tableName_.present
          ? data.tableName_.value
          : this.tableName_,
      lastRefreshedAt: data.lastRefreshedAt.present
          ? data.lastRefreshedAt.value
          : this.lastRefreshedAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaRow(')
          ..write('tableName_: $tableName_, ')
          ..write('lastRefreshedAt: $lastRefreshedAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(tableName_, lastRefreshedAt, lastAttemptAt, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaRow &&
          other.tableName_ == this.tableName_ &&
          other.lastRefreshedAt == this.lastRefreshedAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.lastError == this.lastError);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaRow> {
  final Value<String> tableName_;
  final Value<String?> lastRefreshedAt;
  final Value<String?> lastAttemptAt;
  final Value<String?> lastError;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.tableName_ = const Value.absent(),
    this.lastRefreshedAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String tableName_,
    this.lastRefreshedAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : tableName_ = Value(tableName_);
  static Insertable<SyncMetaRow> custom({
    Expression<String>? tableName_,
    Expression<String>? lastRefreshedAt,
    Expression<String>? lastAttemptAt,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tableName_ != null) 'table_name': tableName_,
      if (lastRefreshedAt != null) 'last_refreshed_at': lastRefreshedAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith({
    Value<String>? tableName_,
    Value<String?>? lastRefreshedAt,
    Value<String?>? lastAttemptAt,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return SyncMetaCompanion(
      tableName_: tableName_ ?? this.tableName_,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tableName_.present) {
      map['table_name'] = Variable<String>(tableName_.value);
    }
    if (lastRefreshedAt.present) {
      map['last_refreshed_at'] = Variable<String>(lastRefreshedAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<String>(lastAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('tableName_: $tableName_, ')
          ..write('lastRefreshedAt: $lastRefreshedAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxRowsTable extends OutboxRows
    with TableInfo<$OutboxRowsTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientUuidMeta = const VerificationMeta(
    'clientUuid',
  );
  @override
  late final GeneratedColumn<String> clientUuid = GeneratedColumn<String>(
    'client_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<String> capturedAt = GeneratedColumn<String>(
    'captured_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    clientUuid,
    operation,
    payloadJson,
    capturedAt,
    status,
    attempts,
    lastError,
    serverId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_uuid')) {
      context.handle(
        _clientUuidMeta,
        clientUuid.isAcceptableOrUnknown(data['client_uuid']!, _clientUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_clientUuidMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientUuid};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      clientUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_uuid'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}captured_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $OutboxRowsTable createAlias(String alias) {
    return $OutboxRowsTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  /// The idempotency key, minted on device and sent to the server, so a
  /// retried upload cannot create a second row.
  final String clientUuid;
  final String operation;
  final String payloadJson;

  /// MTR-12: the moment of capture, not the moment of sync.
  final String capturedAt;
  final String status;
  final int attempts;

  /// Surfaced to the user; never silently dropped.
  final String? lastError;
  final String? serverId;
  final String createdAt;
  final String? updatedAt;
  const OutboxRow({
    required this.clientUuid,
    required this.operation,
    required this.payloadJson,
    required this.capturedAt,
    required this.status,
    required this.attempts,
    this.lastError,
    this.serverId,
    required this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_uuid'] = Variable<String>(clientUuid);
    map['operation'] = Variable<String>(operation);
    map['payload_json'] = Variable<String>(payloadJson);
    map['captured_at'] = Variable<String>(capturedAt);
    map['status'] = Variable<String>(status);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['created_at'] = Variable<String>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<String>(updatedAt);
    }
    return map;
  }

  OutboxRowsCompanion toCompanion(bool nullToAbsent) {
    return OutboxRowsCompanion(
      clientUuid: Value(clientUuid),
      operation: Value(operation),
      payloadJson: Value(payloadJson),
      capturedAt: Value(capturedAt),
      status: Value(status),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      clientUuid: serializer.fromJson<String>(json['clientUuid']),
      operation: serializer.fromJson<String>(json['operation']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      capturedAt: serializer.fromJson<String>(json['capturedAt']),
      status: serializer.fromJson<String>(json['status']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientUuid': serializer.toJson<String>(clientUuid),
      'operation': serializer.toJson<String>(operation),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'capturedAt': serializer.toJson<String>(capturedAt),
      'status': serializer.toJson<String>(status),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'serverId': serializer.toJson<String?>(serverId),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String?>(updatedAt),
    };
  }

  OutboxRow copyWith({
    String? clientUuid,
    String? operation,
    String? payloadJson,
    String? capturedAt,
    String? status,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    Value<String?> serverId = const Value.absent(),
    String? createdAt,
    Value<String?> updatedAt = const Value.absent(),
  }) => OutboxRow(
    clientUuid: clientUuid ?? this.clientUuid,
    operation: operation ?? this.operation,
    payloadJson: payloadJson ?? this.payloadJson,
    capturedAt: capturedAt ?? this.capturedAt,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    serverId: serverId.present ? serverId.value : this.serverId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  OutboxRow copyWithCompanion(OutboxRowsCompanion data) {
    return OutboxRow(
      clientUuid: data.clientUuid.present
          ? data.clientUuid.value
          : this.clientUuid,
      operation: data.operation.present ? data.operation.value : this.operation,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      status: data.status.present ? data.status.value : this.status,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('clientUuid: $clientUuid, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    clientUuid,
    operation,
    payloadJson,
    capturedAt,
    status,
    attempts,
    lastError,
    serverId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.clientUuid == this.clientUuid &&
          other.operation == this.operation &&
          other.payloadJson == this.payloadJson &&
          other.capturedAt == this.capturedAt &&
          other.status == this.status &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.serverId == this.serverId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class OutboxRowsCompanion extends UpdateCompanion<OutboxRow> {
  final Value<String> clientUuid;
  final Value<String> operation;
  final Value<String> payloadJson;
  final Value<String> capturedAt;
  final Value<String> status;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<String?> serverId;
  final Value<String> createdAt;
  final Value<String?> updatedAt;
  final Value<int> rowid;
  const OutboxRowsCompanion({
    this.clientUuid = const Value.absent(),
    this.operation = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.serverId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxRowsCompanion.insert({
    required String clientUuid,
    required String operation,
    required String payloadJson,
    required String capturedAt,
    this.status = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.serverId = const Value.absent(),
    required String createdAt,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : clientUuid = Value(clientUuid),
       operation = Value(operation),
       payloadJson = Value(payloadJson),
       capturedAt = Value(capturedAt),
       createdAt = Value(createdAt);
  static Insertable<OutboxRow> custom({
    Expression<String>? clientUuid,
    Expression<String>? operation,
    Expression<String>? payloadJson,
    Expression<String>? capturedAt,
    Expression<String>? status,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<String>? serverId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientUuid != null) 'client_uuid': clientUuid,
      if (operation != null) 'operation': operation,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (status != null) 'status': status,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (serverId != null) 'server_id': serverId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxRowsCompanion copyWith({
    Value<String>? clientUuid,
    Value<String>? operation,
    Value<String>? payloadJson,
    Value<String>? capturedAt,
    Value<String>? status,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<String?>? serverId,
    Value<String>? createdAt,
    Value<String?>? updatedAt,
    Value<int>? rowid,
  }) {
    return OutboxRowsCompanion(
      clientUuid: clientUuid ?? this.clientUuid,
      operation: operation ?? this.operation,
      payloadJson: payloadJson ?? this.payloadJson,
      capturedAt: capturedAt ?? this.capturedAt,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      serverId: serverId ?? this.serverId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientUuid.present) {
      map['client_uuid'] = Variable<String>(clientUuid.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<String>(capturedAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRowsCompanion(')
          ..write('clientUuid: $clientUuid, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxReadingKeysTable extends OutboxReadingKeys
    with TableInfo<$OutboxReadingKeysTable, OutboxReadingKeyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxReadingKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientUuidMeta = const VerificationMeta(
    'clientUuid',
  );
  @override
  late final GeneratedColumn<String> clientUuid = GeneratedColumn<String>(
    'client_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES outbox (client_uuid) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _consumerIdMeta = const VerificationMeta(
    'consumerId',
  );
  @override
  late final GeneratedColumn<String> consumerId = GeneratedColumn<String>(
    'consumer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cycleLabelMeta = const VerificationMeta(
    'cycleLabel',
  );
  @override
  late final GeneratedColumn<String> cycleLabel = GeneratedColumn<String>(
    'cycle_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [clientUuid, consumerId, cycleLabel];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_reading_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxReadingKeyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_uuid')) {
      context.handle(
        _clientUuidMeta,
        clientUuid.isAcceptableOrUnknown(data['client_uuid']!, _clientUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_clientUuidMeta);
    }
    if (data.containsKey('consumer_id')) {
      context.handle(
        _consumerIdMeta,
        consumerId.isAcceptableOrUnknown(data['consumer_id']!, _consumerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_consumerIdMeta);
    }
    if (data.containsKey('cycle_label')) {
      context.handle(
        _cycleLabelMeta,
        cycleLabel.isAcceptableOrUnknown(data['cycle_label']!, _cycleLabelMeta),
      );
    } else if (isInserting) {
      context.missing(_cycleLabelMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientUuid};
  @override
  OutboxReadingKeyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxReadingKeyRow(
      clientUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_uuid'],
      )!,
      consumerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consumer_id'],
      )!,
      cycleLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cycle_label'],
      )!,
    );
  }

  @override
  $OutboxReadingKeysTable createAlias(String alias) {
    return $OutboxReadingKeysTable(attachedDatabase, alias);
  }
}

class OutboxReadingKeyRow extends DataClass
    implements Insertable<OutboxReadingKeyRow> {
  final String clientUuid;
  final String consumerId;

  /// 'YYYY-MM'
  final String cycleLabel;
  const OutboxReadingKeyRow({
    required this.clientUuid,
    required this.consumerId,
    required this.cycleLabel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_uuid'] = Variable<String>(clientUuid);
    map['consumer_id'] = Variable<String>(consumerId);
    map['cycle_label'] = Variable<String>(cycleLabel);
    return map;
  }

  OutboxReadingKeysCompanion toCompanion(bool nullToAbsent) {
    return OutboxReadingKeysCompanion(
      clientUuid: Value(clientUuid),
      consumerId: Value(consumerId),
      cycleLabel: Value(cycleLabel),
    );
  }

  factory OutboxReadingKeyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxReadingKeyRow(
      clientUuid: serializer.fromJson<String>(json['clientUuid']),
      consumerId: serializer.fromJson<String>(json['consumerId']),
      cycleLabel: serializer.fromJson<String>(json['cycleLabel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientUuid': serializer.toJson<String>(clientUuid),
      'consumerId': serializer.toJson<String>(consumerId),
      'cycleLabel': serializer.toJson<String>(cycleLabel),
    };
  }

  OutboxReadingKeyRow copyWith({
    String? clientUuid,
    String? consumerId,
    String? cycleLabel,
  }) => OutboxReadingKeyRow(
    clientUuid: clientUuid ?? this.clientUuid,
    consumerId: consumerId ?? this.consumerId,
    cycleLabel: cycleLabel ?? this.cycleLabel,
  );
  OutboxReadingKeyRow copyWithCompanion(OutboxReadingKeysCompanion data) {
    return OutboxReadingKeyRow(
      clientUuid: data.clientUuid.present
          ? data.clientUuid.value
          : this.clientUuid,
      consumerId: data.consumerId.present
          ? data.consumerId.value
          : this.consumerId,
      cycleLabel: data.cycleLabel.present
          ? data.cycleLabel.value
          : this.cycleLabel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxReadingKeyRow(')
          ..write('clientUuid: $clientUuid, ')
          ..write('consumerId: $consumerId, ')
          ..write('cycleLabel: $cycleLabel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(clientUuid, consumerId, cycleLabel);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxReadingKeyRow &&
          other.clientUuid == this.clientUuid &&
          other.consumerId == this.consumerId &&
          other.cycleLabel == this.cycleLabel);
}

class OutboxReadingKeysCompanion extends UpdateCompanion<OutboxReadingKeyRow> {
  final Value<String> clientUuid;
  final Value<String> consumerId;
  final Value<String> cycleLabel;
  final Value<int> rowid;
  const OutboxReadingKeysCompanion({
    this.clientUuid = const Value.absent(),
    this.consumerId = const Value.absent(),
    this.cycleLabel = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxReadingKeysCompanion.insert({
    required String clientUuid,
    required String consumerId,
    required String cycleLabel,
    this.rowid = const Value.absent(),
  }) : clientUuid = Value(clientUuid),
       consumerId = Value(consumerId),
       cycleLabel = Value(cycleLabel);
  static Insertable<OutboxReadingKeyRow> custom({
    Expression<String>? clientUuid,
    Expression<String>? consumerId,
    Expression<String>? cycleLabel,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientUuid != null) 'client_uuid': clientUuid,
      if (consumerId != null) 'consumer_id': consumerId,
      if (cycleLabel != null) 'cycle_label': cycleLabel,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxReadingKeysCompanion copyWith({
    Value<String>? clientUuid,
    Value<String>? consumerId,
    Value<String>? cycleLabel,
    Value<int>? rowid,
  }) {
    return OutboxReadingKeysCompanion(
      clientUuid: clientUuid ?? this.clientUuid,
      consumerId: consumerId ?? this.consumerId,
      cycleLabel: cycleLabel ?? this.cycleLabel,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientUuid.present) {
      map['client_uuid'] = Variable<String>(clientUuid.value);
    }
    if (consumerId.present) {
      map['consumer_id'] = Variable<String>(consumerId.value);
    }
    if (cycleLabel.present) {
      map['cycle_label'] = Variable<String>(cycleLabel.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxReadingKeysCompanion(')
          ..write('clientUuid: $clientUuid, ')
          ..write('consumerId: $consumerId, ')
          ..write('cycleLabel: $cycleLabel, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedConsumersTable cachedConsumers = $CachedConsumersTable(
    this,
  );
  late final $CachedBillsTable cachedBills = $CachedBillsTable(this);
  late final $CachedPaymentsTable cachedPayments = $CachedPaymentsTable(this);
  late final $CachedNotificationsTable cachedNotifications =
      $CachedNotificationsTable(this);
  late final $CacheOwnerTable cacheOwner = $CacheOwnerTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  late final $OutboxRowsTable outboxRows = $OutboxRowsTable(this);
  late final $OutboxReadingKeysTable outboxReadingKeys =
      $OutboxReadingKeysTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedConsumers,
    cachedBills,
    cachedPayments,
    cachedNotifications,
    cacheOwner,
    syncMeta,
    outboxRows,
    outboxReadingKeys,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'outbox',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('outbox_reading_keys', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$CachedConsumersTableCreateCompanionBuilder =
    CachedConsumersCompanion Function({
      required String id,
      required String consumerNo,
      required String firstName,
      required String lastName,
      Value<String?> contactNumber,
      Value<String?> meterSerialNo,
      required String areaId,
      Value<String?> purok,
      required String accountStatus,
      Value<int> previousReadingHundredths,
      Value<String?> previousReadingDate,
      Value<String?> lastReadCycle,
      Value<String?> updatedAt,
      Value<int> rowid,
    });
typedef $$CachedConsumersTableUpdateCompanionBuilder =
    CachedConsumersCompanion Function({
      Value<String> id,
      Value<String> consumerNo,
      Value<String> firstName,
      Value<String> lastName,
      Value<String?> contactNumber,
      Value<String?> meterSerialNo,
      Value<String> areaId,
      Value<String?> purok,
      Value<String> accountStatus,
      Value<int> previousReadingHundredths,
      Value<String?> previousReadingDate,
      Value<String?> lastReadCycle,
      Value<String?> updatedAt,
      Value<int> rowid,
    });

class $$CachedConsumersTableFilterComposer
    extends Composer<_$AppDatabase, $CachedConsumersTable> {
  $$CachedConsumersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get consumerNo => $composableBuilder(
    column: $table.consumerNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactNumber => $composableBuilder(
    column: $table.contactNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meterSerialNo => $composableBuilder(
    column: $table.meterSerialNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get areaId => $composableBuilder(
    column: $table.areaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purok => $composableBuilder(
    column: $table.purok,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountStatus => $composableBuilder(
    column: $table.accountStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get previousReadingHundredths => $composableBuilder(
    column: $table.previousReadingHundredths,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previousReadingDate => $composableBuilder(
    column: $table.previousReadingDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastReadCycle => $composableBuilder(
    column: $table.lastReadCycle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedConsumersTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedConsumersTable> {
  $$CachedConsumersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get consumerNo => $composableBuilder(
    column: $table.consumerNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactNumber => $composableBuilder(
    column: $table.contactNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meterSerialNo => $composableBuilder(
    column: $table.meterSerialNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get areaId => $composableBuilder(
    column: $table.areaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purok => $composableBuilder(
    column: $table.purok,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountStatus => $composableBuilder(
    column: $table.accountStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get previousReadingHundredths => $composableBuilder(
    column: $table.previousReadingHundredths,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previousReadingDate => $composableBuilder(
    column: $table.previousReadingDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastReadCycle => $composableBuilder(
    column: $table.lastReadCycle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedConsumersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedConsumersTable> {
  $$CachedConsumersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get consumerNo => $composableBuilder(
    column: $table.consumerNo,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<String> get contactNumber => $composableBuilder(
    column: $table.contactNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get meterSerialNo => $composableBuilder(
    column: $table.meterSerialNo,
    builder: (column) => column,
  );

  GeneratedColumn<String> get areaId =>
      $composableBuilder(column: $table.areaId, builder: (column) => column);

  GeneratedColumn<String> get purok =>
      $composableBuilder(column: $table.purok, builder: (column) => column);

  GeneratedColumn<String> get accountStatus => $composableBuilder(
    column: $table.accountStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get previousReadingHundredths => $composableBuilder(
    column: $table.previousReadingHundredths,
    builder: (column) => column,
  );

  GeneratedColumn<String> get previousReadingDate => $composableBuilder(
    column: $table.previousReadingDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastReadCycle => $composableBuilder(
    column: $table.lastReadCycle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedConsumersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedConsumersTable,
          CachedConsumerRow,
          $$CachedConsumersTableFilterComposer,
          $$CachedConsumersTableOrderingComposer,
          $$CachedConsumersTableAnnotationComposer,
          $$CachedConsumersTableCreateCompanionBuilder,
          $$CachedConsumersTableUpdateCompanionBuilder,
          (
            CachedConsumerRow,
            BaseReferences<
              _$AppDatabase,
              $CachedConsumersTable,
              CachedConsumerRow
            >,
          ),
          CachedConsumerRow,
          PrefetchHooks Function()
        > {
  $$CachedConsumersTableTableManager(
    _$AppDatabase db,
    $CachedConsumersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedConsumersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedConsumersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedConsumersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> consumerNo = const Value.absent(),
                Value<String> firstName = const Value.absent(),
                Value<String> lastName = const Value.absent(),
                Value<String?> contactNumber = const Value.absent(),
                Value<String?> meterSerialNo = const Value.absent(),
                Value<String> areaId = const Value.absent(),
                Value<String?> purok = const Value.absent(),
                Value<String> accountStatus = const Value.absent(),
                Value<int> previousReadingHundredths = const Value.absent(),
                Value<String?> previousReadingDate = const Value.absent(),
                Value<String?> lastReadCycle = const Value.absent(),
                Value<String?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedConsumersCompanion(
                id: id,
                consumerNo: consumerNo,
                firstName: firstName,
                lastName: lastName,
                contactNumber: contactNumber,
                meterSerialNo: meterSerialNo,
                areaId: areaId,
                purok: purok,
                accountStatus: accountStatus,
                previousReadingHundredths: previousReadingHundredths,
                previousReadingDate: previousReadingDate,
                lastReadCycle: lastReadCycle,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String consumerNo,
                required String firstName,
                required String lastName,
                Value<String?> contactNumber = const Value.absent(),
                Value<String?> meterSerialNo = const Value.absent(),
                required String areaId,
                Value<String?> purok = const Value.absent(),
                required String accountStatus,
                Value<int> previousReadingHundredths = const Value.absent(),
                Value<String?> previousReadingDate = const Value.absent(),
                Value<String?> lastReadCycle = const Value.absent(),
                Value<String?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedConsumersCompanion.insert(
                id: id,
                consumerNo: consumerNo,
                firstName: firstName,
                lastName: lastName,
                contactNumber: contactNumber,
                meterSerialNo: meterSerialNo,
                areaId: areaId,
                purok: purok,
                accountStatus: accountStatus,
                previousReadingHundredths: previousReadingHundredths,
                previousReadingDate: previousReadingDate,
                lastReadCycle: lastReadCycle,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedConsumersTable, CachedConsumerRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedConsumersTable,
                    CachedConsumerRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedConsumersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedConsumersTable,
      CachedConsumerRow,
      $$CachedConsumersTableFilterComposer,
      $$CachedConsumersTableOrderingComposer,
      $$CachedConsumersTableAnnotationComposer,
      $$CachedConsumersTableCreateCompanionBuilder,
      $$CachedConsumersTableUpdateCompanionBuilder,
      (
        CachedConsumerRow,
        BaseReferences<_$AppDatabase, $CachedConsumersTable, CachedConsumerRow>,
      ),
      CachedConsumerRow,
      PrefetchHooks Function()
    >;
typedef $$CachedBillsTableCreateCompanionBuilder =
    CachedBillsCompanion Function({
      required String id,
      required String billNo,
      required String consumerId,
      required String cycleLabel,
      required int consumptionHundredths,
      Value<int> amountPaidCentavos,
      Value<int?> totalAmountCentavos,
      Value<String?> dueDate,
      Value<String?> generatedAt,
      Value<int> rowid,
    });
typedef $$CachedBillsTableUpdateCompanionBuilder =
    CachedBillsCompanion Function({
      Value<String> id,
      Value<String> billNo,
      Value<String> consumerId,
      Value<String> cycleLabel,
      Value<int> consumptionHundredths,
      Value<int> amountPaidCentavos,
      Value<int?> totalAmountCentavos,
      Value<String?> dueDate,
      Value<String?> generatedAt,
      Value<int> rowid,
    });

class $$CachedBillsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedBillsTable> {
  $$CachedBillsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get billNo => $composableBuilder(
    column: $table.billNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get consumerId => $composableBuilder(
    column: $table.consumerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cycleLabel => $composableBuilder(
    column: $table.cycleLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get consumptionHundredths => $composableBuilder(
    column: $table.consumptionHundredths,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaidCentavos => $composableBuilder(
    column: $table.amountPaidCentavos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalAmountCentavos => $composableBuilder(
    column: $table.totalAmountCentavos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedBillsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedBillsTable> {
  $$CachedBillsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get billNo => $composableBuilder(
    column: $table.billNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get consumerId => $composableBuilder(
    column: $table.consumerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cycleLabel => $composableBuilder(
    column: $table.cycleLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get consumptionHundredths => $composableBuilder(
    column: $table.consumptionHundredths,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaidCentavos => $composableBuilder(
    column: $table.amountPaidCentavos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalAmountCentavos => $composableBuilder(
    column: $table.totalAmountCentavos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedBillsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedBillsTable> {
  $$CachedBillsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get billNo =>
      $composableBuilder(column: $table.billNo, builder: (column) => column);

  GeneratedColumn<String> get consumerId => $composableBuilder(
    column: $table.consumerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cycleLabel => $composableBuilder(
    column: $table.cycleLabel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get consumptionHundredths => $composableBuilder(
    column: $table.consumptionHundredths,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountPaidCentavos => $composableBuilder(
    column: $table.amountPaidCentavos,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalAmountCentavos => $composableBuilder(
    column: $table.totalAmountCentavos,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => column,
  );
}

class $$CachedBillsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedBillsTable,
          CachedBillRow,
          $$CachedBillsTableFilterComposer,
          $$CachedBillsTableOrderingComposer,
          $$CachedBillsTableAnnotationComposer,
          $$CachedBillsTableCreateCompanionBuilder,
          $$CachedBillsTableUpdateCompanionBuilder,
          (
            CachedBillRow,
            BaseReferences<_$AppDatabase, $CachedBillsTable, CachedBillRow>,
          ),
          CachedBillRow,
          PrefetchHooks Function()
        > {
  $$CachedBillsTableTableManager(_$AppDatabase db, $CachedBillsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedBillsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedBillsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedBillsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> billNo = const Value.absent(),
                Value<String> consumerId = const Value.absent(),
                Value<String> cycleLabel = const Value.absent(),
                Value<int> consumptionHundredths = const Value.absent(),
                Value<int> amountPaidCentavos = const Value.absent(),
                Value<int?> totalAmountCentavos = const Value.absent(),
                Value<String?> dueDate = const Value.absent(),
                Value<String?> generatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedBillsCompanion(
                id: id,
                billNo: billNo,
                consumerId: consumerId,
                cycleLabel: cycleLabel,
                consumptionHundredths: consumptionHundredths,
                amountPaidCentavos: amountPaidCentavos,
                totalAmountCentavos: totalAmountCentavos,
                dueDate: dueDate,
                generatedAt: generatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String billNo,
                required String consumerId,
                required String cycleLabel,
                required int consumptionHundredths,
                Value<int> amountPaidCentavos = const Value.absent(),
                Value<int?> totalAmountCentavos = const Value.absent(),
                Value<String?> dueDate = const Value.absent(),
                Value<String?> generatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedBillsCompanion.insert(
                id: id,
                billNo: billNo,
                consumerId: consumerId,
                cycleLabel: cycleLabel,
                consumptionHundredths: consumptionHundredths,
                amountPaidCentavos: amountPaidCentavos,
                totalAmountCentavos: totalAmountCentavos,
                dueDate: dueDate,
                generatedAt: generatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedBillsTable, CachedBillRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedBillsTable,
                    CachedBillRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedBillsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedBillsTable,
      CachedBillRow,
      $$CachedBillsTableFilterComposer,
      $$CachedBillsTableOrderingComposer,
      $$CachedBillsTableAnnotationComposer,
      $$CachedBillsTableCreateCompanionBuilder,
      $$CachedBillsTableUpdateCompanionBuilder,
      (
        CachedBillRow,
        BaseReferences<_$AppDatabase, $CachedBillsTable, CachedBillRow>,
      ),
      CachedBillRow,
      PrefetchHooks Function()
    >;
typedef $$CachedPaymentsTableCreateCompanionBuilder =
    CachedPaymentsCompanion Function({
      required String id,
      Value<String?> billId,
      required String receiptNo,
      required int amountPaidCentavos,
      required String paidAt,
      Value<int> rowid,
    });
typedef $$CachedPaymentsTableUpdateCompanionBuilder =
    CachedPaymentsCompanion Function({
      Value<String> id,
      Value<String?> billId,
      Value<String> receiptNo,
      Value<int> amountPaidCentavos,
      Value<String> paidAt,
      Value<int> rowid,
    });

class $$CachedPaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedPaymentsTable> {
  $$CachedPaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get billId => $composableBuilder(
    column: $table.billId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptNo => $composableBuilder(
    column: $table.receiptNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaidCentavos => $composableBuilder(
    column: $table.amountPaidCentavos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paidAt => $composableBuilder(
    column: $table.paidAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedPaymentsTable> {
  $$CachedPaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get billId => $composableBuilder(
    column: $table.billId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptNo => $composableBuilder(
    column: $table.receiptNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaidCentavos => $composableBuilder(
    column: $table.amountPaidCentavos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paidAt => $composableBuilder(
    column: $table.paidAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedPaymentsTable> {
  $$CachedPaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get billId =>
      $composableBuilder(column: $table.billId, builder: (column) => column);

  GeneratedColumn<String> get receiptNo =>
      $composableBuilder(column: $table.receiptNo, builder: (column) => column);

  GeneratedColumn<int> get amountPaidCentavos => $composableBuilder(
    column: $table.amountPaidCentavos,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paidAt =>
      $composableBuilder(column: $table.paidAt, builder: (column) => column);
}

class $$CachedPaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedPaymentsTable,
          CachedPaymentRow,
          $$CachedPaymentsTableFilterComposer,
          $$CachedPaymentsTableOrderingComposer,
          $$CachedPaymentsTableAnnotationComposer,
          $$CachedPaymentsTableCreateCompanionBuilder,
          $$CachedPaymentsTableUpdateCompanionBuilder,
          (
            CachedPaymentRow,
            BaseReferences<
              _$AppDatabase,
              $CachedPaymentsTable,
              CachedPaymentRow
            >,
          ),
          CachedPaymentRow,
          PrefetchHooks Function()
        > {
  $$CachedPaymentsTableTableManager(
    _$AppDatabase db,
    $CachedPaymentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> billId = const Value.absent(),
                Value<String> receiptNo = const Value.absent(),
                Value<int> amountPaidCentavos = const Value.absent(),
                Value<String> paidAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPaymentsCompanion(
                id: id,
                billId: billId,
                receiptNo: receiptNo,
                amountPaidCentavos: amountPaidCentavos,
                paidAt: paidAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> billId = const Value.absent(),
                required String receiptNo,
                required int amountPaidCentavos,
                required String paidAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedPaymentsCompanion.insert(
                id: id,
                billId: billId,
                receiptNo: receiptNo,
                amountPaidCentavos: amountPaidCentavos,
                paidAt: paidAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedPaymentsTable, CachedPaymentRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedPaymentsTable,
                    CachedPaymentRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedPaymentsTable,
      CachedPaymentRow,
      $$CachedPaymentsTableFilterComposer,
      $$CachedPaymentsTableOrderingComposer,
      $$CachedPaymentsTableAnnotationComposer,
      $$CachedPaymentsTableCreateCompanionBuilder,
      $$CachedPaymentsTableUpdateCompanionBuilder,
      (
        CachedPaymentRow,
        BaseReferences<_$AppDatabase, $CachedPaymentsTable, CachedPaymentRow>,
      ),
      CachedPaymentRow,
      PrefetchHooks Function()
    >;
typedef $$CachedNotificationsTableCreateCompanionBuilder =
    CachedNotificationsCompanion Function({
      required String id,
      required String notifType,
      required String channel,
      required String message,
      required String status,
      Value<bool> isRead,
      required String createdAt,
      Value<int> rowid,
    });
typedef $$CachedNotificationsTableUpdateCompanionBuilder =
    CachedNotificationsCompanion Function({
      Value<String> id,
      Value<String> notifType,
      Value<String> channel,
      Value<String> message,
      Value<String> status,
      Value<bool> isRead,
      Value<String> createdAt,
      Value<int> rowid,
    });

class $$CachedNotificationsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedNotificationsTable> {
  $$CachedNotificationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notifType => $composableBuilder(
    column: $table.notifType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedNotificationsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedNotificationsTable> {
  $$CachedNotificationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notifType => $composableBuilder(
    column: $table.notifType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedNotificationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedNotificationsTable> {
  $$CachedNotificationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get notifType =>
      $composableBuilder(column: $table.notifType, builder: (column) => column);

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CachedNotificationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedNotificationsTable,
          CachedNotificationRow,
          $$CachedNotificationsTableFilterComposer,
          $$CachedNotificationsTableOrderingComposer,
          $$CachedNotificationsTableAnnotationComposer,
          $$CachedNotificationsTableCreateCompanionBuilder,
          $$CachedNotificationsTableUpdateCompanionBuilder,
          (
            CachedNotificationRow,
            BaseReferences<
              _$AppDatabase,
              $CachedNotificationsTable,
              CachedNotificationRow
            >,
          ),
          CachedNotificationRow,
          PrefetchHooks Function()
        > {
  $$CachedNotificationsTableTableManager(
    _$AppDatabase db,
    $CachedNotificationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedNotificationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedNotificationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedNotificationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> notifType = const Value.absent(),
                Value<String> channel = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedNotificationsCompanion(
                id: id,
                notifType: notifType,
                channel: channel,
                message: message,
                status: status,
                isRead: isRead,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String notifType,
                required String channel,
                required String message,
                required String status,
                Value<bool> isRead = const Value.absent(),
                required String createdAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedNotificationsCompanion.insert(
                id: id,
                notifType: notifType,
                channel: channel,
                message: message,
                status: status,
                isRead: isRead,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedNotificationsTable, CachedNotificationRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedNotificationsTable,
                    CachedNotificationRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedNotificationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedNotificationsTable,
      CachedNotificationRow,
      $$CachedNotificationsTableFilterComposer,
      $$CachedNotificationsTableOrderingComposer,
      $$CachedNotificationsTableAnnotationComposer,
      $$CachedNotificationsTableCreateCompanionBuilder,
      $$CachedNotificationsTableUpdateCompanionBuilder,
      (
        CachedNotificationRow,
        BaseReferences<
          _$AppDatabase,
          $CachedNotificationsTable,
          CachedNotificationRow
        >,
      ),
      CachedNotificationRow,
      PrefetchHooks Function()
    >;
typedef $$CacheOwnerTableCreateCompanionBuilder =
    CacheOwnerCompanion Function({
      Value<int> id,
      required String profileId,
      required String role,
      Value<String?> areaId,
      required String cachedAt,
    });
typedef $$CacheOwnerTableUpdateCompanionBuilder =
    CacheOwnerCompanion Function({
      Value<int> id,
      Value<String> profileId,
      Value<String> role,
      Value<String?> areaId,
      Value<String> cachedAt,
    });

class $$CacheOwnerTableFilterComposer
    extends Composer<_$AppDatabase, $CacheOwnerTable> {
  $$CacheOwnerTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get areaId => $composableBuilder(
    column: $table.areaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheOwnerTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheOwnerTable> {
  $$CacheOwnerTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get areaId => $composableBuilder(
    column: $table.areaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheOwnerTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheOwnerTable> {
  $$CacheOwnerTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get areaId =>
      $composableBuilder(column: $table.areaId, builder: (column) => column);

  GeneratedColumn<String> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CacheOwnerTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CacheOwnerTable,
          CacheOwnerRow,
          $$CacheOwnerTableFilterComposer,
          $$CacheOwnerTableOrderingComposer,
          $$CacheOwnerTableAnnotationComposer,
          $$CacheOwnerTableCreateCompanionBuilder,
          $$CacheOwnerTableUpdateCompanionBuilder,
          (
            CacheOwnerRow,
            BaseReferences<_$AppDatabase, $CacheOwnerTable, CacheOwnerRow>,
          ),
          CacheOwnerRow,
          PrefetchHooks Function()
        > {
  $$CacheOwnerTableTableManager(_$AppDatabase db, $CacheOwnerTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheOwnerTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheOwnerTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheOwnerTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String?> areaId = const Value.absent(),
                Value<String> cachedAt = const Value.absent(),
              }) => CacheOwnerCompanion(
                id: id,
                profileId: profileId,
                role: role,
                areaId: areaId,
                cachedAt: cachedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String profileId,
                required String role,
                Value<String?> areaId = const Value.absent(),
                required String cachedAt,
              }) => CacheOwnerCompanion.insert(
                id: id,
                profileId: profileId,
                role: role,
                areaId: areaId,
                cachedAt: cachedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CacheOwnerTable, CacheOwnerRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CacheOwnerTable,
                    CacheOwnerRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheOwnerTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CacheOwnerTable,
      CacheOwnerRow,
      $$CacheOwnerTableFilterComposer,
      $$CacheOwnerTableOrderingComposer,
      $$CacheOwnerTableAnnotationComposer,
      $$CacheOwnerTableCreateCompanionBuilder,
      $$CacheOwnerTableUpdateCompanionBuilder,
      (
        CacheOwnerRow,
        BaseReferences<_$AppDatabase, $CacheOwnerTable, CacheOwnerRow>,
      ),
      CacheOwnerRow,
      PrefetchHooks Function()
    >;
typedef $$SyncMetaTableCreateCompanionBuilder =
    SyncMetaCompanion Function({
      required String tableName_,
      Value<String?> lastRefreshedAt,
      Value<String?> lastAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$SyncMetaTableUpdateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<String> tableName_,
      Value<String?> lastRefreshedAt,
      Value<String?> lastAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tableName_ => $composableBuilder(
    column: $table.tableName_,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastRefreshedAt => $composableBuilder(
    column: $table.lastRefreshedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tableName_ => $composableBuilder(
    column: $table.tableName_,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastRefreshedAt => $composableBuilder(
    column: $table.lastRefreshedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tableName_ => $composableBuilder(
    column: $table.tableName_,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastRefreshedAt => $composableBuilder(
    column: $table.lastRefreshedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetaTable,
          SyncMetaRow,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (
            SyncMetaRow,
            BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaRow>,
          ),
          SyncMetaRow,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tableName_ = const Value.absent(),
                Value<String?> lastRefreshedAt = const Value.absent(),
                Value<String?> lastAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion(
                tableName_: tableName_,
                lastRefreshedAt: lastRefreshedAt,
                lastAttemptAt: lastAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tableName_,
                Value<String?> lastRefreshedAt = const Value.absent(),
                Value<String?> lastAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                tableName_: tableName_,
                lastRefreshedAt: lastRefreshedAt,
                lastAttemptAt: lastAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncMetaTable, SyncMetaRow>(table),
                  BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetaTable,
      SyncMetaRow,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (SyncMetaRow, BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaRow>),
      SyncMetaRow,
      PrefetchHooks Function()
    >;
typedef $$OutboxRowsTableCreateCompanionBuilder =
    OutboxRowsCompanion Function({
      required String clientUuid,
      required String operation,
      required String payloadJson,
      required String capturedAt,
      Value<String> status,
      Value<int> attempts,
      Value<String?> lastError,
      Value<String?> serverId,
      required String createdAt,
      Value<String?> updatedAt,
      Value<int> rowid,
    });
typedef $$OutboxRowsTableUpdateCompanionBuilder =
    OutboxRowsCompanion Function({
      Value<String> clientUuid,
      Value<String> operation,
      Value<String> payloadJson,
      Value<String> capturedAt,
      Value<String> status,
      Value<int> attempts,
      Value<String?> lastError,
      Value<String?> serverId,
      Value<String> createdAt,
      Value<String?> updatedAt,
      Value<int> rowid,
    });

final class $$OutboxRowsTableReferences
    extends BaseReferences<_$AppDatabase, $OutboxRowsTable, OutboxRow> {
  $$OutboxRowsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$OutboxReadingKeysTable, List<OutboxReadingKeyRow>>
  _outboxReadingKeysRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.outboxReadingKeys,
        aliasName: 'outbox__client_uuid__outbox_reading_keys__client_uuid',
      );

  $$OutboxReadingKeysTableProcessedTableManager get outboxReadingKeysRefs {
    final manager =
        $$OutboxReadingKeysTableTableManager(
          $_db,
          $_db.outboxReadingKeys,
        ).filter(
          (f) => f.clientUuid.clientUuid.sqlEquals(
            $_itemColumn<String>('client_uuid')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _outboxReadingKeysRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$OutboxRowsTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxRowsTable> {
  $$OutboxRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientUuid => $composableBuilder(
    column: $table.clientUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> outboxReadingKeysRefs(
    Expression<bool> Function($$OutboxReadingKeysTableFilterComposer f) f,
  ) {
    final $$OutboxReadingKeysTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientUuid,
      referencedTable: $db.outboxReadingKeys,
      getReferencedColumn: (t) => t.clientUuid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxReadingKeysTableFilterComposer(
            $db: $db,
            $table: $db.outboxReadingKeys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$OutboxRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxRowsTable> {
  $$OutboxRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientUuid => $composableBuilder(
    column: $table.clientUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxRowsTable> {
  $$OutboxRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientUuid => $composableBuilder(
    column: $table.clientUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> outboxReadingKeysRefs<T extends Object>(
    Expression<T> Function($$OutboxReadingKeysTableAnnotationComposer a) f,
  ) {
    final $$OutboxReadingKeysTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.clientUuid,
          referencedTable: $db.outboxReadingKeys,
          getReferencedColumn: (t) => t.clientUuid,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OutboxReadingKeysTableAnnotationComposer(
                $db: $db,
                $table: $db.outboxReadingKeys,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$OutboxRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxRowsTable,
          OutboxRow,
          $$OutboxRowsTableFilterComposer,
          $$OutboxRowsTableOrderingComposer,
          $$OutboxRowsTableAnnotationComposer,
          $$OutboxRowsTableCreateCompanionBuilder,
          $$OutboxRowsTableUpdateCompanionBuilder,
          (OutboxRow, $$OutboxRowsTableReferences),
          OutboxRow,
          PrefetchHooks Function({bool outboxReadingKeysRefs})
        > {
  $$OutboxRowsTableTableManager(_$AppDatabase db, $OutboxRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> clientUuid = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> capturedAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxRowsCompanion(
                clientUuid: clientUuid,
                operation: operation,
                payloadJson: payloadJson,
                capturedAt: capturedAt,
                status: status,
                attempts: attempts,
                lastError: lastError,
                serverId: serverId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientUuid,
                required String operation,
                required String payloadJson,
                required String capturedAt,
                Value<String> status = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                required String createdAt,
                Value<String?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxRowsCompanion.insert(
                clientUuid: clientUuid,
                operation: operation,
                payloadJson: payloadJson,
                capturedAt: capturedAt,
                status: status,
                attempts: attempts,
                lastError: lastError,
                serverId: serverId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxRowsTable, OutboxRow>(table),
                  $$OutboxRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({outboxReadingKeysRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (outboxReadingKeysRefs) db.outboxReadingKeys,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (outboxReadingKeysRefs)
                    await $_getPrefetchedData<
                      OutboxRow,
                      $OutboxRowsTable,
                      OutboxReadingKeyRow
                    >(
                      currentTable: table,
                      referencedTable: $$OutboxRowsTableReferences
                          ._outboxReadingKeysRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$OutboxRowsTableReferences(
                            db,
                            table,
                            p0,
                          ).outboxReadingKeysRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.clientUuid == item.clientUuid,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$OutboxRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxRowsTable,
      OutboxRow,
      $$OutboxRowsTableFilterComposer,
      $$OutboxRowsTableOrderingComposer,
      $$OutboxRowsTableAnnotationComposer,
      $$OutboxRowsTableCreateCompanionBuilder,
      $$OutboxRowsTableUpdateCompanionBuilder,
      (OutboxRow, $$OutboxRowsTableReferences),
      OutboxRow,
      PrefetchHooks Function({bool outboxReadingKeysRefs})
    >;
typedef $$OutboxReadingKeysTableCreateCompanionBuilder =
    OutboxReadingKeysCompanion Function({
      required String clientUuid,
      required String consumerId,
      required String cycleLabel,
      Value<int> rowid,
    });
typedef $$OutboxReadingKeysTableUpdateCompanionBuilder =
    OutboxReadingKeysCompanion Function({
      Value<String> clientUuid,
      Value<String> consumerId,
      Value<String> cycleLabel,
      Value<int> rowid,
    });

final class $$OutboxReadingKeysTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $OutboxReadingKeysTable,
          OutboxReadingKeyRow
        > {
  $$OutboxReadingKeysTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $OutboxRowsTable _clientUuidTable(_$AppDatabase db) => db.outboxRows
      .createAlias('outbox_reading_keys__client_uuid__outbox__client_uuid');

  $$OutboxRowsTableProcessedTableManager get clientUuid {
    final $_column = $_itemColumn<String>('client_uuid')!;

    final manager = $$OutboxRowsTableTableManager(
      $_db,
      $_db.outboxRows,
    ).filter((f) => f.clientUuid.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_clientUuidTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OutboxReadingKeysTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxReadingKeysTable> {
  $$OutboxReadingKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get consumerId => $composableBuilder(
    column: $table.consumerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cycleLabel => $composableBuilder(
    column: $table.cycleLabel,
    builder: (column) => ColumnFilters(column),
  );

  $$OutboxRowsTableFilterComposer get clientUuid {
    final $$OutboxRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientUuid,
      referencedTable: $db.outboxRows,
      getReferencedColumn: (t) => t.clientUuid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxRowsTableFilterComposer(
            $db: $db,
            $table: $db.outboxRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxReadingKeysTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxReadingKeysTable> {
  $$OutboxReadingKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get consumerId => $composableBuilder(
    column: $table.consumerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cycleLabel => $composableBuilder(
    column: $table.cycleLabel,
    builder: (column) => ColumnOrderings(column),
  );

  $$OutboxRowsTableOrderingComposer get clientUuid {
    final $$OutboxRowsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientUuid,
      referencedTable: $db.outboxRows,
      getReferencedColumn: (t) => t.clientUuid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxRowsTableOrderingComposer(
            $db: $db,
            $table: $db.outboxRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxReadingKeysTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxReadingKeysTable> {
  $$OutboxReadingKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get consumerId => $composableBuilder(
    column: $table.consumerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cycleLabel => $composableBuilder(
    column: $table.cycleLabel,
    builder: (column) => column,
  );

  $$OutboxRowsTableAnnotationComposer get clientUuid {
    final $$OutboxRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientUuid,
      referencedTable: $db.outboxRows,
      getReferencedColumn: (t) => t.clientUuid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.outboxRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxReadingKeysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxReadingKeysTable,
          OutboxReadingKeyRow,
          $$OutboxReadingKeysTableFilterComposer,
          $$OutboxReadingKeysTableOrderingComposer,
          $$OutboxReadingKeysTableAnnotationComposer,
          $$OutboxReadingKeysTableCreateCompanionBuilder,
          $$OutboxReadingKeysTableUpdateCompanionBuilder,
          (OutboxReadingKeyRow, $$OutboxReadingKeysTableReferences),
          OutboxReadingKeyRow,
          PrefetchHooks Function({bool clientUuid})
        > {
  $$OutboxReadingKeysTableTableManager(
    _$AppDatabase db,
    $OutboxReadingKeysTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxReadingKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxReadingKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxReadingKeysTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> clientUuid = const Value.absent(),
                Value<String> consumerId = const Value.absent(),
                Value<String> cycleLabel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxReadingKeysCompanion(
                clientUuid: clientUuid,
                consumerId: consumerId,
                cycleLabel: cycleLabel,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientUuid,
                required String consumerId,
                required String cycleLabel,
                Value<int> rowid = const Value.absent(),
              }) => OutboxReadingKeysCompanion.insert(
                clientUuid: clientUuid,
                consumerId: consumerId,
                cycleLabel: cycleLabel,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxReadingKeysTable, OutboxReadingKeyRow>(
                    table,
                  ),
                  $$OutboxReadingKeysTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({clientUuid = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (clientUuid) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.clientUuid,
                                referencedTable:
                                    $$OutboxReadingKeysTableReferences
                                        ._clientUuidTable(db),
                                referencedColumn:
                                    $$OutboxReadingKeysTableReferences
                                        ._clientUuidTable(db)
                                        .clientUuid,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OutboxReadingKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxReadingKeysTable,
      OutboxReadingKeyRow,
      $$OutboxReadingKeysTableFilterComposer,
      $$OutboxReadingKeysTableOrderingComposer,
      $$OutboxReadingKeysTableAnnotationComposer,
      $$OutboxReadingKeysTableCreateCompanionBuilder,
      $$OutboxReadingKeysTableUpdateCompanionBuilder,
      (OutboxReadingKeyRow, $$OutboxReadingKeysTableReferences),
      OutboxReadingKeyRow,
      PrefetchHooks Function({bool clientUuid})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedConsumersTableTableManager get cachedConsumers =>
      $$CachedConsumersTableTableManager(_db, _db.cachedConsumers);
  $$CachedBillsTableTableManager get cachedBills =>
      $$CachedBillsTableTableManager(_db, _db.cachedBills);
  $$CachedPaymentsTableTableManager get cachedPayments =>
      $$CachedPaymentsTableTableManager(_db, _db.cachedPayments);
  $$CachedNotificationsTableTableManager get cachedNotifications =>
      $$CachedNotificationsTableTableManager(_db, _db.cachedNotifications);
  $$CacheOwnerTableTableManager get cacheOwner =>
      $$CacheOwnerTableTableManager(_db, _db.cacheOwner);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
  $$OutboxRowsTableTableManager get outboxRows =>
      $$OutboxRowsTableTableManager(_db, _db.outboxRows);
  $$OutboxReadingKeysTableTableManager get outboxReadingKeys =>
      $$OutboxReadingKeysTableTableManager(_db, _db.outboxReadingKeys);
}
