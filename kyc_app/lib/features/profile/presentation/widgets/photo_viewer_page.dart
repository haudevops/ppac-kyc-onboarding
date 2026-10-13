import 'package:flutter/material.dart';

/// Full-screen, zoomable view of a document photo or selfie.
class PhotoViewerPage extends StatelessWidget {
  const PhotoViewerPage({super.key, required this.url, required this.title});

  final String url;
  final String title;

  static Future<void> open(BuildContext context, {required String url, required String title}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PhotoViewerPage(url: url, title: title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
      body: Center(
        child: Hero(
          tag: url,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const CircularProgressIndicator(color: Colors.white),
              errorBuilder: (context, error, stackTrace) => const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'This photo link has expired. Go back and pull down to refresh.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
