// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hito_db.dart';

// ignore_for_file: type=lint
class $CachedPropertiesTable extends CachedProperties
    with TableInfo<$CachedPropertiesTable, CachedPropertyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPropertiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, dataJson, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_properties';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPropertyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedPropertyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPropertyRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedPropertiesTable createAlias(String alias) {
    return $CachedPropertiesTable(attachedDatabase, alias);
  }
}

class CachedPropertyRow extends DataClass
    implements Insertable<CachedPropertyRow> {
  final String id;
  final String dataJson;
  final DateTime cachedAt;
  const CachedPropertyRow({
    required this.id,
    required this.dataJson,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['data_json'] = Variable<String>(dataJson);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedPropertiesCompanion toCompanion(bool nullToAbsent) {
    return CachedPropertiesCompanion(
      id: Value(id),
      dataJson: Value(dataJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedPropertyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPropertyRow(
      id: serializer.fromJson<String>(json['id']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'dataJson': serializer.toJson<String>(dataJson),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedPropertyRow copyWith({
    String? id,
    String? dataJson,
    DateTime? cachedAt,
  }) => CachedPropertyRow(
    id: id ?? this.id,
    dataJson: dataJson ?? this.dataJson,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedPropertyRow copyWithCompanion(CachedPropertiesCompanion data) {
    return CachedPropertyRow(
      id: data.id.present ? data.id.value : this.id,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPropertyRow(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, dataJson, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPropertyRow &&
          other.id == this.id &&
          other.dataJson == this.dataJson &&
          other.cachedAt == this.cachedAt);
}

class CachedPropertiesCompanion extends UpdateCompanion<CachedPropertyRow> {
  final Value<String> id;
  final Value<String> dataJson;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedPropertiesCompanion({
    this.id = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPropertiesCompanion.insert({
    required String id,
    required String dataJson,
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       dataJson = Value(dataJson);
  static Insertable<CachedPropertyRow> custom({
    Expression<String>? id,
    Expression<String>? dataJson,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dataJson != null) 'data_json': dataJson,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPropertiesCompanion copyWith({
    Value<String>? id,
    Value<String>? dataJson,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedPropertiesCompanion(
      id: id ?? this.id,
      dataJson: dataJson ?? this.dataJson,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPropertiesCompanion(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$HitoDatabase extends GeneratedDatabase {
  _$HitoDatabase(QueryExecutor e) : super(e);
  $HitoDatabaseManager get managers => $HitoDatabaseManager(this);
  late final $CachedPropertiesTable cachedProperties = $CachedPropertiesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [cachedProperties];
}

typedef $$CachedPropertiesTableCreateCompanionBuilder =
    CachedPropertiesCompanion Function({
      required String id,
      required String dataJson,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });
typedef $$CachedPropertiesTableUpdateCompanionBuilder =
    CachedPropertiesCompanion Function({
      Value<String> id,
      Value<String> dataJson,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedPropertiesTableFilterComposer
    extends Composer<_$HitoDatabase, $CachedPropertiesTable> {
  $$CachedPropertiesTableFilterComposer({
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

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPropertiesTableOrderingComposer
    extends Composer<_$HitoDatabase, $CachedPropertiesTable> {
  $$CachedPropertiesTableOrderingComposer({
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

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPropertiesTableAnnotationComposer
    extends Composer<_$HitoDatabase, $CachedPropertiesTable> {
  $$CachedPropertiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedPropertiesTableTableManager
    extends
        RootTableManager<
          _$HitoDatabase,
          $CachedPropertiesTable,
          CachedPropertyRow,
          $$CachedPropertiesTableFilterComposer,
          $$CachedPropertiesTableOrderingComposer,
          $$CachedPropertiesTableAnnotationComposer,
          $$CachedPropertiesTableCreateCompanionBuilder,
          $$CachedPropertiesTableUpdateCompanionBuilder,
          (
            CachedPropertyRow,
            BaseReferences<
              _$HitoDatabase,
              $CachedPropertiesTable,
              CachedPropertyRow
            >,
          ),
          CachedPropertyRow,
          PrefetchHooks Function()
        > {
  $$CachedPropertiesTableTableManager(
    _$HitoDatabase db,
    $CachedPropertiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPropertiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPropertiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPropertiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPropertiesCompanion(
                id: id,
                dataJson: dataJson,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String dataJson,
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPropertiesCompanion.insert(
                id: id,
                dataJson: dataJson,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPropertiesTableProcessedTableManager =
    ProcessedTableManager<
      _$HitoDatabase,
      $CachedPropertiesTable,
      CachedPropertyRow,
      $$CachedPropertiesTableFilterComposer,
      $$CachedPropertiesTableOrderingComposer,
      $$CachedPropertiesTableAnnotationComposer,
      $$CachedPropertiesTableCreateCompanionBuilder,
      $$CachedPropertiesTableUpdateCompanionBuilder,
      (
        CachedPropertyRow,
        BaseReferences<
          _$HitoDatabase,
          $CachedPropertiesTable,
          CachedPropertyRow
        >,
      ),
      CachedPropertyRow,
      PrefetchHooks Function()
    >;

class $HitoDatabaseManager {
  final _$HitoDatabase _db;
  $HitoDatabaseManager(this._db);
  $$CachedPropertiesTableTableManager get cachedProperties =>
      $$CachedPropertiesTableTableManager(_db, _db.cachedProperties);
}
