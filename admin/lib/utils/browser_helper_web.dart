import 'dart:html' as html;
import 'dart:js_util' as js_util;
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

    final requestOptions = js_util.newObject();
    js_util.setProperty(requestOptions, 'method', 'POST');
    // Using simple header Content-Type: text/plain prevents preflight CORS check
    final headers = js_util.newObject();
    js_util.setProperty(headers, 'Content-Type', 'text/plain');
    js_util.setProperty(requestOptions, 'headers', headers);
    js_util.setProperty(requestOptions, 'body', body);
    js_util.setProperty(requestOptions, 'mode', 'no-cors');

    final promise = html.window.fetch(url, requestOptions);
    await js_util.promiseToFuture(promise);
    return true; // no-cors mode always completes without CORS errors but results are opaque
  } catch (e) {
    print('Error sending via no-cors fetch: $e');
    return false;
  }
}
