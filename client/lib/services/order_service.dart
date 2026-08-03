import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'cart_service.dart';
import 'city_service.dart';
import 'wilaya_geo_service.dart';
import 'notification_service.dart';

class OrderService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseDatabase _db = FirebaseDatabase.instance;

  static DatabaseReference get _ordersRef => _db.ref('orders');
  static DatabaseReference get _orderCounterRef => _db.ref('orderCounter');

  /// Generate order ID in format: BCYYYYWW00000
  /// BC = Bon de Commande prefix
  /// YYYY = Year (4 digits)
  /// WW = Wilaya code (2 digits)
  /// 00000 = Sequential order number (5 digits)
  static Future<String> _generateOrderId(String wilayaCode) async {
    try {
      // Use full 4-digit year for readability
      final year = DateTime.now().year.toString();

      // Get or create order counter for this wilaya and year
      final counterRef = _orderCounterRef.child('${year}_$wilayaCode');
      final counterSnap = await counterRef.get();

      int orderNumber = 1;
      if (counterSnap.exists) {
        final currentValue = counterSnap.value;
        if (currentValue is int) {
          orderNumber = currentValue + 1;
        } else if (currentValue is num) {
          orderNumber = currentValue.toInt() + 1;
        }
      }

      // Update counter
      await counterRef.set(orderNumber);

      // Format: BCYYYYWW00000
      final wilayaCodePadded = wilayaCode.padLeft(2, '0');
      final orderNumberPadded = orderNumber.toString().padLeft(5, '0');

      return 'BC${year}$wilayaCodePadded$orderNumberPadded';
    } catch (e) {
      print('Error generating order ID: $e');
      // Fallback: use timestamp-based ID
      final year = DateTime.now().year.toString();
      final wilayaCodePadded = wilayaCode.padLeft(2, '0');
      final timestamp = DateTime.now().millisecondsSinceEpoch
          .toString()
          .substring(7);
      return 'BC${year}$wilayaCodePadded$timestamp';
    }
  }

  /// Get wilaya code from address (default: 06 for Béjaïa)
  static String _getWilayaCode({
    String? wilaya,
    String? address,
    double? latitude,
    double? longitude,
  }) {
    String? code;

    if (latitude != null && longitude != null && WilayaGeoService.isLoaded()) {
      final match = WilayaGeoService.findByCoordinates(latitude, longitude);
      if (match != null && match.code.isNotEmpty) {
        code = match.code;
      }
    }

    if (code == null && wilaya != null && wilaya.isNotEmpty) {
      if (CityService.isLoaded()) {
        final normalized = CityService.getWilayaCode(wilaya);
        if (normalized != null && normalized.isNotEmpty) {
          code = normalized.toString();
        }
      }

      if (code == null) {
        final match = RegExp(r'\d+').firstMatch(wilaya);
        if (match != null) {
          code = match.group(0);
        }
      }
    }

    if (code == null && address != null && address.isNotEmpty) {
      final addressLower = address.toLowerCase();
      if (addressLower.contains('béjaïa') || addressLower.contains('bejaia')) {
        code = '06';
      } else if (addressLower.contains('alger') ||
          addressLower.contains('الجزائر')) {
        code = '16';
      } else if (addressLower.contains('oran')) {
        code = '31';
      } else if (addressLower.contains('tizi') ||
          addressLower.contains('ouzou')) {
        code = '15';
      }
    }

    code ??= '06';
    return code.padLeft(2, '0');
  }

  static Future<String?> createOrder({
    required List<CartItem> items,
    required double cartTotal,
    required double deliveryFee,
    required bool expressDelivery,
    required double expressFee,
    required double tip,
    required double total,
    double preparationFee = 0.0,
    String? deliveryAddress,
    String? deliveryLabel,
    String? wilaya,
    double? latitude,
    double? longitude,
    String? receiverName,
    String? receiverPhone,
    String? paymentMethod,
    String? paymentStatus,
    String? paymentId,
    String? unavailabilityPolicy,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    // Fetch user profile info from RTDB /users/{user.uid}
    String customerName = user.displayName ?? '';
    String customerPhone = user.phoneNumber ?? '';
    String customerEmail = user.email ?? '';

    try {
      final userSnap = await _db.ref('users').child(user.uid).get();
      if (userSnap.exists && userSnap.value is Map) {
        final uData = Map<String, dynamic>.from(userSnap.value as Map);
        final nameCandidate = (uData['name'] ?? uData['displayName'] ?? uData['fullName'] ?? uData['username'])?.toString().trim();
        if (nameCandidate != null && nameCandidate.isNotEmpty && nameCandidate.toLowerCase() != 'client') {
          customerName = nameCandidate;
        }

        final phoneCandidate = (uData['phone'] ?? uData['phoneNumber'] ?? uData['contactPhone'])?.toString().trim();
        if (phoneCandidate != null && phoneCandidate.isNotEmpty) {
          customerPhone = phoneCandidate;
        }

        final emailCandidate = (uData['email'] ?? uData['mail'])?.toString().trim();
        if (emailCandidate != null && emailCandidate.isNotEmpty) {
          customerEmail = emailCandidate;
        }
      }
    } catch (e) {
      print('Error fetching user profile for order creation: $e');
    }

    if (customerName.isEmpty) customerName = 'Client';

    await WilayaGeoService.ensureLoaded();

    // Generate order ID
    final wilayaCode = _getWilayaCode(
      wilaya: wilaya,
      address: deliveryAddress,
      latitude: latitude,
      longitude: longitude,
    );
    final orderId = await _generateOrderId(wilayaCode);

    final itemsData = items
        .map(
          (item) => {
            'productId': item.productId,
            'productName': item.productName,
            'quantity': item.quantity,
            'unit': item.unit,
            'unitPrice': item.unitPrice,
            'totalPrice': item.totalPrice,
            if (item.originalPrice != null) 'originalPrice': item.originalPrice,
            if (item.discountPercentage != null)
              'discountPercentage': item.discountPercentage,
            if (item.categoryId != null) 'categoryId': item.categoryId,
            if (item.categoryName != null) 'categoryName': item.categoryName,
          },
        )
        .toList();

    // Create order with generated ID
    final ref = _ordersRef.child(orderId);

    await ref.set({
      'orderId': orderId,
      'userId': user.uid,
      'customerName': customerName,
      'userName': customerName,
      'phone': customerPhone.isNotEmpty ? customerPhone : 'Non fourni',
      'phoneNumber': customerPhone.isNotEmpty ? customerPhone : 'Non fourni',
      'email': customerEmail.isNotEmpty ? customerEmail : 'Non renseigné',
      'userEmail': customerEmail.isNotEmpty ? customerEmail : 'Non renseigné',
      'items': itemsData,
      'cartTotal': cartTotal,
      'deliveryFee': deliveryFee,
      'preparationFee': preparationFee,
      'totalPreparationFee': preparationFee,
      'expressDelivery': expressDelivery,
      'expressFee': expressFee,
      'tip': tip,
      'total': total,
      'currency': 'EUR',
      'status': 'pending',
      'deliveryAddress': deliveryAddress ?? 'Non spécifiée',
      if (deliveryLabel != null && deliveryLabel.isNotEmpty)
        'deliveryLabel': deliveryLabel,
      'wilaya': wilaya ?? '',
      'wilayaCode': wilayaCode,
      if (receiverName != null && receiverName.isNotEmpty) ...{
        'receiverName': receiverName,
        'recipientName': receiverName,
      },
      if (receiverPhone != null && receiverPhone.isNotEmpty) ...{
        'receiverPhone': receiverPhone,
        'recipientPhone': receiverPhone,
      },
      if (paymentMethod != null && paymentMethod.isNotEmpty)
        'paymentMethod': paymentMethod,
      if (paymentStatus != null && paymentStatus.isNotEmpty)
        'paymentStatus': paymentStatus,
      if (paymentId != null && paymentId.isNotEmpty)
        'paymentId': paymentId,
      'unavailabilityPolicy': unavailabilityPolicy ?? 'refund',
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
    });

    // Trigger local confirmation notification
    try {
      await NotificationService.showNotification(
        title: 'Commande confirmée ✅',
        body: 'Votre commande #$orderId a été enregistrée avec succès !',
      );
      
      // NEW: Guarantee admin receives email by sending it directly from client app
      await NotificationService.notifyAdminNewOrder(
        orderId,
        total: '${total.toStringAsFixed(2)} €',
        deliveryAddress: deliveryAddress ?? 'Non spécifiée',
      );
    } catch (e) {
      print('Error showing local notification or sending email: $e');
    }

    return orderId;
  }
}
