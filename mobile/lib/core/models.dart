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
    required this.recipients,
    this.note,
  });

  final String id;
  final String idempotencyKey;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final List<RecipientStatus> recipients;
  final String? note;

  factory AlertRecord.fromJson(Map<String, dynamic> json) => AlertRecord(
        id: json['id'] as String,
        idempotencyKey: json['idempotency_key'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        createdAt: DateTime.parse(json['created_at'] as String),
        recipients: (json['recipients'] as List<dynamic>? ?? const [])
            .map((e) => RecipientStatus.fromJson(e as Map<String, dynamic>))
            .toList(),
        note: json['note'] as String?,
      );

  String get deliveryState {
    if (recipients.isEmpty) return 'No active contacts';
    if (recipients.any((r) => r.acknowledgedAt != null)) return 'Acknowledged';
    if (recipients.any((r) => r.deliveredAt != null)) return 'Delivered';
    return 'Sent';
  }
}

class InboxAlert {
  const InboxAlert({
    required this.alertId,
    required this.senderName,
    required this.senderEmail,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.deliveredAt,
    this.acknowledgedAt,
    this.note,
  });

  final String alertId;
  final String senderName;
  final String senderEmail;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? acknowledgedAt;
  final String? note;

  factory InboxAlert.fromJson(Map<String, dynamic> json) => InboxAlert(
        alertId: json['alert_id'] as String,
        senderName: json['sender_name'] as String,
        senderEmail: json['sender_email'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        createdAt: DateTime.parse(json['created_at'] as String),
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
    this.note,
  });

  final String idempotencyKey;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final String? note;

  Map<String, dynamic> toJson() => {
        'idempotency_key': idempotencyKey,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_m': accuracyM,
        'note': note,
      };

  factory QueuedAlert.fromJson(Map<String, dynamic> json) => QueuedAlert(
        idempotencyKey: json['idempotency_key'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        note: json['note'] as String?,
      );
}
