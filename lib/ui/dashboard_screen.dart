import 'package:flutter/material.dart';

import '../data/almacen.dart';
import '../data/calculo.dart';
import '../data/util.dart';
import 'tema.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard · Túnel 0')),
      body: ListenableBuilder(
        listenable: Almacen.i,
        builder: (context, _) {
          final a = Almacen.i;
          final k = a.kpi;
          if (!a.hayDatos) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Importa el reporte diario para ver los indicadores.', textAlign: TextAlign.center),
            ));
          }
          final retrasados = a.resultado.porModulo.values
              .where((p) => p.estado == EstadoModulo.retrasado)
              .toList()
            ..sort((x, y) => x.modulo.numero.compareTo(y.modulo.numero));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Corte: ${k.fechaReferencia == null ? '—' : fmtFecha(k.fechaReferencia!)}',
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
              const SizedBox(height: 10),
              _Tarjeta(
                titulo: 'Avance total del túnel',
                hijo: Row(children: [
                  Text('${fmtNum(k.avanceTotal)} %',
                      style: TextStyle(
                          fontSize: 34, fontWeight: FontWeight.w800, color: Tema.colorAvance(k.avanceTotal))),
                  const SizedBox(width: 14),
                  Expanded(child: _Barra(valor: k.avanceTotal)),
                ]),
              ),
              Row(children: [
                Expanded(child: _Kpi('Revestido', '${fmtNum(k.metrosRevestidos, dec: 0)} m', 'de ${fmtNum(k.longitudTotal, dec: 0)} m')),
                const SizedBox(width: 10),
                Expanded(child: _Kpi('Faltante', '${fmtNum(k.metrosFaltantes, dec: 0)} m', 'revestimiento')),
              ]),
              Row(children: [
                Expanded(child: _Kpi('Concreto revest.', '${fmtNum(k.concretoRevM3, dec: 0)} m³', 'acumulado')),
                const SizedBox(width: 10),
                Expanded(child: _Kpi('Concreto viga base', '${fmtNum(k.concretoVigaM3, dec: 0)} m³', 'acumulado')),
              ]),
              Row(children: [
                Expanded(child: _Kpi('Últimos 7 días', '${fmtNum(k.metrosSemana, dec: 1)} m', '${fmtNum(k.concretoSemanaM3, dec: 0)} m³')),
                const SizedBox(width: 10),
                Expanded(child: _Kpi('Últimos 30 días', '${fmtNum(k.metrosMes, dec: 1)} m', '${fmtNum(k.concretoMesM3, dec: 0)} m³')),
              ]),
              _Tarjeta(
                titulo: 'Ritmo y proyección (revestimiento)',
                hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Velocidad (30 días): ${fmtNum(k.velocidadMDia, dec: 2)} m/día'),
                  const SizedBox(height: 4),
                  Text(k.fechaEstimadaFin == null
                      ? 'Fecha probable de término: sin ritmo suficiente para proyectar'
                      : 'Fecha probable de término: ${fmtFecha(k.fechaEstimadaFin!)}  (proyección lineal)'),
                ]),
              ),
              _Tarjeta(
                titulo: 'Estado de módulos (${a.modulos.length})',
                hijo: Wrap(spacing: 14, runSpacing: 6, children: [
                  _Punto(Tema.verde, 'Terminados ${k.modulosTerminados}'),
                  _Punto(Tema.amarillo, 'En ejecución ${k.modulosEnEjecucion}'),
                  _Punto(Tema.rojo, 'Retrasados ${k.modulosRetrasados}'),
                  _Punto(Tema.gris, 'No iniciados ${k.modulosNoIniciados}'),
                ]),
              ),
              _Tarjeta(
                titulo: 'Avance por grupo (ponderado por longitud)',
                hijo: Column(children: [
                  for (final e in k.avancePorGrupo.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(flex: 4, child: Text(e.key, style: const TextStyle(fontSize: 13))),
                        Expanded(flex: 5, child: _Barra(valor: e.value, alto: 9)),
                        SizedBox(
                            width: 56,
                            child: Text('${fmtNum(e.value)} %',
                                textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
                      ]),
                    ),
                ]),
              ),
              _Tarjeta(
                titulo: 'Curva S real · metros de revestimiento acumulados',
                hijo: SizedBox(height: 170, width: double.infinity, child: CustomPaint(painter: _CurvaS(k.curvaS))),
              ),
              if (retrasados.isNotEmpty)
                _Tarjeta(
                  titulo: 'Módulos sin registros hace más de $kDiasSinActividadRetraso días',
                  hijo: Text(retrasados.map((p) => 'M${p.modulo.numero} (${fmtNum(p.total, dec: 0)} %)').join(' · '),
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                ),
              if (a.cobrables.where((c) => (c.acumulado ?? 0) > 0).isNotEmpty)
                _Tarjeta(
                  titulo: 'Cobrables Túnel 0 · hoja Matriz cant. (solo con ejecución)',
                  hijo: Column(children: [
                    Row(children: [
                      const Expanded(flex: 6, child: SizedBox()),
                      Expanded(
                          flex: 2,
                          child: Text('Últ. sem.',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)))),
                      Expanded(
                          flex: 2,
                          child: Text('Total',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)))),
                    ]),
                    for (final c in a.cobrables.where((c) => (c.acumulado ?? 0) > 0))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                              flex: 6,
                              child: Text('${c.tarea} (${c.unidad})', style: const TextStyle(fontSize: 12))),
                          Expanded(
                              flex: 2,
                              child: Text(c.semanal == null ? '—' : fmtNum(c.semanal!, dec: 1),
                                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                          Expanded(
                              flex: 2,
                              child: Text(fmtNum(c.acumulado!, dec: 1),
                                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                        ]),
                      ),
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final String titulo;
  final Widget hijo;
  const _Tarjeta({required this.titulo, required this.hijo});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Tema.tarjeta, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: TextStyle(fontSize: 12.5, color: Colors.white.withOpacity(0.65))),
        const SizedBox(height: 8),
        hijo,
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String titulo;
  final String valor;
  final String pie;
  const _Kpi(this.titulo, this.valor, this.pie);
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Tema.tarjeta, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
        const SizedBox(height: 4),
        Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(pie, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5))),
      ]),
    );
  }
}

class _Punto extends StatelessWidget {
  final Color color;
  final String texto;
  const _Punto(this.color, this.texto);
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(texto, style: const TextStyle(fontSize: 13)),
    ]);
  }
}

class _Barra extends StatelessWidget {
  final double valor;
  final double alto;
  const _Barra({required this.valor, this.alto = 12});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: (valor / 100).clamp(0.0, 1.0).toDouble(),
        minHeight: alto,
        backgroundColor: Colors.white12,
        color: Tema.colorAvance(valor),
      ),
    );
  }
}

class _CurvaS extends CustomPainter {
  final List<PuntoCurva> puntos;
  _CurvaS(this.puntos);

  @override
  void paint(Canvas canvas, Size size) {
    final eje = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 14), Offset(size.width, size.height - 14), eje);
    if (puntos.length < 2) {
      final tp = TextPainter(
        text: const TextSpan(text: 'Datos insuficientes', style: TextStyle(color: Colors.white54, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height / 2 - 8));
      return;
    }
    final t0 = puntos.first.fecha.millisecondsSinceEpoch.toDouble();
    final t1 = puntos.last.fecha.millisecondsSinceEpoch.toDouble();
    final span = (t1 - t0) <= 0 ? 1.0 : (t1 - t0);
    final maxV = puntos.last.acumulado <= 0 ? 1.0 : puntos.last.acumulado;
    final alto = size.height - 20;
    final path = Path();
    for (var i = 0; i < puntos.length; i++) {
      final x = (puntos[i].fecha.millisecondsSinceEpoch - t0) / span * size.width;
      final y = alto - (puntos[i].acumulado / maxV) * (alto - 6) + 6;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = Tema.acento,
    );
    void texto(String s, Offset o) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o);
    }

    texto(fmtFecha(puntos.first.fecha), Offset(0, size.height - 12));
    final ult = fmtFecha(puntos.last.fecha);
    texto(ult, Offset(size.width - 58, size.height - 12));
    texto('${fmtNum(maxV, dec: 0)} m', const Offset(2, 0));
  }

  @override
  bool shouldRepaint(covariant _CurvaS old) => true;
}
