class BusinessBrief {
  const BusinessBrief({required this.id, required this.name, required this.role});

  final String id;
  final String name;
  final String role;

  factory BusinessBrief.fromJson(Map<String, dynamic> j) {
    return BusinessBrief(
      id: j['id'].toString(),
      name: j['name'] as String,
      role: j['role'] as String,
    );
  }
}

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.businesses,
  });

  final String accessToken;
  final String refreshToken;
  final List<BusinessBrief> businesses;

  BusinessBrief get primaryBusiness => businesses.first;
}
