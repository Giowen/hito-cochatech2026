import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

/// Extrae texto plano de un PDF en bytes. Funciona cross-platform (Web,
/// Android, iOS, Desktop) porque Syncfusion compila a Dart puro.
///
/// **Por qué Syncfusion** vs alternativas:
///   - `pdfx`: enfocado en render visual, no extracción de texto pura.
///   - `pdf` (dart_pdf): es para GENERAR PDFs, no leer.
///   - `pdf_text`: solo mobile, no soporta Web.
///   - Syncfusion: Dart puro, soporta Web vía Flutter Web canvas. Free para
///     proyectos no comerciales con Community License.
///
/// Si el PDF está escaneado (imagen sin OCR), la extracción devuelve string
/// vacío — en ese caso necesitaríamos un OCR server-side (Phase 2).
class HitoPdfExtractor {
  /// Lee todas las páginas y concatena con `\n\n`. Lanza si el PDF está
  /// corrupto o protegido por password.
  static Future<String> extract(Uint8List bytes) async {
    final document = sf.PdfDocument(inputBytes: bytes);
    try {
      final extractor = sf.PdfTextExtractor(document);
      final pageCount = document.pages.count;
      final buffer = StringBuffer();
      for (var i = 0; i < pageCount; i++) {
        final text = extractor.extractText(startPageIndex: i);
        if (text.trim().isNotEmpty) {
          buffer.write(text);
          if (i < pageCount - 1) buffer.write('\n\n');
        }
      }
      final result = buffer.toString().trim();
      debugPrint(
        '[Hito.PdfExtract] $pageCount páginas, ${result.length} chars',
      );
      return result;
    } finally {
      document.dispose();
    }
  }
}
