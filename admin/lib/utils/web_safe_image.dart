import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Returns an image URL safe for Flutter Web.
/// On web, routes WordPress image URLs through Vercel proxy to bypass CORS.
String webSafeImageUrl(String url) {
  if (!kIsWeb) return url;
  if (url.contains('livriyes.app/wp-content/uploads/')) {
    // Extract the path after /wp-content/uploads/
    final pathIndex = url.indexOf('/wp-content/uploads/');
    if (pathIndex != -1) {
      final imagePath = url.substring(pathIndex + '/wp-content/uploads/'.length);
      return '/img-proxy/$imagePath';
    }
  }
  return url;
}

/// A network image widget that handles CORS issues on Flutter Web
/// by routing WordPress images through the Vercel proxy.
class WebSafeImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? errorWidget;
  final Widget? placeholderWidget;

  const WebSafeImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorWidget,
    this.placeholderWidget,
  });

  @override
  Widget build(BuildContext context) {
    final safeUrl = webSafeImageUrl(imageUrl);

    if (safeUrl.isEmpty) {
      return errorWidget ??
          const Center(
            child: Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
          );
    }

    return Image.network(
      safeUrl,
      fit: fit,
      width: width,
      height: height,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholderWidget ??
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
      },
      errorBuilder: (context, error, stackTrace) {
        return errorWidget ??
            const Center(
              child: Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
            );
      },
    );
  }
}
