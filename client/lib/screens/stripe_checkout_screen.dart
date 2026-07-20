import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme.dart';
import '../services/cart_service.dart';
import '../services/payment_service.dart';
import '../services/order_service.dart';
import 'home_page.dart';

class StripeCheckoutScreen extends StatefulWidget {
  final List<CartItem> cartItems;
  final double cartTotal;
  final double deliveryFee;
  final double expressFee;
  final double tip;
  final double finalTotal;
  final String deliveryAddress;
  final String? deliveryLabel;
  final String wilaya;
  final String? wilayaCode;
  final String? receiverName;
  final String? receiverPhone;
  final String? userId;
  final String unavailabilityPolicy;

  const StripeCheckoutScreen({
    super.key,
    required this.cartItems,
    required this.cartTotal,
    required this.deliveryFee,
    required this.expressFee,
    required this.tip,
    required this.finalTotal,
    required this.deliveryAddress,
    this.deliveryLabel,
    required this.wilaya,
    this.wilayaCode,
    this.receiverName,
    this.receiverPhone,
    this.userId,
    required this.unavailabilityPolicy,
  });

  @override
  State<StripeCheckoutScreen> createState() => _StripeCheckoutScreenState();
}

class _StripeCheckoutScreenState extends State<StripeCheckoutScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _showLoadingAnimation = true;
  String? _stripePublishableKey;
  String? _stripeSecretKey;
  HttpServer? _localServer;

  @override
  void dispose() {
    _localServer?.close(force: true);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    _controller = WebViewController.fromPlatformCreationParams(params);
    _loadKeysAndInitialize();
  }

  Future<void> _loadKeysAndInitialize() async {
    try {
      final keys = await PaymentService.getAdminPublicPaymentInfo();
      _stripePublishableKey = keys['stripePublishableKey'];
      _stripeSecretKey = keys['stripeSecretKey'];

      if ((_stripePublishableKey?.isEmpty ?? true) || (_stripeSecretKey?.isEmpty ?? true)) {
        throw Exception("Les clés Stripe de l'administrateur n'ont pas été configurées. Contactez le support.");
      }

      await _initializeStripeAndWebView();
    } catch (e) {
      if (mounted) {
        setState(() {
          _showLoadingAnimation = false;
        });
        _showErrorDialog(e);
      }
    }
  }

  void _showErrorDialog(dynamic error) {
    if (!mounted) return;

    String title = "Erreur de Paiement";
    String message = error.toString();
    bool isAmountTooSmall = false;

    if (message.startsWith('Exception: ')) {
      message = message.replaceFirst('Exception: ', '');
    }

    if (error is StripeCustomException) {
      message = error.message;
      if (error.code == 'amount_too_small') {
        title = "Montant Insuffisant";
        isAmountTooSmall = true;
      }
    } else if (message.contains('amount_too_small') || message.contains('at least €0.50')) {
      title = "Montant Insuffisant";
      message = "Le montant de votre panier (${widget.finalTotal.toStringAsFixed(2)}€) est inférieur au montant minimum de 0.50€ requis par Stripe.\n\nVeuillez ajouter d'autres articles à votre panier pour finaliser la commande.";
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
                isAmountTooSmall ? Icons.warning_amber_rounded : Icons.error_outline_rounded,
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
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                backgroundColor: isAmountTooSmall ? Colors.amber[800] : AppTheme.errorColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text(
                isAmountTooSmall ? "Ajouter des articles" : "Retour au panier",
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

  Future<void> _initializeStripeAndWebView() async {
    try {
      final amountInCents = (widget.finalTotal * 100).round().toString();
      
      final response = await http.post(
        Uri.parse('https://api.stripe.com/v1/payment_intents'),
        headers: {
          'Authorization': 'Bearer $_stripeSecretKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'amount': amountInCents,
          'currency': 'eur',
          'automatic_payment_methods[enabled]': 'true',
        },
      );

      if (response.statusCode != 200) {
        try {
          final errorData = json.decode(response.body);
          if (errorData is Map && errorData.containsKey('error')) {
            final stripeError = errorData['error'];
            if (stripeError is Map) {
              final errorCode = stripeError['code']?.toString();
              final errorMessage = stripeError['message']?.toString();
              if (errorCode == 'amount_too_small') {
                throw StripeCustomException(
                  code: 'amount_too_small',
                  message: "Le montant de votre panier (${widget.finalTotal.toStringAsFixed(2)}€) est inférieur au montant minimum de 0.50€ requis par notre partenaire de paiement Stripe.\n\nVeuillez ajouter d'autres articles ou augmenter la quantité pour finaliser votre commande.",
                );
              } else if (errorMessage != null) {
                throw StripeCustomException(
                  code: errorCode ?? 'unknown',
                  message: errorMessage,
                );
              }
            }
          }
        } catch (e) {
          if (e is StripeCustomException) rethrow;
        }
        throw Exception('Failed to create payment intent: ${response.body}');
      }

      final responseData = json.decode(response.body);
      final clientSecret = responseData['client_secret'];

      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setBackgroundColor(Colors.transparent);

      // Override User-Agent to identify as a standard Chrome mobile browser and declare Google Pay support.
      // This prevents Stripe.js from identifying this as a restricted WebView and hiding the Google Pay button.
      await _controller.setUserAgent(
        "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36 GOOGLE_PAY_SUPPORTED"
      );

      // Enable Google Pay / Apple Pay inside Android WebView
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final androidController = _controller.platform as AndroidWebViewController;
          final bool paymentRequestSupported = await androidController
              .isWebViewFeatureSupported(WebViewFeatureType.paymentRequest);
          if (paymentRequestSupported) {
            await androidController.setPaymentRequestEnabled(true);
            debugPrint('Stripe Checkout: WebView PaymentRequest enabled successfully.');
          } else {
            debugPrint('Stripe Checkout: WebView PaymentRequest feature NOT supported.');
          }
        } catch (e) {
          debugPrint('Stripe Checkout: Failed to enable WebView PaymentRequest: $e');
        }
      }

      await _controller.addJavaScriptChannel(
        'StripeSuccess',
        onMessageReceived: (JavaScriptMessage message) {
          _handlePaymentSuccess(message.message);
        },
      );

      await _controller.addJavaScriptChannel(
        'StripeCancel',
        onMessageReceived: (JavaScriptMessage message) {
          _handleCancellation();
        },
      );

      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('Page started loading: $url');
          },
          onPageFinished: (String url) {
            debugPrint('Page finished loading: $url');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _showLoadingAnimation = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('Web resource error: ${error.description}');
            
            if (error.description.contains('ERR_CONNECTION_REFUSED') || 
                error.description.contains('net::ERR_CONNECTION_REFUSED')) {
              return;
            }

            if (mounted) {
              setState(() {
                _isLoading = false;
                _showLoadingAnimation = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Erreur de chargement. Veuillez vérifier votre connexion.',
                  ),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith(
              'https://salimstore.onrender.com/payment-success',
            )) {
              final uri = Uri.parse(request.url);
              final paymentIntentId = uri.queryParameters['payment_intent'] ?? uri.queryParameters['orderId'] ?? '';
              _handlePaymentSuccess(paymentIntentId);
              return NavigationDecision.prevent;
            }
            if (request.url.startsWith(
              'https://salimstore.onrender.com/payment-cancel',
            )) {
              _handleCancellation();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

      if (WebViewPlatform.instance is AndroidWebViewPlatform) {
        AndroidWebViewController.enableDebugging(true);
        (_controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }

      final String htmlContent = await rootBundle.loadString(
        'assets/html/stripe_checkout.html',
      );
      final String jsContent = await rootBundle.loadString(
        'assets/html/stripe_checkout.js',
      );

      String modifiedHtml = htmlContent.replaceFirst(
        '<script src="stripe_checkout.js"></script>',
        '<script>$jsContent</script>',
      );

      final cartData = _prepareCartData();
      final enhancedCartData = '''{
        ${cartData.substring(1, cartData.length - 1)},
        "testClientSecret": "$clientSecret",
        "testPublishableKey": "$_stripePublishableKey"
      }''';

      final htmlWithData = modifiedHtml.replaceFirst(
        '<!-- CART_DATA_PLACEHOLDER -->',
        '''<script>
             window.cartData = $enhancedCartData;
             console.log("Cart data injected successfully");
           </script>''',
      );

      // Start a local HTTP server on loopback to provide a secure context (localhost).
      // This is a strict requirement for Chromium WebView and Stripe.js to enable the Payment Request API (Google Pay).
      _localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final int port = _localServer!.port;
      debugPrint('Stripe Checkout: Local HTTP server started on http://127.0.0.1:$port');

      _localServer!.listen((HttpRequest request) {
        request.response
          ..headers.contentType = ContentType.html
          ..write(htmlWithData)
          ..close();
      });

      await _controller.loadRequest(Uri.parse('http://127.0.0.1:$port'));

    } catch (e) {
      debugPrint('Error initializing WebView: $e');
      if (mounted) {
        setState(() {
          _showLoadingAnimation = false;
        });
        _showErrorDialog(e);
      }
    }
  }

  String _prepareCartData() {
    // Prepare cart items with complete product information
    final itemsJson = widget.cartItems
        .map(
          (item) => {
            'id': item.id,
            'productId': item.productId,
            'name': item.productName,
            'quantity': item.quantity,
            'unit': item.unit,
            'price': item.unitPrice,
            'totalPrice': item.totalPrice,
            if (item.originalPrice != null) 'originalPrice': item.originalPrice,
            if (item.discountPercentage != null)
              'discountPercentage': item.discountPercentage,
          },
        )
        .toList();

    // Calculate totals including tip
    final subtotal = widget.cartTotal;
    final delivery = widget.deliveryFee;
    final express = widget.expressFee;
    final tipAmount = widget.tip;
    final total = widget.finalTotal;

    // Get userId from widget or Firebase Auth
    final userId =
        widget.userId ??
        firebase_auth.FirebaseAuth.instance.currentUser?.uid ??
        '';

    return '''{
      "userId": "${userId.replaceAll('"', '\\"')}",
      "items": ${_jsonEncode(itemsJson)},
      "cartTotal": ${subtotal.toString()},
      "deliveryFee": ${delivery.toString()},
      "expressFee": ${express.toString()},
      "tip": ${tipAmount.toString()},
      "finalTotal": ${total.toString()},
      "deliveryAddress": "${widget.deliveryAddress.replaceAll('"', '\\"')}",
      "deliveryLabel": "${widget.deliveryLabel?.replaceAll('"', '\\"') ?? ''}",
      "wilaya": "${widget.wilayaCode ?? '06'}",
      "receiverName": "${widget.receiverName?.replaceAll('"', '\\"') ?? ''}",
      "receiverPhone": "${widget.receiverPhone?.replaceAll('"', '\\"') ?? ''}"
    }''';
  }

  String _jsonEncode(dynamic obj) {
    if (obj is String) {
      return '"${obj.replaceAll('"', '\\"')}"';
    } else if (obj is num) {
      return obj.toString();
    } else if (obj is bool) {
      return obj.toString();
    } else if (obj is List) {
      return '[${obj.map(_jsonEncode).join(',')}]';
    } else if (obj is Map) {
      final entries = obj.entries
          .map((e) => '"${e.key}":${_jsonEncode(e.value)}')
          .join(',');
      return '{$entries}';
    }
    return 'null';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Main content: Header + WebView
          Column(
            children: [
              // Top AppBar with gradient (only shown after loading)
              if (!_showLoadingAnimation)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor,
                        const Color(0xFF0C8A25), // Slightly darker green
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Paiement Sécurisé',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Montant à régler: ${_formatPrice(widget.finalTotal)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.white.withOpacity(0.9),
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shield_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Sécurisé',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // WebView occupies the rest of the space
              Expanded(child: WebViewWidget(controller: _controller)),
            ],
          ),

          // Beautiful Fullscreen Loading Overlay
          if (_showLoadingAnimation)
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryColor,
                    const Color(0xFF0C8A25),
                    const Color(0xFF056619),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),

                    // Animated Icon Container
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.elasticOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 40,
                                  spreadRadius: 5,
                                  offset: const Offset(0, 15),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 60,
                                color: Color(0xFF10AA2E),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 50),

                    // Pulsing Progress Indicator
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                        backgroundColor: Colors.white.withOpacity(0.2),
                      ),
                    ),

                    const SizedBox(height: 50),

                    // Animated Text
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        children: [
                          const Text(
                            'Paiement Sécurisé',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Initialisation de la transaction Stripe...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(flex: 3),

                    // Amount Info
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Montant: ${widget.finalTotal.toStringAsFixed(2)}€',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    return '${price.toString()}€';
  }

  void _handleCancellation() {
    debugPrint('Payment cancelled by user');
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handlePaymentSuccess(String paymentIntentId) async {
    try {
      debugPrint('Payment success with intent: $paymentIntentId');

      if (mounted) {
        setState(() {
          _showLoadingAnimation = true;
        });
      }

      final orderId = await OrderService.createOrder(
        items: widget.cartItems,
        cartTotal: widget.cartTotal,
        deliveryFee: widget.deliveryFee,
        expressDelivery: widget.expressFee > 0,
        expressFee: widget.expressFee,
        tip: widget.tip,
        total: widget.finalTotal,
        deliveryAddress: widget.deliveryAddress,
        deliveryLabel: widget.deliveryLabel,
        wilaya: widget.wilaya,
        receiverName: widget.receiverName,
        receiverPhone: widget.receiverPhone,
        paymentMethod: 'stripe',
        paymentStatus: 'completed',
        paymentId: paymentIntentId,
        unavailabilityPolicy: widget.unavailabilityPolicy,
      );

      // Clear cart immediately
      await _clearCart();

      if (mounted) {
        setState(() {
          _showLoadingAnimation = false;
        });

        // Show success dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 12),
                  Text('Commande Réussie!'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Votre paiement a été traité avec succès.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Numéro de commande:',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          orderId ?? 'En attente',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Vous serez redirigé vers vos commandes dans quelques secondes...',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _redirectToOrders();
                  },
                  child: const Text('Voir mes commandes'),
                ),
              ],
            );
          },
        );

        // Auto-redirect after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            Navigator.of(context).pop(); // Close dialog
            _redirectToOrders();
          }
        });
      }
    } catch (e) {
      debugPrint('Error handling payment success: $e');
      if (mounted) {
        setState(() {
          _showLoadingAnimation = false;
        });
      }
    }
  }

  Future<void> _clearCart() async {
    try {
      await CartService.clearCart();
      debugPrint('Cart cleared successfully');
    } catch (e) {
      debugPrint('Error clearing cart: $e');
    }
  }

  void _redirectToOrders() {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LivriyesHomePage(initialIndex: 4),
        ),
        (route) => false,
      );
    }
  }
}

class StripeCustomException implements Exception {
  final String code;
  final String message;
  StripeCustomException({required this.code, required this.message});

  @override
  String toString() => message;
}
