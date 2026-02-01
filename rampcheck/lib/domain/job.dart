class Job {
  final int? id;           //local id
  final int? remoteId;     //server id
  final String title;
  final String description;
  final String priority;
  final String status;
  final int? userId;
  final String updatedAt;
  final String syncState;  //'clean' | 'dirty' | 'deleted' | 'conflict'

  Job({
    this.id,
    this.remoteId,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    this.userId,
    required this.updatedAt,
    required this.syncState,
  });

  Job copyWith({
    int? id,
    int? remoteId,
    String? title,
    String? description,
    String? priority,
    String? status,
    int? userId,
    String? updatedAt,
    String? syncState,
  }) {
    return Job(
      id: id ?? this.id,
      remoteId: remoteId ?? this.remoteId,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      userId: userId ?? this.userId,
      updatedAt: updatedAt ?? this.updatedAt,
      syncState: syncState ?? this.syncState,
    );
  }

  Map<String, dynamic> toRow() => {
    'id': id,
    'remote_id': remoteId,
    'title': title,
    'description': description,
    'priority': priority,
    'status': status,
    'user_id': userId,
    'updated_at': updatedAt,
    'sync_state': syncState,
  };

  static Job fromRow(Map<String, Object?> row) => Job(
    id: row['id'] as int?,
    remoteId: row['remote_id'] as int?,
    title: row['title'] as String,
    description: row['description'] as String,
    priority: row['priority'] as String,
    status: row['status'] as String,
    userId: row['user_id'] as int?,
    updatedAt: row['updated_at'] as String,
    syncState: row['sync_state'] as String,
  );
}