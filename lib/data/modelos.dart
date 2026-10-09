import 'util.dart';

/// Módulo constructivo (módulo de viga base / revestimiento) del Túnel 0.
class Modulo {
  final int numero;
  final double pkMin;
  final double pkMax;
  final String macrofibra;
  final String microfibra;
  final String malla;

  const Modulo({
    required this.numero,
    required this.pkMin,
    required this.pkMax,
    this.macrofibra = '',
    this.microfibra = '',
    this.malla = '',
  });

  double get longitud => pkMax - pkMin;

  /// Malla electrosoldada exigida en todo el módulo (columna MALLA de Módulos_VB = SI).
  bool get mallaRequerida => malla.trim().toUpperCase() == 'SI';
  double get pkMedio => (pkMin + pkMax) / 2;
}

List<Modulo> modulosPorDefecto() {
  final out = <Modulo>[];
  for (var i = 0; i < kLimitesModulosT0.length - 1; i++) {
    final a = kLimitesModulosT0[i];
    final b = kLimitesModulosT0[i + 1];
    out.add(Modulo(numero: i + 1, pkMin: b, pkMax: a));
  }
  return out;
}

/// Un renglón de ejecución (viene del Excel o de "Cargar jornada").
class Registro {
  final DateTime? fecha;
  final String turno;
  final String actividad;
  final String lado; // 'HD', 'HI' o ''
  final String grupo;
  final double? pkA;
  final double? pkB;
  final double cantidad;
  final String unidad;
  final double? avancePct;
  final String origen; // 'BD', 'AVANCES', 'APP'
  final String nota;

  const Registro({
    required this.fecha,
    required this.turno,
    required this.actividad,
    this.lado = '',
    this.grupo = '',
    this.pkA,
    this.pkB,
    this.cantidad = 0,
    this.unidad = '',
    this.avancePct,
    required this.origen,
    this.nota = '',
  });

  double? get pkMin => (pkA == null || pkB == null) ? null : (pkA! < pkB! ? pkA : pkB);
  double? get pkMax => (pkA == null || pkB == null) ? null : (pkA! > pkB! ? pkA : pkB);

  String get claveDedupe {
    final f = fecha == null ? '-' : fmtFecha(fecha!);
    final a = pkMin == null ? '-' : (pkMin! * 100).round().toString();
    final b = pkMax == null ? '-' : (pkMax! * 100).round().toString();
    return '$f|${norm(turno)}|${norm(actividad)}|${norm(lado)}|$a|$b';
  }

  Map<String, dynamic> toJson() => {
        'f': fecha?.toIso8601String(),
        't': turno,
        'a': actividad,
        'l': lado,
        'g': grupo,
        'pa': pkA,
        'pb': pkB,
        'c': cantidad,
        'u': unidad,
        'n': nota,
      };

  static Registro fromJson(Map<String, dynamic> j) => Registro(
        fecha: j['f'] == null ? null : DateTime.tryParse(j['f'] as String),
        turno: (j['t'] ?? '') as String,
        actividad: (j['a'] ?? '') as String,
        lado: (j['l'] ?? '') as String,
        grupo: (j['g'] ?? '') as String,
        pkA: (j['pa'] as num?)?.toDouble(),
        pkB: (j['pb'] as num?)?.toDouble(),
        cantidad: ((j['c'] ?? 0) as num).toDouble(),
        unidad: (j['u'] ?? '') as String,
        origen: 'APP',
        nota: (j['n'] ?? '') as String,
      );
}

/// Fila cobrable de la hoja "Matriz cant." (solo Túnel 0).
class Cobrable {
  final String grupo;
  final String tarea;
  final String unidad;
  final double? acumulado;
  final double? semanal;
  final double? mensual;

  const Cobrable({
    required this.grupo,
    required this.tarea,
    required this.unidad,
    this.acumulado,
    this.semanal,
    this.mensual,
  });
}

/// Resultado de leer el libro de Excel.
class ReporteImportado {
  final String nombreArchivo;
  final List<Modulo> modulos;
  final bool modulosDelExcel;
  final List<Registro> registros;
  final List<Cobrable> cobrables;
  final List<String> advertencias;
  final Map<String, int> filasPorHoja; // hoja esperada -> filas leídas (0 = no encontrada)
  final DateTime? ultimaFecha;

  const ReporteImportado({
    required this.nombreArchivo,
    required this.modulos,
    required this.modulosDelExcel,
    required this.registros,
    required this.cobrables,
    required this.advertencias,
    required this.filasPorHoja,
    required this.ultimaFecha,
  });
}

// ---------------------------------------------------------------------------
// Catálogo de actividades que se grafican en el modelo
// ---------------------------------------------------------------------------

class DefActividad {
  final String id;
  final String nombre;
  final String grupo;
  final double peso; // peso dentro del avance total del módulo
  final bool porModulo; // true: un registro que cubre ~el módulo lo completa
  final bool dosLados; // viga base: HD + HI
  final String unidad; // unidad de la cantidad que se registra ('' = sin cantidad)

  const DefActividad({
    required this.id,
    required this.nombre,
    required this.grupo,
    required this.peso,
    this.porModulo = false,
    this.dosLados = false,
    this.unidad = '',
  });
}

/// Pesos por defecto (suman 100). Son ajustables. Las actividades que no aplican a un
/// módulo (p. ej. malla donde la columna MALLA dice NO) no entran en su avance total.
const List<DefActividad> kActividades = [
  DefActividad(id: 'imp', nombre: 'Geomembrana (impermeabilización)', grupo: 'Impermeabilización', peso: 14, unidad: 'm'),
  DefActividad(id: 'vb_acero', nombre: 'Viga base - acero', grupo: 'Viga base', peso: 6, dosLados: true, unidad: 'kg'),
  DefActividad(id: 'vb_enc', nombre: 'Viga base - encofrado', grupo: 'Viga base', peso: 4, dosLados: true, unidad: 'm'),
  DefActividad(id: 'vb_conc', nombre: 'Viga base - concreto', grupo: 'Viga base', peso: 10, dosLados: true, unidad: 'm³'),
  DefActividad(id: 'vb_desenc', nombre: 'Viga base - desencofrado', grupo: 'Viga base', peso: 3, dosLados: true, unidad: 'm'),
  DefActividad(id: 'rev_malla', nombre: 'Revestimiento - malla', grupo: 'Revestimiento', peso: 8, unidad: 'kg'),
  DefActividad(id: 'rev_form', nombre: 'Revestimiento - formaleta', grupo: 'Revestimiento', peso: 10, porModulo: true),
  DefActividad(id: 'rev_conc', nombre: 'Revestimiento - concreto', grupo: 'Revestimiento', peso: 35, porModulo: true, unidad: 'm³'),
  DefActividad(id: 'rev_desenc', nombre: 'Revestimiento - desencofrado', grupo: 'Revestimiento', peso: 10, porModulo: true),
];

DefActividad? defPorId(String id) {
  for (final d in kActividades) {
    if (d.id == id) return d;
  }
  return null;
}

/// Clasifica un registro en una actividad del catálogo (o null si no se grafica).
String? clasificarActividad(String actividad, String grupo) {
  final a = norm(actividad);
  if (a.contains('geomembrana')) return 'imp';
  final esViga = a.contains('viga base') || norm(grupo).contains('viga base');
  if (esViga) {
    if (a.contains('desencofrado')) return 'vb_desenc';
    if (a.contains('acero')) return 'vb_acero';
    if (a.contains('encofrado')) return 'vb_enc';
    if (a.contains('concreto') || a.contains('vaciado')) return 'vb_conc';
    return null;
  }
  if (a.contains('desencofrado')) return 'rev_desenc';
  if (a.contains('posicionamiento') || a.contains('formaleta')) return 'rev_form';
  if (a.contains('concreto') &&
      (a.contains('revestimiento') || a.contains('boveda') || a.contains('bovedas'))) {
    return 'rev_conc';
  }
  if (a.contains('malla') && !a.contains('nicho')) return 'rev_malla';
  return null;
}

String ladoDe(String costado, String actividad) {
  final t = ' ${norm('$costado $actividad')} ';
  if (t.contains(' hd ') || t.contains(' derecho ') || t.contains(' derecha ')) return 'HD';
  if (t.contains(' hi ') || t.contains(' izquierdo ') || t.contains(' izquierda ')) return 'HI';
  return '';
}
