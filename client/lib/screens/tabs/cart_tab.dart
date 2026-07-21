import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shimmer/shimmer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/cart_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatting.dart';
import '../../utils/pricing_utils.dart';
import '../product_detail_screen.dart';
import '../../models/product_models.dart';

import '../../services/address_service.dart';
import '../../services/city_service.dart';
import '../../services/wilaya_geo_service.dart';
import '../addresses_management_screen.dart';
import '../receivers_management_screen.dart';
import '../../services/receiver_service.dart';
import '../../services/realtime_database_service.dart';

import '../../widgets/pill_page_header.dart';
import '../payment_config_page.dart';
import '../paypal_checkout_screen.dart';
import '../../services/server_wakeup_service.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/payment_service.dart';
import '../../services/order_service.dart';
import '../home_page.dart';
import '../checkout_address_screen.dart';
import '../stripe_checkout_screen.dart';

class ParsedDeliveryContext {
  final String rawAddress;
  final String simplifiedAddress;
  final List<String> segments;
  final String? wilayaName;
  final String? communeName;
  final double? latitude;
  final double? longitude;

  const ParsedDeliveryContext({
    required this.rawAddress,
    required this.simplifiedAddress,
    required this.segments,
    this.wilayaName,
    this.communeName,
    this.latitude,
    this.longitude,
  });
}

class DeliveryFeeResult {
  final double fee;
  final bool isAllowed;
  final String? wilayaCode;
  final String? wilayaName;
  final String? communeName;

  const DeliveryFeeResult({
    required this.fee,
    required this.isAllowed,
    this.wilayaCode,
    this.wilayaName,
    this.communeName,
  });
}

class CartTab extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const CartTab({super.key, this.onBackToHome});

  @override
  State<CartTab> createState() => _CartTabState();
}

class _CartTabState extends State<CartTab> {
  static const double _expressDeliveryTotalCost = 25.0;
  double _bejaiaFee = 3.49;
  double _otherWilayaFee = 8.99;
  double _bejaiaElectroFee = 14.99;
  double _otherWilayaElectroFee = 24.99;

  List<String> _allowedWilayaCodes = ['06', '15', '18', '19', '34'];
  static const Map<String, String> _wilayaDisplayNames = {
    '06': 'Béjaïa',
    '15': 'Tizi Ouzou',
    '18': 'Jijel',
    '19': 'Sétif',
    '34': 'Bordj Bou Arreridj',
  };

  List<CartItem> _cartItems = [];
  bool _loading = true;

  // Delivery and payment options
  Map<String, dynamic>? _selectedAddress;
  double _deliveryFee = 0.0;
  bool _isBejaia = false;
  bool _expressDelivery = false;
  double _tip = 0.0;
  String _tipMode = 'none'; // 'none', '1', '2', '5', '10', 'custom'
  final TextEditingController _customTipController = TextEditingController();
  bool _showTipOptions = false;
  bool _deliveryAvailable = true;
  String? _resolvedWilayaName;
  String? _stripePublishableKey;
  String? _stripeSecretKey;
  String? _googlePayMerchantId;
  bool _isGooglePaySupported = false;
  bool _isPayPalConfigured = false;
  String? _paypalEmail;
  String? _paypalMerchantId;
  String _unavailabilityPolicy = 'replacement'; // 'refund' or 'replacement'
  bool _acceptedDeliveryTime = false;
  bool _ordersEnabled = true;
  List<Category> _categories = [];

  String? _resolvedCommuneName;

  StreamSubscription<List<CartItem>>? _cartSubscription;
  StreamSubscription<Map<String, dynamic>?>? _defaultAddressSubscription;
  StreamSubscription<Map<String, dynamic>>? _pricesSubscription;
  final FocusNode _customTipFocusNode = FocusNode();
  String? _receiverName;
  String? _receiverPhone;

  ParsedDeliveryContext _parseAddress(
    Map<String, dynamic> sourceAddress,
    String fullAddress,
    String? wilayaField,
    String? communeField,
  ) {
    final segments = fullAddress
        .split(',')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();

    final simplifiedAddress = _simplify(fullAddress);

    String? wilayaName = _cleanAddressPart(wilayaField);
    String? communeName = _cleanAddressPart(communeField);

    final latitude = _parseCoordinate(sourceAddress['latitude']);
    final longitude = _parseCoordinate(sourceAddress['longitude']);

    if (latitude != null && longitude != null) {
      final geoMatch = WilayaGeoService.findByCoordinates(latitude, longitude);
      wilayaName ??= geoMatch?.name;
    }

    if (wilayaName == null || wilayaName.isEmpty) {
      if (segments.isNotEmpty) {
        wilayaName = segments.last;
      }
    }

    if ((communeName == null || communeName.isEmpty) && segments.length >= 2) {
      communeName = segments[segments.length - 2];
    }

    if (CityService.isLoaded() && wilayaName != null && wilayaName.isNotEmpty) {
      final normalizedWilaya = _normalizeWilayaName(wilayaName);
      if (normalizedWilaya != null) {
        wilayaName = normalizedWilaya;
      }

      if (communeName != null && communeName.isNotEmpty) {
        final normalizedCommune = _normalizeCommuneName(
          wilayaName,
          communeName,
        );
        if (normalizedCommune != null) {
          communeName = normalizedCommune;
        }
      }
    }

    return ParsedDeliveryContext(
      rawAddress: fullAddress,
      simplifiedAddress: simplifiedAddress,
      segments: segments,
      wilayaName: wilayaName,
      communeName: communeName,
      latitude: latitude,
      longitude: longitude,
    );
  }

  bool _hasElectroMenagerInCart() {
    for (final item in _cartItems) {
      final categoryId = item.categoryId ?? '';
      final categoryName = item.categoryName ?? '';
      final productName = item.productName.toLowerCase();

      final catNameLower = categoryName.toLowerCase();
      if (catNameLower.contains('électroménager') || catNameLower.contains('electromenager')) {
        return true;
      }

      if (categoryId.isNotEmpty) {
        final cat = _categories.firstWhere(
          (c) => c.id == categoryId || c.subCategoryIds.contains(categoryId),
          orElse: () => Category(id: '', name: '', description: '', iconName: '', color: '', subCategoryIds: [], createdAt: DateTime.now()),
        );
        final nameLower = cat.name.toLowerCase();
        final idLower = cat.id.toLowerCase();
        if (nameLower.contains('électroménager') ||
            nameLower.contains('electromenager') ||
            idLower.contains('électroménager') ||
            idLower.contains('electromenager')) {
          return true;
        }
      }

      if (productName.contains('climatiseur') ||
          productName.contains('refrigerateur') ||
          productName.contains('réfrigérateur') ||
          productName.contains('frigo') ||
          productName.contains('machine à laver') ||
          productName.contains('machine a laver') ||
          productName.contains('lave-linge') ||
          productName.contains('téléviseur') ||
          productName.contains('televiseur') ||
          productName.contains('cuisinière') ||
          productName.contains('cuisiniere') ||
          productName.contains('micro-ondes') ||
          productName.contains('micro-onde') ||
          productName.contains('congélateur')) {
        return true;
      }
    }
    return false;
  }

  bool _hasStandardItemsInCart() {
    for (final item in _cartItems) {
      final categoryId = item.categoryId ?? '';
      final categoryName = item.categoryName ?? '';
      final productName = item.productName.toLowerCase();

      bool isElectro = false;

      final catNameLower = categoryName.toLowerCase();
      if (catNameLower.contains('électroménager') || catNameLower.contains('electromenager')) {
        isElectro = true;
      }

      if (!isElectro && categoryId.isNotEmpty) {
        final cat = _categories.firstWhere(
          (c) => c.id == categoryId || c.subCategoryIds.contains(categoryId),
          orElse: () => Category(id: '', name: '', description: '', iconName: '', color: '', subCategoryIds: [], createdAt: DateTime.now()),
        );
        final nameLower = cat.name.toLowerCase();
        final idLower = cat.id.toLowerCase();
        if (nameLower.contains('électroménager') ||
            nameLower.contains('electromenager') ||
            idLower.contains('électroménager') ||
            idLower.contains('electromenager')) {
          isElectro = true;
        }
      }

      if (!isElectro &&
          (productName.contains('climatiseur') ||
           productName.contains('refrigerateur') ||
           productName.contains('réfrigérateur') ||
           productName.contains('frigo') ||
           productName.contains('machine à laver') ||
           productName.contains('machine a laver') ||
           productName.contains('téléviseur') ||
           productName.contains('televiseur') ||
           productName.contains('cuisinière') ||
           productName.contains('cuisiniere') ||
           productName.contains('micro-ondes') ||
           productName.contains('congélateur'))) {
        isElectro = true;
      }

      if (!isElectro) {
        return true;
      }
    }
    return false;
  }

  DeliveryFeeResult _resolveDeliveryFee(ParsedDeliveryContext context) {
    final wilayaCode = _resolveWilayaCode(
      context.wilayaName,
      context.simplifiedAddress,
      context,
    );

    if (wilayaCode == null || !_allowedWilayaCodes.contains(wilayaCode)) {
      return DeliveryFeeResult(
        fee: 0.0,
        isAllowed: false,
        wilayaCode: wilayaCode,
        wilayaName: context.wilayaName,
        communeName: context.communeName,
      );
    }

    double fee;
    final hasElectro = _hasElectroMenagerInCart();
    final hasStandard = _hasStandardItemsInCart();

    if (wilayaCode == '06') {
      if (hasElectro && hasStandard) {
        fee = _bejaiaFee + _bejaiaElectroFee;
      } else if (hasElectro) {
        fee = _bejaiaElectroFee;
      } else {
        fee = _bejaiaFee;
      }
    } else {
      if (hasElectro && hasStandard) {
        fee = _otherWilayaFee + _otherWilayaElectroFee;
      } else if (hasElectro) {
        fee = _otherWilayaElectroFee;
      } else {
        fee = _otherWilayaFee;
      }
    }

    final displayWilaya = _wilayaDisplayNames[wilayaCode] ?? context.wilayaName;

    return DeliveryFeeResult(
      fee: fee,
      isAllowed: true,
      wilayaCode: wilayaCode,
      wilayaName: displayWilaya ?? context.wilayaName,
      communeName: context.communeName,
    );
  }

  String? _cleanAddressPart(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _simplify(String input) {
    var simplified = input.toLowerCase();
    const replacements = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'ã': 'a',
      'å': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ò': 'o',
      'ó': 'o',
      'õ': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ú': 'u',
      'œ': 'oe',
      'ÿ': 'y',
      'ý': 'y',
    };

    replacements.forEach((key, value) {
      simplified = simplified.replaceAll(key, value);
    });

    simplified = simplified.replaceAll(RegExp(r"[^a-z0-9\s,]"), ' ');
    simplified = simplified.replaceAll(RegExp(r'\s+'), ' ').trim();
    return simplified;
  }

  String? _normalizeWilayaName(String wilayaName) {
    final code = _resolveWilayaCode(wilayaName, _simplify(wilayaName), null);
    if (code == null) {
      return wilayaName;
    }
    return _wilayaDisplayNames[code] ?? wilayaName;
  }

  String? _normalizeCommuneName(String? wilayaName, String communeName) {
    if (wilayaName == null || !CityService.isLoaded()) {
      return communeName;
    }

    final wilayaCode = _resolveWilayaCode(
      wilayaName,
      _simplify(wilayaName),
      null,
    );

    final lookupWilaya = wilayaCode != null
        ? (_wilayaDisplayNames[wilayaCode] ?? wilayaName)
        : wilayaName;

    final communes = CityService.getCommunesForWilaya(lookupWilaya);
    if (communes.isEmpty) {
      return communeName;
    }

    final simplifiedTarget = _simplify(communeName);
    for (final candidate in communes) {
      final simplifiedCandidate = _simplify(candidate);
      if (simplifiedCandidate == simplifiedTarget) {
        final normalized = CityService.getCommuneName(lookupWilaya, candidate);
        return normalized ?? candidate;
      }
    }

    return communeName;
  }

  String? _resolveWilayaCode(
    String? wilayaName,
    String simplifiedAddress,
    ParsedDeliveryContext? context,
  ) {
    final latitude = context?.latitude;
    final longitude = context?.longitude;
    if (latitude != null && longitude != null) {
      final geoMatch = WilayaGeoService.findByCoordinates(latitude, longitude);
      if (geoMatch != null) {
        return geoMatch.code;
      }
    }

    if (wilayaName != null && wilayaName.isNotEmpty && CityService.isLoaded()) {
      final code = CityService.getWilayaCode(wilayaName);
      if (code != null) {
        return code.toString().padLeft(2, '0');
      }
    }

    if (simplifiedAddress.isNotEmpty) {
      final segments = simplifiedAddress.split(',');
      for (final segment in segments.reversed) {
        final value = segment.trim();
        if (value.length >= 2 && int.tryParse(value.substring(0, 2)) != null) {
          return value.substring(0, 2);
        }
      }
    }

    return null;
  }

  double? _parseCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  Future<void> _ensureCityDataLoaded() async {
    if (CityService.isLoaded()) return;
    try {
      final jsonString = await rootBundle.loadString(
        'lib/data/algeria_cities.json',
      );
      await CityService.loadCities(jsonString);
    } catch (e) {
      debugPrint('Failed to load city data: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCart();
    _loadDeliveryAddress();
    _loadReceiverFromPrefs();
    _listenToDefaultAddress();
    // Listen for cart changes
    _cartSubscription = CartService.cartStream().listen((items) {
      if (mounted) {
        setState(() {
          _cartItems = items;
          _refreshExpressSelection();
          if (_selectedAddress != null) {
            _updateDeliveryContext(_selectedAddress!);
          }
        });
      }
    });

    // Listen for delivery prices changes
    _pricesSubscription = RealtimeDatabaseService.deliveryPricesStream().listen(
      (prices) {
        if (mounted) {
          setState(() {
            _bejaiaFee = ((prices['bejaiaCityFee'] ?? 3.49) as num).toDouble();
            _otherWilayaFee = ((prices['otherWilayaFee'] ?? 8.99) as num).toDouble();
            _bejaiaElectroFee = ((prices['bejaiaElectroFee'] ?? 14.99) as num).toDouble();
            _otherWilayaElectroFee = ((prices['otherWilayaElectroFee'] ?? 24.99) as num).toDouble();
            // Re-calculate fee if address is already selected
            if (_selectedAddress != null) {
              _updateDeliveryContext(_selectedAddress!);
            }
          });
        }
      },
    );

    // Proactively wake up server when user opens cart
    ServerWakeupService.wakeupServer();
    _loadAllowedWilayas();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await RealtimeDatabaseService.getCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
        });
      }
    } catch (e) {
      debugPrint('Error loading categories in cart: $e');
    }
  }

  Future<void> _loadAllowedWilayas() async {
    try {
      final DatabaseReference ref =
          FirebaseDatabase.instance.ref().child('settings');
      final snapshot = await ref.get();
      if (snapshot.exists && snapshot.value is Map) {
        final data = snapshot.value as Map;
        
        // Load allowed wilayas
        if (data['allowedWilayas'] != null) {
          if (data['allowedWilayas'] is List) {
            final list = data['allowedWilayas'] as List;
            setState(() {
              _allowedWilayaCodes = list.whereType<String>().toList();
            });
          } else if (data['allowedWilayas'] is Map) {
            final map = data['allowedWilayas'] as Map;
            setState(() {
              _allowedWilayaCodes = map.values.whereType<String>().toList();
            });
          }
        }
        
        // Load orders enabled status
        if (data['ordersEnabled'] != null) {
           setState(() {
              _ordersEnabled = data['ordersEnabled'] == true;
           });
        }
      }
      CityService.setAllowedWilayas(_allowedWilayaCodes);
      if (_selectedAddress != null) {
        _updateDeliveryContext(_selectedAddress!);
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  @override
  void dispose() {
    _cartSubscription?.cancel();
    _defaultAddressSubscription?.cancel();
    _pricesSubscription?.cancel();
    _customTipController.dispose();
    _customTipFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDeliveryAddress() async {
    try {
      await _ensureCityDataLoaded();
      final addresses = await AddressService.getAddresses();
      final defaultAddr = await AddressService.getDefaultAddress();

      setState(() {
        _applySelectedAddress(
          defaultAddr ?? (addresses.isNotEmpty ? addresses.first : null),
        );
      });
    } catch (e) {
      debugPrint('Error loading address: $e');
    }
  }

  void _listenToDefaultAddress() {
    _defaultAddressSubscription?.cancel();
    _defaultAddressSubscription = AddressService.defaultAddressStream().listen((
      address,
    ) {
      if (!mounted) return;
      if (address == null) {
        _loadDeliveryAddress();
        return;
      }

      final normalized = Map<String, dynamic>.from(address);
      setState(() {
        _applySelectedAddress(normalized);
      });
    });
  }

  Future<void> _loadReceiverFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _receiverName = prefs.getString('receiver_name');
      _receiverPhone = prefs.getString('receiver_phone');
    });
  }

  Future<void> _saveReceiverToPrefs(String? name, String? phone) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) {
      await prefs.setString('receiver_name', name);
    }
    if (phone != null) {
      await prefs.setString('receiver_phone', phone);
    }
  }

  Future<void> _showCheckoutAddressScreen() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.grey),
                  label: const Text('Fermer', style: TextStyle(color: Colors.grey)),
                ),
              ),
              AddressesManagementScreen(
                onAddressAdded: () {
                  Navigator.pop(context);
                  _loadDeliveryAddress();
                },
              ),
            ],
          ),
        ),
      ),
    );
    await _loadDeliveryAddress();
  }

  void _applySelectedAddress(Map<String, dynamic>? address) {
    _selectedAddress = address;
    if (_selectedAddress != null) {
      _updateDeliveryContext(_selectedAddress!);
    }
  }

  Future<void> _updateDeliveryContext(Map<String, dynamic> address) async {
    await _ensureCityDataLoaded();
    await WilayaGeoService.ensureLoaded();

    final fullAddress = address['fullAddress']?.toString() ?? '';
    final wilayaFromAddress = address['wilaya']?.toString();
    final communeFromAddress = address['commune']?.toString();

    final parsed = _parseAddress(
      address,
      fullAddress,
      wilayaFromAddress,
      communeFromAddress,
    );
    final feeInfo = _resolveDeliveryFee(parsed);

    if (!mounted) return;

    setState(() {
      _resolvedWilayaName = feeInfo.wilayaName;

      _resolvedCommuneName = feeInfo.communeName;
      _deliveryFee = feeInfo.fee;
      _deliveryAvailable = feeInfo.isAllowed;
      if (!_deliveryAvailable && feeInfo.wilayaCode != null) {
        _deliveryAvailable = _allowedWilayaCodes.contains(feeInfo.wilayaCode);
      }
      _isBejaia = feeInfo.wilayaCode == '06';

      if (!_deliveryAvailable) {
        _expressDelivery = false;
      }

      _refreshExpressSelection();
    });
  }

  Future<void> _loadCart() async {
    try {
      final keys = await PaymentService.getAdminPublicPaymentInfo();
      _stripePublishableKey = keys['stripePublishableKey'];
      _stripeSecretKey = keys['stripeSecretKey'];
      _googlePayMerchantId = keys['googlePayMerchantId'];
      
      final paypalEmail = keys['paypalEmail'];
      final paypalMerchantId = keys['paypalMerchantId'];
      
      setState(() {
        _paypalEmail = paypalEmail;
        _paypalMerchantId = paypalMerchantId;
        _isPayPalConfigured = (paypalEmail != null && paypalEmail.isNotEmpty) ||
                             (paypalMerchantId != null && paypalMerchantId.isNotEmpty);
      });

      if (_stripePublishableKey != null && _stripePublishableKey!.isNotEmpty) {
        Stripe.publishableKey = _stripePublishableKey!;
        await Stripe.instance.applySettings();
        final isGPaySupported = await Stripe.instance.isPlatformPaySupported(
          googlePay: IsGooglePaySupportedParams(),
        );
        setState(() {
          _isGooglePaySupported = isGPaySupported;
        });
      }
    } catch (e) {
      debugPrint('Error fetching payment keys: $e');
    }
    setState(() => _loading = true);
    await CartService.refreshCart();
    final items = await CartService.getCartItems();
    setState(() {
      _cartItems = items;
      _loading = false;
      _refreshExpressSelection();
    });
  }

  Future<void> _updateQuantity(String itemId, double newQuantity) async {
    await CartService.updateQuantity(itemId, newQuantity);
    _loadCart();
  }

  double _getIncrementStep(String unit) {
    return PricingUtils.getQuantityStep(unit);
  }

  String _formatQuantity(double qty, String unit) {
    if (unit.toLowerCase().contains('kg') || unit.toLowerCase().contains('l')) {
      return qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(1);
    }
    return qty.toInt().toString();
  }

  Future<void> _removeItem(String itemId) async {
    final previousItems = List<CartItem>.from(_cartItems);

    setState(() {
      _cartItems = _cartItems.where((item) => item.id != itemId).toList();
      _refreshExpressSelection();
      if (_selectedAddress != null) {
        _updateDeliveryContext(_selectedAddress!);
      }
    });

    try {
      await CartService.removeFromCart(itemId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produit retiré du panier'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _cartItems = previousItems;
        if (_selectedAddress != null) {
          _updateDeliveryContext(_selectedAddress!);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de la suppression: $e"),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _showOrderConfirmationDialog() async {
    setState(() => _loading = true);
    await _loadCart();
    await _loadDeliveryAddress();
    setState(() => _loading = false);

    if (_cartItems.isEmpty || _selectedAddress == null || !_deliveryAvailable) {
      return;
    }

    final cartTotal = _getCartTotal();
    final expressFee = _expressDelivery && _isExpressAvailable(cartTotal)
        ? (_expressDeliveryTotalCost - _deliveryFee)
        : 0.0;
    final finalTotal = _getFinalTotal();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Colors.white, Color(0xFFF7F8FC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.receipt_long_rounded,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Confirmer la commande',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Vérifiez le récapitulatif avant de valider.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Produits',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        ..._cartItems.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.productName} x ${_formatQuantity(item.quantity, item.unit)}',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatPrice(item.totalPrice),
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Adresse de livraison',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatConfirmationAddressLine(),
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Destinataire',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (_receiverName?.isNotEmpty == true ||
                                  _receiverPhone?.isNotEmpty == true)
                              ? '${_receiverName ?? ''}${(_receiverName?.isNotEmpty == true && _receiverPhone?.isNotEmpty == true) ? ' • ' : ''}${_receiverPhone ?? ''}'
                              : 'Non spécifié',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Récapitulatif',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Sous-total',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              _formatPrice(cartTotal),
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Livraison',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              _formatPrice(_deliveryFee),
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (_getTotalPreparationFee() > 0) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Frais de préparation:',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          ..._buildPreparationFeesWidgets(fontSize: 12, forModal: true),
                        ],
                        if (expressFee > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Livraison Express (48h)',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Text(
                                _formatPrice(expressFee),
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_tip > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Pourboire',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Text(
                                _formatPrice(_tip),
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Total à payer',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              _formatPrice(finalTotal),
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: AppTheme.textSecondary.withValues(
                                alpha: 0.4,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Annuler'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await _createOrder();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Confirmer',
                            style: TextStyle(fontWeight: FontWeight.w600),
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
      },
    );
  }

  String _formatConfirmationAddressLine() {
    if (_selectedAddress == null) return '';

    final label = (_selectedAddress!['label'] ?? '').toString().trim();

    // Only show the name the user chose for this address.
    if (label.isNotEmpty) return label;

    // Fallback: very short representation if label is missing.
    final fallback = _selectedAddress!['fullAddress']?.toString().trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;

    return '';
  }

  double _getCartTotal() {
    return _cartItems.fold<double>(0, (sum, item) => sum + item.totalPrice);
  }

  bool _isExpressAvailable(double cartTotal) {
    // Express allowed only if delivery is available, not in Béjaïa,
    // and (cart + tip) is >= 25€
    final baseTotal = cartTotal + _tip;
    return _deliveryAvailable && !_isBejaia && baseTotal >= 25.0;
  }

  void _refreshExpressSelection() {
    final cartTotal = _getCartTotal();
    final canUseExpress = _isExpressAvailable(cartTotal);
    if (!canUseExpress && _expressDelivery) {
      _expressDelivery = false;
    }
  }

  Category? _findCategoryForItem(CartItem item) {
    if (_categories.isEmpty) return null;

    final itemCatId = item.categoryId?.trim() ?? '';
    final itemCatName = item.categoryName?.trim().toLowerCase() ?? '';
    final pName = item.productName.toLowerCase();

    // 1. Direct ID or SubCategory ID match
    if (itemCatId.isNotEmpty) {
      for (var cat in _categories) {
        if (cat.id == itemCatId || cat.subCategoryIds.contains(itemCatId)) {
          return cat;
        }
      }
    }

    // 2. Direct Category Name match (exact, lowercased, or normalized)
    if (itemCatName.isNotEmpty) {
      for (var cat in _categories) {
        final cName = cat.name.trim().toLowerCase();
        if (cName == itemCatName ||
            cName.replaceAll('&', 'et') == itemCatName.replaceAll('&', 'et') ||
            cName.contains(itemCatName) ||
            itemCatName.contains(cName)) {
          return cat;
        }
      }
    }

    // 3. Robust Keyword Fallback for Smartphones, Meat, Fruits, Supérette, etc.
    for (var cat in _categories) {
      final cName = cat.name.trim().toLowerCase();
      final cId = cat.id.trim().toLowerCase();

      // Phones & Tablets (smartphones, téléphone, mobile, etc.)
      if (cName.contains('phone') ||
          cName.contains('téléphone') ||
          cName.contains('telephone') ||
          cName.contains('tablette') ||
          cName.contains('électronique') ||
          cName.contains('electronique') ||
          cId.contains('phone')) {
        if (itemCatName.contains('phone') ||
            itemCatName.contains('tablette') ||
            pName.contains('phone') ||
            pName.contains('iphone') ||
            pName.contains('galaxy') ||
            pName.contains('redmi') ||
            pName.contains('xiaomi') ||
            pName.contains('samsung') ||
            pName.contains('oppo') ||
            pName.contains('realme') ||
            pName.contains('huawei') ||
            pName.contains('tablette') ||
            pName.contains('ipad')) {
          return cat;
        }
      }

      // Meat / Viande
      if (cName.contains('viande')) {
        if (itemCatName.contains('viande') ||
            pName.contains('boeuf') ||
            pName.contains('bœuf') ||
            pName.contains('poulet') ||
            pName.contains('viande') ||
            pName.contains('escalope') ||
            pName.contains('kefta')) {
          return cat;
        }
      }

      // Fruits & Vegetables
      if (cName.contains('fruit') || cName.contains('légume') || cName.contains('legume')) {
        if (itemCatName.contains('fruit') ||
            itemCatName.contains('légume') ||
            pName.contains('nectarine') ||
            pName.contains('pomme') ||
            pName.contains('banane') ||
            pName.contains('orange') ||
            pName.contains('fraise') ||
            pName.contains('tomate') ||
            pName.contains('pomme de terre')) {
          return cat;
        }
      }

      // Supérette / Grocery
      if (cName.contains('superette') || cName.contains('supérette') || cName.contains('market')) {
        if (itemCatName.contains('superette') ||
            itemCatName.contains('market') ||
            pName.contains('coca') ||
            pName.contains('jus') ||
            pName.contains('lait') ||
            pName.contains('sucre') ||
            pName.contains('piment') ||
            pName.contains('eau') ||
            pName.contains('huile')) {
          return cat;
        }
      }
    }

    return null;
  }

  double _getCategoryPrepFee(Category cat) {
    return cat.preparationFee;
  }

  List<Widget> _buildPreparationFeesWidgets({double fontSize = 11, bool forModal = false}) {
    List<Widget> feeWidgets = [];
    Map<String, ({String name, double fee})> categoriesWithFeesInCart = {};

    for (var item in _cartItems) {
      final category = _findCategoryForItem(item);
      if (category != null) {
        final fee = _getCategoryPrepFee(category);
        if (fee > 0) {
          categoriesWithFeesInCart[category.id] = (name: category.name, fee: fee);
        }
      }
    }

    for (var category in categoriesWithFeesInCart.values) {
      final catName = category.name.toLowerCase();
      feeWidgets.add(
        Padding(
          padding: EdgeInsets.symmetric(horizontal: forModal ? 0 : 2, vertical: 1),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Frais de préparation ($catName):',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: fontSize,
                  ),
                ),
              ),
              Text(
                '+${_formatPrice(category.fee)}',
                style: TextStyle(
                  color: forModal ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontSize: fontSize,
                  fontWeight: forModal ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
      if (forModal) feeWidgets.add(const SizedBox(height: 2));
    }
    return feeWidgets;
  }

  double _getTotalPreparationFee() {
    double total = 0.0;
    Map<String, double> categoriesWithFeesInCart = {};
    for (var item in _cartItems) {
      final category = _findCategoryForItem(item);
      if (category != null) {
        final fee = _getCategoryPrepFee(category);
        if (fee > 0) {
          categoriesWithFeesInCart[category.id] = fee;
        }
      }
    }
    for (var fee in categoriesWithFeesInCart.values) {
      total += fee;
    }
    return total;
  }

  double _getFinalTotal() {
    final cartTotal = _getCartTotal();
    final prepFee = _getTotalPreparationFee();
    final expressFee = _expressDelivery && _isExpressAvailable(cartTotal)
        ? (_expressDeliveryTotalCost - _deliveryFee)
        : 0.0;
    return cartTotal + prepFee + _deliveryFee + expressFee + _tip;
  }

  void _setTip(String mode) {
    setState(() {
      final isSameSelection = _tipMode == mode && mode != 'none';

      if (isSameSelection) {
        _tipMode = 'none';
        _tip = 0.0;
        _showTipOptions = false;
        _customTipController.clear();
      } else {
        _tipMode = mode;

        if (mode == 'none') {
          _tip = 0.0;
          _customTipController.clear();
          _showTipOptions = false;
        } else if (mode == '1') {
          _tip = 1.0;
          _customTipController.clear();
          _showTipOptions = true;
        } else if (mode == '2') {
          _tip = 2.0;
          _customTipController.clear();
          _showTipOptions = true;
        } else if (mode == '5') {
          _tip = 5.0;
          _customTipController.clear();
          _showTipOptions = true;
        } else if (mode == '10') {
          _tip = 10.0;
          _customTipController.clear();
          _showTipOptions = true;
        } else if (mode == 'custom') {
          // Always show tip options when custom is selected
          _showTipOptions = true;
          if (_customTipController.text.isEmpty) {
            _tip = 0.0;
          }
        }

        _refreshExpressSelection();
      }
    });

    if (mode == 'custom' && _showTipOptions) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_customTipFocusNode);
      });
    } else {
      _customTipFocusNode.unfocus();
    }
  }

  void _updateCustomTip(String value) {
    if (value.isEmpty) {
      setState(() {
        _tip = 0.0;
        _refreshExpressSelection();
      });
      return;
    }
    final tipValue = double.tryParse(value) ?? 0.0;
    if (tipValue >= 0) {
      setState(() {
        _tip = tipValue;
        _refreshExpressSelection();
      });
    }
  }



  Future<void> _createOrder() async {
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Votre panier est vide'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    if (_selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner une adresse de livraison'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    if (!_deliveryAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Livraison indisponible pour cette adresse'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
      return;
    }

    // Show BottomSheet to select payment method
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Comment souhaitez-vous payer ?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              
              // Google Pay Option (GPay logo pill format matching Image 2)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF3C4043),
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(27),
                    side: const BorderSide(color: Color(0xFF3C4043), width: 1.5),
                  ),
                  elevation: 1,
                ),
                onPressed: () {
                  Navigator.pop(context); // Close BottomSheet
                  _processGooglePayNative();
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.string(
                      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.66 0 6.6 5.38 2.69 13.22l7.98 6.19C12.63 13.7 17.81 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.67 28.59c-.48-1.45-.76-2.99-.76-4.59s.28-3.14.76-4.59l-7.98-6.19C1.03 16.29 0 19.99 0 24s1.03 7.71 2.69 10.78l7.98-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.19 0-11.37-4.2-13.33-9.91l-7.98 6.19C6.6 42.62 14.66 48 24 48z"/></svg>''',
                      height: 24,
                      width: 24,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Pay',
                      style: TextStyle(
                        color: Color(0xFF3C4043),
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // PayPal Option
              if (_isPayPalConfigured) ...[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC439), // PayPal Yellow
                    foregroundColor: const Color(0xFF003087), // PayPal Dark Blue
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 1,
                  ),
                  onPressed: () {
                    Navigator.pop(context); // Close BottomSheet
                    _processPayment('paypal');
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.network(
                        'https://upload.wikimedia.org/wikipedia/commons/b/b5/PayPal.svg',
                        height: 24,
                        errorBuilder: (_, __, ___) => const Icon(Icons.payment, size: 24),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'PayPal',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              // Stripe Card Option
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10AA2E), // Primary Theme Green
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context); // Close BottomSheet
                  _processPayment('stripe');
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.credit_card, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Carte Bancaire',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _processPayment(String provider) async {
    try {
      final cartTotal = _getCartTotal();
      final expressFee = _expressDelivery && _isExpressAvailable(cartTotal)
          ? (_expressDeliveryTotalCost - _deliveryFee)
          : 0.0;
      final finalTotal = _getFinalTotal();
      final deliveryAddress =
          _selectedAddress!['fullAddress'] ?? 'Non spécifiée';
      final deliveryLabel = _selectedAddress!['label']?.toString();
      final wilaya =
          _resolvedWilayaName ?? _selectedAddress!['wilaya']?.toString() ?? '';
      final wilayaCode = _selectedAddress!['wilayaCode']?.toString() ?? '06';

      // Aggressively wake up server before checkout
      // This ensures Render server is ready and reduces payment delay
      if (mounted) {
        // Show a brief loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Préparation du paiement...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        );

        // Wake up server aggressively
        await ServerWakeupService.aggressiveWakeup();

        // Close loading dialog
        if (mounted) Navigator.of(context).pop();
      }

      if (provider == 'stripe') {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => StripeCheckoutScreen(
                cartItems: _cartItems,
                cartTotal: cartTotal,
                deliveryFee: _deliveryFee,
                expressFee: expressFee,
                tip: _tip,
                finalTotal: finalTotal,
                deliveryAddress: deliveryAddress,
                deliveryLabel: deliveryLabel,
                wilaya: wilaya,
                wilayaCode: wilayaCode,
                receiverName: _receiverName,
                receiverPhone: _receiverPhone,
                userId: FirebaseAuth.instance.currentUser?.uid,
                unavailabilityPolicy: _unavailabilityPolicy,
              ),
            ),
          );
        }
      } else if (provider == 'paypal') {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PayPalCheckoutScreen(
                cartItems: _cartItems,
                cartTotal: cartTotal,
                deliveryFee: _deliveryFee,
                expressFee: expressFee,
                tip: _tip,
                finalTotal: finalTotal,
                deliveryAddress: deliveryAddress,
                deliveryLabel: deliveryLabel,
                wilaya: wilaya,
                wilayaCode: wilayaCode,
                receiverName: _receiverName,
                receiverPhone: _receiverPhone,
                userId: FirebaseAuth.instance.currentUser?.uid,
                unavailabilityPolicy: _unavailabilityPolicy,
                paypalEmail: _paypalEmail ?? '',
                paypalMerchantId: _paypalMerchantId,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showPaymentErrorDialog(e);
      }
    }
  }

  /// Processes payment using the native Google Pay sheet (no WebView)
  Future<void> _processGooglePayNative() async {
    try {
      if (_stripePublishableKey == null || _stripePublishableKey!.isEmpty) {
        throw Exception('Stripe non configuré. Contactez le support.');
      }
      if (_stripeSecretKey == null || _stripeSecretKey!.isEmpty) {
        throw Exception('Clé Stripe manquante. Contactez le support.');
      }

      final finalTotal = _getFinalTotal();
      final amountInCents = (finalTotal * 100).round();

      if (amountInCents < 50) {
        throw Exception(
          'Le montant (${finalTotal.toStringAsFixed(2)}€) est inférieur au minimum requis (0.50€).\nVeuillez ajouter des articles.',
        );
      }

      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Ouverture de Google Pay...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // 1. Create Payment Intent directly via Stripe REST API
      final response = await http.post(
        Uri.parse('https://api.stripe.com/v1/payment_intents'),
        headers: {
          'Authorization': 'Bearer $_stripeSecretKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'amount': amountInCents.toString(),
          'currency': 'eur',
          'payment_method_types[]': 'card',
        },
      );

      if (mounted) Navigator.of(context).pop(); // Close loading

      if (response.statusCode != 200) {
        final errorData = json.decode(response.body);
        final errMsg = errorData['error']?['message'] ?? 'Erreur Stripe';
        throw Exception(errMsg);
      }

      final clientSecret = json.decode(response.body)['client_secret'] as String;

      // 2. Confirm via native Google Pay sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'LivriYes',
          googlePay: PaymentSheetGooglePay(
            merchantCountryCode: 'FR',
            currencyCode: 'EUR',
            testEnv: false,
          ),
          style: ThemeMode.light,
        ),
      );

      await Stripe.instance.presentPaymentSheet();

      // 3. Payment succeeded — save order
      final cartTotal = _getCartTotal();
      final expressFee = _expressDelivery && _isExpressAvailable(cartTotal)
          ? (_expressDeliveryTotalCost - _deliveryFee)
          : 0.0;
      final deliveryAddress = _selectedAddress!['fullAddress'] ?? 'Non spécifiée';
      final deliveryLabel = _selectedAddress!['label']?.toString();
      final wilaya = _resolvedWilayaName ?? _selectedAddress!['wilaya']?.toString() ?? '';

      final orderId = await OrderService.createOrder(
        items: _cartItems,
        cartTotal: cartTotal,
        deliveryFee: _deliveryFee,
        expressDelivery: _expressDelivery,
        expressFee: expressFee,
        tip: _tip,
        total: finalTotal,
        deliveryAddress: deliveryAddress,
        deliveryLabel: deliveryLabel,
        wilaya: wilaya,
        paymentMethod: 'Google Pay',
        paymentStatus: 'paid',
        receiverName: _receiverName,
        receiverPhone: _receiverPhone,
        unavailabilityPolicy: _unavailabilityPolicy,
      );

      await CartService.clearCart();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LivriyesHomePage(initialIndex: 2),
          ),
          (route) => false,
        );
      }
    } on StripeException catch (e) {
      // User cancelled or card error
      if (e.error.code == FailureCode.Canceled) return;
      if (mounted) _showPaymentErrorDialog(e);
    } catch (e) {
      if (mounted) _showPaymentErrorDialog(e);
    }
  }

  void _showPaymentErrorDialog(dynamic error) {
    if (!mounted) return;

    String title = "Erreur de Paiement";
    String message = error.toString();
    bool isAmountTooSmall = false;

    // Clean up "Exception: " prefix
    if (message.startsWith('Exception: ')) {
      message = message.replaceFirst('Exception: ', '');
    }

    if (error is StripeCustomException) {
      message = error.message;
      if (error.code == 'amount_too_small') {
        title = "Montant Insuffisant";
        isAmountTooSmall = true;
      }
    } else if (error is StripeException) {
      message = error.error.localizedMessage ?? error.toString();
    } else if (message.contains('amount_too_small') || message.contains('at least €0.50')) {
      title = "Montant Insuffisant";
      final cartTotal = _getFinalTotal();
      message = "Le montant de votre panier (${cartTotal.toStringAsFixed(2)}€) est inférieur au montant minimum de 0.50€ requis par Stripe.\n\nVeuillez ajouter d'autres articles à votre panier pour finaliser la commande.";
      isAmountTooSmall = true;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                isAmountTooSmall
                    ? Icons.warning_amber_rounded
                    : Icons.error_outline_rounded,
                color: isAmountTooSmall ? Colors.amber[800] : AppTheme.errorColor,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(
                backgroundColor:
                    isAmountTooSmall ? Colors.amber[800] : AppTheme.errorColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text(
                isAmountTooSmall ? "Ajouter des articles" : "Fermer",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartTotal = _getCartTotal();
    final finalTotal = _getFinalTotal();
    final canUseExpress = _isExpressAvailable(cartTotal);
    final expressFee = _expressDelivery && canUseExpress
        ? (_expressDeliveryTotalCost - _deliveryFee)
        : 0.0;
    final hasTip = _tip > 0;
    final hasReceiver = _receiverName?.isNotEmpty == true && _receiverPhone?.isNotEmpty == true;
    final canPlaceOrder =
        _ordersEnabled && _deliveryAvailable && _selectedAddress != null && hasReceiver && _acceptedDeliveryTime && _cartItems.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
      child: SafeArea(
        child: Column(
          children: [
            PillPageHeader(title: 'Mon Panier', onBack: widget.onBackToHome),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () async {
                        await _loadCart();
                        await _loadDeliveryAddress();
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                        children: [
                          if (_cartItems.isEmpty)
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shopping_cart_outlined,
                                    size: 68,
                                    color: AppTheme.textLight,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Votre panier est vide',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Ajoutez des produits pour commencer',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            for (var i = 0; i < _cartItems.length; i++) ...[
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.98),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryColor.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  dense: true,
                                  visualDensity: const VisualDensity(
                                    horizontal: -1,
                                    vertical: -2,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  leading: GestureDetector(
                                    onTap: () async {
                                      try {
                                        final allProducts =
                                            await RealtimeDatabaseService.getAllProducts();
                                        final product = allProducts.firstWhere(
                                          (p) =>
                                              p.id == _cartItems[i].productId,
                                        );
                                        if (!mounted) return;
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                ProductDetailScreen(
                                                  product: product,
                                                ),
                                          ),
                                        );
                                        if (mounted) _loadCart();
                                      } catch (e) {
                                        debugPrint('Error loading product: $e');
                                      }
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child:
                                          _cartItems[i]
                                              .productImageUrl
                                              .isNotEmpty
                                          ? Image.network(
                                              _cartItems[i].productImageUrl,
                                              width: 50,
                                              height: 50,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                    width: 46,
                                                    height: 46,
                                                    color: AppTheme.accentColor
                                                        .withValues(alpha: 0.1),
                                                    child: const Icon(
                                                      Icons.image,
                                                      size: 30,
                                                    ),
                                                  ),
                                            )
                                          : Container(
                                              width: 46,
                                              height: 46,
                                              color: AppTheme.accentColor
                                                  .withValues(alpha: 0.08),
                                              child: const Icon(
                                                Icons.image,
                                                size: 30,
                                              ),
                                            ),
                                    ),
                                  ),
                                  title: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _cartItems[i].productName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                        ),
                                        onPressed: () =>
                                            _removeItem(_cartItems[i].id),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                        color: AppTheme.errorColor,
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (_cartItems[i].isOnPromotion) ...[
                                        Row(
                                          children: [
                                            Text(
                                              _formatPrice(
                                                _cartItems[i]
                                                    .totalOriginalPrice!,
                                              ),
                                              style: TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 10,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.successColor,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '-${_cartItems[i].discountPercentage!.toStringAsFixed(0)}%',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      Text(
                                        PricingUtils.formatPriceWithUnit(
                                          _cartItems[i].unitPrice,
                                          _cartItems[i].unit,
                                        ),
                                        style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryColor
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.remove,
                                                size: 16,
                                              ),
                                              onPressed:
                                                  _cartItems[i].quantity >
                                                      _getIncrementStep(
                                                        _cartItems[i].unit,
                                                      )
                                                  ? () {
                                                      final step =
                                                          _getIncrementStep(
                                                            _cartItems[i].unit,
                                                          );
                                                      _updateQuantity(
                                                        _cartItems[i].id,
                                                        (_cartItems[i]
                                                                    .quantity -
                                                                step)
                                                            .clamp(
                                                              step,
                                                              double.infinity,
                                                            ),
                                                      );
                                                    }
                                                  : null,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            child: Text(
                                              (_cartItems[i].unit
                                                              .toLowerCase()
                                                              .contains('kg') ||
                                                          (_cartItems[i].unit
                                                                  .toLowerCase()
                                                                  .contains(
                                                                    'l',
                                                                  ) &&
                                                              !_cartItems[i]
                                                                  .unit
                                                                  .toLowerCase()
                                                                  .contains(
                                                                    'ml',
                                                                  ))) &&
                                                      !RegExp(r'^\d').hasMatch(
                                                        _cartItems[i].unit,
                                                      )
                                                  ? '${_formatQuantity(_cartItems[i].quantity, _cartItems[i].unit)} ${_cartItems[i].unit}'
                                                  : '${_formatQuantity(_cartItems[i].quantity, _cartItems[i].unit)} x ${_cartItems[i].unit}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryColor
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.add,
                                                size: 16,
                                              ),
                                              onPressed: () {
                                                final step = _getIncrementStep(
                                                  _cartItems[i].unit,
                                                );
                                                _updateQuantity(
                                                  _cartItems[i].id,
                                                  _cartItems[i].quantity + step,
                                                );
                                              },
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 30,
                                                minHeight: 30,
                                              ),
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '= ${PricingUtils.formatTotalWeight(_cartItems[i].quantity, _cartItems[i].unit)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.successColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _formatPrice(_cartItems[i].totalPrice),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                      ),
                                      Text(
                                        '(${_formatPrice(_cartItems[i].unitPrice)} / ${_cartItems[i].unit})',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (i != _cartItems.length - 1)
                                const SizedBox(height: 12),
                            ],
                            const SizedBox(height: 16),
                          ],
                          if (!_deliveryAvailable) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.errorColor.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppTheme.errorColor.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: AppTheme.errorColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Livraison non disponible pour ${_resolvedCommuneName ?? 'cette commune'} (${_resolvedWilayaName ?? 'wilaya'}). \nVeuillez sélectionner une adresse dans nos zones desservies (Béjaïa, Tizi Ouzou, Jijel, Sétif ou Bordj Bou Arreridj).',
                                      style: TextStyle(
                                        color: AppTheme.errorColor,
                                        fontSize: 12,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_deliveryAvailable) ...[
                            Row(
                              children: [
                                // Compact Express Delivery (only if outside Béjaïa and total >= 25)
                                if (!_isBejaia && canUseExpress) ...[
                                  Expanded(
                                    flex: 3,
                                    child: InkWell(
                                      onTap: canUseExpress
                                          ? () => setState(
                                              () => _expressDelivery =
                                                  !_expressDelivery,
                                            )
                                          : null,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: _expressDelivery
                                              ? const LinearGradient(
                                                  colors: [
                                                    AppTheme.secondaryColor,
                                                    AppTheme.primaryColor,
                                                  ],
                                                )
                                              : null,
                                          color: _expressDelivery
                                              ? null
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: _expressDelivery
                                                ? Colors.transparent
                                                : AppTheme.primaryColor
                                                      .withValues(alpha: 0.25),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppTheme.primaryColor
                                                  .withValues(
                                                    alpha: _expressDelivery
                                                        ? 0.25
                                                        : 0.06,
                                                  ),
                                              blurRadius: _expressDelivery
                                                  ? 16
                                                  : 8,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.speed,
                                              color: _expressDelivery
                                                  ? Colors.white
                                                  : AppTheme.primaryColor,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Livraison Express',
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: _expressDelivery
                                                      ? Colors.white
                                                      : AppTheme.primaryColor,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _formatPrice(
                                                _expressDeliveryTotalCost,
                                              ),
                                              style: TextStyle(
                                                color: _expressDelivery
                                                    ? Colors.white
                                                    : AppTheme.primaryColor,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                // Compact Tip Module
                                Expanded(
                                  flex: 2,
                                  child: GestureDetector(
                                    onTap: () => _setTip('custom'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: _tipMode == 'custom'
                                            ? const LinearGradient(
                                                colors: [
                                                  Color(0xFF10AA2E),
                                                  Color(0xFF67DF47),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              )
                                            : null,
                                        color: _tipMode == 'custom'
                                            ? null
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _tipMode == 'custom'
                                              ? Colors.transparent
                                              : AppTheme.primaryColor
                                                    .withValues(alpha: 0.25),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.primaryColor
                                                .withValues(
                                                  alpha: _tipMode == 'custom'
                                                      ? 0.25
                                                      : 0.06,
                                                ),
                                            blurRadius: _tipMode == 'custom'
                                                ? 16
                                                : 8,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.money,
                                            color: _tipMode == 'custom'
                                                ? Colors.white
                                                : AppTheme.primaryColor,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Pourboire',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: _tipMode == 'custom'
                                                    ? Colors.white
                                                    : AppTheme.primaryColor,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            _formatPrice(_tip),
                                            style: TextStyle(
                                              color: _tipMode == 'custom'
                                                  ? Colors.white
                                                  : AppTheme.primaryColor,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_tipMode == 'custom' && _showTipOptions) ...[
                              const SizedBox(height: 12),
                              // Predefined tip buttons row
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildTipButton('1', '1.00 €'),
                                    const SizedBox(width: 8),
                                    _buildTipButton('2', '2.00 €'),
                                    const SizedBox(width: 8),
                                    _buildTipButton('5', '5.00 €'),
                                    const SizedBox(width: 8),
                                    _buildTipButton('10', '10.00 €'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Custom tip input field
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: TextField(
                                  controller: _customTipController,
                                  focusNode: _customTipFocusNode,
                                  decoration: InputDecoration(
                                    labelText:
                                        'Montant du pourboire personnalisé',
                                    labelStyle: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.euro,
                                      color: AppTheme.primaryColor,
                                      size: 20,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppTheme.primaryColor,
                                        width: 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppTheme.textSecondary
                                            .withValues(alpha: 0.3),
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  keyboardType: TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  onChanged: _updateCustomTip,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _buildUnavailabilitySection(),
                            const SizedBox(height: 16),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              switchInCurve: Curves.easeOutBack,
                              switchOutCurve: Curves.easeIn,
                              child: _loading
                                  ? _buildAddressPlaceholder()
                                  : _buildCheckoutAddressCard(),
                            ),
                            const SizedBox(height: 16),
                          ],
                          // 1. Dont livraison
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Dont livraison',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatPrice(_deliveryFee + expressFee),
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_hasElectroMenagerInCart()) ...[
                            const SizedBox(height: 2),
                            Padding(
                              padding: const EdgeInsets.only(left: 8, right: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '  • Livraison Électroménager',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 10,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatPrice(_isBejaia ? _bejaiaElectroFee : _otherWilayaElectroFee),
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // 2. Frais de préparation
                          if (_getTotalPreparationFee() > 0) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Text(
                                'Frais de préparation:',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            ..._buildPreparationFeesWidgets(),
                          ],
                          const SizedBox(height: 6),
                          // 3. Total at bottom
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Total',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                _formatPrice(finalTotal),
                                style: TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          if (hasTip)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'Merci pour votre pourboire !',
                                style: TextStyle(
                                  color: AppTheme.successColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (!hasTip)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'Ajoutez un pourboire pour remercier notre équipe ❤️',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _buildSecurePaymentHighlight(),
                          ),
                          if (!_ordersEnabled)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.red),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Les commandes sont temporairement indisponibles. Merci de revenir un peu plus tard.',
                                        style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_ordersEnabled)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: _acceptedDeliveryTime,
                                    activeColor: AppTheme.primaryColor,
                                    onChanged: (val) {
                                      setState(() {
                                        _acceptedDeliveryTime = val ?? false;
                                      });
                                    },
                                  ),
                                  const Expanded(
                                    child: Text(
                                      "J'accepte que ma commande soit livrée dans un délai de 24 à 48 heures après sa validation.",
                                      style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: ElevatedButton(
                              onPressed: canPlaceOrder
                                  ? _showOrderConfirmationDialog
                                  : null,
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: AppTheme.primaryColor,
                                minimumSize: const Size(double.infinity, 44),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Passer commande',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailabilitySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: AppTheme.primaryColor, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'En cas d\'indisponibilité d\'un produit :',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildPolicyOption(
                    id: 'replacement',
                    label: 'Remplacement',
                    icon: Icons.cached_rounded,
                    subtitle: 'Produit similaire',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPolicyOption(
                    id: 'refund',
                    label: 'Remboursement',
                    icon: Icons.monetization_on_outlined,
                    subtitle: 'Retour des fonds',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyOption({
    required String id,
    required String label,
    required IconData icon,
    required String subtitle,
  }) {
    final isSelected = _unavailabilityPolicy == id;
    return InkWell(
      onTap: () => setState(() => _unavailabilityPolicy = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : AppTheme.textSecondary.withValues(alpha: 0.2),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppTheme.primaryColor,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.8)
                    : AppTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurePaymentHighlight() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: isCompact ? 3.6 : 4.4,
                  child: Image.asset(
                    'lib/assets/images/secure-paiements.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTipButton(String mode, String label) {
    final isSelected = _tipMode == mode;

    return GestureDetector(
      onTap: () => _setTip(mode),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: mode == 'custom' ? 14 : 16,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                )
              : null,
          color: isSelected ? null : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : AppTheme.primaryColor.withValues(alpha: 0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withValues(
                alpha: isSelected ? 0.25 : 0.06,
              ),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.primaryColor,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildAddressPlaceholder() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.35),
      highlightColor: Colors.white.withValues(alpha: 0.75),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 12,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: MediaQuery.of(context).size.width * 0.4,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
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

  Widget _buildCheckoutAddressCard() {
    final hasAddress = _selectedAddress != null;
    final label = _selectedAddress?['label']?.toString().trim();
    final fullAddressStr = _selectedAddress?['fullAddress']?.toString().trim();
    final recipientName = _selectedAddress?['recipientName']?.toString().trim();
    final phone = _selectedAddress?['phone']?.toString().trim();

    final addressText = hasAddress
        ? (fullAddressStr != null && fullAddressStr.isNotEmpty
            ? fullAddressStr
            : (label != null && label.isNotEmpty ? label : 'Adresse enregistrée'))
        : 'Veuillez ajouter une adresse de livraison (Obligatoire) *';

    final hasReceiver = (recipientName != null && recipientName.isNotEmpty) || (phone != null && phone.isNotEmpty) || (_receiverName != null && _receiverName!.isNotEmpty);
    final receiverText = hasReceiver
        ? '${recipientName ?? _receiverName ?? ''}${(recipientName ?? _receiverName)?.isNotEmpty == true && (phone ?? _receiverPhone)?.isNotEmpty == true ? ' • ' : ''}${phone ?? _receiverPhone ?? ''}'
        : 'Destinataire';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showCheckoutAddressScreen,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hasAddress ? Colors.white : Colors.red.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasAddress ? AppTheme.primaryColor.withOpacity(0.15) : AppTheme.errorColor,
            width: hasAddress ? 1 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (hasAddress ? AppTheme.primaryColor : AppTheme.errorColor).withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (hasAddress ? AppTheme.primaryColor : AppTheme.errorColor).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: hasAddress ? AppTheme.primaryColor : AppTheme.errorColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    addressText,
                    style: TextStyle(
                      color: hasAddress ? AppTheme.textPrimary : AppTheme.errorColor,
                      fontWeight: FontWeight.w600,
                      fontSize: hasAddress ? 13 : 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  hasAddress ? Icons.edit : Icons.add_circle,
                  size: 18,
                  color: hasAddress ? AppTheme.textSecondary : AppTheme.errorColor,
                ),
              ],
            ),
            if (hasAddress) ...[
              const Divider(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.blue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      receiverText,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: hasReceiver ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatPrice(double value) {
    final locale = Localizations.localeOf(context);
    return FormattingUtils.formatPriceWithLocale(value, locale);
  }
}
