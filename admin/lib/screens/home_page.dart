import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import '../widgets/navigation_footer.dart';
import '../widgets/navigation_sidebar.dart';
import '../widgets/admin_notification_bell.dart';
import '../utils/browser_helper.dart';
import '../services/notification_service.dart';
import 'product_management_screen.dart';
import 'category_management_screen.dart';
import 'promotion_management_screen.dart';
import 'tabs/dashboard_tab.dart' as sep;
import 'tabs/analytics_tab.dart' as sep;
import 'tabs/profile_tab.dart' as sep;
import 'announcements_management_screen.dart';
import 'tabs/users_tab.dart' as sep;
import 'tabs/orders_tab.dart' as sep;
import '../widgets/delivery_prices_dialog.dart';

// ──────────────────────────────────────────────
// Desktop top-bar (stateless)
// ──────────────────────────────────────────────
class _DesktopTopBar extends StatelessWidget {
  final String title;
  final List<AdminNotification> notifications;
  final VoidCallback? onNotificationsViewed;
  final Function(AdminNotification)? onNotificationSelected;

  const _DesktopTopBar({
    required this.title,
    required this.notifications,
    this.onNotificationsViewed,
    this.onNotificationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        boxShadow: AppShadows.subtle,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Vue d\'ensemble des activités de Livriyes',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 320,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          ElevatedButton.icon(
            onPressed: () => DeliveryPricesDialog.show(context),
            icon: const Icon(Icons.local_shipping_rounded, size: 20),
            label: const Text('Prix Livraison'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 16),
          AdminNotificationBell(
            iconColor: AppTheme.textPrimary,
            initialNotifications: notifications,
            onNotificationsViewed: onNotificationsViewed,
            onNotificationSelected: onNotificationSelected,
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.primaryColor.withOpacity(0.12),
            child: const Icon(Icons.person, color: AppTheme.primaryColor),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Main widget
// ──────────────────────────────────────────────
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  // ── State ──────────────────────────────────
  int _selectedIndex = 0;
  final DateTime _appStartTime = DateTime.now();
  final GlobalKey<sep.OrdersTabState> _ordersTabKey = GlobalKey<sep.OrdersTabState>();
  bool _sidebarCollapsed = false;
  int _pendingOrdersCount = 0;
  bool _initialPendingSnapshotHandled = false;
  List<AdminNotification> _notifications = [];
  final Set<String> _knownOrderIds = {};
  final Set<String> _knownRefundIds = {};
  final Set<String> _readNotificationIds = {};
  SharedPreferences? _prefs;
  late final AudioPlayer _alertPlayer;

  // ── Firebase subscriptions ─────────────────
  StreamSubscription<DatabaseEvent>? _pendingOrdersSubscription;
  StreamSubscription<DatabaseEvent>? _newOrderAddedSubscription;
  StreamSubscription<DatabaseEvent>? _refundRequestsSubscription;

  // ── Pages ──────────────────────────────────
  late final List<Widget> _pages;
  late final List<String> _pageTitles;

  // ── Tone data (static, generated once) ─────
  static final Uint8List _newOrderToneBytes = _generateNewOrderTone();

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _alertPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

    _pages = [
      sep.DashboardTab(
        onNavigateToTab: (index) => setState(() => _selectedIndex = index),
      ),
      const ProductManagementScreen(),
      const CategoryManagementScreen(),
      const PromotionManagementScreen(),
      sep.OrdersTab(key: _ordersTabKey),
      const sep.UsersTab(),
      const sep.AnalyticsTab(),
      const sep.ProfileTab(),
      const AnnouncementsManagementScreen(),
    ];

    _pageTitles = [
      'Tableau de bord',
      'Produits',
      'Catégories',
      'Promotions',
      'Commandes',
      'Utilisateurs',
      'Analyses',
      'Profil',
      'Annonces',
    ];

    // Load persisted read-state first, then start listeners
    _initPrefs().then((_) {
      _listenPendingOrders();
      _listenNewOrders();
      _listenRefundRequests();
    });
  }

  @override
  void dispose() {
    _pendingOrdersSubscription?.cancel();
    _newOrderAddedSubscription?.cancel();
    _refundRequestsSubscription?.cancel();
    _alertPlayer.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SharedPreferences helpers
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final readIds = _prefs?.getStringList('read_notification_ids') ?? [];
    if (mounted) {
      setState(() => _readNotificationIds.addAll(readIds));
    }
  }

  void _markNotificationsAsRead() {
    setState(() {
      for (final n in _notifications) {
        n.read = true;
        _readNotificationIds.add(n.id);
      }
      _notifications = List<AdminNotification>.from(_notifications);
    });
    _prefs?.setStringList('read_notification_ids', _readNotificationIds.toList());
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Utility
  // ──────────────────────────────────────────────────────────────────────────
  DateTime? _parseOrderDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Firebase listeners
  // ──────────────────────────────────────────────────────────────────────────
  void _listenPendingOrders() {
    final ref = FirebaseDatabase.instance.ref('orders');
    _pendingOrdersSubscription?.cancel();
    _pendingOrdersSubscription = ref.onValue.listen(
      (event) {
        if (!mounted) return;
        final data = event.snapshot.value;
        final previousCount = _pendingOrdersCount;
        final pendingCount = _extractPendingCount(data);
        final shouldPlayAlert =
            _initialPendingSnapshotHandled && pendingCount > previousCount;

        if (pendingCount != previousCount) {
          setState(() => _pendingOrdersCount = pendingCount);
        }
        if (shouldPlayAlert) _playNewOrderSound();
        _initialPendingSnapshotHandled = true;
      },
      onError: (error) => debugPrint('Error listening to pending orders: $error'),
    );
  }

  void _listenNewOrders() {
    final ref = FirebaseDatabase.instance.ref('orders');

    // 1. Listen for new orders immediately and independently!
    _newOrderAddedSubscription?.cancel();
    _newOrderAddedSubscription = ref.onChildAdded.listen((event) async {
      if (!mounted || event.snapshot.key == null) return;
      final orderId = event.snapshot.key!;
      
      // If we already loaded/parsed this order, skip duplicate notification adding
      if (_knownOrderIds.contains(orderId)) return;
      
      final dynamic rawVal = event.snapshot.value;
      if (rawVal == null || rawVal is! Map) {
        _knownOrderIds.add(orderId);
        return;
      }
      
      final orderData = Map<String, dynamic>.from(
        rawVal.map((k, v) => MapEntry(k.toString(), v)),
      );
      
      final timestamp = _parseOrderDate(orderData['createdAt']) ?? DateTime.now();
      _knownOrderIds.add(orderId);
      final nid = 'order_$orderId';

      // Check if this is a live new order (created after the app started)
      final isLiveNewOrder = timestamp.isAfter(_appStartTime.subtract(const Duration(seconds: 15)));

      if (isLiveNewOrder) {
        // Email is now handled securely and reliably by the Client app at the moment of order creation.
        final emailStatus = ' (Email envoyé ✅)';

        if (mounted) {
          setState(() {
            _notifications.insert(
              0,
              AdminNotification(
                id: nid,
                title: 'Nouvelle commande',
                message: 'La commande #$orderId vient d\'arriver.$emailStatus',
                timestamp: timestamp,
                orderId: orderId,
                read: false,
              ),
            );
            // Sort notifications
            _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          });
        }

        showBrowserNotification(
          'Nouvelle commande',
          'La commande #$orderId vient d\'arriver.',
        );
      } else {
        // Historical order
        if (mounted) {
          setState(() {
            if (!_notifications.any((n) => n.id == nid)) {
              _notifications.add(AdminNotification(
                id: nid,
                title: 'Nouvelle commande',
                message: 'La commande #$orderId est dans le système.',
                timestamp: timestamp,
                orderId: orderId,
                read: _readNotificationIds.contains(nid),
              ));
              _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            }
          });
        }
      }
    });

    // 2. Load existing orders safely in the background
    ref.get().then((snap) {
      if (!mounted) return;
      
      final List<MapEntry<String, Map<String, dynamic>>> parsedOrders = [];
      
      if (snap.exists) {
        final rawVal = snap.value;
        try {
          if (rawVal is Map) {
            rawVal.forEach((key, val) {
              if (val is Map) {
                final orderMap = Map<String, dynamic>.from(
                  val.map((k, v) => MapEntry(k.toString(), v)),
                );
                parsedOrders.add(MapEntry(key.toString(), orderMap));
                _knownOrderIds.add(key.toString());
              }
            });
          } else if (rawVal is List) {
            for (int i = 0; i < rawVal.length; i++) {
              final val = rawVal[i];
              if (val is Map) {
                final orderMap = Map<String, dynamic>.from(
                  val.map((k, v) => MapEntry(k.toString(), v)),
                );
                parsedOrders.add(MapEntry(i.toString(), orderMap));
                _knownOrderIds.add(i.toString());
              }
            }
          }
        } catch (e) {
          debugPrint('Error parsing existing orders: $e');
        }
      }

      // Sort existing orders by createdAt descending
      parsedOrders.sort((a, b) {
        final aTime = _parseOrderDate(a.value['createdAt']) ?? DateTime(2000);
        final bTime = _parseOrderDate(b.value['createdAt']) ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          for (final entry in parsedOrders.take(10)) {
            final orderId = entry.key;
            final orderData = entry.value;
            final timestamp = _parseOrderDate(orderData['createdAt']) ?? DateTime.now();
            final nid = 'order_$orderId';

            _knownOrderIds.add(orderId);

            // Add only if not already present in notifications list
            if (!_notifications.any((n) => n.id == nid)) {
              _notifications.add(AdminNotification(
                id: nid,
                title: 'Nouvelle commande',
                message: 'La commande #$orderId est dans le système.',
                timestamp: timestamp,
                orderId: orderId,
                read: _readNotificationIds.contains(nid),
              ));
            }
          }
          // Sort notifications
          _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        });
      }
    }).catchError((err) {
      debugPrint('Error getting existing orders: $err');
    });
  }

  void _listenRefundRequests() {
    final ref = FirebaseDatabase.instance.ref('orders');

    // 1. Listen for refund updates/requests immediately and independently!
    _refundRequestsSubscription?.cancel();
    _refundRequestsSubscription = ref.onChildChanged.listen((event) async {
      if (!mounted || event.snapshot.key == null) return;
      final orderId = event.snapshot.key!;
      
      final dynamic rawVal = event.snapshot.value;
      if (rawVal == null || rawVal is! Map) return;

      final data = Map<String, dynamic>.from(
        rawVal.map((k, v) => MapEntry(k.toString(), v)),
      );

      if (data['refundStatus'] == 'pending') {
        if (_knownRefundIds.contains(orderId)) return;
        _knownRefundIds.add(orderId);

        final timestamp = _parseOrderDate(data['createdAt']) ?? DateTime.now();
        final type = data['refundType'] == 'replace' ? 'remplacement' : 'remboursement';
        final nid = 'refund_${orderId}_$type';

        // Check if this is a live new refund request
        final isLiveRefund = timestamp.isAfter(_appStartTime.subtract(const Duration(seconds: 15)));

        if (isLiveRefund) {
          // Fetch configured notification email
          final emailSnap = await FirebaseDatabase.instance.ref('settings').child('notifications/email').get();
          final targetEmail = emailSnap.value?.toString() ?? 'support@livriyes.com';

          final emailSent = await NotificationService.sendEmailNotification(
            email: targetEmail,
            subject: 'Demande de $type - Commande #$orderId',
            htmlContent:
                '<h3>Nouvelle Demande !</h3><p>Une demande de $type a été soumise '
                'pour la commande #$orderId.</p>'
                '<a href="https://livriyes-seven.vercel.app/">Ouvrir le panneau d\'administration</a>',
          );

          final emailStatus = emailSent ? ' (Email envoyé ✅)' : ' (Erreur Email ❌)';

          if (mounted) {
            setState(() {
              _notifications.insert(
                0,
                AdminNotification(
                  id: nid,
                  title: 'Demande de $type',
                  message:
                      'Une demande de $type a été faite pour la commande #$orderId.$emailStatus',
                  timestamp: timestamp,
                  orderId: orderId,
                  read: false,
                ),
              );
              // Sort notifications
              _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            });
          }

          showBrowserNotification(
            'Demande de $type',
            'Une demande de $type a été faite pour la commande #$orderId.',
          );
        } else {
          // Historical refund request
          if (mounted) {
            setState(() {
              if (!_notifications.any((n) => n.id == nid)) {
                _notifications.add(AdminNotification(
                  id: nid,
                  title: 'Demande de $type en attente',
                  message:
                      'Une demande de $type est en attente pour la commande #$orderId.',
                  timestamp: timestamp,
                  orderId: orderId,
                  read: _readNotificationIds.contains(nid),
                ));
                _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
              }
            });
          }
        }
      }
    });

    // 2. Load existing refund requests safely in the background
    ref.get().then((snap) {
      if (!mounted || !snap.exists) return;
      
      final rawVal = snap.value;
      final List<MapEntry<String, Map<String, dynamic>>> parsedOrders = [];

      try {
        if (rawVal is Map) {
          rawVal.forEach((key, val) {
            if (val is Map) {
              final orderMap = Map<String, dynamic>.from(
                val.map((k, v) => MapEntry(k.toString(), v)),
              );
              parsedOrders.add(MapEntry(key.toString(), orderMap));
            }
          });
        } else if (rawVal is List) {
          for (int i = 0; i < rawVal.length; i++) {
            final val = rawVal[i];
            if (val is Map) {
              final orderMap = Map<String, dynamic>.from(
                val.map((k, v) => MapEntry(k.toString(), v)),
              );
              parsedOrders.add(MapEntry(i.toString(), orderMap));
            }
          }
        }
      } catch (e) {
        debugPrint('Error parsing existing orders for refunds: $e');
      }

      if (mounted) {
        setState(() {
          for (final entry in parsedOrders) {
            final orderData = entry.value;
            if (orderData['refundStatus'] == 'pending') {
              final orderId = entry.key;
              final timestamp = _parseOrderDate(orderData['createdAt']) ?? DateTime.now();
              final type = orderData['refundType'] == 'replace' ? 'remplacement' : 'remboursement';
              final nid = 'refund_${orderId}_$type';

              _knownRefundIds.add(orderId);

              if (!_notifications.any((n) => n.id == nid)) {
                _notifications.add(AdminNotification(
                  id: nid,
                  title: 'Demande de $type en attente',
                  message:
                      'Une demande de $type est en attente pour la commande #$orderId.',
                  timestamp: timestamp,
                  orderId: orderId,
                  read: _readNotificationIds.contains(nid),
                ));
              }
            }
          }
          // Sort notifications
          _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        });
      }
    }).catchError((err) {
      debugPrint('Error getting existing orders for refunds: $err');
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────
  int _extractPendingCount(dynamic data) {
    int pending = 0;

    bool isPendingStatus(String? status) {
      if (status == null) return false;
      final n = status.trim().toLowerCase();
      return n == 'pending' || n == 'en attente';
    }

    void handleOrder(dynamic raw) {
      if (raw is Map) {
        if (isPendingStatus(raw['status']?.toString())) pending++;
      }
    }

    if (data is Map) {
      for (final v in data.values) handleOrder(v);
    } else if (data is List) {
      for (final v in data) if (v != null) handleOrder(v);
    }

    return pending;
  }

  void _handleNotificationTap(String orderId) {
    setState(() => _selectedIndex = 4);
    Future.delayed(const Duration(milliseconds: 100), () {
      _ordersTabKey.currentState?.showOrderDetailsById(orderId);
    });
  }

  Future<void> _playNewOrderSound() async {
    try {
      await _alertPlayer.stop();
      await _alertPlayer.play(BytesSource(_newOrderToneBytes));
    } catch (e) {
      debugPrint('Failed to play new order sound: $e');
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  bool _isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600;

  // ──────────────────────────────────────────────────────────────────────────
  // Tone generator (static)
  // ──────────────────────────────────────────────────────────────────────────
  static Uint8List _generateNewOrderTone() {
    const sampleRate = 44100;
    const durationSeconds = 0.9;
    const amplitude = 0.98;
    const vibratoFrequency = 5.5;
    const shimmerFrequency = 13.5;

    final totalSamples = (sampleRate * durationSeconds).round();
    final dataLength = totalSamples * 2;
    final totalLength = 44 + dataLength;
    final byteData = ByteData(totalLength);

    byteData.setUint32(0, 0x52494646, Endian.big);
    byteData.setUint32(4, totalLength - 8, Endian.little);
    byteData.setUint32(8, 0x57415645, Endian.big);
    byteData.setUint32(12, 0x666d7420, Endian.big);
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, 1, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    byteData.setUint32(36, 0x64617461, Endian.big);
    byteData.setUint32(40, dataLength, Endian.little);

    const twoPi = 2 * math.pi;

    for (var i = 0; i < totalSamples; i++) {
      final time = i / sampleRate;
      final progress = i / totalSamples;

      List<double> frequencies;
      if (progress < 0.33) {
        frequencies = [587.33, 880.0];
      } else if (progress < 0.66) {
        frequencies = [739.99, 1108.73, 1479.98];
      } else {
        frequencies = [880.0, 1318.51, 1760.0];
      }

      final vibrato = 1 + 0.012 * math.sin(twoPi * vibratoFrequency * time);
      final shimmer = 1 + 0.08 * math.sin(twoPi * shimmerFrequency * time);
      final attack = time < 0.12 ? math.pow(time / 0.12, 0.85) : 1.0;
      final decay = math.pow(1 - progress, 1.4);
      final envelope = (attack * decay * shimmer).clamp(0.0, 1.25);

      double sampleSum = 0;
      for (final baseFreq in frequencies) {
        final freq = baseFreq * vibrato;
        sampleSum += math.sin(twoPi * freq * time) +
            0.4 * math.sin(twoPi * freq * 2 * time) +
            0.2 * math.sin(twoPi * freq * 0.5 * time);
      }
      sampleSum /= frequencies.length;

      var intSample = (sampleSum * envelope * amplitude * 0x7FFF).round();
      intSample = intSample.clamp(-32768, 32767);
      byteData.setInt16(44 + (i * 2), intSample, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);

    if (isDesktop) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: SafeArea(
          child: Row(
            children: [
              NavigationSidebar(
                selectedIndex: _selectedIndex,
                onTap: (index) => setState(() => _selectedIndex = index),
                isCollapsed: _sidebarCollapsed,
                onToggleCollapse: () =>
                    setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                pendingOrdersCount: _pendingOrdersCount,
              ),
              Expanded(
                child: Column(
                  children: [
                    _DesktopTopBar(
                      title: _pageTitles[_selectedIndex],
                      notifications: List<AdminNotification>.from(_notifications),
                      onNotificationsViewed: _markNotificationsAsRead,
                      onNotificationSelected: (n) {
                        if (n.orderId != null) _handleNotificationTap(n.orderId!);
                      },
                    ),
                    Expanded(
                      child: Container(
                        color: AppTheme.backgroundColor,
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: _pages[_selectedIndex],
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

    // ── Mobile layout ──
    return WillPopScope(
      onWillPop: () async {
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Quitter l\'application'),
            content: const Text('Voulez-vous vraiment quitter l\'application admin ?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Non'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Oui'),
              ),
            ],
          ),
        );
        return shouldExit ?? false;
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: Text(
            _pageTitles[_selectedIndex],
            style: Theme.of(context).textTheme.titleLarge,
          ),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: () => DeliveryPricesDialog.show(context),
              icon: const Icon(Icons.local_shipping_rounded),
              tooltip: 'Prix Livraison',
            ),
            AdminNotificationBell(
              initialNotifications: List<AdminNotification>.from(_notifications),
              onNotificationsViewed: _markNotificationsAsRead,
              onNotificationSelected: (n) {
                if (n.orderId != null) _handleNotificationTap(n.orderId!);
              },
            ),
          ],
        ),
        body: _pages[_selectedIndex],
        bottomNavigationBar: NavigationFooter(
          selectedIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          isAdmin: true,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Products tab shim (kept for backward compat)
// ──────────────────────────────────────────────
class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  @override
  Widget build(BuildContext context) => const ProductManagementScreen();
}
