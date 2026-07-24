import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import '../services/city_service.dart';
import '../theme/app_theme.dart';

class GpsMapSelectionModal extends StatefulWidget {
  final LatLng? initialLocation;
  final String? initialWilaya;
  final String? initialCommune;

  const GpsMapSelectionModal({
    super.key,
    this.initialLocation,
    this.initialWilaya,
    this.initialCommune,
  });

  @override
  State<GpsMapSelectionModal> createState() => _GpsMapSelectionModalState();
}

class _GpsMapSelectionModalState extends State<GpsMapSelectionModal> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng _currentLocation = const LatLng(36.7538, 5.0588); // Default Béjaïa
  LatLng? _selectedLocation;
  String? _formattedAddress;
  String? _detectedWilaya;
  String? _detectedCommune;
  bool _isAllowedWilaya = true;

  bool _loadingGps = false;
  bool _isSearching = false;
  bool _reverseGeocoding = false;
  List<Map<String, dynamic>> _searchResults = [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialLocation != null) {
      _currentLocation = widget.initialLocation!;
      _selectedLocation = widget.initialLocation!;
      _reverseGeocode(_selectedLocation!);
    } else if (widget.initialWilaya != null && widget.initialWilaya!.isNotEmpty) {
      _initFromWilayaCommune();
    } else {
      _detectGpsLocation(initial: true);
    }
  }

  Future<void> _initFromWilayaCommune() async {
    final parts = <String>[];
    if (widget.initialCommune != null && widget.initialCommune!.isNotEmpty) {
      parts.add(widget.initialCommune!);
    }
    if (widget.initialWilaya != null && widget.initialWilaya!.isNotEmpty) {
      parts.add(widget.initialWilaya!);
    }
    parts.add('Algeria');
    final query = parts.join(', ');

    _searchController.text = query;
    if (mounted) setState(() => _isSearching = true);

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&addressdetails=1&limit=1&countrycodes=dz',
      );
      final response = await http.get(url, headers: {'User-Agent': 'LivriYesApp'}).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty && data.first is Map) {
          final first = data.first as Map<String, dynamic>;
          final lat = double.tryParse(first['lat'].toString()) ?? 0.0;
          final lon = double.tryParse(first['lon'].toString()) ?? 0.0;
          if (lat != 0.0 && lon != 0.0) {
            final target = LatLng(lat, lon);
            final displayName = first['display_name']?.toString() ?? query;

            if (mounted) {
              setState(() {
                _currentLocation = target;
                _selectedLocation = target;
                _formattedAddress = displayName;
                _detectedWilaya = widget.initialWilaya;
                _detectedCommune = widget.initialCommune;
                _isAllowedWilaya = _checkIfWilayaAllowed(displayName);
                _isSearching = false;
              });
              _mapController.move(target, 14.0);
              return;
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isSearching = false);
      _detectGpsLocation(initial: true);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  String _normalize(String str) {
    return str
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ï', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('û', 'u')
        .replaceAll('ç', 'c');
  }

  String? _matchWilaya(String input) {
    if (!CityService.isLoaded()) return null;
    final normInput = _normalize(input);
    final allWilayas = CityService.getAllWilayas();
    for (final w in allWilayas) {
      final normW = _normalize(w);
      if (normInput.contains(normW) || normW.contains(normInput)) {
        return w;
      }
    }
    return null;
  }

  String? _matchCommune(String wilaya, String input) {
    if (!CityService.isLoaded()) return null;
    final normInput = _normalize(input);
    final communes = CityService.getCommunesForWilaya(wilaya);
    for (final c in communes) {
      final normC = _normalize(c);
      if (normInput.contains(normC) || normC.contains(normInput)) {
        return c;
      }
    }
    return null;
  }

  bool _checkIfWilayaAllowed(String addressText) {
    if (!CityService.isLoaded()) return true;
    final allowedWilayas = CityService.getWilayas();

    final matched = _matchWilaya(addressText);
    if (matched != null) {
      _detectedWilaya = matched;
      _detectedCommune = _matchCommune(matched, addressText);
      if (allowedWilayas.isEmpty) return true;
      return allowedWilayas.contains(matched);
    }
    return true;
  }

  Future<void> _detectGpsLocation({bool initial = false}) async {
    setState(() => _loadingGps = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!initial && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Veuillez activer la localisation GPS.'),
              backgroundColor: AppTheme.warningColor,
            ),
          );
        }
        setState(() => _loadingGps = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _loadingGps = false);
          return;
        }
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final newLatLng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentLocation = newLatLng;
        _selectedLocation = newLatLng;
        _loadingGps = false;
      });

      _mapController.move(newLatLng, 15.0);
      await _reverseGeocode(newLatLng);
    } catch (e) {
      setState(() => _loadingGps = false);
    }
  }

  Future<void> _reverseGeocode(LatLng location) async {
    setState(() => _reverseGeocoding = true);
    String? fullAddr;
    String? foundWilaya;
    String? foundCommune;

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${location.latitude}&lon=${location.longitude}&format=json&addressdetails=1',
      );
      final response = await http.get(url, headers: {'User-Agent': 'LivriYesApp'}).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map) {
          if (data.containsKey('display_name')) {
            fullAddr = data['display_name']?.toString();
          }
          if (data['address'] is Map) {
            final addrMap = data['address'] as Map;
            final rawState = addrMap['state'] ?? addrMap['province'] ?? addrMap['county'] ?? addrMap['state_district'];
            if (rawState != null) {
              foundWilaya = _matchWilaya(rawState.toString());
            }
            final rawCommune = addrMap['city'] ?? addrMap['town'] ?? addrMap['village'] ?? addrMap['suburb'] ?? addrMap['municipality'] ?? addrMap['district'];
            if (rawCommune != null) {
              if (foundWilaya != null) {
                foundCommune = _matchCommune(foundWilaya, rawCommune.toString());
              } else {
                foundWilaya = _matchWilaya(rawCommune.toString());
              }
            }
          }
        }
      }
    } catch (_) {}

    if (fullAddr == null || fullAddr.isEmpty || foundWilaya == null) {
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          if (fullAddr == null || fullAddr.isEmpty) {
            final parts = <String>[];
            if (p.street != null && p.street!.trim().isNotEmpty) parts.add(p.street!.trim());
            if (p.subLocality != null && p.subLocality!.trim().isNotEmpty) parts.add(p.subLocality!.trim());
            if (p.locality != null && p.locality!.trim().isNotEmpty) parts.add(p.locality!.trim());
            if (p.administrativeArea != null && p.administrativeArea!.trim().isNotEmpty) parts.add(p.administrativeArea!.trim());
            if (p.country != null && p.country!.trim().isNotEmpty) parts.add(p.country!.trim());
            if (parts.isNotEmpty) {
              fullAddr = parts.join(', ');
            }
          }

          if (foundWilaya == null && p.administrativeArea != null) {
            foundWilaya = _matchWilaya(p.administrativeArea!);
          }
          if (foundWilaya == null && p.locality != null) {
            foundWilaya = _matchWilaya(p.locality!);
          }

          if (foundWilaya != null && foundCommune == null) {
            if (p.subLocality != null) {
              foundCommune = _matchCommune(foundWilaya, p.subLocality!);
            }
            if (foundCommune == null && p.locality != null) {
              foundCommune = _matchCommune(foundWilaya, p.locality!);
            }
          }
        }
      } catch (_) {}
    }

    fullAddr ??= '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';

    if (foundWilaya != null) {
      _detectedWilaya = foundWilaya;
    }
    if (foundCommune != null) {
      _detectedCommune = foundCommune;
    }

    bool allowed = _checkIfWilayaAllowed(fullAddr);

    if (mounted) {
      setState(() {
        _formattedAddress = fullAddr;
        _isAllowedWilaya = allowed;
        _reverseGeocoding = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (query.trim().length >= 2) {
        _searchAddress(query.trim());
      } else {
        setState(() => _searchResults = []);
      }
    });
  }

  Future<void> _searchAddress(String query) async {
    setState(() => _isSearching = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5&countrycodes=dz',
      );
      final response = await http.get(url, headers: {'User-Agent': 'LivriYesApp'});
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Map<String, dynamic>> parsed = List<Map<String, dynamic>>.from(data);
        setState(() {
          _searchResults = parsed;
          _isSearching = false;
        });
      } else {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    } catch (_) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  void _selectSearchResult(Map<String, dynamic> result) {
    final lat = double.tryParse(result['lat'].toString()) ?? 0.0;
    final lon = double.tryParse(result['lon'].toString()) ?? 0.0;
    final target = LatLng(lat, lon);
    final displayName = result['display_name']?.toString() ?? '';

    bool allowed = _checkIfWilayaAllowed(displayName);

    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Désolé, la livraison n'est pas disponible à $displayName."),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() {
      _selectedLocation = target;
      _formattedAddress = displayName;
      _isAllowedWilaya = true;
      _searchResults = [];
      _searchController.clear();
      FocusScope.of(context).unfocus();
    });

    _mapController.move(target, 15.0);
  }

  void _confirmSelection() {
    if (_selectedLocation == null || _formattedAddress == null) return;
    if (!_isAllowedWilaya) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("La livraison n'est pas encore disponible dans cette wilaya."),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'address': _formattedAddress,
      'wilaya': _detectedWilaya,
      'commune': _detectedCommune,
      'latitude': _selectedLocation!.latitude,
      'longitude': _selectedLocation!.longitude,
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final modalHeight = mediaQuery.size.height * 0.85;

    return Container(
      height: modalHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.map,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Localisation GPS & Carte',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Search Bar Input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Rechercher une adresse / ville...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchResults = []);
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),

            // Search Results Overlay list
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_searchResults.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                color: Colors.white,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    final name = item['display_name']?.toString() ?? '';
                    final allowed = _checkIfWilayaAllowed(name);

                    return ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.location_on,
                        color: allowed ? AppTheme.primaryColor : Colors.grey,
                      ),
                      title: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: allowed ? Colors.black : Colors.grey,
                        ),
                      ),
                      subtitle: !allowed
                          ? const Text(
                              'Livraison non disponible',
                              style: TextStyle(color: Colors.red, fontSize: 11),
                            )
                          : null,
                      onTap: () => _selectSearchResult(item),
                    );
                  },
                ),
              ),

            // Interactive Map
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      center: _currentLocation,
                      zoom: 15.0,
                      onTap: (_, latlng) {
                        setState(() {
                          _selectedLocation = latlng;
                        });
                        _reverseGeocode(latlng);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.salimstore.client',
                      ),
                      if (_selectedLocation != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedLocation!,
                              width: 44,
                              height: 44,
                              child: Icon(
                                Icons.location_pin,
                                color: _isAllowedWilaya ? AppTheme.primaryColor : Colors.red,
                                size: 44,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  // Floating GPS My Location button
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'gps_fab_modal',
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryColor,
                      onPressed: _loadingGps ? null : () => _detectGpsLocation(),
                      child: _loadingGps
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Confirmation Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_reverseGeocoding)
                    const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Détection de l\'adresse...',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    )
                  else if (_formattedAddress != null) ...[
                    Row(
                      children: [
                        Icon(
                          _isAllowedWilaya ? Icons.check_circle : Icons.warning,
                          size: 18,
                          color: _isAllowedWilaya ? AppTheme.successColor : AppTheme.errorColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _formattedAddress!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!_isAllowedWilaya)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '⚠️ La livraison n\'est pas encore disponible dans cette wilaya.',
                          style: TextStyle(fontSize: 12, color: AppTheme.errorColor),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: (_selectedLocation != null && _isAllowedWilaya && !_reverseGeocoding)
                        ? _confirmSelection
                        : null,
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text(
                      'Confirmer cette position',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
