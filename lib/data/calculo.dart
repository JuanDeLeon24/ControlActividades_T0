import 'dart:math' as math;

import 'modelos.dart';
import 'util.dart';

enum EstadoModulo { noIniciado, enEjecucion, retrasado, terminado }

/// Días sin registros a partir de los cuales un módulo iniciado se marca "retrasado".
const int kDiasSinActividadRetraso = 7;

class ProgresoModulo {
  final Modulo modulo;
  /// Cobertura 0..1 por id de actividad.
  final Map<String, double> cobertura;
  final double total; // 0..100
  final DateTime? ultimaActividad;
  final double concretoRevM3;
  final List<Registro> historial;
  final EstadoModulo estado;
  /// Actividades que no aplican a este módulo (p. ej. malla donde MALLA = NO).
  final Set<String> noAplica;

  const ProgresoModulo({
    required this.modulo,
    required this.cobertura,
    required this.total,
    required this.ultimaActividad,
    required this.concretoRevM3,
    required this.historial,
    required this.estado,
    required this.noAplica,
  });

  double pct(String idActividad) => (cobertura[idActividad] ?? 0) * 100;
}

class PuntoCurva {
  final DateTime fecha;
  final double acumulado;
  const PuntoCurva(this.fecha, this.acumulado);
}

class Indicadores {
  final double avanceTotal;
  final double metrosRevestidos;
  final double metrosFaltantes;
  final double longitudTotal;
  final int modulosTerminados;
  final int modulosEnEjecucion;
  final int modulosRetrasados;
  final int modulosNoIniciados;
  final double concretoRevM3;
  final double concretoVigaM3;
  final double concretoSemanaM3;
  final double concretoMesM3;
  final double metrosSemana;
  final double metrosMes;
  final double velocidadMDia; // m de revestimiento / día (últimos 30 días)
  final DateTime? fechaEstimadaFin;
  final Map<String, double> avancePorGrupo; // % ponderado por longitud
  final List<PuntoCurva> curvaS; // m de revestimiento acumulados vs fecha
  final DateTime? fechaReferencia;

  const Indicadores({
    required this.avanceTotal,
    required this.metrosRevestidos,
    required this.metrosFaltantes,
    required this.longitudTotal,
    required this.modulosTerminados,
    required this.modulosEnEjecucion,
    required this.modulosRetrasados,
    required this.modulosNoIniciados,
    required this.concretoRevM3,
    required this.concretoVigaM3,
    required this.concretoSemanaM3,
    required this.concretoMesM3,
    required this.metrosSemana,
    required this.metrosMes,
    required this.velocidadMDia,
    required this.fechaEstimadaFin,
    required this.avancePorGrupo,
    required this.curvaS,
    required this.fechaReferencia,
  });
}

class ResultadoCalculo {
  final Map<int, ProgresoModulo> porModulo;
  final Indicadores kpi;
  const ResultadoCalculo(this.porModulo, this.kpi);
}

class Calculo {
  static ResultadoCalculo calcular(List<Modulo> modulos, List<Registro> registros) {
    // Fecha de referencia = último registro del reporte (no la fecha del teléfono).
    DateTime? ref;
    for (final r in registros) {
      if (r.fecha != null && (ref == null || r.fecha!.isAfter(ref))) ref = r.fecha;
    }

    // intervalos[modulo][actividad|lado] = lista de [lo, hi] ya recortados al módulo
    final intervalos = <int, Map<String, List<List<double>>>>{};
    final ultima = <int, DateTime>{};
    final historial = <int, List<Registro>>{};
    final m3 = <int, double>{};
    final finRevConc = <int, DateTime>{}; // fecha del último vaciado que cubre el módulo

    final clasif = <Registro, String?>{};
    for (final r in registros) {
      clasif[r] = clasificarActividad(r.actividad, r.grupo);
    }

    for (final r in registros) {
      final lo = r.pkMin;
      final hi = r.pkMax;
      if (lo == null || hi == null) continue;
      final idAct = clasif[r];
      final largo = hi - lo;
      final puntual = largo < 0.05;

      for (final m in modulos) {
        if (puntual) {
          if (lo < m.pkMin - 1e-6 || lo > m.pkMax + 1e-6) continue;
        } else {
          final solape = math.min(hi, m.pkMax) - math.max(lo, m.pkMin);
          if (solape <= 0.05) continue;
        }
        historial.putIfAbsent(m.numero, () => <Registro>[]).add(r);
        if (r.fecha != null) {
          final u = ultima[m.numero];
          if (u == null || r.fecha!.isAfter(u)) ultima[m.numero] = r.fecha!;
        }
        if (puntual) continue;

        final a = math.max(lo, m.pkMin);
        final b = math.min(hi, m.pkMax);
        if (idAct == 'rev_conc' && (r.unidad.isEmpty || esUnidadVolumen(r.unidad))) {
          m3[m.numero] = (m3[m.numero] ?? 0) + r.cantidad * ((b - a) / largo);
        }
        if (idAct == null) continue;

        final def = defPorId(idAct)!;
        var ia = a;
        var ib = b;
        // Actividades "por módulo": el registro cubre el módulo completo si lo abarca en >= 60 %;
        // si solo lo roza (cota de formaleta/PK ligeramente corrida) no suma nada al vecino.
        if (def.porModulo) {
          if ((b - a) / m.longitud < 0.6) continue;
          ia = m.pkMin;
          ib = m.pkMax;
          if (idAct == 'rev_conc' && r.fecha != null) {
            final u = finRevConc[m.numero];
            if (u == null || r.fecha!.isAfter(u)) finRevConc[m.numero] = r.fecha!;
          }
        }
        final lado = def.dosLados ? r.lado : '';
        intervalos
            .putIfAbsent(m.numero, () => <String, List<List<double>>>{})
            .putIfAbsent('$idAct|$lado', () => <List<double>>[])
            .add([ia, ib]);
      }
    }

    double cobertura(int numero, String id, bool dosLados, double lon) {
      final mapa = intervalos[numero];
      if (mapa == null) return 0;
      double cub(String clave) {
        final lista = mapa[clave];
        if (lista == null || lista.isEmpty) return 0;
        final ord = List<List<double>>.from(lista)..sort((x, y) => x[0].compareTo(y[0]));
        var total = 0.0;
        var ini = ord[0][0];
        var fin = ord[0][1];
        for (var i = 1; i < ord.length; i++) {
          if (ord[i][0] <= fin) {
            if (ord[i][1] > fin) fin = ord[i][1];
          } else {
            total += fin - ini;
            ini = ord[i][0];
            fin = ord[i][1];
          }
        }
        total += fin - ini;
        return (total / lon).clamp(0.0, 1.0);
      }

      if (!dosLados) {
        // sin lados: se toma la mejor cobertura entre todas las variantes
        var mejor = 0.0;
        for (final k in mapa.keys) {
          if (k.startsWith('$id|')) mejor = math.max(mejor, cub(k));
        }
        return mejor;
      }
      final sin = cub('$id|');
      final hd = math.max(cub('$id|HD'), sin);
      final hi = math.max(cub('$id|HI'), sin);
      return (hd + hi) / 2;
    }

    final porModulo = <int, ProgresoModulo>{};

    for (final m in modulos) {
      final cob = <String, double>{};
      final noAplica = <String>{};
      var suma = 0.0;
      var pesoTotal = 0.0;
      for (final d in kActividades) {
        final c = cobertura(m.numero, d.id, d.dosLados, m.longitud);
        cob[d.id] = c;
        // La malla solo cuenta donde Módulos_VB la exige (SI) o ya se instaló (nichos SOS).
        if (d.id == 'rev_malla' && !m.mallaRequerida && c <= 0) {
          noAplica.add(d.id);
          continue;
        }
        suma += c * d.peso;
        pesoTotal += d.peso;
      }
      final total = pesoTotal == 0 ? 0.0 : (suma / pesoTotal) * 100;
      final u = ultima[m.numero];

      EstadoModulo estado;
      if (total <= 0.0) {
        estado = EstadoModulo.noIniciado;
      } else if (total >= 99.5) {
        estado = EstadoModulo.terminado;
      } else if (ref != null && u != null && ref.difference(u).inDays > kDiasSinActividadRetraso) {
        estado = EstadoModulo.retrasado;
      } else {
        estado = EstadoModulo.enEjecucion;
      }

      final hist = List<Registro>.from(historial[m.numero] ?? const <Registro>[]);
      hist.sort((x, y) {
        final fx = x.fecha, fy = y.fecha;
        if (fx == null && fy == null) return 0;
        if (fx == null) return 1;
        if (fy == null) return -1;
        return fy.compareTo(fx);
      });

      porModulo[m.numero] = ProgresoModulo(
        modulo: m,
        cobertura: cob,
        total: total,
        ultimaActividad: u,
        concretoRevM3: m3[m.numero] ?? 0,
        historial: hist,
        estado: estado,
        noAplica: noAplica,
      );
    }

    return ResultadoCalculo(porModulo, _indicadores(modulos, registros, porModulo, clasif, finRevConc, ref));
  }

  static Indicadores _indicadores(
    List<Modulo> modulos,
    List<Registro> registros,
    Map<int, ProgresoModulo> prog,
    Map<Registro, String?> clasif,
    Map<int, DateTime> finRevConc,
    DateTime? ref,
  ) {
    var longTotal = 0.0;
    var pondTotal = 0.0;
    var metrosRev = 0.0;
    var term = 0, ejec = 0, retr = 0, noIni = 0;
    final sumaGrupo = <String, double>{};
    final pesoGrupo = <String, double>{};

    for (final m in modulos) {
      final p = prog[m.numero]!;
      longTotal += m.longitud;
      pondTotal += p.total * m.longitud;
      metrosRev += (p.cobertura['rev_conc'] ?? 0) * m.longitud;
      switch (p.estado) {
        case EstadoModulo.terminado:
          term++;
          break;
        case EstadoModulo.enEjecucion:
          ejec++;
          break;
        case EstadoModulo.retrasado:
          retr++;
          break;
        case EstadoModulo.noIniciado:
          noIni++;
          break;
      }
      for (final g in ['Impermeabilización', 'Viga base', 'Revestimiento']) {
        var s = 0.0, w = 0.0;
        for (final d in kActividades) {
          if (d.grupo != g || p.noAplica.contains(d.id)) continue;
          s += (p.cobertura[d.id] ?? 0) * d.peso;
          w += d.peso;
        }
        if (w > 0) {
          sumaGrupo[g] = (sumaGrupo[g] ?? 0) + (s / w) * 100 * m.longitud;
          pesoGrupo[g] = (pesoGrupo[g] ?? 0) + m.longitud;
        }
      }
    }
    final porGrupo = <String, double>{};
    sumaGrupo.forEach((g, s) {
      final w = pesoGrupo[g] ?? 0;
      porGrupo[g] = w == 0 ? 0 : s / w;
    });

    var concRev = 0.0, concViga = 0.0, concSem = 0.0, concMes = 0.0;
    var mSem = 0.0, mMes = 0.0;

    for (final r in registros) {
      final id = clasif[r];
      if (id != 'rev_conc' && id != 'vb_conc') continue;
      final q = (r.unidad.isEmpty || esUnidadVolumen(r.unidad)) ? r.cantidad : 0.0;
      if (id == 'rev_conc') {
        concRev += q;
        if (r.fecha != null && ref != null) {
          final dia = DateTime(r.fecha!.year, r.fecha!.month, r.fecha!.day);
          final dd = ref.difference(dia).inDays;
          if (dd >= 0 && dd < 7) concSem += q;
          if (dd >= 0 && dd < 30) concMes += q;
        }
      } else {
        concViga += q;
      }
    }

    // Curva S y ritmo: metros de revestimiento por fecha en que se completó el vaciado de cada módulo.
    final porFecha = <DateTime, double>{};
    for (final m in modulos) {
      final f = finRevConc[m.numero];
      if (f == null) continue;
      final cov = prog[m.numero]?.cobertura['rev_conc'] ?? 0;
      if (cov < 0.99) continue;
      final dia = DateTime(f.year, f.month, f.day);
      porFecha[dia] = (porFecha[dia] ?? 0) + m.longitud;
      if (ref != null) {
        final dd = ref.difference(dia).inDays;
        if (dd >= 0 && dd < 7) mSem += m.longitud;
        if (dd >= 0 && dd < 30) mMes += m.longitud;
      }
    }

    final dias = porFecha.keys.toList()..sort();
    final curva = <PuntoCurva>[];
    var acum = 0.0;
    for (final d in dias) {
      acum += porFecha[d]!;
      curva.add(PuntoCurva(d, acum));
    }

    final vel = mMes / 30.0;
    final faltan = math.max(0.0, longTotal - metrosRev);
    DateTime? fin;
    if (ref != null && vel > 0.01) {
      fin = ref.add(Duration(days: (faltan / vel).ceil()));
    }

    return Indicadores(
      avanceTotal: longTotal == 0 ? 0 : pondTotal / longTotal,
      metrosRevestidos: metrosRev,
      metrosFaltantes: faltan,
      longitudTotal: longTotal,
      modulosTerminados: term,
      modulosEnEjecucion: ejec,
      modulosRetrasados: retr,
      modulosNoIniciados: noIni,
      concretoRevM3: concRev,
      concretoVigaM3: concViga,
      concretoSemanaM3: concSem,
      concretoMesM3: concMes,
      metrosSemana: mSem,
      metrosMes: mMes,
      velocidadMDia: vel,
      fechaEstimadaFin: fin,
      avancePorGrupo: porGrupo,
      curvaS: curva,
      fechaReferencia: ref,
    );
  }
}
