DateTime parseApiTime(String raw) {
  final hasOffset = raw.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw);
  return DateTime.parse(hasOffset ? raw : '${raw}Z');
}

class UserProfile {
  const UserProfile({required this.id, required this.name, required this.email, this.phoneE164});
  final String id;
  final String name;
  final String email;
  final String? phoneE164;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        phoneE164: json['phone_e164'] as String?,
      );
}

class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.name,
    required this.email,
    required this.alias,
    required this.status,
    this.phoneE164,
    this.inviteToken,
  });

  final String id;
  final String name;
  final String email;
  final String alias;
  final String status;
  final String? phoneE164;
  final String? inviteToken;

  factory TrustedContact.fromJson(Map<String, dynamic> json) => TrustedContact(
        id: json['id'] as String,
        name: json['contact_name'] as String,
        email: json['contact_email'] as String,
        alias: json['alias'] as String,
        status: json['status'] as String,
        phoneE164: json['contact_phone_e164'] as String?,
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
        deliveredAt: json['delivered_at'] == null ? null : parseApiTime(json['delivered_at'] as String),
        acknowledgedAt: json['acknowledged_at'] == null ? null : parseApiTime(json['acknowledged_at'] as String),
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
    required this.silentMode,
    this.accuracyM,
    this.batteryPercent,
    this.networkState,
    this.note,
    this.cancelledAt,
    this.resolvedAt,
    this.lastDeviceSeenAt,
    this.lastGpsFixAt,
    this.lastLocationSyncAt,
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
  final bool silentMode;
  final String? note;
  final DateTime? cancelledAt;
  final DateTime? resolvedAt;
  final DateTime? lastDeviceSeenAt;
  final DateTime? lastGpsFixAt;
  final DateTime? lastLocationSyncAt;

  factory AlertRecord.fromJson(Map<String, dynamic> json) => AlertRecord(
        id: json['id'] as String,
        idempotencyKey: json['idempotency_key'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        batteryPercent: json['battery_percent'] as int?,
        networkState: json['network_state'] as String?,
        createdAt: parseApiTime(json['created_at'] as String),
        updatedAt: parseApiTime(json['updated_at'] as String),
        recipients: (json['recipients'] as List<dynamic>? ?? const [])
            .map((e) => RecipientStatus.fromJson(e as Map<String, dynamic>))
            .toList(),
        state: json['state'] as String? ?? 'active',
        isTest: json['is_test'] as bool? ?? false,
        silentMode: json['silent_mode'] as bool? ?? false,
        note: json['note'] as String?,
        cancelledAt: json['cancelled_at'] == null ? null : parseApiTime(json['cancelled_at'] as String),
        resolvedAt: json['resolved_at'] == null ? null : parseApiTime(json['resolved_at'] as String),
        lastDeviceSeenAt: json['last_device_seen_at'] == null ? null : parseApiTime(json['last_device_seen_at'] as String),
        lastGpsFixAt: json['last_gps_fix_at'] == null ? null : parseApiTime(json['last_gps_fix_at'] as String),
        lastLocationSyncAt: json['last_location_sync_at'] == null ? null : parseApiTime(json['last_location_sync_at'] as String),
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
    this.speedMps,
    this.headingDeg,
  });

  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int? batteryPercent;
  final String? networkState;
  final double? speedMps;
  final double? headingDeg;
  final DateTime recordedAt;

  factory AlertLocationPoint.fromJson(Map<String, dynamic> json) => AlertLocationPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        batteryPercent: json['battery_percent'] as int?,
        networkState: json['network_state'] as String?,
        speedMps: (json['speed_mps'] as num?)?.toDouble(),
        headingDeg: (json['heading_deg'] as num?)?.toDouble(),
        recordedAt: parseApiTime(json['recorded_at'] as String),
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
    required this.silentMode,
    this.senderPhoneE164,
    this.accuracyM,
    this.batteryPercent,
    this.networkState,
    this.deliveredAt,
    this.acknowledgedAt,
    this.note,
    this.lastDeviceSeenAt,
    this.lastGpsFixAt,
    this.lastLocationSyncAt,
  });

  final String alertId;
  final String senderName;
  final String senderEmail;
  final String? senderPhoneE164;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int? batteryPercent;
  final String? networkState;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String state;
  final bool isTest;
  final bool silentMode;
  final DateTime? deliveredAt;
  final DateTime? acknowledgedAt;
  final String? note;
  final DateTime? lastDeviceSeenAt;
  final DateTime? lastGpsFixAt;
  final DateTime? lastLocationSyncAt;

  bool get isActive => state == 'active';

  factory InboxAlert.fromJson(Map<String, dynamic> json) => InboxAlert(
        alertId: json['alert_id'] as String,
        senderName: json['sender_name'] as String,
        senderEmail: json['sender_email'] as String,
        senderPhoneE164: json['sender_phone_e164'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        batteryPercent: json['battery_percent'] as int?,
        networkState: json['network_state'] as String?,
        createdAt: parseApiTime(json['created_at'] as String),
        updatedAt: parseApiTime(json['updated_at'] as String),
        state: json['state'] as String? ?? 'active',
        isTest: json['is_test'] as bool? ?? false,
        silentMode: json['silent_mode'] as bool? ?? false,
        deliveredAt: json['delivered_at'] == null ? null : parseApiTime(json['delivered_at'] as String),
        acknowledgedAt: json['acknowledged_at'] == null ? null : parseApiTime(json['acknowledged_at'] as String),
        note: json['note'] as String?,
        lastDeviceSeenAt: json['last_device_seen_at'] == null ? null : parseApiTime(json['last_device_seen_at'] as String),
        lastGpsFixAt: json['last_gps_fix_at'] == null ? null : parseApiTime(json['last_gps_fix_at'] as String),
        lastLocationSyncAt: json['last_location_sync_at'] == null ? null : parseApiTime(json['last_location_sync_at'] as String),
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
    this.speedMps,
    this.headingDeg,
    this.isTest = false,
    this.silentMode = false,
    this.note,
  });

  final String idempotencyKey;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int? batteryPercent;
  final String? networkState;
  final double? speedMps;
  final double? headingDeg;
  final bool isTest;
  final bool silentMode;
  final String? note;

  Map<String, dynamic> toJson() => {
        'idempotency_key': idempotencyKey,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_m': accuracyM,
        'battery_percent': batteryPercent,
        'network_state': networkState,
        'speed_mps': speedMps,
        'heading_deg': headingDeg,
        'is_test': isTest,
        'silent_mode': silentMode,
        'note': note,
      };

  factory QueuedAlert.fromJson(Map<String, dynamic> json) => QueuedAlert(
        idempotencyKey: json['idempotency_key'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        batteryPercent: json['battery_percent'] as int?,
        networkState: json['network_state'] as String?,
        speedMps: (json['speed_mps'] as num?)?.toDouble(),
        headingDeg: (json['heading_deg'] as num?)?.toDouble(),
        isTest: json['is_test'] as bool? ?? false,
        silentMode: json['silent_mode'] as bool? ?? false,
        note: json['note'] as String?,
      );
}

class QueuedLocationUpdate {
  const QueuedLocationUpdate({
    required this.alertId,
    required this.latitude,
    required this.longitude,
    required this.recordedLocallyAt,
    this.accuracyM,
    this.batteryPercent,
    this.networkState,
    this.speedMps,
    this.headingDeg,
  });

  final String alertId;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int? batteryPercent;
  final String? networkState;
  final double? speedMps;
  final double? headingDeg;
  final DateTime recordedLocallyAt;

  Map<String, dynamic> toJson() => {
        'alert_id': alertId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_m': accuracyM,
        'battery_percent': batteryPercent,
        'network_state': networkState,
        'speed_mps': speedMps,
        'heading_deg': headingDeg,
        'recorded_locally_at': recordedLocallyAt.toUtc().toIso8601String(),
      };

  factory QueuedLocationUpdate.fromJson(Map<String, dynamic> json) => QueuedLocationUpdate(
        alertId: json['alert_id'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        batteryPercent: json['battery_percent'] as int?,
        networkState: json['network_state'] as String?,
        speedMps: (json['speed_mps'] as num?)?.toDouble(),
        headingDeg: (json['heading_deg'] as num?)?.toDouble(),
        recordedLocallyAt: parseApiTime(json['recorded_locally_at'] as String),
      );
}


class ResponderState {
  const ResponderState({
    required this.responderUserId,
    required this.responderName,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    required this.distanceM,
    required this.etaSeconds,
    this.accuracyM,
    this.speedMps,
    this.headingDeg,
  });

  final String responderUserId;
  final String responderName;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final double? speedMps;
  final double? headingDeg;
  final DateTime updatedAt;
  final int distanceM;
  final int etaSeconds;

  factory ResponderState.fromJson(Map<String, dynamic> json) => ResponderState(
        responderUserId: json['responder_user_id'] as String,
        responderName: json['responder_name'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        speedMps: (json['speed_mps'] as num?)?.toDouble(),
        headingDeg: (json['heading_deg'] as num?)?.toDouble(),
        updatedAt: parseApiTime(json['updated_at'] as String),
        distanceM: json['distance_m'] as int,
        etaSeconds: json['eta_seconds'] as int,
      );
}


class ResponderTrailPoint {
  const ResponderTrailPoint({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.accuracyM,
    this.speedMps,
    this.headingDeg,
  });

  final double latitude;
  final double longitude;
  final double? accuracyM;
  final double? speedMps;
  final double? headingDeg;
  final DateTime recordedAt;

  factory ResponderTrailPoint.fromJson(Map<String, dynamic> json) => ResponderTrailPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        speedMps: (json['speed_mps'] as num?)?.toDouble(),
        headingDeg: (json['heading_deg'] as num?)?.toDouble(),
        recordedAt: parseApiTime(json['recorded_at'] as String),
      );
}


class PresencePoint {
  const PresencePoint({
    required this.approxDistanceM,
    required this.bearingDeg,
    required this.ageSeconds,
  });

  final int approxDistanceM;
  final int bearingDeg;
  final int ageSeconds;

  factory PresencePoint.fromJson(Map<String, dynamic> json) => PresencePoint(
        approxDistanceM: json['approx_distance_m'] as int,
        bearingDeg: json['bearing_deg'] as int,
        ageSeconds: json['age_seconds'] as int,
      );
}

class SafeNodePoint {
  const SafeNodePoint({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.verified,
    required this.approxDistanceM,
    required this.bearingDeg,
    this.phoneE164,
    this.address,
  });

  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final String? phoneE164;
  final String? address;
  final bool verified;
  final int approxDistanceM;
  final int bearingDeg;

  factory SafeNodePoint.fromJson(Map<String, dynamic> json) => SafeNodePoint(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        phoneE164: json['phone_e164'] as String?,
        address: json['address'] as String?,
        verified: json['verified'] as bool? ?? false,
        approxDistanceM: json['approx_distance_m'] as int,
        bearingDeg: json['bearing_deg'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'latitude': latitude,
        'longitude': longitude,
        'phone_e164': phoneE164,
        'address': address,
        'verified': verified,
        'approx_distance_m': approxDistanceM,
        'bearing_deg': bearingDeg,
      };
}
