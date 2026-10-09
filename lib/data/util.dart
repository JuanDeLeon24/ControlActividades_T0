/// Utilidades de texto, números y abscisas (PK).

const String _conTilde = 'áàäâãéèëêíìïîóòöôõúùüûñ';
const String _sinTilde = 'aaaaaeeeeiiiiooooouuuun';

/// Minúsculas, sin tildes, solo letras/números separados por un espacio.
String norm(String s) {
  final sb = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = _conTilde.indexOf(c);
    sb.write(i >= 0 ? _sinTilde[i] : c);
  }
  return sb.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Igual que [norm] pero sin espacios (para comparar nombres de hoja).
String normClave(String s) => norm(s).replaceAll(' ', '');

double? aNumero(Object? v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) {
    var t = v.trim().replaceAll('%', '');
    if (t.isEmpty) return null;
    if (t.contains(',') && !t.contains('.')) {
      t = t.replaceAll(',', '.');
    } else {
      t = t.replaceAll(',', '');
    }
    return double.tryParse(t);
  }
  return null;
}

String aTexto(Object? v) {
  if (v == null) return '';
  if (v is double) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }
  if (v is DateTime) return fmtFecha(v);
  return v.toString().trim();
}

/// Acepta 6583.5 / "6583,5" / "K6+583.5".
double? parsePk(Object? v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) {
    final m = RegExp(r'[kK]\s*(\d+)\s*\+\s*(\d+(?:[.,]\d+)?)').firstMatch(v);
    if (m != null) {
      final km = double.parse(m.group(1)!);
      final mt = double.parse(m.group(2)!.replaceAll(',', '.'));
      return km * 1000 + mt;
    }
    return aNumero(v);
  }
  return null;
}

DateTime? aFecha(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return null;
    final iso = DateTime.tryParse(t);
    if (iso != null) return iso;
    final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$').firstMatch(t);
    if (m != null) {
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) return DateTime(y, mo, d);
    }
  }
  return null;
}

/// "m³", "m3", "M3" -> true.
bool esUnidadVolumen(String u) {
  final t = u.toLowerCase().trim();
  return t.contains('\u00b3') || t == 'm3' || t.startsWith('m3');
}

String fmtFecha(DateTime d) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${dos(d.month)}-${dos(d.day)}';
}

/// 6583.5 -> K6+583.50
String fmtPk(double pk) {
  final km = pk ~/ 1000;
  final m = pk - km * 1000;
  return 'K$km+${m.toStringAsFixed(2).padLeft(6, '0')}';
}

String fmtNum(double v, {int dec = 1}) {
  final s = v.toStringAsFixed(dec);
  final partes = s.split('.');
  final ent = partes[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return dec > 0 ? '$ent.${partes[1]}' : ent;
}

/// Límites de los 137 módulos del Túnel 0 (PK en metros, de portal K7+173 hacia K6+176).
const List<double> kLimitesModulosT0 = [7173,7165.5,7158,7152,7144.5,7137,7129.5,7122,7114.5,7107,7099.5,7092,7084.5,7077,7069.5,7062,7054.5,7047,7039.5,7032,7024.5,7017,7009.5,7002,6994.5,6987,6979.5,6972,6964.5,6957,6949.5,6942,6934.5,6927,6919.5,6912,6904.5,6897,6889.5,6882,6874.5,6867,6859.5,6852,6844.5,6837,6829.5,6822,6814.5,6807,6799.5,6792,6784.5,6777,6769.5,6762,6754.5,6747,6739.5,6732,6724.5,6717,6709.8,6702.6,6699.86,6694.66,6689.16,6683.66,6677.66,6671.66,6665.66,6659.66,6654.46,6649.26,6646.79,6639.29,6631.79,6624.29,6616.79,6609.59,6602.39,6594.89,6587.39,6579.89,6572.39,6564.89,6557.39,6549.89,6542.39,6534.89,6527.39,6519.89,6512.39,6504.89,6497.39,6489.89,6482.39,6474.89,6467.39,6459.89,6452.39,6444.89,6437.39,6429.89,6422.39,6414.89,6407.39,6399.89,6392.39,6384.89,6377.39,6369.89,6362.39,6354.89,6347.39,6339.89,6332.39,6324.9,6317.42,6309.95,6302.5,6295.05,6287.62,6280.2,6272.79,6265.39,6257.99,6250.59,6243.19,6235.78,6228.38,6220.98,6213.58,6206.18,6198.77,6191.37,6183.97,6176.57];
