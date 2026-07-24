import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import '../services/address_service.dart';
import '../services/city_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gps_map_selection_modal.dart';

class AddressesManagementScreen extends StatefulWidget {
  final VoidCallback? onAddressAdded;
  const AddressesManagementScreen({super.key, this.onAddressAdded});

  @override
  State<AddressesManagementScreen> createState() =>
      _AddressesManagementScreenState();
}

class _AddressesManagementScreenState extends State<AddressesManagementScreen> {
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;
  String? _defaultAddressId;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    setState(() => _loading = true);
    try {
      final addresses = await AddressService.getAddresses();
      final defaultAddr = await AddressService.getDefaultAddress();

      if (mounted) {
        setState(() {
          _addresses = addresses;
          _defaultAddressId = defaultAddr?['id'];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setAsDefault(String addressId, String fullAddress) async {
    try {
      await AddressService.setDefaultAddress(addressId);
      await _loadAddresses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adresse par défaut mise à jour'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _deleteAddress(String addressId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l\'adresse'),
        content: const Text(
          'Êtes-vous sûr de vouloir supprimer cette adresse ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await AddressService.removeAddress(addressId);
        await _loadAddresses();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Adresse supprimée'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur: ${e.toString()}'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Navigation Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mes Adresses',
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 26,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_addresses.length} adresses enregistrées',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Annuler'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Card: Nouvelle adresse
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: _AddAddressModalForm(
                    onAddressAdded: _loadAddresses,
                  ),
                ),
                const SizedBox(height: 24),

                // Registered Addresses List (if any)
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_addresses.isNotEmpty) ...[
                  Text(
                    'Adresses enregistrées',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _addresses.length,
                    itemBuilder: (context, index) {
                      final address = _addresses[index];
                      final isDefault = address['id'] == _defaultAddressId;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDefault
                                ? AppTheme.primaryColor
                                : Colors.grey.shade200,
                            width: isDefault ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDefault
                                      ? AppTheme.primaryColor.withOpacity(0.12)
                                      : Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.location_on,
                                  color: isDefault
                                      ? AppTheme.primaryColor
                                      : AppTheme.textSecondary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      address['label'] ?? 'Adresse',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDefault
                                            ? AppTheme.primaryColor
                                            : AppTheme.textPrimary,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      address['fullAddress'] ?? '',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isDefault)
                                TextButton(
                                  onPressed: () => _setAsDefault(
                                    address['id'],
                                    address['fullAddress'] ?? '',
                                  ),
                                  child: const Text('Choisir'),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Active',
                                    style: TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                                onPressed: () => _deleteAddress(address['id']),
                                color: AppTheme.errorColor,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddAddressModalForm extends StatefulWidget {
  final VoidCallback? onAddressAdded;

  const _AddAddressModalForm({this.onAddressAdded});

  @override
  State<_AddAddressModalForm> createState() => _AddAddressModalFormState();
}

class _AddAddressModalFormState extends State<_AddAddressModalForm>
    with SingleTickerProviderStateMixin {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController(text: '');
  final TextEditingController _notesController = TextEditingController();

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  String? _labelError;
  String? _nameError;
  String? _phoneError;
  String? _wilayaError;
  String? _communeError;

  String? _selectedWilaya;
  String? _selectedCommune;
  List<String> _allWilayas = [];
  List<String> _communes = [];
  bool _loadingWilayas = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

    _labelController.addListener(() {
      if (_labelError != null && _labelController.text.trim().isNotEmpty) {
        setState(() => _labelError = null);
      }
    });
    _nameController.addListener(() {
      if (_nameError != null && _nameController.text.trim().isNotEmpty) {
        setState(() => _nameError = null);
      }
    });
    _phoneController.addListener(() {
      if (_phoneError != null && _phoneController.text.trim().isNotEmpty) {
        setState(() => _phoneError = null);
      }
    });

    _loadWilayasData();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _labelController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadWilayasData() async {
    try {
      if (!CityService.isLoaded()) {
        final jsonString = await rootBundle.loadString('lib/data/algeria_cities.json');
        await CityService.loadCities(jsonString);
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
        print('Error loading allowed wilayas in form: $e');
      }

      setState(() {
        _allWilayas = CityService.getWilayas();
        if (_allWilayas.isNotEmpty && _selectedWilaya == null) {
          _selectedWilaya = _allWilayas.first;
          _communes = CityService.getCommunesForWilaya(_selectedWilaya!);
          if (_communes.isNotEmpty) _selectedCommune = _communes.first;
        }
        _loadingWilayas = false;
      });
    } catch (e) {
      print('Error loading wilayas data: $e');
      setState(() => _loadingWilayas = false);
    }
  }

  void _onWilayaSelected(String wilaya) {
    setState(() {
      _selectedWilaya = wilaya;
      _communes = CityService.getCommunesForWilaya(wilaya);
      _selectedCommune = _communes.isNotEmpty ? _communes.first : null;
      _wilayaError = null;
      _communeError = null;
    });
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
        .replaceAll('ç', 'c')
        .replaceAll('-', ' ')
        .replaceAll("'", ' ');
  }

  Future<void> _fillAddressFromGps() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GpsMapSelectionModal(
        initialWilaya: _selectedWilaya,
        initialCommune: _selectedCommune,
      ),
    );

    if (result != null && result['address'] != null) {
      setState(() {
        _notesController.text = result['address'];
        final detectedWilaya = result['wilaya']?.toString();
        final detectedCommune = result['commune']?.toString();

        if (detectedWilaya != null && detectedWilaya.isNotEmpty) {
          final normDetectedWilaya = _normalize(detectedWilaya);
          String? matchedWilaya;

          for (final w in _allWilayas) {
            final normW = _normalize(w);
            if (normW == normDetectedWilaya ||
                normDetectedWilaya.contains(normW) ||
                normW.contains(normDetectedWilaya)) {
              matchedWilaya = w;
              break;
            }
          }

          if (matchedWilaya != null) {
            _selectedWilaya = matchedWilaya;
            _communes = CityService.getCommunesForWilaya(matchedWilaya);

            if (detectedCommune != null && detectedCommune.isNotEmpty) {
              final normDetectedCommune = _normalize(detectedCommune);
              String? matchedCommune;
              for (final c in _communes) {
                final normC = _normalize(c);
                if (normC == normDetectedCommune ||
                    normDetectedCommune.contains(normC) ||
                    normC.contains(normDetectedCommune)) {
                  matchedCommune = c;
                  break;
                }
              }
              if (matchedCommune != null) {
                _selectedCommune = matchedCommune;
              } else if (_communes.isNotEmpty) {
                _selectedCommune = _communes.first;
              }
            } else if (_communes.isNotEmpty) {
              _selectedCommune = _communes.first;
            }
            _wilayaError = null;
            _communeError = null;
          }
        }
      });
    }
  }

  Future<void> _submitAddress() async {
    bool hasError = false;
    String? labelErr;
    String? nameErr;
    String? phoneErr;
    String? wilayaErr;
    String? communeErr;

    final label = _labelController.text.trim();
    if (label.isEmpty) {
      labelErr = 'Veuillez saisir un label (ex: Maison, Bureau)';
      hasError = true;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      nameErr = 'Veuillez saisir le nom du destinataire';
      hasError = true;
    }

    String rawPhone = _phoneController.text.trim().replaceAll('+213', '').replaceAll(' ', '').trim();
    if (rawPhone.startsWith('0')) {
      if (rawPhone.length == 10 && (rawPhone.startsWith('05') || rawPhone.startsWith('06') || rawPhone.startsWith('07'))) {
        rawPhone = rawPhone.substring(1);
      } else {
        if (!rawPhone.startsWith('05') && !rawPhone.startsWith('06') && !rawPhone.startsWith('07')) {
          phoneErr = 'Numéro invalide (doit commencer par 05, 06 ou 07)';
        } else {
          phoneErr = 'Numéro incomplet (doit contenir 10 chiffres)';
        }
        hasError = true;
      }
    } else {
      if (rawPhone.length == 9 && (rawPhone.startsWith('5') || rawPhone.startsWith('6') || rawPhone.startsWith('7'))) {
        // Valid 9 digits starting with 5, 6, 7
      } else {
        if (!rawPhone.startsWith('5') && !rawPhone.startsWith('6') && !rawPhone.startsWith('7')) {
          phoneErr = 'Numéro invalide (doit commencer par 5, 6 ou 7)';
        } else {
          phoneErr = 'Numéro incomplet (doit contenir 9 chiffres)';
        }
        hasError = true;
      }
    }

    if (_selectedWilaya == null || _selectedWilaya!.isEmpty) {
      wilayaErr = 'Veuillez sélectionner une Wilaya';
      hasError = true;
    }

    if (_selectedCommune == null || _selectedCommune!.isEmpty) {
      communeErr = 'Veuillez sélectionner une Commune';
      hasError = true;
    }

    if (hasError) {
      setState(() {
        _labelError = labelErr;
        _nameError = nameErr;
        _phoneError = phoneErr;
        _wilayaError = wilayaErr;
        _communeError = communeErr;
      });
      _shakeController.forward(from: 0.0);
      return;
    }

    final formattedPhone = '+213 $rawPhone';
    setState(() => _submitting = true);

    try {
      final notes = _notesController.text.trim();

      final parts = <String>[];
      if (_selectedWilaya != null && _selectedWilaya!.isNotEmpty) parts.add(_selectedWilaya!);
      if (_selectedCommune != null && _selectedCommune!.isNotEmpty) parts.add(_selectedCommune!);
      if (notes.isNotEmpty) parts.add(notes);

      final fullAddr = parts.isNotEmpty
          ? parts.join(', ')
          : '$_selectedWilaya, $_selectedCommune ($label)';

      final addressData = {
        'label': label,
        'recipientName': name,
        'phone': formattedPhone,
        'wilaya': _selectedWilaya,
        'commune': _selectedCommune,
        'additionalInfo': notes,
        'fullAddress': fullAddr,
      };

      final newId = await AddressService.addAddress(addressData);
      if (newId != null) {
        await AddressService.setDefaultAddress(newId, fullAddress: fullAddr);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('delivery_address', fullAddr);
        await prefs.setString('delivery_address_label', label);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adresse ajoutée avec succès'),
            backgroundColor: AppTheme.successColor,
          ),
        );
        widget.onAddressAdded?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    String? errorText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    final hasError = errorText != null && errorText.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: hasError ? const Color(0xFFFFF2F2) : const Color(0xFFF5F7FA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasError ? AppTheme.errorColor : Colors.transparent,
              width: hasError ? 1.5 : 1.0,
            ),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 13, color: AppTheme.errorColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    errorText,
                    style: const TextStyle(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPhoneField() {
    final hasError = _phoneError != null && _phoneError!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: hasError ? const Color(0xFFFFF2F2) : const Color(0xFFF5F7FA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasError ? AppTheme.errorColor : Colors.transparent,
              width: hasError ? 1.5 : 1.0,
            ),
          ),
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              AlgerianPhoneInputFormatter(),
            ],
            style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              prefixIcon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                margin: const EdgeInsets.only(right: 8),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
                ),
                child: const Text(
                  '+213',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              hintText: 'Ex: 0778029960 ou 778029960',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.normal),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 13, color: AppTheme.errorColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _phoneError!,
                    style: const TextStyle(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildWilayaSelector() {
    if (_loadingWilayas) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_allWilayas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Aucune wilaya disponible pour le moment.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _allWilayas.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final wilaya = _allWilayas[index];
              final isSelected = _selectedWilaya == wilaya;

              return ChoiceChip(
                label: Text(
                  wilaya,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                selected: isSelected,
                selectedColor: AppTheme.primaryColor,
                backgroundColor: const Color(0xFFF5F7FA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                  ),
                ),
                onSelected: (selected) {
                  if (selected) {
                    _onWilayaSelected(wilaya);
                  }
                },
              );
            },
          ),
        ),
        if (_wilayaError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              _wilayaError!,
              style: const TextStyle(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }

  Widget _buildCommuneSelector() {
    if (_communes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Veuillez sélectionner une wilaya.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _communes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final commune = _communes[index];
              final isSelected = _selectedCommune == commune;

              return ChoiceChip(
                label: Text(
                  commune,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                selected: isSelected,
                selectedColor: AppTheme.primaryColor,
                backgroundColor: const Color(0xFFF5F7FA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                  ),
                ),
                onSelected: (selected) {
                  setState(() {
                    _selectedCommune = selected ? commune : null;
                    if (selected) _communeError = null;
                  });
                },
              );
            },
          ),
        ),
        if (_communeError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              _communeError!,
              style: const TextStyle(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) => Transform.translate(
        offset: Offset(_shakeAnimation.value, 0),
        child: child,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title Row: Green Pin Icon + Nouvelle adresse
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Nouvelle adresse',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Input 1: Label
          _buildTextField(
            controller: _labelController,
            hintText: 'Label (ex: Maison, Bureau)',
            errorText: _labelError,
          ),
          const SizedBox(height: 12),

          // Input 2: Destinataire
          _buildTextField(
            controller: _nameController,
            hintText: 'Destinataire',
            errorText: _nameError,
          ),
          const SizedBox(height: 12),

          // Input 3: Phone Number with Fixed +213
          _buildPhoneField(),
          const SizedBox(height: 16),

          // Section: Wilaya *
          Row(
            children: const [
              Text(
                'Wilaya ',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                '*',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.errorColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildWilayaSelector(),
          const SizedBox(height: 16),

          // Section: Commune
          if (_selectedWilaya != null && _selectedWilaya!.isNotEmpty) ...[
            Row(
              children: const [
                Text(
                  'Commune ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '*',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.errorColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildCommuneSelector(),
            const SizedBox(height: 16),
          ],

          // GPS Action Button
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: _fillAddressFromGps,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map, size: 16, color: AppTheme.primaryColor),
                      SizedBox(width: 6),
                      Text(
                        '📍 Choisir sur la carte (GPS)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Input 4: Message facultatif (étage, adresse exacte, etc..)
          _buildTextField(
            controller: _notesController,
            hintText: 'Message facultatif (étage, adresse exacte, etc..)',
            maxLines: 3,
          ),
          const SizedBox(height: 20),

          // Submit Button: + Ajouter l'adresse
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submitAddress,
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.add, size: 20),
              label: Text(
                _submitting ? 'Enregistrement...' : 'Ajouter l\'adresse',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AlgerianPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;
    if (text.isEmpty) return newValue;

    text = text.replaceAll(RegExp(r'\D'), '');
    int maxLen = text.startsWith('0') ? 10 : 9;

    if (text.length > maxLen) {
      text = text.substring(0, maxLen);
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
