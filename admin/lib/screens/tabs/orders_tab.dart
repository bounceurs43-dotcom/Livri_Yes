import 'dart:async';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lottie/lottie.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_search_bar.dart';
import '../../services/notification_service.dart';
import '../../firebase_options.dart';
import '../../services/product_service.dart';
import '../../models/product_models.dart';
import '../../utils/web_safe_image.dart';
import '../../services/realtime_database_service.dart';

class _StatusVisuals {
  final Color color;
  final String label;
  final IconData icon;
  final int stageIndex;

  const _StatusVisuals({
    required this.color,
    required this.label,
    required this.icon,
    required this.stageIndex,
  });
}

class _ClientProfile {
  final String name;
  final String? photoUrl;
  final String? email;
  final String? phone;

  const _ClientProfile({
    required this.name,
    this.photoUrl,
    this.email,
    this.phone,
  });
}

class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});

  @override
  State<OrdersTab> createState() => OrdersTabState();
}

class OrdersTabState extends State<OrdersTab>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<Map<String, dynamic>> _allOrders = [];
  late TabController _tabController;
  StreamSubscription<DatabaseEvent>? _ordersSubscription;
  StreamSubscription<DatabaseEvent>? _usersSubscription;
  String _searchQuery = '';
  final Map<String, _ClientProfile> _clientProfiles = {};
  final Set<String> _pdfInProgress = <String>{};
  bool _bulkExporting = false;
  List<Category> _categories = [];

  // Selection mode state
  bool _isSelectionMode = false;
  final Set<String> _selectedOrderIds = {};
  bool _deleting = false;
  static const List<String> _tabStatusKeys = [
    'pending',
    'processing',
    'delivered',
  ];
  static const Map<String, String> _tabDisplayLabels = {
    'pending': 'En attente',
    'processing': 'En livraison',
    'delivered': 'Terminée',
  };

  _StatusVisuals _resolveStatusVisuals(String status) {
    final normalized = status.toLowerCase();

    if (normalized == 'pending' || normalized == 'en attente') {
      return _StatusVisuals(
        color: AppTheme.warningColor,
        label: 'En attente',
        icon: Icons.watch_later_rounded,
        stageIndex: 0,
      );
    }

    if (normalized == 'processing' ||
        normalized == 'en cours' ||
        normalized == 'en cours de livraison' ||
        normalized == 'livraison') {
      return _StatusVisuals(
        color: AppTheme.accentColor,
        label: 'En livraison',
        icon: Icons.local_shipping_outlined,
        stageIndex: 2,
      );
    }

    if (normalized == 'awaiting_confirmation' ||
        normalized == 'validation' ||
        normalized == 'client_confirmed') {
      return _StatusVisuals(
        color: AppTheme.warningColor,
        label: 'Code à valider',
        icon: Icons.verified_outlined,
        stageIndex: 3,
      );
    }

    if (normalized == 'delivered' ||
        normalized == 'livré' ||
        normalized == 'delivre' ||
        normalized == 'delivré' ||
        normalized == 'termines' ||
        normalized == 'terminé' ||
        normalized == 'termine') {
      return _StatusVisuals(
        color: AppTheme.successColor,
        label: 'Terminée',
        icon: Icons.task_alt,
        stageIndex: 3,
      );
    }

    if (normalized == 'awaiting_confirmation' ||
        normalized == 'validation' ||
        normalized == 'client_confirmed') {
      return _StatusVisuals(
        color: AppTheme.warningColor,
        label: 'Code à valider',
        icon: Icons.verified_outlined,
        stageIndex: 3,
      );
    }

    return _StatusVisuals(
      color: AppTheme.textSecondary,
      label: status,
      icon: Icons.info_outline_rounded,
      stageIndex: 0,
    );
  }

  double _safeToDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  Future<({pw.Font base, pw.Font bold})> _loadPdfFonts() async {
    try {
      final regular = await PdfGoogleFonts.interRegular();
      final bold = await PdfGoogleFonts.interSemiBold();
      return (base: regular, bold: bold);
    } catch (e) {
      debugPrint('PDF font download failed, fallback to Helvetica: $e');
      return (base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
    }
  }

  List<pw.Widget> _buildGroupedItemsPdf(
    List<Map<String, dynamic>> items,
    pw.Font boldFont,
    String Function(double) formatCurrency,
  ) {
    if (items.isEmpty) return [];

    // Group items by categoryId
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var item in items) {
      String categoryId = (item['categoryId'] ?? 'Autres').toString();
      if (!grouped.containsKey(categoryId)) {
        grouped[categoryId] = [];
      }
      grouped[categoryId]!.add(item);
    }

    List<pw.Widget> widgets = [];

    for (var entry in grouped.entries) {
      String categoryId = entry.key;
      String categoryName = categoryId; // Default to ID
      try {
        final cat = _categories.firstWhere((c) => c.id == categoryId);
        categoryName = cat.name;
      } catch (_) {
        if (categoryId == 'Autres') categoryName = 'Autres';
      }

      final itemRows = entry.value.map((item) {
        final name = (item['productName'] ?? 'Produit').toString();
        final qty = _formatQuantity(item['quantity']);
        final unit = (item['unit'] ?? '').toString();
        final itemTotal =
            _safeToDouble(item['totalPrice'] ?? item['price'] ?? 0);
        return [
          name,
          unit.isNotEmpty ? '$qty $unit' : qty,
          formatCurrency(itemTotal),
        ];
      }).toList();

      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(
            categoryName.toUpperCase(),
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 12,
              color: PdfColors.deepOrange600,
            ),
          ),
        ),
      );

      widgets.add(
        pw.TableHelper.fromTextArray(
          headers: ['Produit', 'Quantité', 'Total'],
          data: itemRows,
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.deepOrange400,
          ),
          headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
          ),
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: {
            0: const pw.FlexColumnWidth(2.5),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(1.2),
          },
        ),
      );
      widgets.add(pw.SizedBox(height: 14));
    }

    return widgets;
  }

  Future<Uint8List> _createOrderPdf(Map<String, dynamic> order) async {
    final doc = pw.Document();
    final fonts = await _loadPdfFonts();
    final regularFont = fonts.base;
    final boldFont = fonts.bold;
    final pdfTheme = pw.ThemeData.withFont(base: regularFont, bold: boldFont);
    final orderId = _resolveOrderId(order);
    final statusVisuals = _resolveStatusVisuals(
      (order['status'] ?? '').toString(),
    );
    final customerName =
        (order['customerName'] ?? order['userName'] ?? 'Client').toString();
    final deliveryAddress =
        (order['deliveryAddress'] ?? 'Adresse non spécifiée').toString();
    final phone = (order['phone'] ?? order['phoneNumber'] ?? 'Non fourni')
        .toString();
    final receiverName = (order['receiverName'] ?? '').toString();
    final receiverPhone = (order['receiverPhone'] ?? '').toString();
    final hasReceiver =
        receiverName.trim().isNotEmpty || receiverPhone.trim().isNotEmpty;
    final createdAt = _parseOrderDate(order['createdAt']);
    final formattedDate = _formatOrderDate(createdAt);

    final items = _extractOrderItems(order);
    final cartTotal = _safeToDouble(order['cartTotal']);
    final deliveryFee = _safeToDouble(order['deliveryFee']);
    final expressFee = _safeToDouble(order['expressFee']);
    final tip = _safeToDouble(order['tip']);
    final total = _safeToDouble(order['total']);

    String formatCurrency(double value) => '${value.toString()} €';

    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        theme: pdfTheme,
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(24),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [PdfColors.orange400, PdfColors.deepOrange600],
              ),
              borderRadius: pw.BorderRadius.circular(18),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'LivriYes',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    font: boldFont,
                    fontSize: 22,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Récapitulatif de commande',
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 14),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'Commande #$orderId',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    font: boldFont,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(16),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Informations client',
                  style: pw.TextStyle(font: boldFont, fontSize: 15),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Client: $customerName',
                  style: pw.TextStyle(font: boldFont, fontSize: 14),
                ),
                pw.Text(
                  'Téléphone: $phone',
                  style: pw.TextStyle(font: boldFont, fontSize: 14),
                ),
                pw.SizedBox(height: 6),
                pw.Text('Adresse: $deliveryAddress'),
                if (hasReceiver) ...[
                  pw.Text(
                    'Destinataire: '
                    '${receiverName.trim().isEmpty ? '—' : receiverName.trim()}',
                  ),
                  if (receiverPhone.trim().isNotEmpty)
                    pw.Text('Téléphone destinataire: ${receiverPhone.trim()}'),
                ],
                pw.Text('Date: $formattedDate'),
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(12),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Container(
                        width: 12,
                        height: 12,
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(
                            statusVisuals.color.toARGB32(),
                          ),
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Text(
                        statusVisuals.label,
                        style: pw.TextStyle(font: boldFont),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ..._buildGroupedItemsPdf(items, boldFont, formatCurrency),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(16),
            ),
            child: pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Sous-total'),
                    pw.Text(formatCurrency(cartTotal)),
                  ],
                ),
                if (deliveryFee > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Frais de livraison'),
                      pw.Text(formatCurrency(deliveryFee)),
                    ],
                  ),
                if (expressFee > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Livraison express'),
                      pw.Text(formatCurrency(expressFee)),
                    ],
                  ),
                if (tip > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Pourboire'),
                      pw.Text(formatCurrency(tip)),
                    ],
                  ),
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total encaissé',
                      style: pw.TextStyle(font: boldFont),
                    ),
                    pw.Text(
                      formatCurrency(total),
                      style: pw.TextStyle(font: boldFont),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (order['notes'] != null &&
              order['notes'].toString().trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'Notes internes',
              style: pw.TextStyle(font: boldFont, fontSize: 14),
            ),
            pw.SizedBox(height: 6),
            pw.Text(order['notes'].toString()),
          ],
        ],
      ),
    );

    return doc.save();
  }

  Future<void> _exportOrderAsPdf(Map<String, dynamic> order) async {
    final orderId = _resolveOrderId(order);
    if (orderId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Commande introuvable pour PDF'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    if (_pdfInProgress.contains(orderId)) return;

    setState(() => _pdfInProgress.add(orderId));
    try {
      final bytes = await _createOrderPdf(order);
      final printingInfo = await Printing.info();
      String successMessage;

      if (printingInfo.canShare) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'commande_admin_$orderId.pdf',
        );
        successMessage =
            'PDF généré pour la commande #$orderId et prêt à être partagé.';
      } else if (printingInfo.canPrint || kIsWeb) {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
        successMessage =
            'Aperçu du reçu ouvert — vous pouvez l\'imprimer ou l\'enregistrer.';
      } else {
        throw UnsupportedError(
          'Le partage de PDF n\'est pas disponible sur cet appareil.',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is UnsupportedError
                  ? e.message ??
                        'Le partage de PDF n\'est pas disponible sur cet appareil.'
                  : 'Erreur: $e',
            ),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pdfInProgress.remove(orderId));
      } else {
        _pdfInProgress.remove(orderId);
      }
    }
  }

  DateTime? _parseOrderDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  String _formatOrderDate(DateTime? date) {
    if (date == null) return 'Date indisponible';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/$year · $hour:$minute';
  }

  List<Map<String, dynamic>> _extractOrderItems(Map<String, dynamic> order) {
    final rawItems = order['items'];
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map>()
        .map((element) => Map<String, dynamic>.from(element))
        .toList();
  }

  String _formatQuantity(dynamic value) {
    if (value is num) {
      return value % 1 == 0
          ? value.toInt().toString()
          : value.toStringAsFixed(1);
    }
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return '1';
  }

  Widget _buildStatusTimeline(int activeStage, Color accentColor) {
    final stages = [
      {'icon': Icons.receipt_long, 'label': 'Reçue'},
      {'icon': Icons.inventory_2_rounded, 'label': 'Préparation'},
      {'icon': Icons.local_shipping_outlined, 'label': 'Livraison'},
      {'icon': Icons.verified_rounded, 'label': 'Terminée'},
    ];

    final clampedStage = activeStage.clamp(0, stages.length - 1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(stages.length, (index) {
        final isReached = index <= clampedStage;
        final isCurrent = index == clampedStage;
        final hasLeftConnector = index > 0;
        final hasRightConnector = index < stages.length - 1;

        BoxDecoration _connectorDecoration(bool active) => BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [
                    accentColor.withValues(alpha: 0.7),
                    accentColor.withValues(alpha: 0.2),
                  ]
                : [
                    AppTheme.textLight.withValues(alpha: 0.5),
                    AppTheme.textLight.withValues(alpha: 0.2),
                  ],
          ),
        );

        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: EdgeInsets.only(
                          right: hasLeftConnector ? 8 : 0,
                        ),
                        decoration: hasLeftConnector
                            ? _connectorDecoration(index - 1 <= clampedStage)
                            : const BoxDecoration(color: Colors.transparent),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isReached
                            ? accentColor.withValues(alpha: 0.15)
                            : Colors.white,
                        border: Border.all(
                          color: isReached ? accentColor : AppTheme.textLight,
                          width: 2,
                        ),
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: accentColor.withValues(alpha: 0.28),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        stages[index]['icon'] as IconData,
                        size: 16,
                        color: isReached ? accentColor : AppTheme.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: EdgeInsets.only(
                          left: hasRightConnector ? 8 : 0,
                        ),
                        decoration: hasRightConnector
                            ? _connectorDecoration(index < clampedStage)
                            : const BoxDecoration(color: Colors.transparent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                stages[index]['label'] as String,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isReached
                      ? accentColor
                      : AppTheme.textSecondary.withValues(alpha: 0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildInfoChip(
    IconData icon,
    String label, {
    Color? textColor,
    Color? backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.textLight.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor ?? AppTheme.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: textColor ?? AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          // Exit selection mode when changing tabs
          _isSelectionMode = false;
          _selectedOrderIds.clear();
        });
      }
    });
    _setupRealtimeListener();
    _setupClientProfilesListener();
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
      debugPrint('Error loading categories for orders tab: $e');
    }
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _usersSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _setupRealtimeListener() {
    setState(() => _loading = true);
    final db = FirebaseDatabase.instance;
    final ref = db.ref('orders');

    _ordersSubscription = ref.onValue.listen(
      (event) {
        if (!mounted) return;
        List<Map<String, dynamic>> found = [];

        if (event.snapshot.exists) {
          final value = event.snapshot.value;
          if (value is Map) {
            value.forEach((id, orderData) {
              if (orderData != null && orderData is Map) {
                final orderMap = Map<String, dynamic>.from(orderData);
                orderMap['id'] = orderMap['orderId'] ?? id;
                found.add(orderMap);
              }
            });
          }
        }

        found.sort((a, b) {
          final aTime = a['createdAt'] is int
              ? a['createdAt'] as int
              : (a['createdAt'] is String
                    ? DateTime.tryParse(
                            a['createdAt'],
                          )?.millisecondsSinceEpoch ??
                          0
                    : 0);
          final bTime = b['createdAt'] is int
              ? b['createdAt'] as int
              : (b['createdAt'] is String
                    ? DateTime.tryParse(
                            b['createdAt'],
                          )?.millisecondsSinceEpoch ??
                          0
                    : 0);
          return bTime.compareTo(aTime);
        });

        if (mounted) {
          setState(() {
            _allOrders = found;
            _loading = false;
          });
        }
      },
      onError: (error) {
        debugPrint('Error listening to orders: $error');
        if (mounted) {
          setState(() => _loading = false);
        }
      },
    );
  }

  void _setupClientProfilesListener() {
    final db = FirebaseDatabase.instance;
    final ref = db.ref('users');

    _usersSubscription = ref.onValue.listen(
      (event) {
        if (!mounted) return;

        final Map<String, _ClientProfile> resolved = {};

        if (event.snapshot.exists && event.snapshot.value is Map) {
          final raw = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
          raw.forEach((key, value) {
            if (value is Map) {
              final data = Map<dynamic, dynamic>.from(value);
              final name =
                  _resolveStringCandidate(data['name']) ??
                  _resolveStringCandidate(data['displayName']) ??
                  _resolveStringCandidate(data['fullName']) ??
                  _resolveStringCandidate(data['username']) ??
                  'Client';
              final photo = _resolveStringCandidate(
                data['photoUrl'] ?? data['photoURL'] ?? data['avatar'],
              );
              final email = _resolveStringCandidate(
                data['email'] ?? data['mail'] ?? data['contactEmail'],
              );
              final phone = _resolveStringCandidate(
                data['phone'] ?? data['phoneNumber'] ?? data['contactPhone'],
              );
              resolved[key.toString()] = _ClientProfile(
                name: name,
                photoUrl: photo,
                email: email,
                phone: phone,
              );
            }
          });
        }

        setState(() {
          _clientProfiles
            ..clear()
            ..addAll(resolved);
        });
      },
      onError: (error) =>
          debugPrint('Error listening to user profiles for orders: $error'),
    );
  }

  String? _resolveStringCandidate(dynamic value) {
    if (value == null) return null;
    final candidate = value.toString().trim();
    if (candidate.isEmpty) return null;
    if (candidate.toLowerCase() == 'null') return null;
    return candidate;
  }

  String _resolveCustomerName(Map<String, dynamic> order) {
    final userId = _resolveStringCandidate(order['userId']);
    if (userId != null) {
      final profile = _clientProfiles[userId];
      if (profile != null && profile.name.trim().isNotEmpty) {
        return profile.name;
      }
    }

    final keys = [
      'customerName',
      'clientName',
      'fullName',
      'name',
      'userName',
      'customer',
      'contactName',
    ];

    for (final key in keys) {
      final value = _resolveStringCandidate(order[key]);
      if (value != null &&
          value.isNotEmpty &&
          value.toLowerCase() != 'client') {
        return value;
      }
    }

    final customer = order['customer'];
    if (customer is Map) {
      final nested =
          _resolveStringCandidate(customer['name']) ??
          _resolveStringCandidate(customer['fullName']) ??
          _resolveStringCandidate(customer['displayName']);
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }
    }

    return 'Client';
  }

  String? _resolveCustomerPhoto(Map<String, dynamic> order) {
    final userId = _resolveStringCandidate(order['userId']);
    if (userId != null) {
      final profile = _clientProfiles[userId];
      if (profile != null && profile.photoUrl != null) {
        final trimmed = profile.photoUrl!.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }

    final keys = [
      'photoUrl',
      'photoURL',
      'avatar',
      'customerPhoto',
      'clientPhoto',
    ];

    for (final key in keys) {
      final value = _resolveStringCandidate(order[key]);
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    final customer = order['customer'];
    if (customer is Map) {
      final nested = _resolveStringCandidate(customer['photo']);
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }
    }

    return null;
  }

  String? _resolveCustomerEmail(Map<String, dynamic> order) {
    final userId = _resolveStringCandidate(order['userId']);
    if (userId != null) {
      final profile = _clientProfiles[userId];
      final email = profile?.email;
      if (email != null && email.trim().isNotEmpty) {
        return email.trim();
      }
    }

    final keys = ['email', 'customerEmail', 'contactEmail', 'userEmail'];

    for (final key in keys) {
      final candidate = _resolveStringCandidate(order[key]);
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }

    final customer = order['customer'];
    if (customer is Map) {
      final nested = _resolveStringCandidate(
        customer['email'] ?? customer['contactEmail'],
      );
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }
    }

    return null;
  }

  String? _resolveCustomerPhone(
    Map<String, dynamic> order, {
    String? fallback,
  }) {
    final userId = _resolveStringCandidate(order['userId']);
    if (userId != null) {
      final profile = _clientProfiles[userId];
      final phone = profile?.phone;
      if (phone != null && phone.trim().isNotEmpty) {
        return phone.trim();
      }
    }

    final keys = [
      'phone',
      'phoneNumber',
      'contactPhone',
      'customerPhone',
      'mobile',
    ];

    for (final key in keys) {
      final candidate = _resolveStringCandidate(order[key]);
      if (candidate != null && candidate.isNotEmpty && candidate != '—') {
        return candidate;
      }
    }

    final customer = order['customer'];
    if (customer is Map) {
      final nested = _resolveStringCandidate(
        customer['phone'] ?? customer['phoneNumber'] ?? customer['mobile'],
      );
      if (nested != null && nested.isNotEmpty && nested != '—') {
        return nested;
      }
    }

    final resolvedFallback = _resolveStringCandidate(fallback);
    if (resolvedFallback != null && resolvedFallback != '—') {
      return resolvedFallback;
    }
    return null;
  }

  bool _looksLikeCoordinates(String value) {
    final cleaned = value.trim();
    return RegExp(r'^-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?$').hasMatch(cleaned);
  }

  String _resolveDeliveryLabel(Map<String, dynamic> order) {
    final commune = _resolveStringCandidate(order['commune']);
    final wilaya = _resolveStringCandidate(order['wilaya']);
    if (commune != null && wilaya != null) {
      return '$commune, $wilaya';
    }
    if (wilaya != null) {
      return wilaya;
    }

    final address =
        _resolveStringCandidate(order['deliveryAddress'] ?? order['address']) ??
        '';
    if (address.isNotEmpty && !_looksLikeCoordinates(address)) {
      return address;
    }

    final candidates = [
      order['deliveryLabel'],
      order['addressLabel'],
      order['customerAddressLabel'],
      order['addressName'],
    ];

    for (final candidate in candidates) {
      final resolved = _resolveStringCandidate(candidate);
      if (resolved != null) {
        return resolved;
      }
    }

    if (address.isNotEmpty && _looksLikeCoordinates(address)) {
      return 'Position partagée';
    }
    return 'Adresse non renseignée';
  }

  Widget _buildCopyableRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                SelectableText(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.primaryColor),
            tooltip: 'Copier',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copié dans le presse-papier : $value'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: AppTheme.successColor,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showLocationDetailsModal(Map<String, dynamic> order) {
    final wilaya = _resolveStringCandidate(order['wilaya']) ?? 'Non renseignée';
    final commune = _resolveStringCandidate(order['commune']) ?? 'Non renseignée';
    final fullAddress = (order['deliveryAddress'] ?? order['fullAddress'] ?? order['address'] ?? 'Non renseignée').toString();
    final addressLabel = _resolveStringCandidate(order['deliveryLabel'] ?? order['addressLabel']);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.location_on_rounded, color: AppTheme.primaryColor, size: 26),
            const SizedBox(width: 10),
            const Text('Lieu de livraison', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (addressLabel != null && addressLabel.isNotEmpty) ...[
              _buildCopyableRow('Libellé adresse', addressLabel),
              const SizedBox(height: 8),
            ],
            _buildCopyableRow('Wilaya', wilaya),
            const SizedBox(height: 8),
            _buildCopyableRow('Commune', commune),
            const SizedBox(height: 8),
            _buildCopyableRow('Adresse exacte', fullAddress),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openMap(fullAddress);
            },
            icon: const Icon(Icons.map_outlined),
            label: const Text('Ouvrir Maps'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _showClientInfoModal(Map<String, dynamic> order) {
    final customerName = _resolveCustomerName(order);
    final fallbackPhone = (order['phone'] ?? order['phoneNumber'] ?? 'Non fourni').toString();
    final phone = _resolveCustomerPhone(order, fallback: fallbackPhone) ?? 'Non fourni';
    final email = _resolveCustomerEmail(order) ?? 'Non renseigné';
    final receiverName = (order['receiverName'] ?? '').toString().trim();
    final receiverPhone = (order['receiverPhone'] ?? '').toString().trim();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.person_rounded, color: AppTheme.primaryColor, size: 26),
            const SizedBox(width: 10),
            const Text('Informations du client', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCopyableRow('Nom du client', customerName),
            const SizedBox(height: 8),
            _buildCopyableRow('Téléphone', phone),
            const SizedBox(height: 8),
            _buildCopyableRow('Email / Compte', email),
            if (receiverName.isNotEmpty || receiverPhone.isNotEmpty) ...[
              const Divider(height: 18),
              Text('Destinataire', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 12)),
              const SizedBox(height: 6),
              if (receiverName.isNotEmpty) _buildCopyableRow('Nom destinataire', receiverName),
              if (receiverPhone.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildCopyableRow('Tél. destinataire', receiverPhone),
              ],
            ],
          ],
        ),
        actions: [
          if (phone != 'Non fourni')
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _makePhoneCall(phone);
              },
              icon: const Icon(Icons.phone_outlined),
              label: const Text('Appeler'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String name, {String? photoUrl, double size = 26}) {
    final trimmed = name.trim();
    final display = trimmed.isNotEmpty ? trimmed : 'Client';
    final initial = display.isNotEmpty ? display[0].toUpperCase() : 'C';

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
      backgroundImage: photoUrl != null && photoUrl.isNotEmpty
          ? NetworkImage(photoUrl)
          : null,
      child: photoUrl == null || photoUrl.isEmpty
          ? Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
                fontSize: size * 0.5,
              ),
            )
          : null,
    );
  }

  Widget _buildClientChip(String name, {String? photoUrl}) {
    final trimmed = name.trim();
    final display = trimmed.isNotEmpty ? trimmed : 'Client';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.textLight.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAvatar(display, photoUrl: photoUrl, size: 26),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              display,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getOrdersByStatus(String status) {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = _allOrders.where((order) {
      final orderStatus = (order['status'] ?? 'pending')
          .toString()
          .toLowerCase();
      final searchStatus = status.toLowerCase();

      if (searchStatus == 'en attente' || searchStatus == 'pending') {
        return orderStatus == 'pending' || orderStatus == 'en attente';
      }
      if (searchStatus == 'en cours' || searchStatus == 'processing') {
        return orderStatus == 'processing' ||
            orderStatus == 'en cours' ||
            orderStatus == 'en cours de livraison' ||
            orderStatus == 'livraison' ||
            orderStatus == 'awaiting_confirmation';
      }
      if (searchStatus == 'livré' ||
          searchStatus == 'delivered' ||
          searchStatus == 'delivre') {
        return orderStatus == 'delivered' ||
            orderStatus == 'livré' ||
            orderStatus == 'delivre' ||
            orderStatus == 'termines' ||
            orderStatus == 'terminé' ||
            orderStatus == 'termine';
      }

      final matchesStatus = orderStatus == searchStatus;
      if (!matchesStatus) return false;

      if (query.isEmpty) return true;

      final customerName = (order['customerName'] ?? order['userName'] ?? '')
          .toString()
          .toLowerCase();
      final phone = (order['phone'] ?? order['phoneNumber'] ?? '')
          .toString()
          .toLowerCase();
      final address = (order['deliveryAddress'] ?? '').toString().toLowerCase();
      final orderId = (order['orderId'] ?? order['id'] ?? '')
          .toString()
          .toLowerCase();

      return customerName.contains(query) ||
          phone.contains(query) ||
          address.contains(query) ||
          orderId.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final aDate = _parseOrderDate(a['createdAt']);
      final bDate = _parseOrderDate(b['createdAt']);
      final aMillis = aDate?.millisecondsSinceEpoch ?? 0;
      final bMillis = bDate?.millisecondsSinceEpoch ?? 0;
      return bMillis.compareTo(aMillis);
    });

    return filtered;
  }

  String _statusKeyForIndex(int index) {
    if (index < 0 || index >= _tabStatusKeys.length) {
      return _tabStatusKeys.first;
    }
    return _tabStatusKeys[index];
  }

  Future<void> _exportCurrentTabOrders() async {
    final statusKey = _statusKeyForIndex(_tabController.index);
    final orders = _getOrdersByStatus(statusKey);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final displayLabel = _tabDisplayLabels[statusKey] ?? statusKey;
    final normalized = displayLabel.toLowerCase().replaceAll(' ', '_');
    final filename = 'commandes_${normalized}_$timestamp.pdf';
    await _exportOrdersAsPdf(orders, filename);
  }

  Future<void> _exportOrdersAsPdf(
    List<Map<String, dynamic>> orders,
    String filename,
  ) async {
    if (orders.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucune commande à exporter pour cet onglet.'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
      }
      return;
    }

    setState(() => _bulkExporting = true);
    try {
      final doc = pw.Document();
      final fonts = await _loadPdfFonts();
      final baseFont = fonts.base;
      final boldFont = fonts.bold;
      final theme = pw.ThemeData.withFont(base: baseFont, bold: boldFont);

      for (final order in orders) {
        final items = _extractOrderItems(order);
        final cartTotal = _safeToDouble(order['cartTotal']);
        final deliveryFee = _safeToDouble(order['deliveryFee']);
        final expressFee = _safeToDouble(order['expressFee']);
        final tip = _safeToDouble(order['tip']);
        final total = _safeToDouble(order['total']);
        final orderId = _resolveOrderId(order);
        final createdAt = _parseOrderDate(order['createdAt']);
        final formattedDate = _formatOrderDate(createdAt);
        final customerName =
            (order['customerName'] ?? order['userName'] ?? 'Client').toString();
        final deliveryAddress =
            (order['deliveryAddress'] ?? 'Adresse non spécifiée').toString();
        final phone = (order['phone'] ?? order['phoneNumber'] ?? 'Non fourni')
            .toString();
        final receiverName = (order['receiverName'] ?? '').toString();
        final receiverPhone = (order['receiverPhone'] ?? '').toString();
        final hasReceiver =
            receiverName.trim().isNotEmpty || receiverPhone.trim().isNotEmpty;
        final status = (order['status'] ?? '').toString();
        final visuals = _resolveStatusVisuals(status);

        String formatCurrency(double value) => '${value.toString()} €';

        doc.addPage(
          pw.MultiPage(
            margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 26),
            theme: theme,
            build: (context) => [
              pw.Container(
                padding: const pw.EdgeInsets.all(24),
                decoration: pw.BoxDecoration(
                  gradient: pw.LinearGradient(
                    colors: [PdfColors.orange400, PdfColors.deepOrange600],
                  ),
                  borderRadius: pw.BorderRadius.circular(18),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'LivriYes',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        font: boldFont,
                        fontSize: 22,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Récapitulatif de commande',
                      style: pw.TextStyle(color: PdfColors.white, fontSize: 14),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      orderId.isNotEmpty ? 'Commande #$orderId' : 'Commande',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        font: boldFont,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(16),
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Informations client',
                      style: pw.TextStyle(font: boldFont, fontSize: 15),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text(
                      'Client: $customerName',
                      style: pw.TextStyle(font: boldFont, fontSize: 14),
                    ),
                    pw.Text(
                      'Téléphone: $phone',
                      style: pw.TextStyle(font: boldFont, fontSize: 14),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text('Adresse: $deliveryAddress'),
                    if (hasReceiver) ...[
                      pw.Text(
                        'Destinataire: '
                        '${receiverName.trim().isEmpty ? '—' : receiverName.trim()}',
                      ),
                      if (receiverPhone.trim().isNotEmpty)
                        pw.Text(
                          'Téléphone destinataire: ${receiverPhone.trim()}',
                        ),
                    ],
                    pw.Text('Date: $formattedDate'),
                    pw.SizedBox(height: 12),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.circular(12),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Container(
                            width: 12,
                            height: 12,
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromInt(visuals.color.toARGB32()),
                              shape: pw.BoxShape.circle,
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Text(
                            visuals.label,
                            style: pw.TextStyle(font: boldFont),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Text(
                'Détails des articles',
                style: pw.TextStyle(font: boldFont, fontSize: 15),
              ),
              pw.SizedBox(height: 10),
              ..._buildGroupedItemsPdf(items, boldFont, formatCurrency),
              pw.SizedBox(height: 18),
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(16),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Sous-total'),
                        pw.Text(formatCurrency(cartTotal)),
                      ],
                    ),
                    if (deliveryFee > 0)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Frais de livraison'),
                          pw.Text(formatCurrency(deliveryFee)),
                        ],
                      ),
                    if (expressFee > 0)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Livraison express'),
                          pw.Text(formatCurrency(expressFee)),
                        ],
                      ),
                    if (tip > 0)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Pourboire'),
                          pw.Text(formatCurrency(tip)),
                        ],
                      ),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Total encaissé',
                          style: pw.TextStyle(font: boldFont),
                        ),
                        pw.Text(
                          formatCurrency(total),
                          style: pw.TextStyle(font: boldFont),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (order['notes'] != null &&
                  order['notes'].toString().trim().isNotEmpty) ...[
                pw.SizedBox(height: 16),
                pw.Text(
                  'Notes internes',
                  style: pw.TextStyle(font: boldFont, fontSize: 14),
                ),
                pw.SizedBox(height: 6),
                pw.Text(order['notes'].toString()),
              ],
            ],
          ),
        );
      }

      final bytes = await doc.save();
      final printingInfo = await Printing.info();
      if (printingInfo.canShare) {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } else if (printingInfo.canPrint || kIsWeb) {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else {
        throw UnsupportedError(
          'L\'export PDF n\'est pas supporté sur cet appareil.',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF exporté (${orders.length} commandes).'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'export: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _bulkExporting = false);
      } else {
        _bulkExporting = false;
      }
    }
  }

  Future<void> _acceptOrder(Map<String, dynamic> order) async {
    final orderId = order['orderId'] ?? order['id'];
    if (orderId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Commande introuvable'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Accepter la commande'),
          content: Text(
            'Voulez-vous vraiment accepter la commande #$orderId et la passer en livraison ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirmer'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    try {
      final db = FirebaseDatabase.instance;
      await db.ref('orders').child(orderId.toString()).update({
        'status': 'livraison',
        'acceptedAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });

      // Notify the client
      try {
        final userId = order['userId']?.toString();
        if (userId != null) {
          final clientEmail = _resolveCustomerEmail(order);
          await NotificationService.notifyOrderStatusUpdate(
            userId: userId,
            orderId: orderId.toString(),
            status: 'livraison',
            email: clientEmail,
          );
        }
      } catch (e) {
        debugPrint('Error sending acceptance notification: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Commande acceptée'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  String _resolveOrderId(Map<String, dynamic> order) {
    final dynamic raw = order['orderId'] ?? order['id'];
    if (raw == null) return '';
    return raw.toString();
  }

  Future<void> _completeDelivery(Map<String, dynamic> order) async {
    final orderId = _resolveOrderId(order);
    if (orderId.isEmpty) return;

    try {
      final db = FirebaseDatabase.instance;

      await db.ref('orders').child(orderId).update({
        'status': 'termines',
        'adminConfirmedAt': ServerValue.timestamp,
        'deliveryCodeValidatedAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });

      await db.ref('orders/$orderId/deliveryCode').remove();

      // Notify the client
      try {
        final userId = order['userId']?.toString();
        if (userId != null) {
          final clientEmail = _resolveCustomerEmail(order);
          await NotificationService.notifyOrderStatusUpdate(
            userId: userId,
            orderId: orderId,
            status: 'termines',
            email: clientEmail,
          );
        }
      } catch (e) {
        debugPrint('Error sending completion notification: $e');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Commande #$orderId complétée'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _showDeliveryConfirmation(Map<String, dynamic> order) async {
    final orderId = _resolveOrderId(order);
    if (orderId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Commande introuvable'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Confirmer la livraison'),
          content: Text(
            'Voulez-vous vraiment marquer la commande #$orderId comme livrée ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirmer'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _completeDelivery(order);
    }
  }

  Future<void> showOrderDetailsById(String orderId) async {
    final db = FirebaseDatabase.instance;
    
    final snap = await db.ref('orders').child(orderId).get();
    if (snap.exists && mounted) {
      final orderData = Map<String, dynamic>.from(snap.value as Map);
      // Ensure orderId is preserved in the data map for helpers
      if (orderData['orderId'] == null) orderData['orderId'] = orderId;
      _showOrderDetails(orderData);
    }
  }

  Future<void> _showOrderDetails(Map<String, dynamic> order) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final items = _extractOrderItems(order);
            final cartTotal = _safeToDouble(order['cartTotal']);
            final deliveryFee = _safeToDouble(order['deliveryFee']);
            final expressFee = _safeToDouble(order['expressFee']);
            final tip = _safeToDouble(order['tip']);
            final total = _safeToDouble(order['total']);
            final deliveryAddress = (order['deliveryAddress'] ?? 'Adresse non spécifiée').toString();
            final fallbackPhone = (order['phone'] ?? order['phoneNumber'] ?? '—').toString();
            final orderId = _resolveOrderId(order);
            final createdAt = _parseOrderDate(order['createdAt']);
            final formattedDate = _formatOrderDate(createdAt);
            final status = (order['status'] ?? '').toString();
            final visuals = _resolveStatusVisuals(status);
            final pdfBusy = orderId.isEmpty ? false : _pdfInProgress.contains(orderId);
            final theme = Theme.of(context);
            final customerName = _resolveCustomerName(order);
            final customerPhoto = _resolveCustomerPhoto(order);
            final customerEmail = _resolveCustomerEmail(order);
            final customerPhone = _resolveCustomerPhone(order, fallback: fallbackPhone);
            final deliveryLabel = _resolveDeliveryLabel(order);
            final emailLabel = (customerEmail ?? '').trim();
            final displayEmail = emailLabel.isEmpty ? 'Email non renseigné' : emailLabel;
            final normalizedPhone = (customerPhone ?? '').trim();
            final displayPhone = normalizedPhone.isEmpty || normalizedPhone == '—' ? 'Téléphone non renseigné' : normalizedPhone;
            final canCallClient = normalizedPhone.isNotEmpty && normalizedPhone != '—';
            final receiverName = (order['receiverName'] ?? '').toString();
            final receiverPhone = (order['receiverPhone'] ?? '').toString();
            final hasReceiver = receiverName.trim().isNotEmpty || receiverPhone.trim().isNotEmpty;
            final receiverLabel = hasReceiver
                ? '${receiverName.trim().isNotEmpty ? receiverName.trim() : 'Destinataire'}${receiverPhone.trim().isNotEmpty ? ' • ${receiverPhone.trim()}' : ''}'
                : '';

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              contentPadding: EdgeInsets.zero,
              content: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, visuals.color.withValues(alpha: 0.05)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Colors.white, visuals.color.withValues(alpha: 0.08)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: visuals.color.withValues(alpha: 0.15),
                              blurRadius: 26,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _buildAvatar(customerName, photoUrl: customerPhoto, size: 78),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customerName,
                                        style: theme.textTheme.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Client premium',
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          color: AppTheme.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: visuals.color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(visuals.icon, color: visuals.color, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        visuals.label,
                                        style: TextStyle(color: visuals.color, fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                             Wrap(
                               spacing: 10,
                               runSpacing: 10,
                               children: [
                                 _buildInfoChip(Icons.calendar_today_outlined, formattedDate, textColor: AppTheme.textPrimary, backgroundColor: Colors.white.withValues(alpha: 0.85)),
                                 GestureDetector(
                                   onTap: () => _showLocationDetailsModal(order),
                                   child: _buildInfoChip(Icons.location_on_outlined, deliveryLabel, textColor: AppTheme.textPrimary, backgroundColor: Colors.white.withValues(alpha: 0.85)),
                                 ),
                                 if (hasReceiver)
                                   GestureDetector(
                                     onTap: () => _showClientInfoModal(order),
                                     child: _buildInfoChip(Icons.person_outline_rounded, receiverLabel, textColor: AppTheme.textPrimary, backgroundColor: Colors.white.withValues(alpha: 0.85)),
                                   ),
                                 GestureDetector(
                                   onTap: () => _showClientInfoModal(order),
                                   child: _buildInfoChip(Icons.mail_outline_rounded, displayEmail, textColor: emailLabel.isEmpty ? AppTheme.warningColor : AppTheme.textPrimary, backgroundColor: emailLabel.isEmpty ? AppTheme.warningColor.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.9)),
                                 ),
                                 GestureDetector(
                                   onTap: () => _showClientInfoModal(order),
                                   child: _buildInfoChip(Icons.phone_rounded, displayPhone, textColor: canCallClient ? AppTheme.textPrimary : AppTheme.textSecondary, backgroundColor: canCallClient ? Colors.white.withValues(alpha: 0.9) : AppTheme.textLight.withValues(alpha: 0.32)),
                                 ),
                               ],
                             ),
                           ],
                         ),
                       ),
                      const SizedBox(height: 28),
                      Text('Produits', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                      (() {
                        final Map<String, List<Map<String, dynamic>>> groupedItems = {};
                        for (var item in items) {
                          final categoryId = (item['categoryId'] ?? 'Autres').toString();
                          if (!groupedItems.containsKey(categoryId)) {
                            groupedItems[categoryId] = [];
                          }
                          groupedItems[categoryId]!.add(item);
                        }

                        final List<Widget> groupedWidgets = [];
                        for (var entry in groupedItems.entries) {
                          final categoryId = entry.key;
                          String categoryName = categoryId;
                          try {
                            final cat = _categories.firstWhere((c) => c.id == categoryId);
                            categoryName = cat.name;
                          } catch (_) {
                            if (categoryId == 'Autres') categoryName = 'Autres';
                          }

                          groupedWidgets.add(
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 6),
                              child: Text(
                                categoryName.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor.withOpacity(0.85),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          );

                          for (var item in entry.value) {
                             final name = (item['productName'] ?? 'Produit').toString();
                             final qty = _formatQuantity(item['quantity']);
                             final unit = (item['unit'] ?? item['priceUnit'] ?? '').toString().trim();
                             final totalItem = _safeToDouble(item['totalPrice'] ?? item['price'] ?? 0);
                             final quantityLabel = unit.isEmpty ? qty : '$qty x $unit';
                             final isRefunded = item['status'] == 'refunded';
                             final isReplaced = item['isReplaced'] == true;
                             final isPrepared = item['isPrepared'] == true;

                             groupedWidgets.add(
                               Padding(
                                 padding: const EdgeInsets.only(bottom: 8),
                                 child: Row(
                                   children: [
                                     Checkbox(
                                       value: isPrepared,
                                       activeColor: AppTheme.successColor,
                                       onChanged: (val) async {
                                         if (val == null) return;
                                         item['isPrepared'] = val;
                                         final rawItems = order['items'];
                                         if (rawItems is List) {
                                           for (var i in rawItems) {
                                             if (i is Map) {
                                               final itemId = i['productId'] ?? i['id'];
                                               final tId = item['productId'] ?? item['id'];
                                               if (itemId == tId) {
                                                 i['isPrepared'] = val;
                                                 break;
                                               }
                                             }
                                           }
                                         }
                                         setDialogState(() {});
                                         await _toggleItemPreparation(
                                           (order['id'] ?? order['key'] ?? order['orderId']).toString(),
                                           item,
                                           val,
                                         );
                                       },
                                     ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$name ($quantityLabel)',
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: isRefunded ? AppTheme.textSecondary : AppTheme.textPrimary,
                                              decoration: (isRefunded || isPrepared) ? TextDecoration.lineThrough : null,
                                            ),
                                          ),
                                          if (isReplaced)
                                            Text(
                                              'Remplacé (Original: ${item['originalProductName']})',
                                              style: TextStyle(fontSize: 10, color: AppTheme.accentColor, fontStyle: FontStyle.italic),
                                            ),
                                          if (isRefunded)
                                            const Text(
                                              'Remboursé',
                                              style: TextStyle(fontSize: 10, color: AppTheme.errorColor, fontWeight: FontWeight.bold),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${totalItem.toStringAsFixed(2)} €',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: isRefunded ? AppTheme.textSecondary : AppTheme.textPrimary,
                                        decoration: (isRefunded || isPrepared) ? TextDecoration.lineThrough : null,
                                      ),
                                    ),
                                    if (status == 'pending' || status == 'processing' || status == 'en attente' || status == 'livraison')
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.swap_horiz, size: 20, color: AppTheme.accentColor),
                                            onPressed: () => _showProductReplacementDialog(order, item, onDone: () => setDialogState(() {})),
                                            tooltip: 'Remplacer ce produit',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.money_off_rounded, size: 20, color: AppTheme.errorColor),
                                            onPressed: () => _confirmItemRefund(order, item, onDone: () => setDialogState(() {})),
                                            tooltip: 'Rembourser ce produit',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: groupedWidgets,
                        );
                      }()),
                      const Divider(),
                       (() {
                         final prepFee = _safeToDouble(order['preparationFee'] ?? order['totalPreparationFee']);
                         return Column(
                           children: [
                             _buildDetailRow('Sous-total', '${cartTotal.toStringAsFixed(2)} €'),
                             if (deliveryFee > 0) _buildDetailRow('Frais de livraison', '${deliveryFee.toStringAsFixed(2)} €'),
                             if (prepFee > 0) _buildDetailRow('Frais de préparation', '${prepFee.toStringAsFixed(2)} €'),
                             if (expressFee > 0) _buildDetailRow('Livraison express', '${expressFee.toStringAsFixed(2)} €'),
                             if (tip > 0) _buildDetailRow('Pourboire', '${tip.toStringAsFixed(2)} €'),
                             const Divider(),
                             _buildDetailRow('Total encaissé', '${total.toStringAsFixed(2)} €', isTotal: true),
                           ],
                         );
                       }()),
                      const SizedBox(height: 20),
                      
                      if (order['notes'] != null && order['notes'].toString().trim().isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.sticky_note_2_outlined, color: Colors.orange.shade800, size: 20),
                                  const SizedBox(width: 8),
                                  Text('Journal des opérations', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(order['notes'].toString(), style: TextStyle(color: Colors.orange.shade900, fontSize: 12.5, height: 1.4)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),

                      if (order['unavailabilityPolicy'] != null)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.successColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.policy_outlined, color: AppTheme.successColor, size: 20),
                                  const SizedBox(width: 8),
                                  Text('Choix du client (Si indisponible)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.successColor.withValues(alpha: 0.9))),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    order['unavailabilityPolicy'] == 'replacement' ? Icons.cached_rounded : Icons.monetization_on_outlined,
                                    size: 16,
                                    color: AppTheme.successColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    order['unavailabilityPolicy'] == 'replacement' ? 'Remplacement (Produit similaire)' : 'Remboursement (Retour des fonds)',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.successColor.withValues(alpha: 0.8)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      
                      _buildStatusIndicator(visuals, formattedDate),
                      if (order['refundStatus'] != null) ...[
                        const SizedBox(height: 20),
                        _buildRefundRequest(order, onDone: () => setDialogState(() {})),
                      ],
                      const SizedBox(height: 20),
                      
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _openMap(order['deliveryAddress']),
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('Carte'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: AppTheme.primaryColor),
                                foregroundColor: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: canCallClient ? () => _makePhoneCall(normalizedPhone) : null,
                              icon: const Icon(Icons.phone_outlined),
                              label: const Text('Appeler'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: AppTheme.primaryColor),
                                foregroundColor: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Fermer', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                ),
                if (orderId.isNotEmpty)
                  FilledButton.icon(
                    onPressed: pdfBusy ? null : () => _exportOrderAsPdf(order),
                    icon: pdfBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf),
                    label: const Text('PDF'),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleRefundRequest(Map<String, dynamic> order, String newStatus, {VoidCallback? onDone}) async {
    final orderId = _resolveOrderId(order);
    if (orderId.isEmpty) return;
    try {
      final db = FirebaseDatabase.instance;
      await db.ref('orders').child(orderId).update({'refundStatus': newStatus, 'updatedAt': ServerValue.timestamp});
      order['refundStatus'] = newStatus; // Update locally
      if (onDone != null) onDone();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(newStatus == 'approved' ? 'Demande approuvée' : 'Demande refusée'), backgroundColor: newStatus == 'approved' ? AppTheme.successColor : AppTheme.errorColor));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: AppTheme.errorColor));
    }
  }

  Future<void> _showProductReplacementDialog(Map<String, dynamic> order, Map<String, dynamic> originalItem, {VoidCallback? onDone}) async {
    final orderId = _resolveOrderId(order);
    String selectedCategory = '';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setInternalState) {
            return AlertDialog(
              title: Text(selectedCategory.isEmpty ? 'Choisir une catégorie' : 'Remplacer par :'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: selectedCategory.isEmpty 
                  ? StreamBuilder<DatabaseEvent>(
                      stream: FirebaseDatabase.instance.ref('categories').onValue,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) return const Center(child: CircularProgressIndicator());
                        final categoriesMap = snapshot.data!.snapshot.value as Map;
                        final categories = categoriesMap.entries.map((e) => {'id': e.key, ...Map<String, dynamic>.from(e.value as Map)}).toList();
                        return ListView(
                          children: categories.map((cat) => ListTile(
                            leading: Icon(Icons.category_outlined, color: AppTheme.primaryColor),
                            title: Text(cat['name'] ?? 'Catégorie'),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => setInternalState(() => selectedCategory = cat['id']),
                          )).toList(),
                        );
                      },
                    )
                    : Column(
                        children: [
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.arrow_back, size: 20),
                            title: const Text('Retour aux catégories', style: TextStyle(fontWeight: FontWeight.w600)),
                            onTap: () => setInternalState(() => selectedCategory = ''),
                          ),
                          const Divider(),
                          Expanded(
                            child: StreamBuilder<DatabaseEvent>(
                              stream: FirebaseDatabase.instance.ref('products').onValue,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                final value = snapshot.data?.snapshot.value;
                                if (value == null) {
                                  return const Center(child: Text('Aucun produit disponible'));
                                }

                                List<Product> products = [];
                                try {
                                  if (value is Map) {
                                    value.forEach((key, val) {
                                      if (val is Map) {
                                        products.add(Product.fromMap(Map<String, dynamic>.from(val), key.toString()));
                                      }
                                    });
                                  } else if (value is List) {
                                    for (int i = 0; i < value.length; i++) {
                                      if (value[i] != null && value[i] is Map) {
                                        products.add(Product.fromMap(Map<String, dynamic>.from(value[i]), i.toString()));
                                      }
                                    }
                                  }
                                } catch (e) {
                                  debugPrint('Error parsing products: $e');
                                }

                                final filteredProducts = products.where((p) => p.categoryId == selectedCategory).toList();
                                
                                if (filteredProducts.isEmpty) {
                                  return const Center(child: Text('Aucun produit dans cette catégorie'));
                                }

                                return ListView.builder(
                                  itemCount: filteredProducts.length,
                                  itemBuilder: (context, index) {
                                    final product = filteredProducts[index];
                                    return ListTile(
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: product.imageUrl.isNotEmpty 
                                          ? Image.network(
                                              webSafeImageUrl(product.imageUrl), 
                                              width: 40, 
                                              height: 40, 
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
                                            )
                                          : const Icon(Icons.image_not_supported),
                                      ),
                                      title: Text(product.name),
                                      subtitle: Text('${product.price.toStringAsFixed(2)} €'),
                                      onTap: () async {
                                        Navigator.pop(context);
                                        await _replaceItemInDatabase(orderId, originalItem, product);
                                        
                                        // Update local order data so UI refreshes immediately
                                        final localItems = _extractOrderItems(order);
                                        double cartTotal = _safeToDouble(order['cartTotal']);
                                        double total = _safeToDouble(order['total']);
                                        
                                        for (var i = 0; i < localItems.length; i++) {
                                          final itemId = localItems[i]['productId'] ?? localItems[i]['id'];
                                          final targetId = originalItem['productId'] ?? originalItem['id'];
                                          if (itemId == targetId) {
                                            final qty = _safeToDouble(localItems[i]['quantity'] ?? 1);
                                            final oldItemTotal = _safeToDouble(localItems[i]['totalPrice'] ?? localItems[i]['price'] ?? 0);
                                            final newItemPrice = product.price;
                                            final newItemTotal = newItemPrice * qty;
                                            
                                            localItems[i]['productName'] = product.name;
                                            localItems[i]['productId'] = product.id;
                                            localItems[i]['productImage'] = product.imageUrl;
                                            localItems[i]['price'] = newItemPrice;
                                            localItems[i]['totalPrice'] = newItemTotal;
                                            localItems[i]['isReplaced'] = true;
                                            localItems[i]['originalProductName'] = originalItem['productName'];
                                            
                                            // Adjust order totals
                                            final diff = newItemTotal - oldItemTotal;
                                            cartTotal += diff;
                                            total += diff;
                                            break;
                                          }
                                        }
                                        order['items'] = localItems;
                                        order['cartTotal'] = cartTotal;
                                        order['total'] = total;
                                        
                                        if (onDone != null) onDone();
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleItemPreparation(
    String orderId,
    Map<String, dynamic> targetItem,
    bool isPrepared,
  ) async {
    try {
      final db = FirebaseDatabase.instance;
      final orderRef = db.ref('orders').child(orderId);
      final snap = await orderRef.get();
      if (!snap.exists) return;

      final orderDataMap = Map<String, dynamic>.from(snap.value as Map);
      final List<Map<String, dynamic>> items = _extractOrderItems(orderDataMap);

      final itemIndex = items.indexWhere((i) {
        final itemId = i['productId'] ?? i['id'];
        final tId = targetItem['productId'] ?? targetItem['id'];
        return itemId == tId;
      });

      if (itemIndex == -1) return;

      items[itemIndex]['isPrepared'] = isPrepared;
      await orderRef.update({'items': items});
    } catch (e) {
      debugPrint('Error toggling preparation: $e');
    }
  }

  Future<void> _replaceItemInDatabase(String orderId, Map<String, dynamic> originalItem, Product newProduct) async {
    try {
      final db = FirebaseDatabase.instance;
      
      final orderRef = db.ref('orders').child(orderId);
      final snap = await orderRef.get();
      
      if (!snap.exists) return;
      
      final orderDataMap = Map<String, dynamic>.from(snap.value as Map);
      final List<Map<String, dynamic>> items = _extractOrderItems(orderDataMap);
      
      final itemIndex = items.indexWhere((i) {
        final itemId = i['productId'] ?? i['id'];
        final targetId = originalItem['productId'] ?? originalItem['id'];
        return itemId == targetId;
      });
      
      if (itemIndex == -1) return;
      
      // Update item in list
      final updatedItem = Map<String, dynamic>.from(items[itemIndex]);
      final qty = _safeToDouble(updatedItem['quantity'] ?? 1);
      final oldItemTotal = _safeToDouble(updatedItem['totalPrice'] ?? updatedItem['price'] ?? 0);
      final newItemPrice = newProduct.price;
      final newItemTotal = newItemPrice * qty;

      updatedItem['productName'] = newProduct.name;
      updatedItem['productId'] = newProduct.id;
      updatedItem['productImage'] = newProduct.imageUrl;
      updatedItem['price'] = newItemPrice;
      updatedItem['totalPrice'] = newItemTotal;
      updatedItem['isReplaced'] = true;
      updatedItem['originalProductName'] = originalItem['productName'];
      
      items[itemIndex] = updatedItem;
      
      // Update order totals
      final currentCartTotal = _safeToDouble(orderDataMap['cartTotal']);
      final currentTotal = _safeToDouble(orderDataMap['total']);
      final diff = newItemTotal - oldItemTotal;

      await orderRef.update({
        'items': items,
        'cartTotal': currentCartTotal + diff,
        'total': currentTotal + diff,
        'updatedAt': ServerValue.timestamp,
        'notes': '${orderDataMap['notes'] ?? ''}\n[Admin] Produit "${originalItem['productName']}" remplacé par "${newProduct.name}" (Prix mis à jour: ${newItemTotal.toStringAsFixed(2)} €).'.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Produit remplacé par ${newProduct.name}'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du remplacement: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _confirmItemRefund(Map<String, dynamic> order, Map<String, dynamic> item, {VoidCallback? onDone}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer le remboursement'),
        content: Text('Voulez-vous vraiment rembourser le produit "${item['productName']}" (${item['price']} €) ?\nCe produit sera marqué comme annulé et sa valeur sera déduite du total.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Rembourser'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _refundItemInDatabase(order, item);
      if (onDone != null) onDone();
    }
  }

  Future<void> _refundItemInDatabase(Map<String, dynamic> order, Map<String, dynamic> itemToRefund) async {
    final orderId = _resolveOrderId(order);
    try {
      final db = FirebaseDatabase.instance;
      
      final orderRef = db.ref('orders').child(orderId);
      final snap = await orderRef.get();
      
      if (!snap.exists) return;
      
      final orderDataMap = Map<String, dynamic>.from(snap.value as Map);
      final List<Map<String, dynamic>> items = _extractOrderItems(orderDataMap);
      
      final itemIndex = items.indexWhere((i) {
        final itemId = i['productId'] ?? i['id'];
        final targetId = itemToRefund['productId'] ?? itemToRefund['id'];
        return itemId == targetId;
      });

      if (itemIndex == -1 || items[itemIndex]['status'] == 'refunded') return;

      final itemValue = _safeToDouble(items[itemIndex]['totalPrice'] ?? items[itemIndex]['price'] ?? 0);
      
      // Mark item as refunded in a copy
      final updatedItem = Map<String, dynamic>.from(items[itemIndex]);
      updatedItem['status'] = 'refunded';
      updatedItem['refundedAt'] = ServerValue.timestamp;
      items[itemIndex] = updatedItem;

      // Update order totals
      final currentCartTotal = _safeToDouble(orderDataMap['cartTotal']);
      final currentTotal = _safeToDouble(orderDataMap['total']);
      
      await orderRef.update({
        'items': items,
        'cartTotal': currentCartTotal - itemValue,
        'total': currentTotal - itemValue,
        'updatedAt': ServerValue.timestamp,
        'refundStatus': 'partial_refunded',
        'notes': '${orderDataMap['notes'] ?? ''}\n[Admin] Produit "${itemToRefund['productName']}" remboursé (${itemValue.toStringAsFixed(2)} €).'.trim(),
      });

      // Update local order object if provided
      if (order.containsKey('items')) {
        order['items'] = items;
        order['cartTotal'] = currentCartTotal - itemValue;
        order['total'] = currentTotal - itemValue;
        order['refundStatus'] = 'partial_refunded';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produit remboursé avec succès'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du remboursement: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Widget _buildDetailRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 15 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 15 : 13,
              fontWeight: FontWeight.bold,
              color: isTotal ? AppTheme.primaryColor : null,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedOrderIds.clear();
    });
  }

  void _toggleOrderSelection(String orderId) {
    setState(() {
      if (_selectedOrderIds.contains(orderId)) {
        _selectedOrderIds.remove(orderId);
      } else {
        _selectedOrderIds.add(orderId);
      }
    });
  }

  void _selectAllOrders(List<Map<String, dynamic>> orders) {
    setState(() {
      if (_selectedOrderIds.length == orders.length) {
        _selectedOrderIds.clear();
      } else {
        _selectedOrderIds.clear();
        for (final order in orders) {
          final orderId = _resolveOrderId(order);
          if (orderId.isNotEmpty) {
            _selectedOrderIds.add(orderId);
          }
        }
      }
    });
  }

  Future<void> _deleteSelectedOrders() async {
    if (_selectedOrderIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer la suppression'),
        content: Text(
          'Voulez-vous vraiment supprimer ${_selectedOrderIds.length} commande(s) ? Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deleting = true);

    try {
      final db = FirebaseDatabase.instance;

      for (final orderId in _selectedOrderIds) {
        await db.ref('orders').child(orderId).remove();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Commandes supprimées avec succès'),
            backgroundColor: AppTheme.successColor,
          ),
        );
        setState(() {
          _isSelectionMode = false;
          _selectedOrderIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la suppression: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Widget _buildOrdersList(
    List<Map<String, dynamic>> orders, {
    bool allowSelection = false,
  }) {
    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: AppTheme.textLight,
              ),
              const SizedBox(height: 8),
              Text(
                'Aucune commande',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (allowSelection)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isSelectionMode) ...[
                  TextButton.icon(
                    onPressed: () => _selectAllOrders(orders),
                    icon: const Icon(Icons.select_all),
                    label: Text(
                      _selectedOrderIds.length == orders.length
                          ? 'Tout désélectionner'
                          : 'Tout sélectionner',
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _selectedOrderIds.isEmpty || _deleting
                        ? null
                        : _deleteSelectedOrders,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorColor,
                      foregroundColor: Colors.white,
                    ),
                    icon: _deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Supprimer'),
                  ),
                ] else if (orders.isNotEmpty)
                  TextButton.icon(
                    onPressed: _toggleSelectionMode,
                    icon: const Icon(Icons.checklist),
                    label: const Text('Sélectionner'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _buildOrderCard(orders[index], allowSelection: allowSelection),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(
    Map<String, dynamic> order, {
    bool allowSelection = false,
  }) {
    final total = (order['total'] ?? 0).toDouble();
    final status = (order['status'] ?? 'pending').toString();
    final visuals = _resolveStatusVisuals(status);
    final items = _extractOrderItems(order);
    final previewItems = items.take(3).toList();
    final remainingItems = items.length - previewItems.length;
    final customerName = _resolveCustomerName(order);
    final deliveryLabel = _resolveDeliveryLabel(order);
    final customerPhoto = _resolveCustomerPhoto(order);
    final orderCode = order['orderId'] != null
        ? 'Commande ${order['orderId']}'
        : 'Commande #${order['id'].toString().substring(0, 6).toUpperCase()}';
    final normalizedStatus = status.toLowerCase();
    final isPending =
        normalizedStatus == 'pending' || normalizedStatus == 'en attente';
    final isProcessing =
        normalizedStatus == 'processing' ||
        normalizedStatus == 'en cours' ||
        normalizedStatus == 'en cours de livraison' ||
        normalizedStatus == 'livraison';
    final awaitingValidation = normalizedStatus == 'awaiting_confirmation';
    final canMarkDelivered = isProcessing || awaitingValidation;
    final receiverName = (order['receiverName'] ?? '').toString();
    final receiverPhone = (order['receiverPhone'] ?? '').toString();
    final hasReceiver =
        receiverName.trim().isNotEmpty || receiverPhone.trim().isNotEmpty;
    final receiverLabel = hasReceiver
        ? '${receiverName.trim().isNotEmpty ? receiverName.trim() : 'Destinataire'}${receiverPhone.trim().isNotEmpty ? ' • ${receiverPhone.trim()}' : ''}'
        : '';

    final orderId = _resolveOrderId(order);
    final isSelected = _selectedOrderIds.contains(orderId);

    return GestureDetector(
      onTap: () {
        if (_isSelectionMode && allowSelection) {
          _toggleOrderSelection(orderId);
        } else {
          _showOrderDetails(order);
        }
      },
      onLongPress: () {
        if (allowSelection && !_isSelectionMode) {
          _toggleSelectionMode();
          _toggleOrderSelection(orderId);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [visuals.color.withValues(alpha: 0.14), Colors.white],
          ),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : visuals.color.withValues(alpha: 0.2),
            width: isSelected ? 2.5 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: visuals.color.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -28,
              right: -20,
              child: Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      visuals.color.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            if (_isSelectionMode && allowSelection)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryColor : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.check,
                      size: 16,
                      color: isSelected ? Colors.white : Colors.transparent,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              visuals.color.withAlpha(36),
                              visuals.color.withAlpha(12),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          visuals.icon,
                          size: 24,
                          color: visuals.color,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              orderCode,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                GestureDetector(
                                  onTap: () => _showClientInfoModal(order),
                                  child: _buildClientChip(
                                    customerName,
                                    photoUrl: customerPhoto,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _showLocationDetailsModal(order),
                                  child: _buildInfoChip(
                                    Icons.location_on_outlined,
                                    deliveryLabel,
                                  ),
                                ),
                                if (hasReceiver)
                                  GestureDetector(
                                    onTap: () => _showClientInfoModal(order),
                                    child: _buildInfoChip(
                                      Icons.person_outline_rounded,
                                      receiverLabel,
                                    ),
                                  ),
                                _buildInfoChip(
                                  order['unavailabilityPolicy'] == 'replacement' 
                                      ? Icons.cached_rounded 
                                      : Icons.monetization_on_outlined,
                                  order['unavailabilityPolicy'] == 'replacement'
                                      ? 'Remplacer'
                                      : 'Rembourser',
                                  textColor: AppTheme.primaryColor,
                                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!_isSelectionMode)
                        Align(
                          alignment: Alignment.topRight,
                          child: _buildInfoChip(
                            visuals.icon,
                            visuals.label,
                            textColor: Colors.white,
                            backgroundColor: visuals.color,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _buildStatusTimeline(visuals.stageIndex, visuals.color),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Résumé',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                              ),
                              Text(
                                '${total.toStringAsFixed(2)} €',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ...previewItems.map((item) {
                            final itemMap = Map<String, dynamic>.from(item);
                            final productName =
                                (itemMap['productName'] ?? 'Produit')
                                    .toString();
                            final quantity = _formatQuantity(
                              itemMap['quantity'],
                            );
                            final unit = (itemMap['unit'] ?? '').toString();
                            final itemTotal = (itemMap['totalPrice'] ?? 0)
                                .toDouble();
                            final quantityLabel = unit.isEmpty
                                ? quantity
                                : '$quantity $unit';
                            final initial = productName.isNotEmpty
                                ? productName[0].toUpperCase()
                                : '?';

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: visuals.color.withValues(
                                        alpha: 0.12,
                                      ),
                                    ),
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: visuals.color,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          productName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.textPrimary,
                                              ),
                                        ),
                                        Text(
                                          quantityLabel,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppTheme.textSecondary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${itemTotal.toStringAsFixed(2)} €',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary,
                                        ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          if (remainingItems > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+ $remainingItems autres articles',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppTheme.textSecondary,
                                      fontStyle: FontStyle.italic,
                                    ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          if (isPending) ...[
                            const SizedBox(height: 12),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.successColor,
                                    AppTheme.successColor.withValues(
                                      alpha: 0.8,
                                    ),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.successColor.withValues(
                                      alpha: 0.32,
                                    ),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () => _acceptOrder(order),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  size: 20,
                                ),
                                label: const Text(
                                  'Accepter la commande',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (canMarkDelivered) ...[
                            const SizedBox(height: 12),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.successColor,
                                    AppTheme.successColor.withValues(
                                      alpha: 0.8,
                                    ),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.successColor.withValues(
                                      alpha: 0.32,
                                    ),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _showDeliveryConfirmation(order),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  size: 20,
                                ),
                                label: const Text(
                                  'Marquer comme livrée',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
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

  @override
  Widget build(BuildContext context) {
    final pendingCount = _getOrdersByStatus('pending').length;
    final inProgressCount = _getOrdersByStatus('en cours').length;
    final deliveredCount = _getOrdersByStatus('delivre').length;

    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Commandes',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: AdminSearchBar(
                hintText: 'Rechercher par client, téléphone ou commande...',
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withValues(alpha: 0.75),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
                tabs: [
                  Tab(child: _buildTabWithBadge('En attente', pendingCount)),
                  Tab(
                    child: _buildTabWithBadge('En livraison', inProgressCount),
                  ),
                  Tab(child: _buildTabWithBadge('Terminée', deliveredCount)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _bulkExporting
                                ? null
                                : _exportCurrentTabOrders,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            icon: _bulkExporting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.picture_as_pdf_rounded),
                            label: Text(
                              _bulkExporting
                                  ? 'Export en cours...'
                                  : 'Exporter les commandes',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildOrdersList(
                                _getOrdersByStatus(_tabStatusKeys[0]),
                              ),
                              _buildOrdersList(
                                _getOrdersByStatus(_tabStatusKeys[1]),
                              ),
                              _buildOrdersList(
                                _getOrdersByStatus(_tabStatusKeys[2]),
                                allowSelection: true,
                              ),
                            ],
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

  Widget _buildTabWithBadge(String label, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count > 0)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusIndicator(_StatusVisuals visuals, String date) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: visuals.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: visuals.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(visuals.icon, color: visuals.color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visuals.label,
                  style: TextStyle(fontWeight: FontWeight.bold, color: visuals.color, fontSize: 15),
                ),
                Text(
                  'Dernière mise à jour : $date',
                  style: TextStyle(fontSize: 12, color: visuals.color.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefundRequest(Map<String, dynamic> order, {VoidCallback? onDone}) {
    final status = order['refundStatus'] ?? 'pending';
    final isPending = status == 'pending';
    final color = status == 'approved' ? AppTheme.successColor : status == 'rejected' ? AppTheme.errorColor : AppTheme.warningColor;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                'Demande de ${order['refundType'] == 'replace' ? 'remplacement' : 'remboursement'}',
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
              const Spacer(),
              _buildInfoChip(
                isPending ? Icons.hourglass_empty : status == 'approved' ? Icons.check : Icons.close,
                isPending ? 'En attente' : status == 'approved' ? 'Approuvée' : 'Refusée',
                backgroundColor: color,
                textColor: Colors.white,
              ),
            ],
          ),
          if (isPending) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleRefundRequest(order, 'rejected', onDone: onDone),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorColor),
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _handleRefundRequest(order, 'approved', onDone: onDone),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.successColor),
                    child: const Text('Accepter'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openMap(String address) async {
    final encoded = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _makePhoneCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
