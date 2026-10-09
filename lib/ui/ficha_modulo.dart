import 'package:flutter/material.dart';

import '../data/almacen.dart';
import '../data/calculo.dart';
import '../data/modelos.dart';
import '../data/util.dart';
import 'tema.dart';

/// Ficha técnica del módulo (hoja inferior).
void mostrarFichaModulo(BuildContext context, int numero) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tema.superficie,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.58,
      minChildSize: 0.3,
      maxChildSize: 0.94,
      builder: (ctx, controller) => _Ficha(numero: numero, controller: controller),
    ),
  );
}

class _Ficha extends StatelessWidget {
  final int numero;
  final ScrollController controller;
  const _Ficha({required this.numero, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = Almacen.i.progreso(numero);
    if (p == null) {
      return const Center(child: Text('Módulo sin datos'));
    }
    final m = p.modulo;
    final color = Tema.colorEstado(p.estado);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text('MÓDULO ${m.numero}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color),
            ),
            child: Text(Tema.textoEstado(p.estado), style: const TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('${fmtPk(m.pkMin)}  →  ${fmtPk(m.pkMax)}   ·   ${fmtNum(m.longitud, dec: 2)} m',
            style: TextStyle(color: Colors.white.withOpacity(0.75))),
        const SizedBox(height: 14),
        Row(children: [
          Text('${fmtNum(p.total)} %',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Tema.colorAvance(p.total))),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (p.total / 100).clamp(0.0, 1.0).toDouble(),
                minHeight: 12,
                backgroundColor: Colors.white12,
                color: Tema.colorAvance(p.total),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Avance total ponderado del módulo',
            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5))),
        const SizedBox(height: 18),
        const Text('ACTIVIDADES', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        for (final d in kActividades)
          _FilaActividad(def: d, pct: p.pct(d.id), aplica: !p.noAplica.contains(d.id)),
        const SizedBox(height: 14),
        _Dato('Concreto de revestimiento', p.concretoRevM3 > 0 ? '${fmtNum(p.concretoRevM3)} m³' : '—'),
        _Dato('Última actividad', p.ultimaActividad == null ? '—' : fmtFecha(p.ultimaActividad!)),
        if (m.macrofibra.isNotEmpty) _Dato('Macrofibra', m.macrofibra),
        if (m.microfibra.isNotEmpty) _Dato('Microfibra', m.microfibra),
        if (m.malla.isNotEmpty) _Dato('Malla electrosoldada', m.malla),
        const SizedBox(height: 16),
        const Text('HISTORIAL', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 6),
        if (p.historial.isEmpty)
          Text('Sin registros para este módulo.', style: TextStyle(color: Colors.white.withOpacity(0.55)))
        else
          for (final r in p.historial.take(30)) _FilaHistorial(r: r),
        const SizedBox(height: 16),
        Text('Fotografías y observaciones por módulo: próxima fase.',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.45))),
      ],
    );
  }
}

class _FilaActividad extends StatelessWidget {
  final DefActividad def;
  final double pct;
  final bool aplica;
  const _FilaActividad({required this.def, required this.pct, required this.aplica});

  @override
  Widget build(BuildContext context) {
    if (!aplica) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
              child: Text(def.nombre,
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4)))),
          Text('No aplica', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(flex: 5, child: Text(def.nombre, style: const TextStyle(fontSize: 13))),
        Expanded(
          flex: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              backgroundColor: Colors.white12,
              color: Tema.colorAvance(pct),
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text('${fmtNum(pct, dec: 0)} %', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
        ),
      ]),
    );
  }
}

class _Dato extends StatelessWidget {
  final String k;
  final String v;
  const _Dato(this.k, this.v);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(k, style: TextStyle(color: Colors.white.withOpacity(0.65)))),
        Text(v),
      ]),
    );
  }
}

class _FilaHistorial extends StatelessWidget {
  final Registro r;
  const _FilaHistorial({required this.r});
  @override
  Widget build(BuildContext context) {
    final cant = r.cantidad > 0 ? ' · ${fmtNum(r.cantidad)} ${r.unidad}' : '';
    final lado = r.lado.isEmpty ? '' : ' (${r.lado})';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 82,
          child: Text(r.fecha == null ? '—' : fmtFecha(r.fecha!),
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
        ),
        Expanded(
          child: Text('${r.actividad}$lado$cant${r.turno.isEmpty ? '' : ' · ${r.turno}'}',
              style: const TextStyle(fontSize: 12.5)),
        ),
        if (r.origen == 'BASE')
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.flag_outlined, size: 14, color: Colors.white54),
          ),
        if (r.origen == 'APP')
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.phone_android, size: 14, color: Tema.acento),
          ),
      ]),
    );
  }
}
