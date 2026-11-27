import 'package:flutter/material.dart';

/// Jenis aktivitas akun yang dicatat untuk pemantauan alur pengguna.
enum ActivityType {
  register,
  login,
  logout,
  order,
  cancel,
  profile,
  password,
  checkIn,
  review,
  voucher,
}

extension ActivityTypeInfo on ActivityType {
  IconData get icon {
    switch (this) {
      case ActivityType.register:
        return Icons.how_to_reg_outlined;
      case ActivityType.login:
        return Icons.login;
      case ActivityType.logout:
        return Icons.logout;
      case ActivityType.order:
        return Icons.shopping_bag_outlined;
      case ActivityType.cancel:
        return Icons.cancel_outlined;
      case ActivityType.profile:
        return Icons.person_outline;
      case ActivityType.password:
        return Icons.lock_reset;
      case ActivityType.checkIn:
        return Icons.event_available_outlined;
      case ActivityType.review:
        return Icons.rate_review_outlined;
      case ActivityType.voucher:
        return Icons.local_offer_outlined;
    }
  }

  Color get color {
    switch (this) {
      case ActivityType.register:
        return const Color(0xFF2E7D32);
      case ActivityType.login:
        return const Color(0xFF1565C0);
      case ActivityType.logout:
        return const Color(0xFF616161);
      case ActivityType.order:
        return const Color(0xFFEC1C24);
      case ActivityType.cancel:
        return const Color(0xFF9E9E9E);
      case ActivityType.profile:
        return const Color(0xFF6A4FA3);
      case ActivityType.password:
        return const Color(0xFFEF6C00);
      case ActivityType.checkIn:
        return const Color(0xFF00897B);
      case ActivityType.review:
        return const Color(0xFFF9A825);
      case ActivityType.voucher:
        return const Color(0xFFC2185B);
    }
  }

  String get label {
    switch (this) {
      case ActivityType.register:
        return 'Pendaftaran';
      case ActivityType.login:
        return 'Masuk';
      case ActivityType.logout:
        return 'Keluar';
      case ActivityType.order:
        return 'Pesanan';
      case ActivityType.cancel:
        return 'Pembatalan';
      case ActivityType.profile:
        return 'Profil';
      case ActivityType.password:
        return 'Keamanan';
      case ActivityType.checkIn:
        return 'Check-in';
      case ActivityType.review:
        return 'Ulasan';
      case ActivityType.voucher:
        return 'Voucher';
    }
  }
}

/// Satu catatan aktivitas milik member.
class ActivityEvent {
  final String id;
  final String memberId;
  final ActivityType type;
  final String title;
  final String detail;
  final DateTime at;

  /// Perubahan poin akibat aktivitas ini (mis. check-in), jika ada.
  final int points;

  const ActivityEvent({
    required this.id,
    required this.memberId,
    required this.type,
    required this.title,
    this.detail = '',
    required this.at,
    this.points = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'memberId': memberId,
        'type': type.name,
        'title': title,
        'detail': detail,
        'at': at.toIso8601String(),
        'points': points,
      };

  factory ActivityEvent.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String?;
    return ActivityEvent(
      id: json['id'] as String,
      memberId: json['memberId'] as String,
      type: ActivityType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => ActivityType.profile,
      ),
      title: json['title'] as String,
      detail: (json['detail'] as String?) ?? '',
      at: DateTime.parse(json['at'] as String),
      points: (json['points'] as num?)?.toInt() ?? 0,
    );
  }
}
