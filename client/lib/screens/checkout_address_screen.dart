import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../services/city_service.dart';
import '../services/address_service.dart';
import '../services/receiver_service.dart';
import '../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';

class CheckoutAddressScreen extends StatefulWidget {
  final Map<String, dynamic>? initialAddress;
  final String? initialReceiverName;
  final String? initialReceiverPhone;

  const CheckoutAddressScreen({
    super.key,
    this.initialAddress,
    this.initialReceiverName,
    this.initialReceiverPhone,
  });

  @override
  State<CheckoutAddressScreen> createState() => _CheckoutAddressScreenState();
}

class _CheckoutAddressScreenState extends State<CheckoutAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String? _selectedWilaya = 'Béjaïa';
  String? _selectedCommune;
  List<String> _wilayas = [];
  List<String> _communes = [];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _additionalInfoController = TextEditingController();

  final MapController _mapController = MapController();
  final Completer<void> _mapReadyCompleter = Completer<void>();
  LatLng _selectedLocation = const LatLng(36.7515, 5.0550); // Default Bejaia
  bool _loadingLocation = false;
  
  @override
  void initState() {
    super.initState();
    _mapController.mapEventStream.listen((event) {
      if (!_mapReadyCompleter.isCompleted) {
        _mapReadyCompleter.complete();
      }
    });
    _initData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _additionalInfoController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    if (!CityService.isLoaded()) {
      try {
        final jsonString = await rootBundle.loadString('lib/data/algeria_cities.json');
        await CityService.loadCities(jsonString);
      } catch (e) {
        print('Error loading cities: $e');
      }
    }

    try {
      final snap = await FirebaseDatabase.instance.ref('settings/allowedWilayas').get();
      if (snap.exists) {
        List<String> codes = [];
        if (snap.value is List) {
          codes = (snap.value as List).cast<String>();
        } else if (snap.value is Map) {
          codes = (snap.value as Map).values.cast<String>().toList();
        }
        CityService.setAllowedWilayas(codes);
      }
    } catch (e) {
      print('Error loading allowed wilayas: $e');
    }

    setState(() {
      _wilayas = CityService.getWilayas();
      if (_wilayas.isNotEmpty && !_wilayas.contains(_selectedWilaya)) {
        _selectedWilaya = _wilayas.first;
      }
      _communes = _selectedWilaya != null ? CityService.getCommunesForWilaya(_selectedWilaya!) : [];
    });

    if (widget.initialAddress != null) {
      final w = widget.initialAddress!['wilaya']?.toString();
      final c = widget.initialAddress!['commune']?.toString();
      final lat = widget.initialAddress!['latitude'];
      final lng = widget.initialAddress!['longitude'];
      final label = widget.initialAddress!['label']?.toString();
      
      if (w != null && _wilayas.contains(w)) {
        _selectedWilaya = w;
        _communes = CityService.getCommunesForWilaya(w);
      }
      if (c != null && _communes.contains(c)) {
        _selectedCommune = c;
      }
      if (lat != null && lng != null) {
        _selectedLocation = LatLng((lat as num).toDouble(), (lng as num).toDouble());
        _moveMap(_selectedLocation);
      }
      if (label != null && label.isNotEmpty) {
        _additionalInfoController.text = label;
      }
    }

    _nameController.text = widget.initialReceiverName ?? '';
    _phoneController.text = widget.initialReceiverPhone ?? '';
  }

  Future<void> _moveMap(LatLng target) async {
    try {
      await _mapReadyCompleter.future;
      if (!mounted) return;
      _mapController.move(target, 14.0);
    } catch (e) {
      print('Error moving map: $e');
    }
  }

  Future<void> _geocodeAndMoveToCommune() async {
    if (_selectedCommune == null || _selectedWilaya == null) return;
    final query = '$_selectedCommune, $_selectedWilaya, Algeria';
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1',
      );
      final response = await http.get(url, headers: {'User-Agent': 'com.salimstore.client'});
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.tryParse(data[0]['lat'].toString()) ?? 0.0;
          final lon = double.tryParse(data[0]['lon'].toString()) ?? 0.0;
          if (lat != 0 && lon != 0) {
            setState(() {
              _selectedLocation = LatLng(lat, lon);
            });
            await _moveMap(_selectedLocation);
          }
        }
      }
    } catch (e) {
      print('Geocoding error: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Les services de localisation sont désactivés.');
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Les permissions de localisation sont refusées');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Les permissions de localisation sont définitivement refusées.');
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;

      setState(() {
        _selectedLocation = LatLng(position.latitude, position.longitude);
        _loadingLocation = false;
      });
      await _moveMap(_selectedLocation);
      
      // Optionally reverse geocode to update wilaya/commune
    } catch (e) {
      setState(() => _loadingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  void _submit() async {
    if (_selectedCommune == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vous devez indiquer l'adresse de livraison"), backgroundColor: AppTheme.errorColor),
      );
      return;
    }
    
    if (!_formKey.currentState!.validate()) return;
    
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final additionalInfo = _additionalInfoController.text.trim();

    final addressData = {
      'wilaya': _selectedWilaya,
      'commune': _selectedCommune,
      'fullAddress': '$_selectedCommune, $_selectedWilaya',
      'label': additionalInfo.isNotEmpty ? additionalInfo : 'Adresse de livraison',
      'latitude': _selectedLocation.latitude,
      'longitude': _selectedLocation.longitude,
    };

    final receiverData = {
      'name': name,
      'phone': phone,
    };
    
    // Save to SharedPreferences for quick recall
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('receiver_name', name);
    await prefs.setString('receiver_phone', phone);

    Navigator.pop(context, {
      'address': addressData,
      'receiver': receiverData,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Adresse et Destinataire'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Address Section
                      const Text(
                        '1. Adresse de livraison',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedWilaya,
                        decoration: InputDecoration(
                          labelText: 'Wilaya',
                          prefixIcon: const Icon(Icons.map),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: _wilayas.map((w) {
                          return DropdownMenuItem(
                            value: w,
                            child: Text(
                              w,
                              style: const TextStyle(color: Colors.black),
                            ),
                          );
                        }).toList(),
                        validator: (val) {
                          if (val == null) return "Veuillez sélectionner une wilaya";
                          return null;
                        },
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedWilaya = val;
                              _communes = CityService.getCommunesForWilaya(val);
                              _selectedCommune = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedCommune,
                        decoration: InputDecoration(
                          labelText: 'Commune',
                          prefixIcon: const Icon(Icons.location_city),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: _communes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedCommune = val;
                            });
                            _geocodeAndMoveToCommune();
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                center: _selectedLocation,
                                zoom: 14,
                                onTap: (tapPos, latlng) {
                                  setState(() => _selectedLocation = latlng);
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                                  userAgentPackageName: 'com.salimstore.client',
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _selectedLocation,
                                      width: 40,
                                      height: 40,
                                      child: const Icon(Icons.location_on, size: 40, color: AppTheme.primaryColor),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: FloatingActionButton.small(
                                backgroundColor: Colors.white,
                                child: _loadingLocation 
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.my_location, color: AppTheme.primaryColor),
                                onPressed: _getCurrentLocation,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Tapez sur la carte pour affiner la position exacte.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _additionalInfoController,
                        decoration: InputDecoration(
                          labelText: 'Informations supplémentaires',
                          hintText: 'Bâtiment, appartement, étage etc',
                          prefixIcon: const Icon(Icons.home_work_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Recipient Section
                      const Text(
                        '2. Informations du destinataire',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                      ),
                      const SizedBox(height: 16),
                       TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Nom complet',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          errorMaxLines: 2,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Veuillez entrer le nom';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Téléphone',
                          prefixIcon: const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Text('+213', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          errorMaxLines: 2,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return "Vous devez indiquer le numéro de téléphone du destinataire.";
                          }
                          if (val.length != 10) {
                            return 'Le numéro de téléphone doit être exactement de 10 chiffres';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5)),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Confirmer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
