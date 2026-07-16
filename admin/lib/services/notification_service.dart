import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

class NotificationService {
  static final FirebaseDatabase _db = FirebaseDatabase.instance;

  /// Send a push notification to a specific user
  static Future<void> sendPushNotification({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // 1. Get the user's FCM token from RTDB
      final snapshot = await _db.ref('users').child(userId).child('fcmToken').get();
      
      if (!snapshot.exists) {
        if (kDebugMode) {
          print('No FCM token found for user $userId');
        }
        return;
      }

      final String fcmToken = snapshot.value.toString();

      // 2. In a real production app, you should use a Cloud Function to send FCM.
      // However, for this implementation, we will push a notification request to RTDB
      // which can be handled by a Cloud Function or a backend service.
      
      await _db.ref('notifications_queue').push().set({
        'to': fcmToken,
        'userId': userId,
        'title': title,
        'body': body,
        'data': data ?? {},
        'createdAt': ServerValue.timestamp,
        'type': 'push',
        'status': 'pending',
      });

      if (kDebugMode) {
        print('Notification queued for $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error queueing notification: $e');
      }
    }
  }

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

      // Method 1: Google Apps Script Web App (Completely CORS-free & direct Gmail)
      if (appsScriptUrl != null && appsScriptUrl.isNotEmpty) {
        final response = await http.post(
          Uri.parse(appsScriptUrl),
          headers: {
            'Content-Type': 'text/plain', // Prevents CORS preflight, super fast!
          },
          body: json.encode({
            'to': email,
            'subject': subject,
            'html': htmlContent,
          }),
        );
        if (kDebugMode) {
          print('Google Apps Script response: ${response.statusCode} - ${response.body}');
        }
        return response.statusCode == 200 || response.body.toLowerCase().contains('ok');
      }

      // Method 2: Resend API Key (Backup)
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
        if (kDebugMode) {
          print('Resend response: ${response.statusCode} - ${response.body}');
        }
        return response.statusCode == 200 || response.statusCode == 201;
      }

      if (kDebugMode) {
        print('No email service configured (Google Apps Script URL or Resend API Key missing)');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error sending email notification: $e');
      }
      return false;
    }
  }

  /// Helper to send order status updates
  static Future<void> notifyOrderStatusUpdate({
    required String userId,
    required String orderId,
    required String status,
    required String? email,
  }) async {
    String title = '';
    String body = '';
    String emailSubject = '';
    String emailBody = '';

    switch (status.toLowerCase()) {
      case 'livraison':
      case 'processing':
        title = 'Commande en route';
        body = 'Votre commande #$orderId est maintenant en cours de livraison.';
        emailSubject = 'Votre commande Livriyes est en route';
        break;
      case 'termines':
      case 'delivered':
        title = 'Commande livree';
        body = 'Bonne nouvelle ! Votre commande #$orderId a été livrée avec succès.';
        emailSubject = 'Commande Livriyes livree';
        break;
      case 'pending':
        title = 'Commande confirmee';
        body = 'Nous avons bien reçu votre commande #$orderId. Elle est en cours de préparation.';
        emailSubject = 'Confirmation de votre commande Livriyes';
        break;
      default:
        title = 'Mise a jour de votre commande';
        body = 'Le statut de votre commande #$orderId a été mis à jour : $status';
        emailSubject = 'Mise a jour de votre commande Livriyes';
    }

    // Send Push
    await sendPushNotification(
      userId: userId,
      title: title,
      body: body,
      data: {'orderId': orderId, 'status': status},
    );

    // Send Email if available
    if (email != null && email.isNotEmpty) {
      emailBody = _getEmailTemplate(title, body, orderId);
      await sendEmailNotification(
        email: email,
        subject: emailSubject,
        htmlContent: emailBody,
      );
    }
  }

  static String _getEmailTemplate(String title, String body, String orderId) {
    return '''
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
        .container { font-family: sans-serif; padding: 25px; color: #333; background-color: #f7f9fc; }
        .card { background: white; padding: 30px; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); border: 1px solid #eef2f6; }
        .header { background: #6366F1; color: white; padding: 20px; border-radius: 12px 12px 0 0; text-align: center; }
        .logo { font-size: 22px; font-weight: bold; color: white; letter-spacing: 0.5px; }
        .content { padding: 30px 20px; }
        .title { font-size: 18px; font-weight: bold; color: #1e293b; margin-bottom: 16px; }
        .body-text { font-size: 14px; color: #475569; line-height: 1.6; margin-bottom: 20px; }
        .order-id-box { padding: 12px 16px; background: #f1f5f9; border-radius: 8px; font-size: 14px; color: #334155; margin-bottom: 20px; border-left: 4px solid #6366F1; }
        .footer { margin-top: 24px; font-size: 11px; color: #94a3b8; text-align: center; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="card">
          <div class="header">
            <span class="logo">Livriyes</span>
          </div>
          <div class="content">
            <div class="title">$title</div>
            <div class="body-text">$body</div>
            <div class="order-id-box">
              ID de commande : <strong>#$orderId</strong>
            </div>
          </div>
          <div class="footer">
            <p>&copy; 2026 Livriyes. Tous droits réservés.</p>
          </div>
        </div>
      </div>
    </body>
    </html>
    ''';
  }
}
