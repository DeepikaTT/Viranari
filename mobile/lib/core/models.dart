class UserProfile {
  const UserProfile({required this.id, required this.name, required this.email});
  final String id;
  final String name;
  final String email;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
      );
}

class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.name,
    required this.email,
    required this.alias,
    required this.status,
    this.inviteToken,
  });

  final String id;
  final String name;
  final String email;
  final String alias;
  final String status;
  final String? inviteToken;

  factory TrustedContact.fromJson(Map<String, dynamic> json) => TrustedContact(
        id: json['id'] as String,
        name: json['contact_name'] as String,
        email: json['contact_email'] as String,
        alias: json['alias'] as String,
        status: json['status'] as String,
        inviteToken: json['invite_token'] as String?,
      );
}

class RecipientStatus {
  const RecipientStatus({required this.name, this.deliveredAt, this.acknowledgedAt});
  final String name;
  final DateTime? deliveredAt;
  final DateTime? acknowledgedAt;

  factory RecipientStatus.fromJson(Map<String, dynamic> json) => RecipientStatus(
        name: json['recipient_name'] as String,
        deliveredAt: json['delivered_at'] == null ? null : DateTime.parse(json['delivered_at'] as String),
        acknowledgedAt: json['acknowledged_at'] == null ? null : DateTime.parse(json['acknowledged_at'] as String),
      );
}

class AlertRecord {
  const AlertRecord({
    required this.id,
    required this.idempotencyKey,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.updatedAt,
    required this.recipients,
    required this.state,
    required this.isTest,
    this.accuracyM,
    this.batteryPercent,
    this.networkState,
    this.note,
    this.cancelledAt,
    this.resolvedAt,
  });

  final String id;
  final String idempotencyKey;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int? batteryPercent;
  final String? networkState;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<RecipientStatus> recipients;
  final String state;
  final bool isTest;
  final String? note;
  final DateTime? cancelledAt;
  final DateTime? resolvedAt;

  factory AlertRecord.fromJson(Map<String, dynamic> json) => AlertRecord(
        id: json['id'] as String,
        idempotencyKey: json['idempotency_key'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        batteryPercent: json['battery_percent'] as int?,
        networkState: json['network_state'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        recipients: (json['recipients'] as List<dynamic>? ?? const [])
            .map((e) => RecipientStatus.fromJson(e as Map<String, dynamic>))
            .toList(),
        state: json['state'] as String? ?? 'active',
        isTest: json['is_test'] as bool? ?? false,
        note: json['note'] as String?,
        cancelledAt: json['cancelled_at'] == null ? null : DateTime.parse(json['cancelled_at'] as String),
        resolvedAt: json['resolved_at'] == null ? null : DateTime.parse(json['resolved_at'] as String),
      );

  bool get isActive => state == 'active';

  String get deliveryState {
    if (state == 'cancelled') return 'Cancelled';
    if (state == 'resolved') return 'Resolved';
    if (recipients.isEmpty) return 'No active contacts';
    if (recipients.any((r) => r.acknowledgedAt != null)) return 'Acknowledged';
    if (recipients.any((r) => r.deliveredAt != null)) return 'Delivered';
    return 'Sent';
  }

  int get acknowledgedCount => recipients.where((r) => r.acknowledgedAt != null).length;
  int get deliveredCount => recipients.where((r) => r.deliveredAt != null).length;
}

class AlertLocationPoint {
  const AlertLocationPoint({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.accuracyM,
    this.batteryPercent,
    this.networkState,
  });

  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int? batteryPercent;
  final String? networkState;
  final DateTime recordedAt;

  factory AlertLocationPoint.fromJson(Map<String, dynamic> json) => AlertLocationPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        batteryPercent: json['battery_percent'] as int?,
        networkState: json['network_state'] as String?,
        recordedAt: DateTime.parse(json['recorded_at'] as String),
      );
}

class InboxAlert {
  const InboxAlert({
    required this.alertId,
    required this.senderName,
    required this.senderEmail,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.updatedAt,
    required this.state,
    required this.isTest,
    this.accuracyM,
    this.batteryPercent,
    this.networkState,
    this.deliveredAt,
    this.acknowledgedAt,
    this.note,
  });

  final String alertId;
  final String senderName;
  final String senderEmail;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int? batteryPercent;
  final String? networkState;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String state;
  final bool isTest;
  final DateTime? deliveredAt;
  final DateTime? acknowledgedAt;
  final String? note;

  bool get isActive => state == 'active';

  factory InboxAlert.fromJson(Map<String, dynamic> json) => InboxAlert(
        alertId: json['alert_id'] as String,
        senderName: json['sender_name'] as String,
        senderEmail: json['sender_email'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        batteryPercent: json['battery_percent'] as int?,
        networkState: json['network_state'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        state: json['state'] as String? ?? 'active',
        isTest: json['is_test'] as bool? ?? false,
        deliveredAt: json['delivered_at'] == null ? null : DateTime.parse(json['delivered_at'] as String),
        acknowledgedAt: json['acknowledged_at'] == null ? null : DateTime.parse(json['acknowledged_at'] as String),
        note: json['note'] as String?,
      );
}

class QueuedAlert {
  const QueuedAlert({
    required this.idempotencyKey,
    required this.latitude,
    required this.longitude,
    this.accuracyM,
    this.batteryPercent,
    this.networkState,
    this.isTest = false,
    this.note,
  });

  final String idempotencyKey;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int? batteryPercent;
  final String? networkState;
  final bool isTest;
  final String? note;

  Map<String, dynamic> toJson() => {
        'idempotency_key': idempotencyKey,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_m': accuracyM,
        'battery_percent': batteryPercent,
        'network_state': networkState,
        'is_test': isTest,
        'note': note,
      };

  factory QueuedAlert.fromJson(Map<String, dynamic> json) => QueuedAlert(
        idempotencyKey: json['idempotency_key'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        batteryPercent: json['battery_percent'] as int?,
        networkState: json['network_state'] as String?,
        isTest: json['is_test'] as bool? ?? false,
        note: json['note'] as String?,
      );
}
