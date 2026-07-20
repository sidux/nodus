// dart format width=80
// ignore_for_file: type=lint
part of 'nodus.runtime.g.dart';

class $TaskRowsTable extends TaskRows with TableInfo<$TaskRowsTable, TaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('todo'),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('normal'),
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<String> dueAt = GeneratedColumn<String>(
    'due_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<String> completedAt = GeneratedColumn<String>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<String> archivedAt = GeneratedColumn<String>(
    'archived_at',
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
  static const VerificationMeta _orderRankMeta = const VerificationMeta(
    'orderRank',
  );
  @override
  late final GeneratedColumn<String> orderRank = GeneratedColumn<String>(
    'order_rank',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(
      '057896044618658097711785492504343953926634992332820282019728792003956564819967',
    ),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'local_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acceptedSnapshotMeta = const VerificationMeta(
    'acceptedSnapshot',
  );
  @override
  late final GeneratedColumn<String> acceptedSnapshot = GeneratedColumn<String>(
    'accepted_snapshot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    projectId,
    title,
    description,
    status,
    priority,
    dueAt,
    completedAt,
    archivedAt,
    createdAt,
    orderRank,
    deletedAt,
    serverVersion,
    localRevision,
    acceptedSnapshot,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
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
    if (data.containsKey('order_rank')) {
      context.handle(
        _orderRankMeta,
        orderRank.isAcceptableOrUnknown(data['order_rank']!, _orderRankMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    if (data.containsKey('local_revision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['local_revision']!,
          _localRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localRevisionMeta);
    }
    if (data.containsKey('accepted_snapshot')) {
      context.handle(
        _acceptedSnapshotMeta,
        acceptedSnapshot.isAcceptableOrUnknown(
          data['accepted_snapshot']!,
          _acceptedSnapshotMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_at'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}completed_at'],
      ),
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}archived_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      orderRank: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_rank'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      )!,
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_revision'],
      )!,
      acceptedSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accepted_snapshot'],
      ),
    );
  }

  @override
  $TaskRowsTable createAlias(String alias) {
    return $TaskRowsTable(attachedDatabase, alias);
  }
}

class TaskRow extends DataClass implements Insertable<TaskRow> {
  final String id;
  final String ownerId;
  final String? projectId;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String? dueAt;
  final String? completedAt;
  final String? archivedAt;
  final String createdAt;
  final String orderRank;
  final String? deletedAt;
  final int serverVersion;
  final int localRevision;
  final String? acceptedSnapshot;
  const TaskRow({
    required this.id,
    required this.ownerId,
    this.projectId,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    this.dueAt,
    this.completedAt,
    this.archivedAt,
    required this.createdAt,
    required this.orderRank,
    this.deletedAt,
    required this.serverVersion,
    required this.localRevision,
    this.acceptedSnapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['status'] = Variable<String>(status);
    map['priority'] = Variable<String>(priority);
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<String>(dueAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<String>(completedAt);
    }
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<String>(archivedAt);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['order_rank'] = Variable<String>(orderRank);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    map['server_version'] = Variable<int>(serverVersion);
    map['local_revision'] = Variable<int>(localRevision);
    if (!nullToAbsent || acceptedSnapshot != null) {
      map['accepted_snapshot'] = Variable<String>(acceptedSnapshot);
    }
    return map;
  }

  TaskRowsCompanion toCompanion(bool nullToAbsent) {
    return TaskRowsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      status: Value(status),
      priority: Value(priority),
      dueAt: dueAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dueAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      createdAt: Value(createdAt),
      orderRank: Value(orderRank),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      serverVersion: Value(serverVersion),
      localRevision: Value(localRevision),
      acceptedSnapshot: acceptedSnapshot == null && nullToAbsent
          ? const Value.absent()
          : Value(acceptedSnapshot),
    );
  }

  factory TaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskRow(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      projectId: serializer.fromJson<String?>(json['projectId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      status: serializer.fromJson<String>(json['status']),
      priority: serializer.fromJson<String>(json['priority']),
      dueAt: serializer.fromJson<String?>(json['dueAt']),
      completedAt: serializer.fromJson<String?>(json['completedAt']),
      archivedAt: serializer.fromJson<String?>(json['archivedAt']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      orderRank: serializer.fromJson<String>(json['orderRank']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
      serverVersion: serializer.fromJson<int>(json['serverVersion']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
      acceptedSnapshot: serializer.fromJson<String?>(json['acceptedSnapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'projectId': serializer.toJson<String?>(projectId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'status': serializer.toJson<String>(status),
      'priority': serializer.toJson<String>(priority),
      'dueAt': serializer.toJson<String?>(dueAt),
      'completedAt': serializer.toJson<String?>(completedAt),
      'archivedAt': serializer.toJson<String?>(archivedAt),
      'createdAt': serializer.toJson<String>(createdAt),
      'orderRank': serializer.toJson<String>(orderRank),
      'deletedAt': serializer.toJson<String?>(deletedAt),
      'serverVersion': serializer.toJson<int>(serverVersion),
      'localRevision': serializer.toJson<int>(localRevision),
      'acceptedSnapshot': serializer.toJson<String?>(acceptedSnapshot),
    };
  }

  TaskRow copyWith({
    String? id,
    String? ownerId,
    Value<String?> projectId = const Value.absent(),
    String? title,
    Value<String?> description = const Value.absent(),
    String? status,
    String? priority,
    Value<String?> dueAt = const Value.absent(),
    Value<String?> completedAt = const Value.absent(),
    Value<String?> archivedAt = const Value.absent(),
    String? createdAt,
    String? orderRank,
    Value<String?> deletedAt = const Value.absent(),
    int? serverVersion,
    int? localRevision,
    Value<String?> acceptedSnapshot = const Value.absent(),
  }) => TaskRow(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    projectId: projectId.present ? projectId.value : this.projectId,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    dueAt: dueAt.present ? dueAt.value : this.dueAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    createdAt: createdAt ?? this.createdAt,
    orderRank: orderRank ?? this.orderRank,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    serverVersion: serverVersion ?? this.serverVersion,
    localRevision: localRevision ?? this.localRevision,
    acceptedSnapshot: acceptedSnapshot.present
        ? acceptedSnapshot.value
        : this.acceptedSnapshot,
  );
  TaskRow copyWithCompanion(TaskRowsCompanion data) {
    return TaskRow(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      status: data.status.present ? data.status.value : this.status,
      priority: data.priority.present ? data.priority.value : this.priority,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      orderRank: data.orderRank.present ? data.orderRank.value : this.orderRank,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
      acceptedSnapshot: data.acceptedSnapshot.present
          ? data.acceptedSnapshot.value
          : this.acceptedSnapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskRow(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('projectId: $projectId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('dueAt: $dueAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('orderRank: $orderRank, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('localRevision: $localRevision, ')
          ..write('acceptedSnapshot: $acceptedSnapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    projectId,
    title,
    description,
    status,
    priority,
    dueAt,
    completedAt,
    archivedAt,
    createdAt,
    orderRank,
    deletedAt,
    serverVersion,
    localRevision,
    acceptedSnapshot,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskRow &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.projectId == this.projectId &&
          other.title == this.title &&
          other.description == this.description &&
          other.status == this.status &&
          other.priority == this.priority &&
          other.dueAt == this.dueAt &&
          other.completedAt == this.completedAt &&
          other.archivedAt == this.archivedAt &&
          other.createdAt == this.createdAt &&
          other.orderRank == this.orderRank &&
          other.deletedAt == this.deletedAt &&
          other.serverVersion == this.serverVersion &&
          other.localRevision == this.localRevision &&
          other.acceptedSnapshot == this.acceptedSnapshot);
}

class TaskRowsCompanion extends UpdateCompanion<TaskRow> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String?> projectId;
  final Value<String> title;
  final Value<String?> description;
  final Value<String> status;
  final Value<String> priority;
  final Value<String?> dueAt;
  final Value<String?> completedAt;
  final Value<String?> archivedAt;
  final Value<String> createdAt;
  final Value<String> orderRank;
  final Value<String?> deletedAt;
  final Value<int> serverVersion;
  final Value<int> localRevision;
  final Value<String?> acceptedSnapshot;
  final Value<int> rowid;
  const TaskRowsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.orderRank = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.acceptedSnapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskRowsCompanion.insert({
    required String id,
    required String ownerId,
    this.projectId = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    required String createdAt,
    this.orderRank = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    required int localRevision,
    this.acceptedSnapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       title = Value(title),
       createdAt = Value(createdAt),
       localRevision = Value(localRevision);
  static Insertable<TaskRow> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? projectId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? status,
    Expression<String>? priority,
    Expression<String>? dueAt,
    Expression<String>? completedAt,
    Expression<String>? archivedAt,
    Expression<String>? createdAt,
    Expression<String>? orderRank,
    Expression<String>? deletedAt,
    Expression<int>? serverVersion,
    Expression<int>? localRevision,
    Expression<String>? acceptedSnapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (projectId != null) 'project_id': projectId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (dueAt != null) 'due_at': dueAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (orderRank != null) 'order_rank': orderRank,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (serverVersion != null) 'server_version': serverVersion,
      if (localRevision != null) 'local_revision': localRevision,
      if (acceptedSnapshot != null) 'accepted_snapshot': acceptedSnapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String?>? projectId,
    Value<String>? title,
    Value<String?>? description,
    Value<String>? status,
    Value<String>? priority,
    Value<String?>? dueAt,
    Value<String?>? completedAt,
    Value<String?>? archivedAt,
    Value<String>? createdAt,
    Value<String>? orderRank,
    Value<String?>? deletedAt,
    Value<int>? serverVersion,
    Value<int>? localRevision,
    Value<String?>? acceptedSnapshot,
    Value<int>? rowid,
  }) {
    return TaskRowsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueAt: dueAt ?? this.dueAt,
      completedAt: completedAt ?? this.completedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      orderRank: orderRank ?? this.orderRank,
      deletedAt: deletedAt ?? this.deletedAt,
      serverVersion: serverVersion ?? this.serverVersion,
      localRevision: localRevision ?? this.localRevision,
      acceptedSnapshot: acceptedSnapshot ?? this.acceptedSnapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<String>(dueAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<String>(completedAt.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<String>(archivedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (orderRank.present) {
      map['order_rank'] = Variable<String>(orderRank.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (localRevision.present) {
      map['local_revision'] = Variable<int>(localRevision.value);
    }
    if (acceptedSnapshot.present) {
      map['accepted_snapshot'] = Variable<String>(acceptedSnapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskRowsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('projectId: $projectId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('dueAt: $dueAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('orderRank: $orderRank, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('localRevision: $localRevision, ')
          ..write('acceptedSnapshot: $acceptedSnapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskActivityRowsTable extends TaskActivityRows
    with TableInfo<$TaskActivityRowsTable, TaskActivityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskActivityRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
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
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceOperationIdMeta = const VerificationMeta(
    'sourceOperationId',
  );
  @override
  late final GeneratedColumn<String> sourceOperationId =
      GeneratedColumn<String>(
        'source_operation_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<String> occurredAt = GeneratedColumn<String>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'local_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acceptedSnapshotMeta = const VerificationMeta(
    'acceptedSnapshot',
  );
  @override
  late final GeneratedColumn<String> acceptedSnapshot = GeneratedColumn<String>(
    'accepted_snapshot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    subjectId,
    actorId,
    operation,
    label,
    sourceOperationId,
    occurredAt,
    deletedAt,
    serverVersion,
    localRevision,
    acceptedSnapshot,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_activities';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskActivityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actorIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('source_operation_id')) {
      context.handle(
        _sourceOperationIdMeta,
        sourceOperationId.isAcceptableOrUnknown(
          data['source_operation_id']!,
          _sourceOperationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceOperationIdMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    if (data.containsKey('local_revision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['local_revision']!,
          _localRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localRevisionMeta);
    }
    if (data.containsKey('accepted_snapshot')) {
      context.handle(
        _acceptedSnapshotMeta,
        acceptedSnapshot.isAcceptableOrUnknown(
          data['accepted_snapshot']!,
          _acceptedSnapshotMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskActivityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskActivityRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      sourceOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_operation_id'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurred_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      )!,
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_revision'],
      )!,
      acceptedSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accepted_snapshot'],
      ),
    );
  }

  @override
  $TaskActivityRowsTable createAlias(String alias) {
    return $TaskActivityRowsTable(attachedDatabase, alias);
  }
}

class TaskActivityRow extends DataClass implements Insertable<TaskActivityRow> {
  final String id;
  final String ownerId;
  final String subjectId;
  final String actorId;
  final String operation;
  final String label;
  final String sourceOperationId;
  final String occurredAt;
  final String? deletedAt;
  final int serverVersion;
  final int localRevision;
  final String? acceptedSnapshot;
  const TaskActivityRow({
    required this.id,
    required this.ownerId,
    required this.subjectId,
    required this.actorId,
    required this.operation,
    required this.label,
    required this.sourceOperationId,
    required this.occurredAt,
    this.deletedAt,
    required this.serverVersion,
    required this.localRevision,
    this.acceptedSnapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['subject_id'] = Variable<String>(subjectId);
    map['actor_id'] = Variable<String>(actorId);
    map['operation'] = Variable<String>(operation);
    map['label'] = Variable<String>(label);
    map['source_operation_id'] = Variable<String>(sourceOperationId);
    map['occurred_at'] = Variable<String>(occurredAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    map['server_version'] = Variable<int>(serverVersion);
    map['local_revision'] = Variable<int>(localRevision);
    if (!nullToAbsent || acceptedSnapshot != null) {
      map['accepted_snapshot'] = Variable<String>(acceptedSnapshot);
    }
    return map;
  }

  TaskActivityRowsCompanion toCompanion(bool nullToAbsent) {
    return TaskActivityRowsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      subjectId: Value(subjectId),
      actorId: Value(actorId),
      operation: Value(operation),
      label: Value(label),
      sourceOperationId: Value(sourceOperationId),
      occurredAt: Value(occurredAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      serverVersion: Value(serverVersion),
      localRevision: Value(localRevision),
      acceptedSnapshot: acceptedSnapshot == null && nullToAbsent
          ? const Value.absent()
          : Value(acceptedSnapshot),
    );
  }

  factory TaskActivityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskActivityRow(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      subjectId: serializer.fromJson<String>(json['subjectId']),
      actorId: serializer.fromJson<String>(json['actorId']),
      operation: serializer.fromJson<String>(json['operation']),
      label: serializer.fromJson<String>(json['label']),
      sourceOperationId: serializer.fromJson<String>(json['sourceOperationId']),
      occurredAt: serializer.fromJson<String>(json['occurredAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
      serverVersion: serializer.fromJson<int>(json['serverVersion']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
      acceptedSnapshot: serializer.fromJson<String?>(json['acceptedSnapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'subjectId': serializer.toJson<String>(subjectId),
      'actorId': serializer.toJson<String>(actorId),
      'operation': serializer.toJson<String>(operation),
      'label': serializer.toJson<String>(label),
      'sourceOperationId': serializer.toJson<String>(sourceOperationId),
      'occurredAt': serializer.toJson<String>(occurredAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
      'serverVersion': serializer.toJson<int>(serverVersion),
      'localRevision': serializer.toJson<int>(localRevision),
      'acceptedSnapshot': serializer.toJson<String?>(acceptedSnapshot),
    };
  }

  TaskActivityRow copyWith({
    String? id,
    String? ownerId,
    String? subjectId,
    String? actorId,
    String? operation,
    String? label,
    String? sourceOperationId,
    String? occurredAt,
    Value<String?> deletedAt = const Value.absent(),
    int? serverVersion,
    int? localRevision,
    Value<String?> acceptedSnapshot = const Value.absent(),
  }) => TaskActivityRow(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    subjectId: subjectId ?? this.subjectId,
    actorId: actorId ?? this.actorId,
    operation: operation ?? this.operation,
    label: label ?? this.label,
    sourceOperationId: sourceOperationId ?? this.sourceOperationId,
    occurredAt: occurredAt ?? this.occurredAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    serverVersion: serverVersion ?? this.serverVersion,
    localRevision: localRevision ?? this.localRevision,
    acceptedSnapshot: acceptedSnapshot.present
        ? acceptedSnapshot.value
        : this.acceptedSnapshot,
  );
  TaskActivityRow copyWithCompanion(TaskActivityRowsCompanion data) {
    return TaskActivityRow(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      operation: data.operation.present ? data.operation.value : this.operation,
      label: data.label.present ? data.label.value : this.label,
      sourceOperationId: data.sourceOperationId.present
          ? data.sourceOperationId.value
          : this.sourceOperationId,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
      acceptedSnapshot: data.acceptedSnapshot.present
          ? data.acceptedSnapshot.value
          : this.acceptedSnapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskActivityRow(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('subjectId: $subjectId, ')
          ..write('actorId: $actorId, ')
          ..write('operation: $operation, ')
          ..write('label: $label, ')
          ..write('sourceOperationId: $sourceOperationId, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('localRevision: $localRevision, ')
          ..write('acceptedSnapshot: $acceptedSnapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    subjectId,
    actorId,
    operation,
    label,
    sourceOperationId,
    occurredAt,
    deletedAt,
    serverVersion,
    localRevision,
    acceptedSnapshot,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskActivityRow &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.subjectId == this.subjectId &&
          other.actorId == this.actorId &&
          other.operation == this.operation &&
          other.label == this.label &&
          other.sourceOperationId == this.sourceOperationId &&
          other.occurredAt == this.occurredAt &&
          other.deletedAt == this.deletedAt &&
          other.serverVersion == this.serverVersion &&
          other.localRevision == this.localRevision &&
          other.acceptedSnapshot == this.acceptedSnapshot);
}

class TaskActivityRowsCompanion extends UpdateCompanion<TaskActivityRow> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> subjectId;
  final Value<String> actorId;
  final Value<String> operation;
  final Value<String> label;
  final Value<String> sourceOperationId;
  final Value<String> occurredAt;
  final Value<String?> deletedAt;
  final Value<int> serverVersion;
  final Value<int> localRevision;
  final Value<String?> acceptedSnapshot;
  final Value<int> rowid;
  const TaskActivityRowsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.actorId = const Value.absent(),
    this.operation = const Value.absent(),
    this.label = const Value.absent(),
    this.sourceOperationId = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.acceptedSnapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskActivityRowsCompanion.insert({
    required String id,
    required String ownerId,
    required String subjectId,
    required String actorId,
    required String operation,
    required String label,
    required String sourceOperationId,
    required String occurredAt,
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    required int localRevision,
    this.acceptedSnapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       subjectId = Value(subjectId),
       actorId = Value(actorId),
       operation = Value(operation),
       label = Value(label),
       sourceOperationId = Value(sourceOperationId),
       occurredAt = Value(occurredAt),
       localRevision = Value(localRevision);
  static Insertable<TaskActivityRow> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? subjectId,
    Expression<String>? actorId,
    Expression<String>? operation,
    Expression<String>? label,
    Expression<String>? sourceOperationId,
    Expression<String>? occurredAt,
    Expression<String>? deletedAt,
    Expression<int>? serverVersion,
    Expression<int>? localRevision,
    Expression<String>? acceptedSnapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (subjectId != null) 'subject_id': subjectId,
      if (actorId != null) 'actor_id': actorId,
      if (operation != null) 'operation': operation,
      if (label != null) 'label': label,
      if (sourceOperationId != null) 'source_operation_id': sourceOperationId,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (serverVersion != null) 'server_version': serverVersion,
      if (localRevision != null) 'local_revision': localRevision,
      if (acceptedSnapshot != null) 'accepted_snapshot': acceptedSnapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskActivityRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? subjectId,
    Value<String>? actorId,
    Value<String>? operation,
    Value<String>? label,
    Value<String>? sourceOperationId,
    Value<String>? occurredAt,
    Value<String?>? deletedAt,
    Value<int>? serverVersion,
    Value<int>? localRevision,
    Value<String?>? acceptedSnapshot,
    Value<int>? rowid,
  }) {
    return TaskActivityRowsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      subjectId: subjectId ?? this.subjectId,
      actorId: actorId ?? this.actorId,
      operation: operation ?? this.operation,
      label: label ?? this.label,
      sourceOperationId: sourceOperationId ?? this.sourceOperationId,
      occurredAt: occurredAt ?? this.occurredAt,
      deletedAt: deletedAt ?? this.deletedAt,
      serverVersion: serverVersion ?? this.serverVersion,
      localRevision: localRevision ?? this.localRevision,
      acceptedSnapshot: acceptedSnapshot ?? this.acceptedSnapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (sourceOperationId.present) {
      map['source_operation_id'] = Variable<String>(sourceOperationId.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<String>(occurredAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (localRevision.present) {
      map['local_revision'] = Variable<int>(localRevision.value);
    }
    if (acceptedSnapshot.present) {
      map['accepted_snapshot'] = Variable<String>(acceptedSnapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskActivityRowsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('subjectId: $subjectId, ')
          ..write('actorId: $actorId, ')
          ..write('operation: $operation, ')
          ..write('label: $label, ')
          ..write('sourceOperationId: $sourceOperationId, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('localRevision: $localRevision, ')
          ..write('acceptedSnapshot: $acceptedSnapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskProjectRowsTable extends TaskProjectRows
    with TableInfo<$TaskProjectRowsTable, TaskProjectRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskProjectRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderRankMeta = const VerificationMeta(
    'orderRank',
  );
  @override
  late final GeneratedColumn<String> orderRank = GeneratedColumn<String>(
    'order_rank',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(
      '057896044618658097711785492504343953926634992332820282019728792003956564819967',
    ),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'local_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acceptedSnapshotMeta = const VerificationMeta(
    'acceptedSnapshot',
  );
  @override
  late final GeneratedColumn<String> acceptedSnapshot = GeneratedColumn<String>(
    'accepted_snapshot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    title,
    orderRank,
    deletedAt,
    serverVersion,
    localRevision,
    acceptedSnapshot,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskProjectRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('order_rank')) {
      context.handle(
        _orderRankMeta,
        orderRank.isAcceptableOrUnknown(data['order_rank']!, _orderRankMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    if (data.containsKey('local_revision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['local_revision']!,
          _localRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localRevisionMeta);
    }
    if (data.containsKey('accepted_snapshot')) {
      context.handle(
        _acceptedSnapshotMeta,
        acceptedSnapshot.isAcceptableOrUnknown(
          data['accepted_snapshot']!,
          _acceptedSnapshotMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskProjectRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskProjectRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      orderRank: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_rank'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      )!,
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_revision'],
      )!,
      acceptedSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accepted_snapshot'],
      ),
    );
  }

  @override
  $TaskProjectRowsTable createAlias(String alias) {
    return $TaskProjectRowsTable(attachedDatabase, alias);
  }
}

class TaskProjectRow extends DataClass implements Insertable<TaskProjectRow> {
  final String id;
  final String ownerId;
  final String title;
  final String orderRank;
  final String? deletedAt;
  final int serverVersion;
  final int localRevision;
  final String? acceptedSnapshot;
  const TaskProjectRow({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.orderRank,
    this.deletedAt,
    required this.serverVersion,
    required this.localRevision,
    this.acceptedSnapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['title'] = Variable<String>(title);
    map['order_rank'] = Variable<String>(orderRank);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    map['server_version'] = Variable<int>(serverVersion);
    map['local_revision'] = Variable<int>(localRevision);
    if (!nullToAbsent || acceptedSnapshot != null) {
      map['accepted_snapshot'] = Variable<String>(acceptedSnapshot);
    }
    return map;
  }

  TaskProjectRowsCompanion toCompanion(bool nullToAbsent) {
    return TaskProjectRowsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      title: Value(title),
      orderRank: Value(orderRank),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      serverVersion: Value(serverVersion),
      localRevision: Value(localRevision),
      acceptedSnapshot: acceptedSnapshot == null && nullToAbsent
          ? const Value.absent()
          : Value(acceptedSnapshot),
    );
  }

  factory TaskProjectRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskProjectRow(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      title: serializer.fromJson<String>(json['title']),
      orderRank: serializer.fromJson<String>(json['orderRank']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
      serverVersion: serializer.fromJson<int>(json['serverVersion']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
      acceptedSnapshot: serializer.fromJson<String?>(json['acceptedSnapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'title': serializer.toJson<String>(title),
      'orderRank': serializer.toJson<String>(orderRank),
      'deletedAt': serializer.toJson<String?>(deletedAt),
      'serverVersion': serializer.toJson<int>(serverVersion),
      'localRevision': serializer.toJson<int>(localRevision),
      'acceptedSnapshot': serializer.toJson<String?>(acceptedSnapshot),
    };
  }

  TaskProjectRow copyWith({
    String? id,
    String? ownerId,
    String? title,
    String? orderRank,
    Value<String?> deletedAt = const Value.absent(),
    int? serverVersion,
    int? localRevision,
    Value<String?> acceptedSnapshot = const Value.absent(),
  }) => TaskProjectRow(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    title: title ?? this.title,
    orderRank: orderRank ?? this.orderRank,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    serverVersion: serverVersion ?? this.serverVersion,
    localRevision: localRevision ?? this.localRevision,
    acceptedSnapshot: acceptedSnapshot.present
        ? acceptedSnapshot.value
        : this.acceptedSnapshot,
  );
  TaskProjectRow copyWithCompanion(TaskProjectRowsCompanion data) {
    return TaskProjectRow(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      title: data.title.present ? data.title.value : this.title,
      orderRank: data.orderRank.present ? data.orderRank.value : this.orderRank,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
      acceptedSnapshot: data.acceptedSnapshot.present
          ? data.acceptedSnapshot.value
          : this.acceptedSnapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskProjectRow(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('title: $title, ')
          ..write('orderRank: $orderRank, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('localRevision: $localRevision, ')
          ..write('acceptedSnapshot: $acceptedSnapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    title,
    orderRank,
    deletedAt,
    serverVersion,
    localRevision,
    acceptedSnapshot,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskProjectRow &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.title == this.title &&
          other.orderRank == this.orderRank &&
          other.deletedAt == this.deletedAt &&
          other.serverVersion == this.serverVersion &&
          other.localRevision == this.localRevision &&
          other.acceptedSnapshot == this.acceptedSnapshot);
}

class TaskProjectRowsCompanion extends UpdateCompanion<TaskProjectRow> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> title;
  final Value<String> orderRank;
  final Value<String?> deletedAt;
  final Value<int> serverVersion;
  final Value<int> localRevision;
  final Value<String?> acceptedSnapshot;
  final Value<int> rowid;
  const TaskProjectRowsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.title = const Value.absent(),
    this.orderRank = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.acceptedSnapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskProjectRowsCompanion.insert({
    required String id,
    required String ownerId,
    required String title,
    this.orderRank = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    required int localRevision,
    this.acceptedSnapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       title = Value(title),
       localRevision = Value(localRevision);
  static Insertable<TaskProjectRow> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? title,
    Expression<String>? orderRank,
    Expression<String>? deletedAt,
    Expression<int>? serverVersion,
    Expression<int>? localRevision,
    Expression<String>? acceptedSnapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (title != null) 'title': title,
      if (orderRank != null) 'order_rank': orderRank,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (serverVersion != null) 'server_version': serverVersion,
      if (localRevision != null) 'local_revision': localRevision,
      if (acceptedSnapshot != null) 'accepted_snapshot': acceptedSnapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskProjectRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? title,
    Value<String>? orderRank,
    Value<String?>? deletedAt,
    Value<int>? serverVersion,
    Value<int>? localRevision,
    Value<String?>? acceptedSnapshot,
    Value<int>? rowid,
  }) {
    return TaskProjectRowsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      title: title ?? this.title,
      orderRank: orderRank ?? this.orderRank,
      deletedAt: deletedAt ?? this.deletedAt,
      serverVersion: serverVersion ?? this.serverVersion,
      localRevision: localRevision ?? this.localRevision,
      acceptedSnapshot: acceptedSnapshot ?? this.acceptedSnapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (orderRank.present) {
      map['order_rank'] = Variable<String>(orderRank.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (localRevision.present) {
      map['local_revision'] = Variable<int>(localRevision.value);
    }
    if (acceptedSnapshot.present) {
      map['accepted_snapshot'] = Variable<String>(acceptedSnapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskProjectRowsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('title: $title, ')
          ..write('orderRank: $orderRank, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('localRevision: $localRevision, ')
          ..write('acceptedSnapshot: $acceptedSnapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksExampleSyncWorkRowsTable extends TasksExampleSyncWorkRows
    with TableInfo<$TasksExampleSyncWorkRowsTable, TasksExampleSyncWorkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksExampleSyncWorkRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _syncTargetMeta = const VerificationMeta(
    'syncTarget',
  );
  @override
  late final GeneratedColumn<String> syncTarget = GeneratedColumn<String>(
    'sync_target',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
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
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseServerVersionMeta = const VerificationMeta(
    'baseServerVersion',
  );
  @override
  late final GeneratedColumn<int> baseServerVersion = GeneratedColumn<int>(
    'base_server_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'local_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _protocolVersionMeta = const VerificationMeta(
    'protocolVersion',
  );
  @override
  late final GeneratedColumn<int> protocolVersion = GeneratedColumn<int>(
    'protocol_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _leaseUntilMeta = const VerificationMeta(
    'leaseUntil',
  );
  @override
  late final GeneratedColumn<DateTime> leaseUntil = GeneratedColumn<DateTime>(
    'lease_until',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorDetailMeta = const VerificationMeta(
    'lastErrorDetail',
  );
  @override
  late final GeneratedColumn<String> lastErrorDetail = GeneratedColumn<String>(
    'last_error_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    syncTarget,
    direction,
    kind,
    status,
    entityType,
    entityId,
    operationId,
    baseServerVersion,
    localRevision,
    protocolVersion,
    payload,
    attemptCount,
    nextAttemptAt,
    leaseUntil,
    lastErrorCode,
    lastErrorDetail,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_entity_sync_work';
  @override
  VerificationContext validateIntegrity(
    Insertable<TasksExampleSyncWorkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_target')) {
      context.handle(
        _syncTargetMeta,
        syncTarget.isAcceptableOrUnknown(data['sync_target']!, _syncTargetMeta),
      );
    } else if (isInserting) {
      context.missing(_syncTargetMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('base_server_version')) {
      context.handle(
        _baseServerVersionMeta,
        baseServerVersion.isAcceptableOrUnknown(
          data['base_server_version']!,
          _baseServerVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseServerVersionMeta);
    }
    if (data.containsKey('local_revision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['local_revision']!,
          _localRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localRevisionMeta);
    }
    if (data.containsKey('protocol_version')) {
      context.handle(
        _protocolVersionMeta,
        protocolVersion.isAcceptableOrUnknown(
          data['protocol_version']!,
          _protocolVersionMeta,
        ),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('lease_until')) {
      context.handle(
        _leaseUntilMeta,
        leaseUntil.isAcceptableOrUnknown(data['lease_until']!, _leaseUntilMeta),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('last_error_detail')) {
      context.handle(
        _lastErrorDetailMeta,
        lastErrorDetail.isAcceptableOrUnknown(
          data['last_error_detail']!,
          _lastErrorDetailMeta,
        ),
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
  TasksExampleSyncWorkRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TasksExampleSyncWorkRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      syncTarget: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_target'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      baseServerVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_server_version'],
      )!,
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_revision'],
      )!,
      protocolVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}protocol_version'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      leaseUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}lease_until'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      lastErrorDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_detail'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TasksExampleSyncWorkRowsTable createAlias(String alias) {
    return $TasksExampleSyncWorkRowsTable(attachedDatabase, alias);
  }
}

class TasksExampleSyncWorkRow extends DataClass
    implements Insertable<TasksExampleSyncWorkRow> {
  final int id;
  final String syncTarget;
  final String direction;
  final String kind;
  final String status;
  final String entityType;
  final String entityId;
  final String operationId;
  final int baseServerVersion;
  final int localRevision;
  final int protocolVersion;
  final String payload;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final DateTime? leaseUntil;
  final String? lastErrorCode;
  final String? lastErrorDetail;
  final DateTime createdAt;
  const TasksExampleSyncWorkRow({
    required this.id,
    required this.syncTarget,
    required this.direction,
    required this.kind,
    required this.status,
    required this.entityType,
    required this.entityId,
    required this.operationId,
    required this.baseServerVersion,
    required this.localRevision,
    required this.protocolVersion,
    required this.payload,
    required this.attemptCount,
    this.nextAttemptAt,
    this.leaseUntil,
    this.lastErrorCode,
    this.lastErrorDetail,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['sync_target'] = Variable<String>(syncTarget);
    map['direction'] = Variable<String>(direction);
    map['kind'] = Variable<String>(kind);
    map['status'] = Variable<String>(status);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation_id'] = Variable<String>(operationId);
    map['base_server_version'] = Variable<int>(baseServerVersion);
    map['local_revision'] = Variable<int>(localRevision);
    map['protocol_version'] = Variable<int>(protocolVersion);
    map['payload'] = Variable<String>(payload);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || leaseUntil != null) {
      map['lease_until'] = Variable<DateTime>(leaseUntil);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    if (!nullToAbsent || lastErrorDetail != null) {
      map['last_error_detail'] = Variable<String>(lastErrorDetail);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TasksExampleSyncWorkRowsCompanion toCompanion(bool nullToAbsent) {
    return TasksExampleSyncWorkRowsCompanion(
      id: Value(id),
      syncTarget: Value(syncTarget),
      direction: Value(direction),
      kind: Value(kind),
      status: Value(status),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operationId: Value(operationId),
      baseServerVersion: Value(baseServerVersion),
      localRevision: Value(localRevision),
      protocolVersion: Value(protocolVersion),
      payload: Value(payload),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      leaseUntil: leaseUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseUntil),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      lastErrorDetail: lastErrorDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorDetail),
      createdAt: Value(createdAt),
    );
  }

  factory TasksExampleSyncWorkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TasksExampleSyncWorkRow(
      id: serializer.fromJson<int>(json['id']),
      syncTarget: serializer.fromJson<String>(json['syncTarget']),
      direction: serializer.fromJson<String>(json['direction']),
      kind: serializer.fromJson<String>(json['kind']),
      status: serializer.fromJson<String>(json['status']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operationId: serializer.fromJson<String>(json['operationId']),
      baseServerVersion: serializer.fromJson<int>(json['baseServerVersion']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
      protocolVersion: serializer.fromJson<int>(json['protocolVersion']),
      payload: serializer.fromJson<String>(json['payload']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      leaseUntil: serializer.fromJson<DateTime?>(json['leaseUntil']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      lastErrorDetail: serializer.fromJson<String?>(json['lastErrorDetail']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncTarget': serializer.toJson<String>(syncTarget),
      'direction': serializer.toJson<String>(direction),
      'kind': serializer.toJson<String>(kind),
      'status': serializer.toJson<String>(status),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operationId': serializer.toJson<String>(operationId),
      'baseServerVersion': serializer.toJson<int>(baseServerVersion),
      'localRevision': serializer.toJson<int>(localRevision),
      'protocolVersion': serializer.toJson<int>(protocolVersion),
      'payload': serializer.toJson<String>(payload),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'leaseUntil': serializer.toJson<DateTime?>(leaseUntil),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'lastErrorDetail': serializer.toJson<String?>(lastErrorDetail),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TasksExampleSyncWorkRow copyWith({
    int? id,
    String? syncTarget,
    String? direction,
    String? kind,
    String? status,
    String? entityType,
    String? entityId,
    String? operationId,
    int? baseServerVersion,
    int? localRevision,
    int? protocolVersion,
    String? payload,
    int? attemptCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<DateTime?> leaseUntil = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
    Value<String?> lastErrorDetail = const Value.absent(),
    DateTime? createdAt,
  }) => TasksExampleSyncWorkRow(
    id: id ?? this.id,
    syncTarget: syncTarget ?? this.syncTarget,
    direction: direction ?? this.direction,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operationId: operationId ?? this.operationId,
    baseServerVersion: baseServerVersion ?? this.baseServerVersion,
    localRevision: localRevision ?? this.localRevision,
    protocolVersion: protocolVersion ?? this.protocolVersion,
    payload: payload ?? this.payload,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    leaseUntil: leaseUntil.present ? leaseUntil.value : this.leaseUntil,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    lastErrorDetail: lastErrorDetail.present
        ? lastErrorDetail.value
        : this.lastErrorDetail,
    createdAt: createdAt ?? this.createdAt,
  );
  TasksExampleSyncWorkRow copyWithCompanion(
    TasksExampleSyncWorkRowsCompanion data,
  ) {
    return TasksExampleSyncWorkRow(
      id: data.id.present ? data.id.value : this.id,
      syncTarget: data.syncTarget.present
          ? data.syncTarget.value
          : this.syncTarget,
      direction: data.direction.present ? data.direction.value : this.direction,
      kind: data.kind.present ? data.kind.value : this.kind,
      status: data.status.present ? data.status.value : this.status,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      baseServerVersion: data.baseServerVersion.present
          ? data.baseServerVersion.value
          : this.baseServerVersion,
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
      protocolVersion: data.protocolVersion.present
          ? data.protocolVersion.value
          : this.protocolVersion,
      payload: data.payload.present ? data.payload.value : this.payload,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      leaseUntil: data.leaseUntil.present
          ? data.leaseUntil.value
          : this.leaseUntil,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      lastErrorDetail: data.lastErrorDetail.present
          ? data.lastErrorDetail.value
          : this.lastErrorDetail,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TasksExampleSyncWorkRow(')
          ..write('id: $id, ')
          ..write('syncTarget: $syncTarget, ')
          ..write('direction: $direction, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operationId: $operationId, ')
          ..write('baseServerVersion: $baseServerVersion, ')
          ..write('localRevision: $localRevision, ')
          ..write('protocolVersion: $protocolVersion, ')
          ..write('payload: $payload, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('leaseUntil: $leaseUntil, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorDetail: $lastErrorDetail, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    syncTarget,
    direction,
    kind,
    status,
    entityType,
    entityId,
    operationId,
    baseServerVersion,
    localRevision,
    protocolVersion,
    payload,
    attemptCount,
    nextAttemptAt,
    leaseUntil,
    lastErrorCode,
    lastErrorDetail,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TasksExampleSyncWorkRow &&
          other.id == this.id &&
          other.syncTarget == this.syncTarget &&
          other.direction == this.direction &&
          other.kind == this.kind &&
          other.status == this.status &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operationId == this.operationId &&
          other.baseServerVersion == this.baseServerVersion &&
          other.localRevision == this.localRevision &&
          other.protocolVersion == this.protocolVersion &&
          other.payload == this.payload &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.leaseUntil == this.leaseUntil &&
          other.lastErrorCode == this.lastErrorCode &&
          other.lastErrorDetail == this.lastErrorDetail &&
          other.createdAt == this.createdAt);
}

class TasksExampleSyncWorkRowsCompanion
    extends UpdateCompanion<TasksExampleSyncWorkRow> {
  final Value<int> id;
  final Value<String> syncTarget;
  final Value<String> direction;
  final Value<String> kind;
  final Value<String> status;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operationId;
  final Value<int> baseServerVersion;
  final Value<int> localRevision;
  final Value<int> protocolVersion;
  final Value<String> payload;
  final Value<int> attemptCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<DateTime?> leaseUntil;
  final Value<String?> lastErrorCode;
  final Value<String?> lastErrorDetail;
  final Value<DateTime> createdAt;
  const TasksExampleSyncWorkRowsCompanion({
    this.id = const Value.absent(),
    this.syncTarget = const Value.absent(),
    this.direction = const Value.absent(),
    this.kind = const Value.absent(),
    this.status = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operationId = const Value.absent(),
    this.baseServerVersion = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.protocolVersion = const Value.absent(),
    this.payload = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.leaseUntil = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorDetail = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TasksExampleSyncWorkRowsCompanion.insert({
    this.id = const Value.absent(),
    required String syncTarget,
    required String direction,
    required String kind,
    required String status,
    required String entityType,
    required String entityId,
    required String operationId,
    required int baseServerVersion,
    required int localRevision,
    this.protocolVersion = const Value.absent(),
    required String payload,
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.leaseUntil = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorDetail = const Value.absent(),
    required DateTime createdAt,
  }) : syncTarget = Value(syncTarget),
       direction = Value(direction),
       kind = Value(kind),
       status = Value(status),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operationId = Value(operationId),
       baseServerVersion = Value(baseServerVersion),
       localRevision = Value(localRevision),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<TasksExampleSyncWorkRow> custom({
    Expression<int>? id,
    Expression<String>? syncTarget,
    Expression<String>? direction,
    Expression<String>? kind,
    Expression<String>? status,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operationId,
    Expression<int>? baseServerVersion,
    Expression<int>? localRevision,
    Expression<int>? protocolVersion,
    Expression<String>? payload,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<DateTime>? leaseUntil,
    Expression<String>? lastErrorCode,
    Expression<String>? lastErrorDetail,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncTarget != null) 'sync_target': syncTarget,
      if (direction != null) 'direction': direction,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operationId != null) 'operation_id': operationId,
      if (baseServerVersion != null) 'base_server_version': baseServerVersion,
      if (localRevision != null) 'local_revision': localRevision,
      if (protocolVersion != null) 'protocol_version': protocolVersion,
      if (payload != null) 'payload': payload,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (leaseUntil != null) 'lease_until': leaseUntil,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (lastErrorDetail != null) 'last_error_detail': lastErrorDetail,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TasksExampleSyncWorkRowsCompanion copyWith({
    Value<int>? id,
    Value<String>? syncTarget,
    Value<String>? direction,
    Value<String>? kind,
    Value<String>? status,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operationId,
    Value<int>? baseServerVersion,
    Value<int>? localRevision,
    Value<int>? protocolVersion,
    Value<String>? payload,
    Value<int>? attemptCount,
    Value<DateTime?>? nextAttemptAt,
    Value<DateTime?>? leaseUntil,
    Value<String?>? lastErrorCode,
    Value<String?>? lastErrorDetail,
    Value<DateTime>? createdAt,
  }) {
    return TasksExampleSyncWorkRowsCompanion(
      id: id ?? this.id,
      syncTarget: syncTarget ?? this.syncTarget,
      direction: direction ?? this.direction,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operationId: operationId ?? this.operationId,
      baseServerVersion: baseServerVersion ?? this.baseServerVersion,
      localRevision: localRevision ?? this.localRevision,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      payload: payload ?? this.payload,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      leaseUntil: leaseUntil ?? this.leaseUntil,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorDetail: lastErrorDetail ?? this.lastErrorDetail,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncTarget.present) {
      map['sync_target'] = Variable<String>(syncTarget.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (baseServerVersion.present) {
      map['base_server_version'] = Variable<int>(baseServerVersion.value);
    }
    if (localRevision.present) {
      map['local_revision'] = Variable<int>(localRevision.value);
    }
    if (protocolVersion.present) {
      map['protocol_version'] = Variable<int>(protocolVersion.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (leaseUntil.present) {
      map['lease_until'] = Variable<DateTime>(leaseUntil.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (lastErrorDetail.present) {
      map['last_error_detail'] = Variable<String>(lastErrorDetail.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksExampleSyncWorkRowsCompanion(')
          ..write('id: $id, ')
          ..write('syncTarget: $syncTarget, ')
          ..write('direction: $direction, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operationId: $operationId, ')
          ..write('baseServerVersion: $baseServerVersion, ')
          ..write('localRevision: $localRevision, ')
          ..write('protocolVersion: $protocolVersion, ')
          ..write('payload: $payload, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('leaseUntil: $leaseUntil, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorDetail: $lastErrorDetail, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $TasksExampleSyncCursorRowsTable extends TasksExampleSyncCursorRows
    with
        TableInfo<$TasksExampleSyncCursorRowsTable, TasksExampleSyncCursorRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksExampleSyncCursorRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncTargetMeta = const VerificationMeta(
    'syncTarget',
  );
  @override
  late final GeneratedColumn<String> syncTarget = GeneratedColumn<String>(
    'sync_target',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<int> cursor = GeneratedColumn<int>(
    'cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [syncTarget, cursor];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_entity_sync_cursor';
  @override
  VerificationContext validateIntegrity(
    Insertable<TasksExampleSyncCursorRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_target')) {
      context.handle(
        _syncTargetMeta,
        syncTarget.isAcceptableOrUnknown(data['sync_target']!, _syncTargetMeta),
      );
    } else if (isInserting) {
      context.missing(_syncTargetMeta);
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    } else if (isInserting) {
      context.missing(_cursorMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {syncTarget};
  @override
  TasksExampleSyncCursorRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TasksExampleSyncCursorRow(
      syncTarget: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_target'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor'],
      )!,
    );
  }

  @override
  $TasksExampleSyncCursorRowsTable createAlias(String alias) {
    return $TasksExampleSyncCursorRowsTable(attachedDatabase, alias);
  }
}

class TasksExampleSyncCursorRow extends DataClass
    implements Insertable<TasksExampleSyncCursorRow> {
  final String syncTarget;
  final int cursor;
  const TasksExampleSyncCursorRow({
    required this.syncTarget,
    required this.cursor,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_target'] = Variable<String>(syncTarget);
    map['cursor'] = Variable<int>(cursor);
    return map;
  }

  TasksExampleSyncCursorRowsCompanion toCompanion(bool nullToAbsent) {
    return TasksExampleSyncCursorRowsCompanion(
      syncTarget: Value(syncTarget),
      cursor: Value(cursor),
    );
  }

  factory TasksExampleSyncCursorRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TasksExampleSyncCursorRow(
      syncTarget: serializer.fromJson<String>(json['syncTarget']),
      cursor: serializer.fromJson<int>(json['cursor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncTarget': serializer.toJson<String>(syncTarget),
      'cursor': serializer.toJson<int>(cursor),
    };
  }

  TasksExampleSyncCursorRow copyWith({String? syncTarget, int? cursor}) =>
      TasksExampleSyncCursorRow(
        syncTarget: syncTarget ?? this.syncTarget,
        cursor: cursor ?? this.cursor,
      );
  TasksExampleSyncCursorRow copyWithCompanion(
    TasksExampleSyncCursorRowsCompanion data,
  ) {
    return TasksExampleSyncCursorRow(
      syncTarget: data.syncTarget.present
          ? data.syncTarget.value
          : this.syncTarget,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TasksExampleSyncCursorRow(')
          ..write('syncTarget: $syncTarget, ')
          ..write('cursor: $cursor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(syncTarget, cursor);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TasksExampleSyncCursorRow &&
          other.syncTarget == this.syncTarget &&
          other.cursor == this.cursor);
}

class TasksExampleSyncCursorRowsCompanion
    extends UpdateCompanion<TasksExampleSyncCursorRow> {
  final Value<String> syncTarget;
  final Value<int> cursor;
  final Value<int> rowid;
  const TasksExampleSyncCursorRowsCompanion({
    this.syncTarget = const Value.absent(),
    this.cursor = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksExampleSyncCursorRowsCompanion.insert({
    required String syncTarget,
    required int cursor,
    this.rowid = const Value.absent(),
  }) : syncTarget = Value(syncTarget),
       cursor = Value(cursor);
  static Insertable<TasksExampleSyncCursorRow> custom({
    Expression<String>? syncTarget,
    Expression<int>? cursor,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncTarget != null) 'sync_target': syncTarget,
      if (cursor != null) 'cursor': cursor,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksExampleSyncCursorRowsCompanion copyWith({
    Value<String>? syncTarget,
    Value<int>? cursor,
    Value<int>? rowid,
  }) {
    return TasksExampleSyncCursorRowsCompanion(
      syncTarget: syncTarget ?? this.syncTarget,
      cursor: cursor ?? this.cursor,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncTarget.present) {
      map['sync_target'] = Variable<String>(syncTarget.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<int>(cursor.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksExampleSyncCursorRowsCompanion(')
          ..write('syncTarget: $syncTarget, ')
          ..write('cursor: $cursor, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$TasksExampleDatabase extends GeneratedDatabase {
  _$TasksExampleDatabase(QueryExecutor e) : super(e);
  $TasksExampleDatabaseManager get managers =>
      $TasksExampleDatabaseManager(this);
  late final $TaskRowsTable taskRows = $TaskRowsTable(this);
  late final $TaskActivityRowsTable taskActivityRows = $TaskActivityRowsTable(
    this,
  );
  late final $TaskProjectRowsTable taskProjectRows = $TaskProjectRowsTable(
    this,
  );
  late final $TasksExampleSyncWorkRowsTable tasksExampleSyncWorkRows =
      $TasksExampleSyncWorkRowsTable(this);
  late final $TasksExampleSyncCursorRowsTable tasksExampleSyncCursorRows =
      $TasksExampleSyncCursorRowsTable(this);
  late final Index tasksProjectIdDeletedAtOrderRankIdIdx = Index(
    'tasks_project_id_deleted_at_order_rank_id_idx',
    'CREATE INDEX tasks_project_id_deleted_at_order_rank_id_idx ON tasks (project_id, deleted_at, order_rank, id)',
  );
  late final Index tasksProjectIdIdx = Index(
    'tasks_project_id_idx',
    'CREATE INDEX tasks_project_id_idx ON tasks (project_id)',
  );
  late final Index tasksOwnerIdArchivedAtIdx = Index(
    'tasks_owner_id_archived_at_idx',
    'CREATE INDEX tasks_owner_id_archived_at_idx ON tasks (owner_id, archived_at)',
  );
  late final Index tasksProjectIdArchivedAtDeletedAtStatusDueAtIdIdx = Index(
    'tasks_project_id_archived_at_deleted_at_status_due_at_id_idx',
    'CREATE INDEX tasks_project_id_archived_at_deleted_at_status_due_at_id_idx ON tasks (project_id, archived_at, deleted_at, status, due_at, id)',
  );
  late final Index tasksProjectIdArchivedAtDeletedAtIdIdx = Index(
    'tasks_project_id_archived_at_deleted_at_id_idx',
    'CREATE INDEX tasks_project_id_archived_at_deleted_at_id_idx ON tasks (project_id, archived_at, deleted_at, id)',
  );
  late final Index taskActivitiesSubjectIdOccurredAtIdx = Index(
    'task_activities_subject_id_occurred_at_idx',
    'CREATE INDEX task_activities_subject_id_occurred_at_idx ON task_activities (subject_id, occurred_at)',
  );
  late final Index taskActivitiesOccurredAtIdx = Index(
    'task_activities_occurred_at_idx',
    'CREATE INDEX task_activities_occurred_at_idx ON task_activities (occurred_at)',
  );
  late final Index taskActivitiesSourceOperationIdIdx = Index(
    'task_activities_source_operation_id_idx',
    'CREATE UNIQUE INDEX task_activities_source_operation_id_idx ON task_activities (source_operation_id)',
  );
  late final Index taskProjectsDeletedAtOrderRankIdIdx = Index(
    'task_projects_deleted_at_order_rank_id_idx',
    'CREATE INDEX task_projects_deleted_at_order_rank_id_idx ON task_projects (deleted_at, order_rank, id)',
  );
  late final Index taskProjectsDeletedAtTitleIdIdx = Index(
    'task_projects_deleted_at_title_id_idx',
    'CREATE INDEX task_projects_deleted_at_title_id_idx ON task_projects (deleted_at, title, id)',
  );
  late final Index localEntityPushPatchIdx = Index(
    'local_entity_push_patch_idx',
    'CREATE INDEX local_entity_push_patch_idx ON local_entity_sync_work (sync_target, entity_type, entity_id, id) WHERE direction = \'push\' AND kind = \'statePatch\' AND status = \'pending\'',
  );
  late final Index localEntitySyncReadyIdx = Index(
    'local_entity_sync_ready_idx',
    'CREATE INDEX local_entity_sync_ready_idx ON local_entity_sync_work (sync_target, status, next_attempt_at, direction, id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    taskRows,
    taskActivityRows,
    taskProjectRows,
    tasksExampleSyncWorkRows,
    tasksExampleSyncCursorRows,
    tasksProjectIdDeletedAtOrderRankIdIdx,
    tasksProjectIdIdx,
    tasksOwnerIdArchivedAtIdx,
    tasksProjectIdArchivedAtDeletedAtStatusDueAtIdIdx,
    tasksProjectIdArchivedAtDeletedAtIdIdx,
    taskActivitiesSubjectIdOccurredAtIdx,
    taskActivitiesOccurredAtIdx,
    taskActivitiesSourceOperationIdIdx,
    taskProjectsDeletedAtOrderRankIdIdx,
    taskProjectsDeletedAtTitleIdIdx,
    localEntityPushPatchIdx,
    localEntitySyncReadyIdx,
  ];
}

typedef $$TaskRowsTableCreateCompanionBuilder =
    TaskRowsCompanion Function({
      required String id,
      required String ownerId,
      Value<String?> projectId,
      required String title,
      Value<String?> description,
      Value<String> status,
      Value<String> priority,
      Value<String?> dueAt,
      Value<String?> completedAt,
      Value<String?> archivedAt,
      required String createdAt,
      Value<String> orderRank,
      Value<String?> deletedAt,
      Value<int> serverVersion,
      required int localRevision,
      Value<String?> acceptedSnapshot,
      Value<int> rowid,
    });
typedef $$TaskRowsTableUpdateCompanionBuilder =
    TaskRowsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String?> projectId,
      Value<String> title,
      Value<String?> description,
      Value<String> status,
      Value<String> priority,
      Value<String?> dueAt,
      Value<String?> completedAt,
      Value<String?> archivedAt,
      Value<String> createdAt,
      Value<String> orderRank,
      Value<String?> deletedAt,
      Value<int> serverVersion,
      Value<int> localRevision,
      Value<String?> acceptedSnapshot,
      Value<int> rowid,
    });

class $$TaskRowsTableFilterComposer
    extends Composer<_$TasksExampleDatabase, $TaskRowsTable> {
  $$TaskRowsTableFilterComposer({
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

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderRank => $composableBuilder(
    column: $table.orderRank,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get acceptedSnapshot => $composableBuilder(
    column: $table.acceptedSnapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TaskRowsTableOrderingComposer
    extends Composer<_$TasksExampleDatabase, $TaskRowsTable> {
  $$TaskRowsTableOrderingComposer({
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

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderRank => $composableBuilder(
    column: $table.orderRank,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get acceptedSnapshot => $composableBuilder(
    column: $table.acceptedSnapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TaskRowsTableAnnotationComposer
    extends Composer<_$TasksExampleDatabase, $TaskRowsTable> {
  $$TaskRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get orderRank =>
      $composableBuilder(column: $table.orderRank, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get acceptedSnapshot => $composableBuilder(
    column: $table.acceptedSnapshot,
    builder: (column) => column,
  );
}

class $$TaskRowsTableTableManager
    extends
        RootTableManager<
          _$TasksExampleDatabase,
          $TaskRowsTable,
          TaskRow,
          $$TaskRowsTableFilterComposer,
          $$TaskRowsTableOrderingComposer,
          $$TaskRowsTableAnnotationComposer,
          $$TaskRowsTableCreateCompanionBuilder,
          $$TaskRowsTableUpdateCompanionBuilder,
          (
            TaskRow,
            BaseReferences<_$TasksExampleDatabase, $TaskRowsTable, TaskRow>,
          ),
          TaskRow,
          PrefetchHooks Function()
        > {
  $$TaskRowsTableTableManager(_$TasksExampleDatabase db, $TaskRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<String?> dueAt = const Value.absent(),
                Value<String?> completedAt = const Value.absent(),
                Value<String?> archivedAt = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> orderRank = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> serverVersion = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<String?> acceptedSnapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskRowsCompanion(
                id: id,
                ownerId: ownerId,
                projectId: projectId,
                title: title,
                description: description,
                status: status,
                priority: priority,
                dueAt: dueAt,
                completedAt: completedAt,
                archivedAt: archivedAt,
                createdAt: createdAt,
                orderRank: orderRank,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                localRevision: localRevision,
                acceptedSnapshot: acceptedSnapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                Value<String?> projectId = const Value.absent(),
                required String title,
                Value<String?> description = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<String?> dueAt = const Value.absent(),
                Value<String?> completedAt = const Value.absent(),
                Value<String?> archivedAt = const Value.absent(),
                required String createdAt,
                Value<String> orderRank = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> serverVersion = const Value.absent(),
                required int localRevision,
                Value<String?> acceptedSnapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskRowsCompanion.insert(
                id: id,
                ownerId: ownerId,
                projectId: projectId,
                title: title,
                description: description,
                status: status,
                priority: priority,
                dueAt: dueAt,
                completedAt: completedAt,
                archivedAt: archivedAt,
                createdAt: createdAt,
                orderRank: orderRank,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                localRevision: localRevision,
                acceptedSnapshot: acceptedSnapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TaskRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$TasksExampleDatabase,
      $TaskRowsTable,
      TaskRow,
      $$TaskRowsTableFilterComposer,
      $$TaskRowsTableOrderingComposer,
      $$TaskRowsTableAnnotationComposer,
      $$TaskRowsTableCreateCompanionBuilder,
      $$TaskRowsTableUpdateCompanionBuilder,
      (
        TaskRow,
        BaseReferences<_$TasksExampleDatabase, $TaskRowsTable, TaskRow>,
      ),
      TaskRow,
      PrefetchHooks Function()
    >;
typedef $$TaskActivityRowsTableCreateCompanionBuilder =
    TaskActivityRowsCompanion Function({
      required String id,
      required String ownerId,
      required String subjectId,
      required String actorId,
      required String operation,
      required String label,
      required String sourceOperationId,
      required String occurredAt,
      Value<String?> deletedAt,
      Value<int> serverVersion,
      required int localRevision,
      Value<String?> acceptedSnapshot,
      Value<int> rowid,
    });
typedef $$TaskActivityRowsTableUpdateCompanionBuilder =
    TaskActivityRowsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> subjectId,
      Value<String> actorId,
      Value<String> operation,
      Value<String> label,
      Value<String> sourceOperationId,
      Value<String> occurredAt,
      Value<String?> deletedAt,
      Value<int> serverVersion,
      Value<int> localRevision,
      Value<String?> acceptedSnapshot,
      Value<int> rowid,
    });

class $$TaskActivityRowsTableFilterComposer
    extends Composer<_$TasksExampleDatabase, $TaskActivityRowsTable> {
  $$TaskActivityRowsTableFilterComposer({
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

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceOperationId => $composableBuilder(
    column: $table.sourceOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get acceptedSnapshot => $composableBuilder(
    column: $table.acceptedSnapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TaskActivityRowsTableOrderingComposer
    extends Composer<_$TasksExampleDatabase, $TaskActivityRowsTable> {
  $$TaskActivityRowsTableOrderingComposer({
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

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceOperationId => $composableBuilder(
    column: $table.sourceOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get acceptedSnapshot => $composableBuilder(
    column: $table.acceptedSnapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TaskActivityRowsTableAnnotationComposer
    extends Composer<_$TasksExampleDatabase, $TaskActivityRowsTable> {
  $$TaskActivityRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get sourceOperationId => $composableBuilder(
    column: $table.sourceOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get acceptedSnapshot => $composableBuilder(
    column: $table.acceptedSnapshot,
    builder: (column) => column,
  );
}

class $$TaskActivityRowsTableTableManager
    extends
        RootTableManager<
          _$TasksExampleDatabase,
          $TaskActivityRowsTable,
          TaskActivityRow,
          $$TaskActivityRowsTableFilterComposer,
          $$TaskActivityRowsTableOrderingComposer,
          $$TaskActivityRowsTableAnnotationComposer,
          $$TaskActivityRowsTableCreateCompanionBuilder,
          $$TaskActivityRowsTableUpdateCompanionBuilder,
          (
            TaskActivityRow,
            BaseReferences<
              _$TasksExampleDatabase,
              $TaskActivityRowsTable,
              TaskActivityRow
            >,
          ),
          TaskActivityRow,
          PrefetchHooks Function()
        > {
  $$TaskActivityRowsTableTableManager(
    _$TasksExampleDatabase db,
    $TaskActivityRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskActivityRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskActivityRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskActivityRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> subjectId = const Value.absent(),
                Value<String> actorId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> sourceOperationId = const Value.absent(),
                Value<String> occurredAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> serverVersion = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<String?> acceptedSnapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskActivityRowsCompanion(
                id: id,
                ownerId: ownerId,
                subjectId: subjectId,
                actorId: actorId,
                operation: operation,
                label: label,
                sourceOperationId: sourceOperationId,
                occurredAt: occurredAt,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                localRevision: localRevision,
                acceptedSnapshot: acceptedSnapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String subjectId,
                required String actorId,
                required String operation,
                required String label,
                required String sourceOperationId,
                required String occurredAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> serverVersion = const Value.absent(),
                required int localRevision,
                Value<String?> acceptedSnapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskActivityRowsCompanion.insert(
                id: id,
                ownerId: ownerId,
                subjectId: subjectId,
                actorId: actorId,
                operation: operation,
                label: label,
                sourceOperationId: sourceOperationId,
                occurredAt: occurredAt,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                localRevision: localRevision,
                acceptedSnapshot: acceptedSnapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TaskActivityRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$TasksExampleDatabase,
      $TaskActivityRowsTable,
      TaskActivityRow,
      $$TaskActivityRowsTableFilterComposer,
      $$TaskActivityRowsTableOrderingComposer,
      $$TaskActivityRowsTableAnnotationComposer,
      $$TaskActivityRowsTableCreateCompanionBuilder,
      $$TaskActivityRowsTableUpdateCompanionBuilder,
      (
        TaskActivityRow,
        BaseReferences<
          _$TasksExampleDatabase,
          $TaskActivityRowsTable,
          TaskActivityRow
        >,
      ),
      TaskActivityRow,
      PrefetchHooks Function()
    >;
typedef $$TaskProjectRowsTableCreateCompanionBuilder =
    TaskProjectRowsCompanion Function({
      required String id,
      required String ownerId,
      required String title,
      Value<String> orderRank,
      Value<String?> deletedAt,
      Value<int> serverVersion,
      required int localRevision,
      Value<String?> acceptedSnapshot,
      Value<int> rowid,
    });
typedef $$TaskProjectRowsTableUpdateCompanionBuilder =
    TaskProjectRowsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> title,
      Value<String> orderRank,
      Value<String?> deletedAt,
      Value<int> serverVersion,
      Value<int> localRevision,
      Value<String?> acceptedSnapshot,
      Value<int> rowid,
    });

class $$TaskProjectRowsTableFilterComposer
    extends Composer<_$TasksExampleDatabase, $TaskProjectRowsTable> {
  $$TaskProjectRowsTableFilterComposer({
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

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderRank => $composableBuilder(
    column: $table.orderRank,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get acceptedSnapshot => $composableBuilder(
    column: $table.acceptedSnapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TaskProjectRowsTableOrderingComposer
    extends Composer<_$TasksExampleDatabase, $TaskProjectRowsTable> {
  $$TaskProjectRowsTableOrderingComposer({
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

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderRank => $composableBuilder(
    column: $table.orderRank,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get acceptedSnapshot => $composableBuilder(
    column: $table.acceptedSnapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TaskProjectRowsTableAnnotationComposer
    extends Composer<_$TasksExampleDatabase, $TaskProjectRowsTable> {
  $$TaskProjectRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get orderRank =>
      $composableBuilder(column: $table.orderRank, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get acceptedSnapshot => $composableBuilder(
    column: $table.acceptedSnapshot,
    builder: (column) => column,
  );
}

class $$TaskProjectRowsTableTableManager
    extends
        RootTableManager<
          _$TasksExampleDatabase,
          $TaskProjectRowsTable,
          TaskProjectRow,
          $$TaskProjectRowsTableFilterComposer,
          $$TaskProjectRowsTableOrderingComposer,
          $$TaskProjectRowsTableAnnotationComposer,
          $$TaskProjectRowsTableCreateCompanionBuilder,
          $$TaskProjectRowsTableUpdateCompanionBuilder,
          (
            TaskProjectRow,
            BaseReferences<
              _$TasksExampleDatabase,
              $TaskProjectRowsTable,
              TaskProjectRow
            >,
          ),
          TaskProjectRow,
          PrefetchHooks Function()
        > {
  $$TaskProjectRowsTableTableManager(
    _$TasksExampleDatabase db,
    $TaskProjectRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskProjectRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskProjectRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskProjectRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> orderRank = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> serverVersion = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<String?> acceptedSnapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskProjectRowsCompanion(
                id: id,
                ownerId: ownerId,
                title: title,
                orderRank: orderRank,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                localRevision: localRevision,
                acceptedSnapshot: acceptedSnapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String title,
                Value<String> orderRank = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> serverVersion = const Value.absent(),
                required int localRevision,
                Value<String?> acceptedSnapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskProjectRowsCompanion.insert(
                id: id,
                ownerId: ownerId,
                title: title,
                orderRank: orderRank,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                localRevision: localRevision,
                acceptedSnapshot: acceptedSnapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TaskProjectRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$TasksExampleDatabase,
      $TaskProjectRowsTable,
      TaskProjectRow,
      $$TaskProjectRowsTableFilterComposer,
      $$TaskProjectRowsTableOrderingComposer,
      $$TaskProjectRowsTableAnnotationComposer,
      $$TaskProjectRowsTableCreateCompanionBuilder,
      $$TaskProjectRowsTableUpdateCompanionBuilder,
      (
        TaskProjectRow,
        BaseReferences<
          _$TasksExampleDatabase,
          $TaskProjectRowsTable,
          TaskProjectRow
        >,
      ),
      TaskProjectRow,
      PrefetchHooks Function()
    >;
typedef $$TasksExampleSyncWorkRowsTableCreateCompanionBuilder =
    TasksExampleSyncWorkRowsCompanion Function({
      Value<int> id,
      required String syncTarget,
      required String direction,
      required String kind,
      required String status,
      required String entityType,
      required String entityId,
      required String operationId,
      required int baseServerVersion,
      required int localRevision,
      Value<int> protocolVersion,
      required String payload,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<DateTime?> leaseUntil,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorDetail,
      required DateTime createdAt,
    });
typedef $$TasksExampleSyncWorkRowsTableUpdateCompanionBuilder =
    TasksExampleSyncWorkRowsCompanion Function({
      Value<int> id,
      Value<String> syncTarget,
      Value<String> direction,
      Value<String> kind,
      Value<String> status,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operationId,
      Value<int> baseServerVersion,
      Value<int> localRevision,
      Value<int> protocolVersion,
      Value<String> payload,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<DateTime?> leaseUntil,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorDetail,
      Value<DateTime> createdAt,
    });

class $$TasksExampleSyncWorkRowsTableFilterComposer
    extends Composer<_$TasksExampleDatabase, $TasksExampleSyncWorkRowsTable> {
  $$TasksExampleSyncWorkRowsTableFilterComposer({
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

  ColumnFilters<String> get syncTarget => $composableBuilder(
    column: $table.syncTarget,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseServerVersion => $composableBuilder(
    column: $table.baseServerVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get leaseUntil => $composableBuilder(
    column: $table.leaseUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorDetail => $composableBuilder(
    column: $table.lastErrorDetail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TasksExampleSyncWorkRowsTableOrderingComposer
    extends Composer<_$TasksExampleDatabase, $TasksExampleSyncWorkRowsTable> {
  $$TasksExampleSyncWorkRowsTableOrderingComposer({
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

  ColumnOrderings<String> get syncTarget => $composableBuilder(
    column: $table.syncTarget,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseServerVersion => $composableBuilder(
    column: $table.baseServerVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get leaseUntil => $composableBuilder(
    column: $table.leaseUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorDetail => $composableBuilder(
    column: $table.lastErrorDetail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TasksExampleSyncWorkRowsTableAnnotationComposer
    extends Composer<_$TasksExampleDatabase, $TasksExampleSyncWorkRowsTable> {
  $$TasksExampleSyncWorkRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syncTarget => $composableBuilder(
    column: $table.syncTarget,
    builder: (column) => column,
  );

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baseServerVersion => $composableBuilder(
    column: $table.baseServerVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get leaseUntil => $composableBuilder(
    column: $table.leaseUntil,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorDetail => $composableBuilder(
    column: $table.lastErrorDetail,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TasksExampleSyncWorkRowsTableTableManager
    extends
        RootTableManager<
          _$TasksExampleDatabase,
          $TasksExampleSyncWorkRowsTable,
          TasksExampleSyncWorkRow,
          $$TasksExampleSyncWorkRowsTableFilterComposer,
          $$TasksExampleSyncWorkRowsTableOrderingComposer,
          $$TasksExampleSyncWorkRowsTableAnnotationComposer,
          $$TasksExampleSyncWorkRowsTableCreateCompanionBuilder,
          $$TasksExampleSyncWorkRowsTableUpdateCompanionBuilder,
          (
            TasksExampleSyncWorkRow,
            BaseReferences<
              _$TasksExampleDatabase,
              $TasksExampleSyncWorkRowsTable,
              TasksExampleSyncWorkRow
            >,
          ),
          TasksExampleSyncWorkRow,
          PrefetchHooks Function()
        > {
  $$TasksExampleSyncWorkRowsTableTableManager(
    _$TasksExampleDatabase db,
    $TasksExampleSyncWorkRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksExampleSyncWorkRowsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$TasksExampleSyncWorkRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TasksExampleSyncWorkRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> syncTarget = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operationId = const Value.absent(),
                Value<int> baseServerVersion = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int> protocolVersion = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<DateTime?> leaseUntil = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorDetail = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TasksExampleSyncWorkRowsCompanion(
                id: id,
                syncTarget: syncTarget,
                direction: direction,
                kind: kind,
                status: status,
                entityType: entityType,
                entityId: entityId,
                operationId: operationId,
                baseServerVersion: baseServerVersion,
                localRevision: localRevision,
                protocolVersion: protocolVersion,
                payload: payload,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                leaseUntil: leaseUntil,
                lastErrorCode: lastErrorCode,
                lastErrorDetail: lastErrorDetail,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String syncTarget,
                required String direction,
                required String kind,
                required String status,
                required String entityType,
                required String entityId,
                required String operationId,
                required int baseServerVersion,
                required int localRevision,
                Value<int> protocolVersion = const Value.absent(),
                required String payload,
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<DateTime?> leaseUntil = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorDetail = const Value.absent(),
                required DateTime createdAt,
              }) => TasksExampleSyncWorkRowsCompanion.insert(
                id: id,
                syncTarget: syncTarget,
                direction: direction,
                kind: kind,
                status: status,
                entityType: entityType,
                entityId: entityId,
                operationId: operationId,
                baseServerVersion: baseServerVersion,
                localRevision: localRevision,
                protocolVersion: protocolVersion,
                payload: payload,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                leaseUntil: leaseUntil,
                lastErrorCode: lastErrorCode,
                lastErrorDetail: lastErrorDetail,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TasksExampleSyncWorkRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$TasksExampleDatabase,
      $TasksExampleSyncWorkRowsTable,
      TasksExampleSyncWorkRow,
      $$TasksExampleSyncWorkRowsTableFilterComposer,
      $$TasksExampleSyncWorkRowsTableOrderingComposer,
      $$TasksExampleSyncWorkRowsTableAnnotationComposer,
      $$TasksExampleSyncWorkRowsTableCreateCompanionBuilder,
      $$TasksExampleSyncWorkRowsTableUpdateCompanionBuilder,
      (
        TasksExampleSyncWorkRow,
        BaseReferences<
          _$TasksExampleDatabase,
          $TasksExampleSyncWorkRowsTable,
          TasksExampleSyncWorkRow
        >,
      ),
      TasksExampleSyncWorkRow,
      PrefetchHooks Function()
    >;
typedef $$TasksExampleSyncCursorRowsTableCreateCompanionBuilder =
    TasksExampleSyncCursorRowsCompanion Function({
      required String syncTarget,
      required int cursor,
      Value<int> rowid,
    });
typedef $$TasksExampleSyncCursorRowsTableUpdateCompanionBuilder =
    TasksExampleSyncCursorRowsCompanion Function({
      Value<String> syncTarget,
      Value<int> cursor,
      Value<int> rowid,
    });

class $$TasksExampleSyncCursorRowsTableFilterComposer
    extends Composer<_$TasksExampleDatabase, $TasksExampleSyncCursorRowsTable> {
  $$TasksExampleSyncCursorRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get syncTarget => $composableBuilder(
    column: $table.syncTarget,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TasksExampleSyncCursorRowsTableOrderingComposer
    extends Composer<_$TasksExampleDatabase, $TasksExampleSyncCursorRowsTable> {
  $$TasksExampleSyncCursorRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get syncTarget => $composableBuilder(
    column: $table.syncTarget,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TasksExampleSyncCursorRowsTableAnnotationComposer
    extends Composer<_$TasksExampleDatabase, $TasksExampleSyncCursorRowsTable> {
  $$TasksExampleSyncCursorRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get syncTarget => $composableBuilder(
    column: $table.syncTarget,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);
}

class $$TasksExampleSyncCursorRowsTableTableManager
    extends
        RootTableManager<
          _$TasksExampleDatabase,
          $TasksExampleSyncCursorRowsTable,
          TasksExampleSyncCursorRow,
          $$TasksExampleSyncCursorRowsTableFilterComposer,
          $$TasksExampleSyncCursorRowsTableOrderingComposer,
          $$TasksExampleSyncCursorRowsTableAnnotationComposer,
          $$TasksExampleSyncCursorRowsTableCreateCompanionBuilder,
          $$TasksExampleSyncCursorRowsTableUpdateCompanionBuilder,
          (
            TasksExampleSyncCursorRow,
            BaseReferences<
              _$TasksExampleDatabase,
              $TasksExampleSyncCursorRowsTable,
              TasksExampleSyncCursorRow
            >,
          ),
          TasksExampleSyncCursorRow,
          PrefetchHooks Function()
        > {
  $$TasksExampleSyncCursorRowsTableTableManager(
    _$TasksExampleDatabase db,
    $TasksExampleSyncCursorRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksExampleSyncCursorRowsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$TasksExampleSyncCursorRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TasksExampleSyncCursorRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> syncTarget = const Value.absent(),
                Value<int> cursor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksExampleSyncCursorRowsCompanion(
                syncTarget: syncTarget,
                cursor: cursor,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String syncTarget,
                required int cursor,
                Value<int> rowid = const Value.absent(),
              }) => TasksExampleSyncCursorRowsCompanion.insert(
                syncTarget: syncTarget,
                cursor: cursor,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TasksExampleSyncCursorRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$TasksExampleDatabase,
      $TasksExampleSyncCursorRowsTable,
      TasksExampleSyncCursorRow,
      $$TasksExampleSyncCursorRowsTableFilterComposer,
      $$TasksExampleSyncCursorRowsTableOrderingComposer,
      $$TasksExampleSyncCursorRowsTableAnnotationComposer,
      $$TasksExampleSyncCursorRowsTableCreateCompanionBuilder,
      $$TasksExampleSyncCursorRowsTableUpdateCompanionBuilder,
      (
        TasksExampleSyncCursorRow,
        BaseReferences<
          _$TasksExampleDatabase,
          $TasksExampleSyncCursorRowsTable,
          TasksExampleSyncCursorRow
        >,
      ),
      TasksExampleSyncCursorRow,
      PrefetchHooks Function()
    >;

class $TasksExampleDatabaseManager {
  final _$TasksExampleDatabase _db;
  $TasksExampleDatabaseManager(this._db);
  $$TaskRowsTableTableManager get taskRows =>
      $$TaskRowsTableTableManager(_db, _db.taskRows);
  $$TaskActivityRowsTableTableManager get taskActivityRows =>
      $$TaskActivityRowsTableTableManager(_db, _db.taskActivityRows);
  $$TaskProjectRowsTableTableManager get taskProjectRows =>
      $$TaskProjectRowsTableTableManager(_db, _db.taskProjectRows);
  $$TasksExampleSyncWorkRowsTableTableManager get tasksExampleSyncWorkRows =>
      $$TasksExampleSyncWorkRowsTableTableManager(
        _db,
        _db.tasksExampleSyncWorkRows,
      );
  $$TasksExampleSyncCursorRowsTableTableManager
  get tasksExampleSyncCursorRows =>
      $$TasksExampleSyncCursorRowsTableTableManager(
        _db,
        _db.tasksExampleSyncCursorRows,
      );
}
