import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calculo.dart';
import 'linea_base.dart';
import 'modelos.dart';
import 'parser_reporte.dart';
import 'util.dart';

/// Estado único de la app. Guarda una copia del último Excel importado y las
/// manuales cargadas a mano, y recalcula el avance cada vez que algo cambia.
class Almacen extends ChangeNotifier {
  Almacen._();
  static final Almacen i = Almacen._();

  static const String _archivoLocal = 'reporte_diario.xlsx';
  static const String _kNombre = 'archivo_nombre';
  static const String _kFecha = 'archivo_importado_en';
  static const String _kJornadas = 'jornadas_json';

  List<Modulo> modulos = modulosPorDefecto();
  List<Registro> registrosExcel = <Registro>[];
  List<Registro> manuales = <Registro>[];
  List<Cobrable> cobrables = <Cobrable>[];
  List<String> advertencias = <String>[];
  Map<String, int> filasPorHoja = <String, int>{};
  DateTime? ultimaFecha;
  String? nombreArchivo;
  DateTime? importadoEn;
  bool modulosDelExcel = false;
  bool cargando = false;
  String? error;

  late ResultadoCalculo resultado = Calculo.calcular(modulos, lineaBase(modulos));

  /// Siempre hay datos: la línea base ya viene cargada.
  bool get hayDatos => true;
  bool get hayExcel => registrosExcel.isNotEmpty;
  List<Registro> get todosLosRegistros => <Registro>[...registrosExcel, ...lineaBase(modulos), ...manuales];
  Indicadores get kpi => resultado.kpi;
  ProgresoModulo? progreso(int numero) => resultado.porModulo[numero];

  Future<void> iniciar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kJornadas);
      if (raw != null && raw.isNotEmpty) {
        final lista = jsonDecode(raw) as List<dynamic>;
        manuales = lista.map((e) => Registro.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      }
      nombreArchivo = prefs.getString(_kNombre);
      final f = prefs.getString(_kFecha);
      importadoEn = f == null ? null : DateTime.tryParse(f);

      final dir = await getApplicationDocumentsDirectory();
      final archivo = File('${dir.path}/$_archivoLocal');
      if (await archivo.exists()) {
        final bytes = await archivo.readAsBytes();
        await _procesar(bytes, nombreArchivo ?? _archivoLocal, guardarCopia: false);
        return;
      }
    } catch (e) {
      error = 'No se pudo restaurar el último reporte: $e';
    }
    _recalcular();
  }

  /// Importa un Excel (.xlsx/.xlsm) y actualiza el avance.
  Future<void> importar(Uint8List bytes, String nombre) async {
    await _procesar(bytes, nombre, guardarCopia: true);
  }

  Future<void> _procesar(Uint8List bytes, String nombre, {required bool guardarCopia}) async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final r = await compute(parsearReporte, ArgsParseo(bytes, nombre));
      modulos = r.modulos;
      modulosDelExcel = r.modulosDelExcel;
      registrosExcel = r.registros;
      cobrables = r.cobrables;
      advertencias = r.advertencias;
      filasPorHoja = r.filasPorHoja;
      ultimaFecha = r.ultimaFecha;
      nombreArchivo = nombre;

      if (guardarCopia) {
        final dir = await getApplicationDocumentsDirectory();
        await File('${dir.path}/$_archivoLocal').writeAsBytes(bytes, flush: true);
        importadoEn = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kNombre, nombre);
        await prefs.setString(_kFecha, importadoEn!.toIso8601String());
      }
    } catch (e) {
      error = 'No se pudo leer el archivo: $e';
    }
    cargando = false;
    _recalcular();
  }

  /// Agrega una actividad cargada a mano desde la app (se guarda en el teléfono).
  Future<void> agregarManual(Registro r) async {
    manuales.add(r);
    await _guardarJornadas();
    _recalcular();
  }

  Future<void> eliminarManual(Registro r) async {
    manuales.remove(r);
    await _guardarJornadas();
    _recalcular();
  }

  /// Abscisa más avanzada (la menor, el túnel se construye hacia K6+178) con registros de [idActividad].
  double? frenteActual(String idActividad) {
    double? f;
    for (final r in todosLosRegistros) {
      if (clasificarActividad(r.actividad, r.grupo) != idActividad) continue;
      final lo = r.pkMin;
      if (lo == null) continue;
      if (f == null || lo < f) f = lo;
    }
    return f;
  }

  Future<void> _guardarJornadas() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kJornadas, jsonEncode(manuales.map((j) => j.toJson()).toList()));
  }

  void _recalcular() {
    // Línea base + actividades manuales + Excel. Si el Excel ya trae la misma actividad el mismo
    // día sobre el mismo tramo, se usa el del Excel y se descarta el otro (no se duplica).
    final delExcel = <({String dia, String id, String lado, double lo, double hi})>[];
    for (final e in registrosExcel) {
      final id = clasificarActividad(e.actividad, e.grupo);
      if (id == null || e.fecha == null || e.pkMin == null || e.pkMax == null) continue;
      delExcel.add((dia: fmtFecha(e.fecha!), id: id, lado: e.lado, lo: e.pkMin!, hi: e.pkMax!));
    }

    bool duplicado(Registro r) {
      if (r.fecha == null || r.pkMin == null || r.pkMax == null) return false;
      final id = clasificarActividad(r.actividad, r.grupo);
      if (id == null) return false;
      final dia = fmtFecha(r.fecha!);
      final largo = r.pkMax! - r.pkMin!;
      for (final e in delExcel) {
        if (e.dia != dia || e.id != id) continue;
        if (e.lado.isNotEmpty && r.lado.isNotEmpty && e.lado != r.lado) continue;
        final solape = (e.hi < r.pkMax! ? e.hi : r.pkMax!) - (e.lo > r.pkMin! ? e.lo : r.pkMin!);
        if (solape >= 0.6 * largo) return true;
      }
      return false;
    }

    final extra = <Registro>[
      for (final r in lineaBase(modulos))
        if (!duplicado(r)) r,
      for (final r in manuales)
        if (!duplicado(r)) r,
    ];
    resultado = Calculo.calcular(modulos, <Registro>[...registrosExcel, ...extra]);
    notifyListeners();
  }
}
