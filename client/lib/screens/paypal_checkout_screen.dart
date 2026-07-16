import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../theme/app_theme.dart';
import '../services/cart_service.dart';
import '../services/order_service.dart';
import 'home_page.dart';

class PayPalCheckoutScreen extends StatefulWidget {
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
  final String paypalEmail;
  final String? paypalMerchantId;

  const PayPalCheckoutScreen({
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
    required this.paypalEmail,
    this.paypalMerchantId,
  });

  @override
  State<PayPalCheckoutScreen> createState() => _PayPalCheckoutScreenState();
}

class _PayPalCheckoutScreenState extends State<PayPalCheckoutScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isCreatingOrder = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress > 80) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
            _checkNavigationState(url);
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_checkNavigationState(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    // Build the secure PayPal checkout standard link using PayPal email or merchant ID
    final String business = widget.paypalEmail.isNotEmpty 
        ? widget.paypalEmail 
        : (widget.paypalMerchantId ?? '');

    final String paypalUrl = "https://www.paypal.com/cgi-bin/webscr?"
        "cmd=_xclick&"
        "business=${Uri.encodeComponent(business)}&"
        "item_name=${Uri.encodeComponent('Commande Livriyes')}&"
        "amount=${widget.finalTotal.toStringAsFixed(2)}&"
        "currency_code=EUR&"
        "landing_page=login&"
        "solution_type=Mark&"
        "return=${Uri.encodeComponent('https://salimstore.onrender.com/payment-success')}&"
        "cancel_return=${Uri.encodeComponent('https://salimstore.onrender.com/payment-cancel')}";

    _controller.loadRequest(Uri.parse(paypalUrl));
  }

  bool _checkNavigationState(String url) {
    if (url.startsWith('https://salimstore.onrender.com/payment-success')) {
      _handlePaymentSuccess();
      return true;
    } else if (url.startsWith('https://salimstore.onrender.com/payment-cancel')) {
      _handlePaymentCancel();
      return true;
    }
    return false;
  }

  Future<void> _handlePaymentSuccess() async {
    if (_isCreatingOrder) return;
    setState(() {
      _isCreatingOrder = true;
      _isLoading = true;
    });

    try {
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
        paymentMethod: 'paypal',
        paymentStatus: 'completed',
        paymentId: 'paypal_${DateTime.now().millisecondsSinceEpoch}',
        unavailabilityPolicy: widget.unavailabilityPolicy,
      );

      await CartService.clearCart();

      if (mounted) {
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
                  Icon(Icons.check_circle_rounded, color: Colors.green[600], size: 28),
                  const SizedBox(width: 12),
                  const Text('Commande Réussie!'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Votre paiement via PayPal a été traité avec succès.',
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.2)),
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Vous serez redirigé vers vos commandes dans quelques secondes...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => LivriyesHomePage(initialIndex: 4),
                      ),
                      (route) => false,
                    );
                  },
                  child: const Text('Voir mes commandes'),
                ),
              ],
            );
          },
        );

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => LivriyesHomePage(initialIndex: 4),
              ),
              (route) => false,
            );
          }
        });
      }
    } catch (e) {
      setState(() {
        _isCreatingOrder = false;
        _isLoading = false;
      });
      _showErrorDialog("Échec de la validation de commande: $e");
    }
  }

  void _handlePaymentCancel() {
    _showErrorDialog("Paiement annulé par l'utilisateur.");
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: AppTheme.errorColor, size: 28),
              SizedBox(width: 12),
              Text('Paiement Annulé'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss error dialog
                Navigator.of(this.context).pop(); // Pop PayPal checkout screen
              },
              child: const Text('Retour au Panier'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Row(
          children: [
            Image.network(
              'https://upload.wikimedia.org/wikipedia/commons/b/b5/PayPal.svg',
              height: 24,
              errorBuilder: (_, __, ___) => const Icon(Icons.payment, color: Colors.blue),
            ),
            const SizedBox(width: 10),
            const Text(
              'Paiement PayPal',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Quitter le paiement ?'),
                content: const Text('Êtes-vous sûr de vouloir quitter le paiement PayPal en cours ?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Continuer'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(this.context);
                    },
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
                    child: const Text('Quitter'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading || _isCreatingOrder)
            Container(
              color: Colors.white.withOpacity(0.9),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isCreatingOrder 
                          ? 'Enregistrement de votre commande...' 
                          : 'Sécurisation de la connexion...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Veuillez ne pas quitter cette page.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
