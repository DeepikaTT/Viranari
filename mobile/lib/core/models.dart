DateTime parseApiTime(String raw) {
  final hasOffset = raw.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw);
  return DateTime.parse(hasOffset ? raw : '${raw}Z');
}

class UserProfile {
  const UserProfile({required this.id, required this.name, required this.email, this.phoneE164, this.role = 'traveler'});
  final String id;
  final String name;
  final String email;
  final String? phoneE164;
  final String role;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        phoneE164: json['phone_e164'] as String?,
        role: json['role'] as String? ?? 'traveler',
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

class SafeReachAssignment {
  const SafeReachAssignment({
    required this.assignmentId,
    required this.responderProfileId,
    required this.responderName,
    required this.organizationName,
    required this.category,
    required this.state,
    required this.distanceM,
    required this.offeredAt,
    this.phoneE164,
    this.acceptedAt,
    this.arrivedAt,
    this.completedAt,
  });

  final String assignmentId;
  final String responderProfileId;
  final String responderName;
  final String organizationName;
  final String category;
  final String? phoneE164;
  final String state;
  final double distanceM;
  final DateTime offeredAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? completedAt;

  factory SafeReachAssignment.fromJson(Map<String, dynamic> json) => SafeReachAssignment(
        assignmentId: json['assignment_id'] as String,
        responderProfileId: json['responder_profile_id'] as String,
        responderName: json['responder_name'] as String,
        organizationName: json['organization_name'] as String,
        category: json['category'] as String,
        phoneE164: json['phone_e164'] as String?,
        state: json['state'] as String,
        distanceM: (json['distance_m'] as num).toDouble(),
        offeredAt: parseApiTime(json['offered_at'] as String),
        acceptedAt: json['accepted_at'] == null ? null : parseApiTime(json['accepted_at'] as String),
        arrivedAt: json['arrived_at'] == null ? null : parseApiTime(json['arrived_at'] as String),
        completedAt: json['completed_at'] == null ? null : parseApiTime(json['completed_at'] as String),
      );

  String get statusLabel {
    switch (state) {
      case 'offered': return 'REQUEST SENT';
      case 'accepted': return 'RESPONDER COMING';
      case 'arrived': return 'RESPONDER ARRIVED';
      case 'completed': return 'COMPLETED';
      case 'declined': return 'REMATCHING';
      case 'expired': return 'SEARCHING AGAIN';
      default: return state.toUpperCase();
    }
  }
}

class ProofEvent {
  const ProofEvent({
    required this.sequence,
    required this.eventType,
    required this.actorType,
    required this.payload,
    required this.previousHash,
    required this.eventHash,
    required this.signature,
    required this.keyId,
    required this.createdAt,
  });
  final int sequence;
  final String eventType;
  final String actorType;
  final Map<String, dynamic> payload;
  final String previousHash;
  final String eventHash;
  final String signature;
  final String keyId;
  final DateTime createdAt;

  factory ProofEvent.fromJson(Map<String, dynamic> json) => ProofEvent(
        sequence: json['sequence'] as int,
        eventType: json['event_type'] as String,
        actorType: json['actor_type'] as String,
        payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
        previousHash: json['previous_hash'] as String,
        eventHash: json['event_hash'] as String,
        signature: json['signature'] as String,
        keyId: json['key_id'] as String,
        createdAt: parseApiTime(json['created_at'] as String),
      );
}

class ProofChain {
  const ProofChain({required this.alertId, required this.algorithm, required this.keyId, required this.publicKeyB64, required this.events});
  final String alertId;
  final String algorithm;
  final String keyId;
  final String publicKeyB64;
  final List<ProofEvent> events;

  factory ProofChain.fromJson(Map<String, dynamic> json) => ProofChain(
        alertId: json['alert_id'] as String,
        algorithm: json['algorithm'] as String,
        keyId: json['key_id'] as String,
        publicKeyB64: json['public_key_b64'] as String,
        events: (json['events'] as List<dynamic>? ?? const []).map((e) => ProofEvent.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class ProofVerification {
  const ProofVerification({required this.valid, required this.eventCount, required this.hashChainValid, required this.signaturesValid, required this.keyId, this.firstInvalidSequence});
  final bool valid;
  final int eventCount;
  final bool hashChainValid;
  final bool signaturesValid;
  final String keyId;
  final int? firstInvalidSequence;

  factory ProofVerification.fromJson(Map<String, dynamic> json) => ProofVerification(
        valid: json['valid'] as bool? ?? false,
        eventCount: json['event_count'] as int? ?? 0,
        hashChainValid: json['hash_chain_valid'] as bool? ?? false,
        signaturesValid: json['signatures_valid'] as bool? ?? false,
        keyId: json['key_id'] as String? ?? '',
        firstInvalidSequence: json['first_invalid_sequence'] as int?,
      );
}

class ResponderProfile {
  const ResponderProfile({
    required this.id,
    required this.userId,
    required this.responderName,
    required this.organizationName,
    required this.category,
    required this.verificationStatus,
    required this.isAvailable,
    required this.serviceRadiusM,
    this.latitude,
    this.longitude,
    this.lastSeenAt,
  });
  final String id;
  final String userId;
  final String responderName;
  final String organizationName;
  final String category;
  final String verificationStatus;
  final bool isAvailable;
  final int serviceRadiusM;
  final double? latitude;
  final double? longitude;
  final DateTime? lastSeenAt;

  factory ResponderProfile.fromJson(Map<String, dynamic> json) => ResponderProfile(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        responderName: json['responder_name'] as String,
        organizationName: json['organization_name'] as String,
        category: json['category'] as String,
        verificationStatus: json['verification_status'] as String,
        isAvailable: json['is_available'] as bool? ?? false,
        serviceRadiusM: json['service_radius_m'] as int? ?? 3000,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        lastSeenAt: json['last_seen_at'] == null ? null : parseApiTime(json['last_seen_at'] as String),
      );
}

class ResponderIncident {
  const ResponderIncident({required this.alertId, required this.senderName, required this.latitude, required this.longitude, required this.state, required this.assignment, this.senderPhoneE164, this.accuracyM, this.note});
  final String alertId;
  final String senderName;
  final String? senderPhoneE164;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final String? note;
  final String state;
  final SafeReachAssignment assignment;

  factory ResponderIncident.fromJson(Map<String, dynamic> json) => ResponderIncident(
        alertId: json['alert_id'] as String,
        senderName: json['sender_name'] as String,
        senderPhoneE164: json['sender_phone_e164'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        note: json['note'] as String?,
        state: json['state'] as String,
        assignment: SafeReachAssignment.fromJson(json['assignment'] as Map<String, dynamic>),
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
    this.lastDeviceSeenAt,
    this.lastGpsFixAt,
    this.lastLocationSyncAt,
    this.safeReach,
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
  final DateTime? lastDeviceSeenAt;
  final DateTime? lastGpsFixAt;
  final DateTime? lastLocationSyncAt;
  final SafeReachAssignment? safeReach;

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
        note: json['note'] as String?,
        cancelledAt: json['cancelled_at'] == null ? null : parseApiTime(json['cancelled_at'] as String),
        resolvedAt: json['resolved_at'] == null ? null : parseApiTime(json['resolved_at'] as String),
        lastDeviceSeenAt: json['last_device_seen_at'] == null ? null : parseApiTime(json['last_device_seen_at'] as String),
        lastGpsFixAt: json['last_gps_fix_at'] == null ? null : parseApiTime(json['last_gps_fix_at'] as String),
        lastLocationSyncAt: json['last_location_sync_at'] == null ? null : parseApiTime(json['last_location_sync_at'] as String),
        safeReach: json['safe_reach'] == null ? null : SafeReachAssignment.fromJson(json['safe_reach'] as Map<String, dynamic>),
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
    this.safeReach,
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
  final DateTime? deliveredAt;
  final DateTime? acknowledgedAt;
  final String? note;
  final DateTime? lastDeviceSeenAt;
  final DateTime? lastGpsFixAt;
  final DateTime? lastLocationSyncAt;
  final SafeReachAssignment? safeReach;

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
        deliveredAt: json['delivered_at'] == null ? null : parseApiTime(json['delivered_at'] as String),
        acknowledgedAt: json['acknowledged_at'] == null ? null : parseApiTime(json['acknowledged_at'] as String),
        note: json['note'] as String?,
        lastDeviceSeenAt: json['last_device_seen_at'] == null ? null : parseApiTime(json['last_device_seen_at'] as String),
        lastGpsFixAt: json['last_gps_fix_at'] == null ? null : parseApiTime(json['last_gps_fix_at'] as String),
        lastLocationSyncAt: json['last_location_sync_at'] == null ? null : parseApiTime(json['last_location_sync_at'] as String),
        safeReach: json['safe_reach'] == null ? null : SafeReachAssignment.fromJson(json['safe_reach'] as Map<String, dynamic>),
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
