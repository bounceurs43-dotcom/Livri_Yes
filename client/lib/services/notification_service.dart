import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static final FirebaseDatabase _db = FirebaseDatabase.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<void> initialize() async {
    // Request permission
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      if (kDebugMode) {
        print('User granted permission');
      }
    }

    // Initialize local notifications
    await initializeLocalNotificationsOnly();

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null && !kIsWeb) {
        showNotification(
          title: notification.title ?? '',
          body: notification.body ?? '',
        );
      }
    });

    // Handle token refresh
    _messaging.onTokenRefresh.listen((token) {
      _saveTokenToDatabase(token);
    });

    // Get initial token
    String? token = await _messaging.getToken();
    if (token != null) {
      _saveTokenToDatabase(token);
    }

    // Start listening to order status updates in RTDB for local notifications
    startOrdersListener();
  }

  static Future<void> initializeLocalNotificationsOnly() async {
    if (!kIsWeb) {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      
      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: DarwinInitializationSettings(),
      );

      await _localNotifications.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Handle notification click
        },
      );

      // Create Android Notification Channel
      if (Platform.isAndroid) {
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'high_importance_channel',
          'High Importance Notifications',
          description: 'This channel is used for important notifications.',
          importance: Importance.max,
        );

        await _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }
    }
  }

  static StreamSubscription<DatabaseEvent>? _ordersSubscription;
  static final Map<String, String> _orderStatusMap = {};
  static bool _isFirstLoad = true;

  static void startOrdersListener() {
    _ordersSubscription?.cancel();
    _orderStatusMap.clear();
    _isFirstLoad = true;

    _auth.authStateChanges().listen((User? user) {
      if (user == null) {
        _ordersSubscription?.cancel();
        _ordersSubscription = null;
        _orderStatusMap.clear();
        return;
      }

      final ref = _db.ref('orders');
      
      _ordersSubscription = ref.onValue.listen((event) {
        if (event.snapshot.exists) {
          final value = event.snapshot.value;
          
          void processOrder(dynamic id, dynamic orderData) {
            if (orderData != null && orderData is Map) {
              final orderMap = Map<String, dynamic>.from(orderData);
              if (orderMap['userId'] == user.uid) {
                final String orderId = orderMap['orderId'] ?? id.toString();
                final String status = (orderMap['status'] ?? 'pending').toString();
                
                if (_isFirstLoad) {
                  _orderStatusMap[orderId] = status;
                } else {
                  final oldStatus = _orderStatusMap[orderId];
                  if (oldStatus != null && oldStatus != status) {
                    _orderStatusMap[orderId] = status;
                    _notifyStatusChange(orderId, status);
                  } else if (oldStatus == null) {
                    _orderStatusMap[orderId] = status;
                    _notifyStatusChange(orderId, status, isNew: true);
                  }
                }
              }
            }
          }

          if (value is Map) {
            value.forEach((id, orderData) {
              processOrder(id, orderData);
            });
            _isFirstLoad = false;
          } else if (value is List) {
            for (int i = 0; i < value.length; i++) {
              processOrder(i, value[i]);
            }
            _isFirstLoad = false;
          }
        }
      }, onError: (err) {
        if (kDebugMode) {
          print('Error in orders notification listener: $err');
        }
      });
    });
  }

  static void notifyStatusChange(String orderId, String status, {bool isNew = false}) {
    _notifyStatusChange(orderId, status, isNew: isNew);
  }

  static void _notifyStatusChange(String orderId, String status, {bool isNew = false}) {
    String title = 'Mise à jour de commande';
    String body = 'Le statut de votre commande #$orderId a été mis à jour.';

    final normalized = status.toLowerCase();

    if (isNew) {
      title = 'Commande confirmée ✅';
      body = 'Nous avons bien reçu votre commande #$orderId. Elle est en cours de préparation.';
    } else {
      if (normalized == 'pending' || normalized == 'en attente') {
        title = 'Commande en attente ⏳';
        body = 'Votre commande #$orderId est en attente de validation.';
      } else if (normalized == 'processing' || normalized == 'en cours') {
        title = 'Commande en cours de préparation 🍳';
        body = 'Votre commande #$orderId est en cours de préparation dans nos cuisines.';
      } else if (normalized == 'livraison' || normalized == 'en cours de livraison') {
        title = 'Commande en route 🚚';
        body = 'Votre commande #$orderId est maintenant en cours de livraison.';
      } else if (normalized == 'delivered' ||
          normalized == 'livré' ||
          normalized == 'delivre' ||
          normalized == 'delivré' ||
          normalized == 'termines' ||
          normalized == 'terminé' ||
          normalized == 'termine') {
        title = 'Commande livrée 🎉';
        body = 'Bonne nouvelle ! Votre commande #$orderId a été livrée avec succès. Bon appétit !';
      }
    }

    showNotification(title: title, body: body);
  }

  // Method for showing notifications
  static Future<void> showNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final int id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: data != null ? jsonEncode(data) : null,
    );
  }

  static Future<void> _saveTokenToDatabase(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Get phone from email if possible (as per AuthService logic)
      String? phone;
      if (user.email != null && user.email!.contains('@client.salimstore.com')) {
        phone = user.email!.replaceAll('@client.salimstore.com', '');
      }

      // Update in users/<uid>
      await _db.ref('users').child(user.uid).update({
        'fcmToken': token,
        'updatedAt': ServerValue.timestamp,
      });

      // Update in clients/<phone> if phone is available
      if (phone != null) {
        await _db.ref('clients').child(phone).update({
          'fcmToken': token,
          'updatedAt': ServerValue.timestamp,
        });
      }
      
      if (kDebugMode) {
        print('FCM Token saved: $token');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving FCM token: $e');
      }
    }
  }

  static Future<void> updateToken() async {
    String? token = await _messaging.getToken();
    if (token != null) {
      await _saveTokenToDatabase(token);
    }
  }

  // --- ADMIN NOTIFICATION HELPERS ---
  static Future<bool> sendEmailNotification({
    required String email,
    required String subject,
    required String htmlContent,
  }) async {
    try {
      final snap = await _db.ref('settings').child('notifications').get();
      if (!snap.exists) return false;

      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      final appsScriptUrl = map['appsScriptUrl']?.toString();
      final resendApiKey = map['resendApiKey']?.toString();

      // Method 1: Google Apps Script Web App
      if (appsScriptUrl != null && appsScriptUrl.isNotEmpty) {
        final response = await http.post(
          Uri.parse(appsScriptUrl),
          headers: {'Content-Type': 'text/plain'},
          body: json.encode({
            'to': email,
            'subject': subject,
            'html': htmlContent,
          }),
        );
        return response.statusCode == 200 || response.body.toLowerCase().contains('ok');
      }

      // Method 2: Resend API Key
      if (resendApiKey != null && resendApiKey.isNotEmpty) {
        final response = await http.post(
          Uri.parse('https://api.resend.com/emails'),
          headers: {
            'Authorization': 'Bearer $resendApiKey',
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'from': 'LivriYes <onboarding@resend.dev>',
            'to': [email],
            'subject': subject,
            'html': htmlContent,
          }),
        );
        return response.statusCode == 200 || response.statusCode == 201;
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('Error sending email notification: $e');
      return false;
    }
  }

  static Future<bool> notifyAdminNewOrder(String orderId) async {
    try {
      final emailSnap = await _db.ref('settings').child('notifications/email').get();
      final targetEmail = emailSnap.value?.toString() ?? 'support@livriyes.com';

      return await sendEmailNotification(
        email: targetEmail,
        subject: 'Nouvelle commande LivriYes #$orderId',
        htmlContent:
            '<h3>Nouvelle Commande !</h3><p>La commande #$orderId vient d\'être passée.</p>'
            '<a href="https://livriyes-seven.vercel.app/">Ouvrir le panneau d\'administration</a>',
      );
    } catch (e) {
      if (kDebugMode) print('Error notifying admin: $e');
      return false;
    }
  }
}
