import 'package:flutter/services.dart';

/// Thin wrapper around platform document pickers (Android SAF / iOS UIDocumentPicker).
class DocumentPicker {
  DocumentPicker._();

  static const _channel = MethodChannel('cityshop/document_picker');

  static Future<PickedDocument?> pick() async {
    final raw = await _channel.invokeMethod<dynamic>('pickDocument');
    if (raw is! Map) return null;
    final path = raw['path']?.toString();
    if (path == null || path.isEmpty) return null;
    return PickedDocument(
      path: path,
      name: raw['name']?.toString() ?? 'file',
      size: (raw['size'] is num) ? (raw['size'] as num).toInt() : null,
      mime: raw['mime']?.toString(),
    );
  }
}

class PickedDocument {
  const PickedDocument({
    required this.path,
    required this.name,
    this.size,
    this.mime,
  });

  final String path;
  final String name;
  final int? size;
  final String? mime;
}
