import 'dart:html' as html;
import 'dart:convert';

void showBrowserNotification(String title, String body) {
  if (html.Notification.supported) {
    if (html.Notification.permission == 'granted') {
      html.Notification(title, body: body);
    } else {
      html.Notification.requestPermission().then((permission) {
        if (permission == 'granted') {
          html.Notification(title, body: body);
        }
      });
    }
  }
}

void playBeepSound() {
  try {
    final audio = html.AudioElement()
      ..src = 'https://actions.google.com/sounds/v1/alarms/beep_short.ogg'
      ..autoplay = true;
    html.document.body?.append(audio);
    audio.play();
    Future.delayed(const Duration(seconds: 3), () {
      audio.remove();
    });
  } catch(e) {}
}

Future<bool> sendEmailViaFetch(String url, String to, String subject, String htmlContent) async {
  try {
    final body = json.encode({
      'to': to,
      'subject': subject,
      'html': htmlContent,
    });

    await html.window.fetch(url, {
      'method': 'POST',
      'headers': {
        'Content-Type': 'text/plain',
      },
      'body': body,
      'mode': 'no-cors',
    });
    return true;
  } catch (e) {
    print('Error sending via no-cors fetch: $e');
    return false;
  }
}
