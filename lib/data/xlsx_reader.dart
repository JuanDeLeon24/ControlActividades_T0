import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'util.dart';

/// Hoja de cálculo ya leída: matriz densa de valores
/// (String, double, DateTime, bool o null).
class Hoja {
  final String nombre;
  final List<List<Object?>> filas;
  const Hoja(this.nombre, this.filas);

  Object? celda(int fila, int col) {
    if (fila < 0 || fila >= filas.length) return null;
    final f = filas[fila];
    if (col < 0 || col >= f.length) return null;
    return f[col];
  }
}

class LibroXlsx {
  /// Clave = nombre normalizado (sin tildes, minúsculas, sin separadores).
  final Map<String, Hoja> _hojas;
  final List<String> nombresOriginales;
  const LibroXlsx(this._hojas, this.nombresOriginales);

  Hoja? hoja(String nombre) => _hojas[normClave(nombre)];
}

/// Lector mínimo de .xlsx / .xlsm.
///
/// Motivo: el paquete `excel` 4.x no expone el valor calculado de las celdas con
/// fórmula (solo la fórmula) y cambió la API de `CellValue`, que es lo que rompía
/// la compilación. Este lector lee directamente el valor en caché (`<v>`) que
/// Excel guarda junto a cada fórmula, funciona con .xlsm y no depende de la API
/// de ningún paquete de Excel.
class XlsxReader {
  static const int _maxCol = 300;
  static const int _maxFila = 30000;

  static LibroXlsx leer(List<int> bytes, {Set<String>? soloHojas}) {
    final archivo = ZipDecoder().decodeBytes(bytes);

    String? texto(String ruta) {
      final f = archivo.findFile(ruta);
      if (f == null) return null;
      return utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    final wbXml = texto('xl/workbook.xml');
    if (wbXml == null) {
      throw const FormatException(
          'El archivo no parece un libro de Excel (.xlsx/.xlsm): falta xl/workbook.xml.');
    }

    // Relaciones id -> ruta del XML de cada hoja
    final rels = <String, String>{};
    final relsXml = texto('xl/_rels/workbook.xml.rels');
    if (relsXml != null) {
      for (final r in XmlDocument.parse(relsXml).findAllElements('Relationship')) {
        final id = r.getAttribute('Id');
        final destino = r.getAttribute('Target');
        if (id != null && destino != null) {
          rels[id] = destino.startsWith('/') ? destino.substring(1) : 'xl/$destino';
        }
      }
    }

    // Textos compartidos
    final compartidos = <String>[];
    final ssXml = texto('xl/sharedStrings.xml');
    if (ssXml != null) {
      for (final si in XmlDocument.parse(ssXml).findAllElements('si')) {
        final sb = StringBuffer();
        for (final t in si.findAllElements('t')) {
          final padre = t.parent;
          if (padre is XmlElement && padre.name.local == 'rPh') continue;
          sb.write(t.innerText);
        }
        compartidos.add(sb.toString());
      }
    }

    // Estilos: ¿qué índice de estilo es una fecha?
    final estiloEsFecha = <bool>[];
    final stXml = texto('xl/styles.xml');
    if (stXml != null) {
      final sd = XmlDocument.parse(stXml);
      final personalizados = <int, String>{};
      for (final nf in sd.findAllElements('numFmt')) {
        final id = int.tryParse(nf.getAttribute('numFmtId') ?? '');
        if (id != null) personalizados[id] = nf.getAttribute('formatCode') ?? '';
      }
      final cellXfs = sd.findAllElements('cellXfs').firstOrNull;
      if (cellXfs != null) {
        for (final xf in cellXfs.findElements('xf')) {
          final id = int.tryParse(xf.getAttribute('numFmtId') ?? '0') ?? 0;
          estiloEsFecha.add(_esFormatoFecha(id, personalizados[id]));
        }
      }
    }

    final hojas = <String, Hoja>{};
    final nombres = <String>[];
    for (final s in XmlDocument.parse(wbXml).findAllElements('sheet')) {
      final nombre = s.getAttribute('name') ?? '';
      nombres.add(nombre);
      final clave = normClave(nombre);
      if (soloHojas != null && !soloHojas.contains(clave)) continue;

      String? rid;
      for (final a in s.attributes) {
        if (a.name.local == 'id') rid = a.value;
      }
      final ruta = rid == null ? null : rels[rid];
      if (ruta == null) continue;
      final xml = texto(ruta);
      if (xml == null) continue;
      hojas[clave] = _leerHoja(nombre, xml, compartidos, estiloEsFecha);
    }
    return LibroXlsx(hojas, nombres);
  }

  static bool _esFormatoFecha(int id, String? codigo) {
    if ((id >= 14 && id <= 17) || id == 22 || (id >= 27 && id <= 36) || (id >= 50 && id <= 58)) {
      return true;
    }
    if (codigo == null) return false;
    var c = codigo.toLowerCase();
    c = c.replaceAll(RegExp(r'"[^"]*"'), '');
    c = c.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    c = c.replaceAll(RegExp(r'\\.'), '');
    return RegExp(r'[dy]').hasMatch(c);
  }

  static DateTime _serialAFecha(double n) {
    final base = DateTime.utc(1899, 12, 30).add(Duration(milliseconds: (n * 86400000).round()));
    return DateTime(base.year, base.month, base.day, base.hour, base.minute);
  }

  static Hoja _leerHoja(
    String nombre,
    String xml,
    List<String> compartidos,
    List<bool> estiloEsFecha,
  ) {
    final doc = XmlDocument.parse(xml);
    final celdas = <int, Map<int, Object?>>{};
    var maxFila = -1;
    var maxCol = -1;

    for (final c in doc.findAllElements('c')) {
      final ref = c.getAttribute('r');
      if (ref == null) continue;
      final pos = _posicion(ref);
      if (pos == null) continue;
      final fila = pos[0];
      final col = pos[1];
      if (fila >= _maxFila || col >= _maxCol) continue;

      final tipo = c.getAttribute('t');
      final estilo = int.tryParse(c.getAttribute('s') ?? '');
      Object? valor;

      if (tipo == 'inlineStr') {
        final isEl = c.getElement('is');
        valor = isEl == null ? null : isEl.innerText;
      } else {
        final v = c.getElement('v');
        if (v != null) {
          final txt = v.innerText;
          switch (tipo) {
            case 's':
              final idx = int.tryParse(txt);
              valor = (idx != null && idx >= 0 && idx < compartidos.length) ? compartidos[idx] : null;
              break;
            case 'str':
              valor = txt;
              break;
            case 'b':
              valor = txt == '1';
              break;
            case 'e':
              valor = null;
              break;
            default:
              final n = double.tryParse(txt);
              if (n == null) {
                valor = txt;
              } else if (estilo != null && estilo < estiloEsFecha.length && estiloEsFecha[estilo]) {
                valor = _serialAFecha(n);
              } else {
                valor = n;
              }
          }
        }
      }
      if (valor is String && valor.trim().isEmpty) valor = null;
      if (valor == null) continue;

      celdas.putIfAbsent(fila, () => <int, Object?>{})[col] = valor;
      if (fila > maxFila) maxFila = fila;
      if (col > maxCol) maxCol = col;
    }

    final filas = <List<Object?>>[];
    for (var r = 0; r <= maxFila; r++) {
      final fila = List<Object?>.filled(maxCol + 1, null);
      final m = celdas[r];
      if (m != null) {
        m.forEach((col, v) {
          fila[col] = v;
        });
      }
      filas.add(fila);
    }
    return Hoja(nombre, filas);
  }

  /// "AB12" -> [fila0, col0]
  static List<int>? _posicion(String ref) {
    var col = 0;
    var i = 0;
    while (i < ref.length) {
      final u = ref.codeUnitAt(i);
      if (u >= 65 && u <= 90) {
        col = col * 26 + (u - 64);
      } else if (u >= 97 && u <= 122) {
        col = col * 26 + (u - 96);
      } else {
        break;
      }
      i++;
    }
    if (i == 0 || i >= ref.length) return null;
    final fila = int.tryParse(ref.substring(i));
    if (fila == null || fila < 1) return null;
    return [fila - 1, col - 1];
  }
}
