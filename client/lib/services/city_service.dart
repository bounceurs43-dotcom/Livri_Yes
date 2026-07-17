import 'dart:convert';

class CityService {
  static List<Map<String, dynamic>> _cities = [];
  static List<String> _wilayas = [];
  static List<String> _allowedWilayaCodes = [];

  static void setAllowedWilayas(List<String> codes) {
    _allowedWilayaCodes = codes;
  }

  static Future<void> loadCities(String jsonString) async {
    try {
      final List<dynamic> jsonData = json.decode(jsonString);
      _cities = jsonData.cast<Map<String, dynamic>>();

      // Extract unique wilayas - filter out null values
      final Set<String> wilayaSet = {};
      for (final city in _cities) {
        final wilayaName = city['wilaya_name_ascii'];
        if (wilayaName != null && wilayaName.toString().isNotEmpty) {
          wilayaSet.add(wilayaName.toString());
        }
      }
      _wilayas = wilayaSet.toList()..sort();
    } catch (e) {
      throw Exception('Failed to load cities: $e');
    }
  }

  static List<String> getWilayas() {
    if (_allowedWilayaCodes.isEmpty) {
      return List.from(_wilayas);
    }
    return _wilayas.where((w) => isWilayaAllowed(w)).toList();
  }

  static bool isWilayaAllowed(String wilayaName) {
    if (_allowedWilayaCodes.isEmpty) {
      return true; // Default behavior if nothing loaded yet
    }
    final code = getWilayaCode(wilayaName);
    return code != null && _allowedWilayaCodes.contains(code);
  }

  static List<String> getCommunesForWilaya(String wilayaName) {
    final communes = _cities
        .where(
          (city) =>
              city['wilaya_name_ascii'] != null &&
              city['wilaya_name_ascii'].toString() == wilayaName &&
              city['commune_name_ascii'] != null &&
              city['commune_name_ascii'].toString().isNotEmpty,
        )
        .map((city) => city['commune_name_ascii'].toString())
        .toSet() // Remove duplicates
        .toList();
    communes.sort();
    return communes;
  }

  static String? getWilayaCode(String wilayaName) {
    final city = _cities.firstWhere(
      (city) => city['wilaya_name_ascii'] == wilayaName,
      orElse: () => <String, dynamic>{},
    );
    return city['wilaya_code'];
  }

  static String? getCommuneName(String wilayaName, String communeName) {
    final city = _cities.firstWhere(
      (city) =>
          city['wilaya_name_ascii'] == wilayaName &&
          city['commune_name_ascii'] == communeName,
      orElse: () => <String, dynamic>{},
    );
    return city['commune_name'];
  }

  static bool isLoaded() {
    return _cities.isNotEmpty;
  }
}
