import 'dart:typed_data';

import 'modelos.dart';
import 'util.dart';
import 'xlsx_reader.dart';

/// Nombres de hoja esperados (no cambian, según el equipo de obra).
const String kHojaMatriz = 'Matriz cant.';
const String kHojaAvances = 'Avances_Diarios';
const String kHojaBd = 'BD_Actividades';
const String kHojaModulos = 'Módulos_VB';
const String kHojaDia = 'Formato Túnel_Dia';
const String kHojaNoche = 'Formato Túnel_Noche';

class ArgsParseo {
  final Uint8List bytes;
  final String nombre;
  const ArgsParseo(this.bytes, this.nombre);
}

/// Función de nivel superior para poder ejecutarla con `compute` (otro isolate).
ReporteImportado parsearReporte(ArgsParseo a) {
  final adv = <String>[];
  final filas = <String, int>{};

  final esperadas = [kHojaMatriz, kHojaAvances, kHojaBd, kHojaModulos, kHojaDia, kHojaNoche];
  final libro = XlsxReader.leer(a.bytes, soloHojas: esperadas.map(normClave).toSet());

  for (final h in esperadas) {
    final x = libro.hoja(h);
    filas[h] = x == null ? 0 : x.filas.length;
    if (x == null) {
      adv.add('No se encontró la hoja "$h".');
    }
  }

  // --- Módulos -------------------------------------------------------------
  var modulos = <Modulo>[];
  var delExcel = false;
  final hMod = libro.hoja(kHojaModulos);
  if (hMod != null) modulos = _leerModulos(hMod, adv);
  if (modulos.length >= 5) {
    delExcel = true;
  } else {
    adv.add('No se pudieron leer los módulos de "$kHojaModulos"; se usan los 137 módulos de referencia.');
    modulos = modulosPorDefecto();
  }

  // --- Registros -----------------------------------------------------------
  final registros = <Registro>[];
  final hBd = libro.hoja(kHojaBd);
  if (hBd != null) registros.addAll(_leerBd(hBd, adv));
  // Avances_Diarios es un resumen de BD_Actividades (cada fila apunta a "Fila BD"):
  // solo se usa si BD_Actividades no aportó nada, para no contar dos veces.
  final hAv = libro.hoja(kHojaAvances);
  if (hAv != null) {
    final deAvances = _leerAvances(hAv, adv);
    if (registros.isEmpty) registros.addAll(deAvances);
  }

  // Quitar duplicados (lo mismo suele estar en BD_Actividades y Avances_Diarios)
  final vistos = <String>{};
  final unicos = <Registro>[];
  for (final r in registros) {
    if (vistos.add(r.claveDedupe)) unicos.add(r);
  }

  // --- Cobrables -----------------------------------------------------------
  final hMat = libro.hoja(kHojaMatriz);
  final cobrables = hMat == null ? <Cobrable>[] : _leerMatriz(hMat, adv);

  DateTime? ultima;
  for (final r in unicos) {
    if (r.fecha != null && (ultima == null || r.fecha!.isAfter(ultima))) ultima = r.fecha;
  }

  return ReporteImportado(
    nombreArchivo: a.nombre,
    modulos: modulos,
    modulosDelExcel: delExcel,
    registros: unicos,
    cobrables: cobrables,
    advertencias: adv,
    filasPorHoja: filas,
    ultimaFecha: ultima,
  );
}

// ---------------------------------------------------------------------------
// Utilidades de encabezados
// ---------------------------------------------------------------------------

/// Busca en las primeras [maxFilas] filas la primera que contenga TODAS las
/// palabras clave (normalizadas). Devuelve el índice de fila o -1.
int _buscarEncabezado(Hoja h, List<String> claves, {int maxFilas = 40}) {
  final n = h.filas.length < maxFilas ? h.filas.length : maxFilas;
  for (var i = 0; i < n; i++) {
    final textos = h.filas[i].map((v) => v == null ? '' : norm(aTexto(v))).toSet();
    if (claves.every((k) => textos.contains(k))) return i;
  }
  return -1;
}

/// Primera columna cuyo encabezado cumple [cond]; -1 si no hay.
int _col(Hoja h, int filaEnc, bool Function(String) cond) {
  if (filaEnc < 0 || filaEnc >= h.filas.length) return -1;
  final fila = h.filas[filaEnc];
  for (var c = 0; c < fila.length; c++) {
    final v = fila[c];
    if (v == null) continue;
    if (cond(norm(aTexto(v)))) return c;
  }
  return -1;
}

Object? _en(List<Object?> fila, int col) {
  if (col < 0 || col >= fila.length) return null;
  return fila[col];
}

// ---------------------------------------------------------------------------
// Módulos_VB
// ---------------------------------------------------------------------------

List<Modulo> _leerModulos(Hoja h, List<String> adv) {
  var enc = _buscarEncabezado(h, ['modulo']);
  var cMod = 0, cIni = 1, cFin = 2, cMacro = 4, cMicro = 5, cMalla = 6;
  var inicio = 4;
  if (enc >= 0) {
    final a = _col(h, enc, (t) => t == 'modulo' || t == 'modulos' || t == 'no' || t == 'n');
    final b = _col(h, enc, (t) => t.contains('pk') && t.contains('ini'));
    final c = _col(h, enc, (t) => t.contains('pk') && t.contains('fin'));
    if (a >= 0 && b >= 0 && c >= 0) {
      cMod = a;
      cIni = b;
      cFin = c;
      cMacro = _col(h, enc, (t) => t.contains('macro'));
      cMicro = _col(h, enc, (t) => t.contains('micro'));
      cMalla = _col(h, enc, (t) => t.contains('malla'));
      inicio = enc + 1;
    } else {
      adv.add('"$kHojaModulos": no se reconocieron las columnas por nombre; se usan las posiciones A-G.');
    }
  } else {
    adv.add('"$kHojaModulos": no se encontró la fila de encabezados; se usan las posiciones A-G desde la fila 5.');
  }

  final out = <Modulo>[];
  final usados = <int>{};
  for (var i = inicio; i < h.filas.length; i++) {
    final f = h.filas[i];
    final num = aNumero(_en(f, cMod));
    final pa = parsePk(_en(f, cIni));
    final pb = parsePk(_en(f, cFin));
    if (num == null || pa == null || pb == null) continue;
    final n = num.round();
    if (n <= 0 || (num - n).abs() > 1e-6 || usados.contains(n)) continue;
    if ((pa - pb).abs() < 0.01) continue;
    usados.add(n);
    out.add(Modulo(
      numero: n,
      pkMin: pa < pb ? pa : pb,
      pkMax: pa > pb ? pa : pb,
      macrofibra: aTexto(_en(f, cMacro)),
      microfibra: aTexto(_en(f, cMicro)),
      malla: aTexto(_en(f, cMalla)),
    ));
  }
  out.sort((x, y) => x.numero.compareTo(y.numero));
  return out;
}

// ---------------------------------------------------------------------------
// BD_Actividades  (histórico completo)
// ---------------------------------------------------------------------------

List<Registro> _leerBd(Hoja h, List<String> adv) {
  var enc = _buscarEncabezado(h, ['fecha', 'actividad']);
  var cFecha = 0, cTurno = 1, cAct = 2, cFrente = 3, cGrupo = 4, cUnd = 5;
  var cPkI = 6, cPkF = 7, cEt1 = 8, cD1 = 9, cEt2 = 10, cD2 = 11;
  var inicio = 5;
  if (enc >= 0) {
    cFecha = _col(h, enc, (t) => t == 'fecha');
    cTurno = _col(h, enc, (t) => t == 'turno');
    cAct = _col(h, enc, (t) => t == 'actividad');
    cFrente = _col(h, enc, (t) => t == 'frente' || t == 'costado');
    cGrupo = _col(h, enc, (t) => t == 'grupo');
    cUnd = _col(h, enc, (t) => t == 'und' || t == 'unidad' || t == 'und.');
    cPkI = _col(h, enc, (t) => t.contains('pk') && t.contains('ini'));
    cPkF = _col(h, enc, (t) => t.contains('pk') && t.contains('fin'));
    cEt1 = _col(h, enc, (t) => t.contains('dato 1') && t.contains('que'));
    cD1 = _col(h, enc, (t) => t == 'dato 1');
    cEt2 = _col(h, enc, (t) => t.contains('dato 2') && t.contains('que'));
    cD2 = _col(h, enc, (t) => t == 'dato 2');
    inicio = enc + 1;
    if (cFecha < 0 || cAct < 0) {
      adv.add('"$kHojaBd": encabezados incompletos; se usan las posiciones por defecto.');
      cFecha = 0;
      cAct = 2;
    }
  } else {
    adv.add('"$kHojaBd": no se encontró la fila de encabezados; se usan las posiciones por defecto.');
  }

  final out = <Registro>[];
  var sinPk = 0;
  var galeria = 0;
  for (var i = inicio; i < h.filas.length; i++) {
    final f = h.filas[i];
    final act = aTexto(_en(f, cAct));
    if (act.isEmpty) continue;
    final fecha = aFecha(_en(f, cFecha));
    if (fecha == null) continue;
    final frente = norm(aTexto(_en(f, cFrente)));
    if (frente.isNotEmpty && !frente.contains('tunel 0')) {
      if (frente == 'g t0') {
        galeria++;
      }
      continue; // otros túneles / galería: no se grafican en el modelo del Túnel 0
    }
    final pa = parsePk(_en(f, cPkI));
    final pb = parsePk(_en(f, cPkF));
    if (pa == null || pb == null) sinPk++;

    // Cantidad: se toma el "dato" cuya etiqueta habla de cantidad/volumen; si no, el primero numérico.
    final e1 = norm(aTexto(_en(f, cEt1)));
    final e2 = norm(aTexto(_en(f, cEt2)));
    final d1 = aNumero(_en(f, cD1));
    final d2 = aNumero(_en(f, cD2));
    double cant = 0;
    bool habla(String e) => e.contains('cantidad') || e.contains('volumen') || e.contains('m3');
    if (d1 != null && habla(e1)) {
      cant = d1;
    } else if (d2 != null && habla(e2)) {
      cant = d2;
    } else if (d1 != null) {
      cant = d1;
    } else if (d2 != null) {
      cant = d2;
    }

    final costado = aTexto(_en(f, cFrente));
    out.add(Registro(
      fecha: fecha,
      turno: aTexto(_en(f, cTurno)),
      actividad: act,
      lado: ladoDe(costado, act),
      grupo: aTexto(_en(f, cGrupo)),
      pkA: pa,
      pkB: pb,
      cantidad: cant,
      unidad: aTexto(_en(f, cUnd)),
      origen: 'BD',
    ));
  }
  if (sinPk > 0) {
    adv.add('"$kHojaBd": $sinPk registros del Túnel 0 sin PK inicial/final (no se pueden ubicar).');
  }
  if (galeria > 0) {
    adv.add('"$kHojaBd": $galeria registros de la galería (G-T0) no se grafican todavía (falta su geometría).');
  }
  return out;
}

// ---------------------------------------------------------------------------
// Avances_Diarios
// ---------------------------------------------------------------------------

List<Registro> _leerAvances(Hoja h, List<String> adv) {
  var enc = _buscarEncabezado(h, ['actividad', 'fecha'], maxFilas: 15);
  var cAct = 0, cCos = 1, cFecha = 2, cTurno = 3, cPkI = 4, cPkF = 5;
  var cCant = 7, cUnd = 8, cPct = 10;
  var inicio = 3;
  if (enc >= 0) {
    cAct = _col(h, enc, (t) => t == 'actividad');
    cCos = _col(h, enc, (t) => t == 'costado');
    cFecha = _col(h, enc, (t) => t == 'fecha');
    cTurno = _col(h, enc, (t) => t == 'turno');
    cPkI = _col(h, enc, (t) => t.contains('pk') && t.contains('ini'));
    cPkF = _col(h, enc, (t) => t.contains('pk') && t.contains('fin'));
    cCant = _col(h, enc, (t) => t == 'cantidad');
    cUnd = _col(h, enc, (t) => t == 'und' || t == 'unidad');
    cPct = _col(h, enc, (t) => t.contains('avance'));
    inicio = enc + 1;
    if (cAct < 0 || cFecha < 0) {
      adv.add('"$kHojaAvances": encabezados incompletos; se usan las posiciones por defecto.');
      cAct = 0;
      cFecha = 2;
    }
  } else {
    adv.add('"$kHojaAvances": no se encontró la fila de encabezados; se usan las posiciones por defecto.');
  }

  final out = <Registro>[];
  for (var i = inicio; i < h.filas.length; i++) {
    final f = h.filas[i];
    final act = aTexto(_en(f, cAct));
    if (act.isEmpty) continue;
    final na = norm(act);
    if (na.startsWith('avance') || na.startsWith('tunel')) continue; // títulos de sección
    final fecha = aFecha(_en(f, cFecha));
    if (fecha == null) continue;
    final pa = parsePk(_en(f, cPkI));
    final pb = parsePk(_en(f, cPkF));
    var pct = aNumero(_en(f, cPct));
    if (pct != null && pct <= 1.0) pct = pct * 100; // Excel guarda 0.604 como 60.4 %
    out.add(Registro(
      fecha: fecha,
      turno: aTexto(_en(f, cTurno)),
      actividad: act,
      lado: ladoDe(aTexto(_en(f, cCos)), act),
      pkA: pa,
      pkB: pb,
      cantidad: aNumero(_en(f, cCant)) ?? 0,
      unidad: aTexto(_en(f, cUnd)),
      avancePct: pct,
      origen: 'AVANCES',
    ));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Matriz cant. (actividades cobrables del Túnel 0)
// ---------------------------------------------------------------------------

List<Cobrable> _leerMatriz(Hoja h, List<String> adv) {
  final enc = _buscarEncabezado(h, ['tramo'], maxFilas: 10);
  if (enc < 0) {
    adv.add('"$kHojaMatriz": no se encontró la fila de encabezados (TRAMO).');
    return <Cobrable>[];
  }
  final cTramo = _col(h, enc, (t) => t == 'tramo');
  final cGrupo = _col(h, enc, (t) => t == 'grupo');
  final cTarea = _col(h, enc, (t) => t.contains('nombre'));
  final cUnd = _col(h, enc, (t) => t == 'unidad' || t == 'und');
  final cSuma = _col(h, enc, (t) => t == 'suma');
  // Columnas con fecha = semanas (el encabezado es una fecha); se toma el bloque anterior a SUMA.
  final fechasCols = <int>[];
  final fila = h.filas[enc];
  for (var c = 0; c < fila.length; c++) {
    if (cSuma >= 0 && c >= cSuma) break;
    if (fila[c] is DateTime) fechasCols.add(c);
  }
  final cUltSem = fechasCols.isEmpty ? -1 : fechasCols.last;

  final out = <Cobrable>[];
  for (var i = enc + 1; i < h.filas.length; i++) {
    final f = h.filas[i];
    if (!norm(aTexto(_en(f, cTramo))).contains('tunel 0')) continue;
    final und = aTexto(_en(f, cUnd));
    final tarea = aTexto(_en(f, cTarea));
    if (tarea.isEmpty || und.isEmpty) continue; // filas de título / subtotales
    out.add(Cobrable(
      grupo: aTexto(_en(f, cGrupo)),
      tarea: tarea,
      unidad: und,
      acumulado: cSuma >= 0 ? aNumero(_en(f, cSuma)) : null,
      semanal: cUltSem >= 0 ? aNumero(_en(f, cUltSem)) : null,
    ));
  }
  if (out.isEmpty) {
    adv.add('"$kHojaMatriz": no se encontraron filas cobrables del Túnel 0.');
  }
  return out;
}
