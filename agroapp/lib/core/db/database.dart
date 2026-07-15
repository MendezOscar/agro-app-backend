import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// --- Tablas locales (espejo de las entidades operativas) ---
// `dirty` marca filas modificadas localmente pendientes de empujar en el próximo sync.

class Farms extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get areaHa => real().withDefault(const Constant(0))();
  TextColumn get boundaryJson => text().nullable()(); // [[lng,lat],...]
  RealColumn get lng => real().nullable()();
  RealColumn get lat => real().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Plots extends Table {
  TextColumn get id => text()();
  TextColumn get farmId => text()();
  TextColumn get name => text()();
  RealColumn get areaHa => real().withDefault(const Constant(0))();
  TextColumn get boundaryJson => text().nullable()();
  TextColumn get soilType => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Cycles extends Table {
  TextColumn get id => text()();
  TextColumn get plotId => text()();
  TextColumn get crop => text()();
  TextColumn get variety => text().nullable()();
  IntColumn get status => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Stages extends Table {
  TextColumn get id => text()();
  TextColumn get cycleId => text()();
  IntColumn get kind => integer()();
  IntColumn get status => integer().withDefault(const Constant(0))();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get stageId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get assignedToUserId => text().nullable()();
  IntColumn get status => integer().withDefault(const Constant(0))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class Observations extends Table {
  TextColumn get id => text()();
  TextColumn get cycleId => text()();
  TextColumn get createdByUserId => text()();
  RealColumn get lng => real().nullable()();
  RealColumn get lat => real().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get photoKey => text().nullable()();
  TextColumn get photoLocalPath => text().nullable()(); // foto pendiente de subir
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class Costs extends Table {
  TextColumn get id => text()();
  TextColumn get cycleId => text()();
  IntColumn get kind => integer()();
  TextColumn get description => text().nullable()();
  TextColumn get inputId => text().nullable()();
  TextColumn get workTaskId => text().nullable()();
  TextColumn get stageId => text().nullable()();
  RealColumn get quantity => real()();
  RealColumn get unitCost => real()();
  RealColumn get total => real()();
  DateTimeColumn get incurredAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class SyncMeta extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [Farms, Plots, Cycles, Stages, Tasks, Observations, Costs, SyncMeta],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(costs, costs.stageId);
        },
      );

  Future<DateTime?> lastSyncAt() async {
    final row = await (select(syncMeta)..where((t) => t.id.equals(1))).getSingleOrNull();
    return row?.lastSyncAt;
  }

  Future<void> setLastSyncAt(DateTime value) =>
      into(syncMeta).insertOnConflictUpdate(SyncMetaCompanion.insert(lastSyncAt: Value(value)));
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'agroapp.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
