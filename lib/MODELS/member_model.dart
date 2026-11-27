import 'package:flutter/material.dart';

import '../UTILS/formatters.dart';

/// Level keanggotaan berdasarkan total belanja kumulatif.
enum MemberTier { regular, silver, gold, platinum }

extension MemberTierInfo on MemberTier {
  String get label {
    switch (this) {
      case MemberTier.regular:
        return 'Regular';
      case MemberTier.silver:
        return 'Silver';
      case MemberTier.gold:
        return 'Gold';
      case MemberTier.platinum:
        return 'Platinum';
    }
  }

  /// Total belanja kumulatif minimum untuk mencapai level ini.
  double get minSpend {
    switch (this) {
      case MemberTier.regular:
        return 0;
      case MemberTier.silver:
        return 1000000;
      case MemberTier.gold:
        return 3000000;
      case MemberTier.platinum:
        return 7500000;
    }
  }

  /// Diskon otomatis untuk subtotal produk.
  double get discountRate {
    switch (this) {
      case MemberTier.regular:
        return 0;
      case MemberTier.silver:
        return 0.03;
      case MemberTier.gold:
        return 0.05;
      case MemberTier.platinum:
        return 0.08;
    }
  }

  /// Pengali poin: 1 poin per Rp10.000 belanja x pengali ini.
  double get pointMultiplier {
    switch (this) {
      case MemberTier.regular:
        return 1.0;
      case MemberTier.silver:
        return 1.25;
      case MemberTier.gold:
        return 1.5;
      case MemberTier.platinum:
        return 2.0;
    }
  }

  /// Minimal belanja untuk gratis ongkir (0 = selalu gratis).
  double get freeShippingMinSpend {
    switch (this) {
      case MemberTier.regular:
        return 750000;
      case MemberTier.silver:
        return 500000;
      case MemberTier.gold:
        return 300000;
      case MemberTier.platinum:
        return 0;
    }
  }

  int get discountPercent => (discountRate * 100).round();

  List<Color> get gradient {
    switch (this) {
      case MemberTier.regular:
        return const [Color(0xFF2B2B2B), Color(0xFF555555)];
      case MemberTier.silver:
        return const [Color(0xFF58626F), Color(0xFF9AA5B1)];
      case MemberTier.gold:
        return const [Color(0xFF8A6A12), Color(0xFFD9B13C)];
      case MemberTier.platinum:
        return const [Color(0xFF1E1B2E), Color(0xFF6A4FA3)];
    }
  }

  Color get accent => gradient.last;

  IconData get icon {
    switch (this) {
      case MemberTier.regular:
        return Icons.person;
      case MemberTier.silver:
        return Icons.military_tech;
      case MemberTier.gold:
        return Icons.workspace_premium;
      case MemberTier.platinum:
        return Icons.diamond;
    }
  }

  MemberTier? get next {
    final nextIndex = index + 1;
    if (nextIndex >= MemberTier.values.length) return null;
    return MemberTier.values[nextIndex];
  }

  List<String> get benefits {
    final shipping = freeShippingMinSpend == 0
        ? 'Gratis ongkir untuk semua pesanan'
        : 'Gratis ongkir min. belanja ${formatRupiah(freeShippingMinSpend)}';
    return [
      if (discountRate > 0)
        'Diskon member $discountPercent% otomatis di checkout'
      else
        'Akses harga & promo khusus member',
      'Poin x${pointMultiplier.toStringAsFixed(pointMultiplier % 1 == 0 ? 0 : 2)} '
          '(1 poin tiap Rp10.000 belanja)',
      shipping,
      if (this == MemberTier.gold || this == MemberTier.platinum)
        'Akses voucher eksklusif $label',
    ];
  }
}

/// Menentukan level dari total belanja kumulatif.
MemberTier tierForSpend(double spend) {
  for (final tier in MemberTier.values.reversed) {
    if (spend >= tier.minSpend) return tier;
  }
  return MemberTier.regular;
}

class Member {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String address;
  final String passwordHash;
  final String salt;
  final DateTime joinedAt;

  /// Poin bonus (bonus pendaftaran + check-in harian).
  final int bonusPoints;

  /// Tanggal check-in terakhir (format yyyy-MM-dd) dan jumlah hari beruntun.
  final String? lastCheckInDay;
  final int checkInStreak;

  const Member({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.passwordHash,
    required this.salt,
    required this.joinedAt,
    this.bonusPoints = 0,
    this.lastCheckInDay,
    this.checkInStreak = 0,
  });

  String get firstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'Member' : parts.first;
  }

  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'M';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  Member copyWith({
    String? name,
    String? email,
    String? phone,
    String? address,
    String? passwordHash,
    String? salt,
    int? bonusPoints,
    String? lastCheckInDay,
    int? checkInStreak,
  }) {
    return Member(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      passwordHash: passwordHash ?? this.passwordHash,
      salt: salt ?? this.salt,
      joinedAt: joinedAt,
      bonusPoints: bonusPoints ?? this.bonusPoints,
      lastCheckInDay: lastCheckInDay ?? this.lastCheckInDay,
      checkInStreak: checkInStreak ?? this.checkInStreak,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'address': address,
        'passwordHash': passwordHash,
        'salt': salt,
        'joinedAt': joinedAt.toIso8601String(),
        'bonusPoints': bonusPoints,
        'lastCheckInDay': lastCheckInDay,
        'checkInStreak': checkInStreak,
      };

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: (json['phone'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      passwordHash: json['passwordHash'] as String,
      salt: json['salt'] as String,
      joinedAt: DateTime.parse(json['joinedAt'] as String),
      bonusPoints: (json['bonusPoints'] as num?)?.toInt() ?? 0,
      lastCheckInDay: json['lastCheckInDay'] as String?,
      checkInStreak: (json['checkInStreak'] as num?)?.toInt() ?? 0,
    );
  }
}
