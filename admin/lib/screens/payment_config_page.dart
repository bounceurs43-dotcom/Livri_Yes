import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import '../theme/app_theme.dart';
import '../services/payment_service.dart';
import '../services/notification_service.dart';

import 'notification_config_page.dart';
import 'custom_buttons_config_page.dart';

class PaymentConfigPage extends StatefulWidget {
  const PaymentConfigPage({super.key});

  @override
  State<PaymentConfigPage> createState() => _PaymentConfigPageState();
}

class _PaymentConfigPageState extends State<PaymentConfigPage> {
  final TextEditingController _stripeAccountIdCtrl = TextEditingController();
  final TextEditingController _stripePubKeyCtrl = TextEditingController();
  final TextEditingController _stripeSecretKeyCtrl = TextEditingController();
  final TextEditingController _googlePayMerchantIdCtrl = TextEditingController();
  final TextEditingController _paypalMerchantIdCtrl = TextEditingController();
  final TextEditingController _paypalEmailCtrl = TextEditingController();
  bool _loading = true;
  bool _isLocked = true; // Confidentially lock settings by default
  String? _generatedOtp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stripeAccountIdCtrl.dispose();
    _stripePubKeyCtrl.dispose();
    _stripeSecretKeyCtrl.dispose();
    _googlePayMerchantIdCtrl.dispose();
    _paypalMerchantIdCtrl.dispose();
    _paypalEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      final pub = await AdminPaymentService.getPublicInfo();
      if (!mounted) return;
      setState(() {
        _stripeAccountIdCtrl.text = pub['stripeAccountId'] ?? '';
        _stripePubKeyCtrl.text = pub['stripePublishableKey'] ?? '';
        _stripeSecretKeyCtrl.text = pub['stripeSecretKey'] ?? '';
        _googlePayMerchantIdCtrl.text = pub['googlePayMerchantId'] ?? '';
        _paypalMerchantIdCtrl.text = pub['paypalMerchantId'] ?? '';
        _paypalEmailCtrl.text = pub['paypalEmail'] ?? '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _startUnlockFlow() async {
    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Utilisateur non connecté');
      }

      // Generate a 6-digit code
      final random = Random();
      final otp = (100000 + random.nextInt(900000)).toString();
      _generatedOtp = otp;

      // Send OTP to salimbounceur@gmail.com
      final emailSent = await NotificationService.sendEmailNotification(
        email: 'salimbounceur@gmail.com',
        subject: 'Code OTP - Modification des paiements Livriyes',
        htmlContent: '''
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            .container { font-family: sans-serif; padding: 30px; color: #333; background-color: #f9f9f9; }
            .card { background: white; padding: 30px; border-radius: 12px; box-shadow: 0 4px 10px rgba(0,0,0,0.05); border: 1px solid #eee; }
            .header { text-align: center; margin-bottom: 20px; }
            .logo { font-size: 24px; font-weight: bold; color: #6366F1; }
            .title { font-size: 20px; font-weight: bold; color: #111; margin-top: 10px; }
            .otp-code { font-size: 32px; font-weight: bold; color: #6366F1; letter-spacing: 5px; text-align: center; margin: 30px 0; padding: 15px; background: #EEF2FF; border-radius: 8px; border: 1px dashed #6366F1; }
            .footer { margin-top: 30px; font-size: 12px; color: #777; text-align: center; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="card">
              <div class="header">
                <div class="logo">Livriyes</div>
                <div class="title">Code de Securite OTP</div>
              </div>
              <p>Bonjour,</p>
              <p>Un code a usage unique (OTP) a ete demande pour acceder aux parametres de paiement confidentiels (Stripe / PayPal) sur votre tableau de bord Livriyes.</p>
              <p>Veuillez utiliser le code de securite suivant :</p>
              <div class="otp-code">$otp</div>
              <p><strong>Attention :</strong> Si vous n'etes pas a l'origine de cette demande, veuillez ignorer cet e-mail et verifier la securite de votre compte.</p>
              <p>Cordialement,<br>L'equipe de securite Livriyes</p>
            </div>
            <div class="footer">
              <p>&copy; 2026 Livriyes. Tous droits reserves.</p>
            </div>
          </div>
        </body>
        </html>
        ''',
      );

      setState(() => _loading = false);

      if (!emailSent) {
        throw Exception("Echec de l'envoi de l'e-mail OTP.");
      }

      // Show Verification Dialog
      if (!mounted) return;
      _showVerificationDialog();

    } catch (e) {
      setState(() => _loading = false);
      _showErrorSnackBar("Erreur: $e");
    }
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red[800],
      ),
    );
  }

  void _showVerificationDialog() {
    final otpCtrl = TextEditingController();
    final pwdCtrl = TextEditingController();
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: const [
                  Icon(Icons.shield_outlined, color: AppTheme.primaryColor),
                  SizedBox(width: 10),
                  Text('Verification de securite'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Un e-mail contenant le code OTP a ete envoye a salimbounceur@gmail.com.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: otpCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Code de verification (OTP)',
                        prefixIcon: const Icon(Icons.password_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: pwdCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Mot de passe de l'administrateur",
                        prefixIcon: const Icon(Icons.lock_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying ? null : () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: isVerifying ? null : () async {
                    final enteredOtp = otpCtrl.text.trim();
                    final enteredPwd = pwdCtrl.text.trim();

                    if (enteredOtp.isEmpty || enteredPwd.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Veuillez remplir tous les champs')),
                      );
                      return;
                    }

                    if (enteredOtp != _generatedOtp) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Code OTP incorrect.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    setDialogState(() => isVerifying = true);

                    try {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null || user.email == null) {
                        throw Exception('Aucun utilisateur connecte');
                      }

                      // Re-authenticate user
                      final credential = EmailAuthProvider.credential(
                        email: user.email!,
                        password: enteredPwd,
                      );
                      await user.reauthenticateWithCredential(credential);

                      // Authentication success!
                      setState(() {
                        _isLocked = false;
                      });
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Parametres deverrouilles avec succes !'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      setDialogState(() => isVerifying = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Verification echouee: Mot de passe incorrect.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isVerifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Verifier', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _save() async {
    if (_isLocked) return;
    await AdminPaymentService.savePublicInfo(
      stripeAccountId: _stripeAccountIdCtrl.text.trim(),
      stripePublishableKey: _stripePubKeyCtrl.text.trim(),
      stripeSecretKey: _stripeSecretKeyCtrl.text.trim(),
      googlePayMerchantId: _googlePayMerchantIdCtrl.text.trim(),
      paypalMerchantId: _paypalMerchantIdCtrl.text.trim(),
      paypalEmail: _paypalEmailCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Informations enregistrées')));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 160,
              backgroundColor: AppTheme.primaryColor,
              actions: [
                IconButton(
                  icon: const Icon(Icons.mark_email_unread, color: Colors.white),
                  tooltip: 'Email de notifications',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationConfigPage()),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.link_rounded, color: Colors.white),
                  tooltip: 'Liens & Documents CGU',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CustomButtonsConfigPage()),
                    );
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -50,
                        top: -30,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                        child: Row(
                          children: const [
                            Icon(Icons.payments, color: Colors.white, size: 28),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Configurer les Paiements',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                title: const Text(
                  'Paiements',
                  style: TextStyle(color: Colors.white),
                ),
                centerTitle: false,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Beautiful Premium Security Lock Status Banner
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _isLocked
                                  ? Colors.amber.withOpacity(0.06)
                                  : Colors.green.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: _isLocked
                                    ? Colors.amber.withOpacity(0.2)
                                    : Colors.green.withOpacity(0.2),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _isLocked ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                                  color: _isLocked ? Colors.amber[800] : Colors.green[800],
                                  size: 32,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _isLocked ? 'Paramètres verrouillés' : 'Paramètres déverrouillés',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: _isLocked ? Colors.amber[900] : Colors.green[900],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _isLocked
                                            ? 'Pour modifier vos clés Stripe et PayPal, veuillez déverrouiller la page.'
                                            : 'Vous pouvez modifier et sauvegarder les clés de paiement.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _isLocked ? Colors.amber[800] : Colors.green[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _isLocked ? _startUnlockFlow : () {
                                    setState(() {
                                      _isLocked = true;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isLocked ? AppTheme.primaryColor : Colors.grey[700],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: Icon(_isLocked ? Icons.security_rounded : Icons.lock_rounded, size: 16),
                                  label: Text(_isLocked ? 'Déverrouiller' : 'Verrouiller', style: const TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(duration: 350.ms),
                          
                          CustomCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.credit_card,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Stripe',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _stripeAccountIdCtrl,
                                  obscureText: _isLocked,
                                  readOnly: _isLocked,
                                  decoration: const InputDecoration(
                                    labelText: 'Stripe Account ID (acct_...)',
                                    prefixIcon: Icon(Icons.link),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _stripePubKeyCtrl,
                                  obscureText: _isLocked,
                                  readOnly: _isLocked,
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Stripe Publishable Key (pk_...)',
                                    prefixIcon: Icon(Icons.vpn_key),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _stripeSecretKeyCtrl,
                                  obscureText: _isLocked,
                                  readOnly: _isLocked,
                                  decoration: const InputDecoration(
                                    labelText: 'Stripe Secret Key (sk_...)',
                                    prefixIcon: Icon(Icons.key_off),
                                  ),
                                ),
                              ],
                            ),
                          ).animate().slideY(begin: 0.15, duration: 350.ms),
                          CustomCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.g_mobiledata,
                                        color: Colors.black,
                                        size: 36,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Google Pay',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _googlePayMerchantIdCtrl,
                                  obscureText: _isLocked,
                                  readOnly: _isLocked,
                                  decoration: const InputDecoration(
                                    labelText: 'Google Pay Merchant ID (16-20 chiffres)',
                                    prefixIcon: Icon(Icons.storefront_outlined),
                                  ),
                                ),
                              ],
                            ),
                          ).animate().slideY(
                            begin: 0.15,
                            duration: 350.ms,
                            delay: 50.ms,
                          ),
                          CustomCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: AppTheme.accentColor.withOpacity(
                                          0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.account_balance_wallet,
                                        color: AppTheme.accentColor,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'PayPal',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _paypalMerchantIdCtrl,
                                  obscureText: _isLocked,
                                  readOnly: _isLocked,
                                  decoration: const InputDecoration(
                                    labelText: 'PayPal Merchant ID',
                                    prefixIcon: Icon(Icons.account_balance),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _paypalEmailCtrl,
                                  obscureText: _isLocked,
                                  readOnly: _isLocked,
                                  decoration: const InputDecoration(
                                    labelText: 'PayPal Email',
                                    prefixIcon: Icon(Icons.alternate_email),
                                  ),
                                ),
                              ],
                            ),
                          ).animate().slideY(
                            begin: 0.15,
                            duration: 350.ms,
                            delay: 100.ms,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isLocked ? null : _save,
                                  icon: const Icon(Icons.save),
                                  label: const Text('Enregistrer'),
                                ),
                              )
                              .animate()
                              .fadeIn(duration: 300.ms)
                              .slideY(begin: 0.2),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}












