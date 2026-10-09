import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/calculo.dart';
import '../data/modelos.dart';
import 'tema.dart';

/// Geometría de la sección del túnel.
///
/// IMPORTANTE: valores PROVISIONALES (herradura genérica). Se deben reemplazar con
/// las cotas reales de los planos (sección típica, viga base, bordillo, ménsula,
/// cárcamo, MH). Solo afectan el dibujo, no el cálculo de avance.
class GeoT0 {
  static const double semiAncho = 5.2; // m
  static const double alturaMuro = 2.6; // m
  static const double flecha = 3.6; // m (altura de la bóveda sobre los muros)

  static List<Offset> perfil(double escala) {
    final pts = <Offset>[];
    pts.add(Offset(-semiAncho * escala, 0));
    pts.add(Offset(-semiAncho * escala, alturaMuro * escala));
    const pasos = 14;
    for (var i = 1; i < pasos; i++) {
      final t = math.pi - math.pi * i / pasos;
      pts.add(Offset(
        semiAncho * escala * math.cos(t),
        (alturaMuro + flecha * math.sin(t)) * escala,
      ));
    }
    pts.add(Offset(semiAncho * escala, alturaMuro * escala));
    pts.add(Offset(semiAncho * escala, 0));
    return pts;
  }
}

/// Valor 0..100 con el que se colorea un módulo según el filtro activo.
/// '' = avance total; 'g:Grupo' = grupo de actividades; otro = id de actividad.
double valorFiltro(ProgresoModulo p, String filtro) {
  if (filtro.isEmpty) return p.total;
  if (filtro.startsWith('g:')) {
    final g = filtro.substring(2);
    var s = 0.0;
    var w = 0.0;
    for (final d in kActividades) {
      if (d.grupo != g) continue;
      s += (p.cobertura[d.id] ?? 0) * d.peso;
      w += d.peso;
    }
    return w == 0 ? 0 : s / w * 100;
  }
  return p.pct(filtro);
}

String etiquetaFiltro(String filtro) {
  if (filtro.isEmpty) return 'Avance total';
  if (filtro.startsWith('g:')) return filtro.substring(2);
  final d = defPorId(filtro);
  return d == null ? filtro : d.nombre;
}

class HitModulo {
  final int numero;
  final Path path;
  const HitModulo(this.numero, this.path);
}

class _P {
  final double x;
  final double y;
  final double d;
  const _P(this.x, this.y, this.d);
}

class _Item {
  final ProgresoModulo p;
  final double profundidad;
  const _Item(this.p, this.profundidad);
}

class TunelPainter extends CustomPainter {
  final List<ProgresoModulo> progs;
  final double pk0;
  final double yaw;
  final double pitch;
  final double dist;
  final double tz;
  final double escala;
  final int? seleccion;
  final String filtro;
  final List<HitModulo> hits; // salida: se llena en cada pintado

  TunelPainter({
    required this.progs,
    required this.pk0,
    required this.yaw,
    required this.pitch,
    required this.dist,
    required this.tz,
    required this.escala,
    required this.seleccion,
    required this.filtro,
    required this.hits,
  });

  static const double _near = 0.6;

  static List<_P> _recortar(List<_P> poly) {
    final out = <_P>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final ain = a.d >= _near;
      final bin = b.d >= _near;
      if (ain) out.add(a);
      if (ain != bin) {
        final t = (_near - a.d) / (b.d - a.d);
        out.add(_P(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, _near));
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1220), Color(0xFF1C2535)],
        ).createShader(rect),
    );
    if (progs.isEmpty) return;

    final f = size.width * 0.9;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final cyaw = math.cos(yaw);
    final syaw = math.sin(yaw);
    final cp = math.cos(pitch);
    final sp = math.sin(pitch);
    final ty = (GeoT0.alturaMuro + GeoT0.flecha) * 0.5 * escala;

    _P cam(double x, double y, double z) {
      final dx = x;
      final dy = y - ty;
      final dz = z - tz;
      final x1 = dx * cyaw + dz * syaw;
      final z1 = -dx * syaw + dz * cyaw;
      final y2 = dy * cp + z1 * sp;
      final z2 = -dy * sp + z1 * cp;
      return _P(x1, y2, dist + z2);
    }

    Offset scr(_P p) => Offset(cx + p.x * f / p.d, cy - p.y * f / p.d);

    Path armar(List<List<_P>> quads) {
      final path = Path();
      for (final q in quads) {
        final poly = _recortar(q);
        if (poly.length < 3) continue;
        final o0 = scr(poly[0]);
        path.moveTo(o0.dx, o0.dy);
        for (var i = 1; i < poly.length; i++) {
          final o = scr(poly[i]);
          path.lineTo(o.dx, o.dy);
        }
        path.close();
      }
      return path;
    }

    final perfil = GeoT0.perfil(escala);
    final n = perfil.length;
    final filtroActivo = filtro.isNotEmpty;

    final items = <_Item>[];
    for (final p in progs) {
      final zc = p.modulo.pkMedio - pk0;
      items.add(_Item(p, cam(0, ty, zc).d));
    }
    items.sort((a, b) => b.profundidad.compareTo(a.profundidad));

    final pisoPaint = Paint()..color = const Color(0xFF2B323C);
    final bordePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.black.withOpacity(0.35);
    Path? pathSel;

    for (final it in items) {
      final m = it.p.modulo;
      final z0 = m.pkMin - pk0;
      final z1 = m.pkMax - pk0;
      final r0 = <_P>[];
      final r1 = <_P>[];
      for (final o in perfil) {
        r0.add(cam(o.dx, o.dy, z0));
        r1.add(cam(o.dx, o.dy, z1));
      }
      // piso
      final piso = armar([
        [r0[0], r0[n - 1], r1[n - 1], r1[0]]
      ]);
      canvas.drawPath(piso, pisoPaint);

      // revestimiento (bóveda + hastiales)
      final quads = <List<_P>>[];
      for (var k = 0; k < n - 1; k++) {
        quads.add([r0[k], r0[k + 1], r1[k + 1], r1[k]]);
      }
      final path = armar(quads);

      final v = valorFiltro(it.p, filtro);
      final base = Tema.colorAvance(v);
      final alpha = filtroActivo ? (v > 0 ? 0.92 : 0.13) : 0.88;
      canvas.drawPath(path, Paint()..color = base.withOpacity(alpha));
      canvas.drawPath(path, bordePaint);

      hits.add(HitModulo(m.numero, path));
      if (seleccion == m.numero) pathSel = path;
    }

    if (pathSel != null) {
      canvas.drawPath(
        pathSel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..color = Colors.white,
      );
    }

    // Etiquetas de módulo solo cuando hay zoom suficiente
    if (dist < 170) {
      final top = (GeoT0.alturaMuro + GeoT0.flecha) * escala;
      for (final p in progs) {
        final zc = p.modulo.pkMedio - pk0;
        if ((zc - tz).abs() > 45) continue;
        final c = cam(0, top, zc);
        if (c.d < _near) continue;
        final o = scr(c);
        if (o.dx < 0 || o.dx > size.width || o.dy < 0 || o.dy > size.height) continue;
        final tp = TextPainter(
          text: TextSpan(
            text: 'M${p.modulo.numero}',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(o.dx - tp.width / 2, o.dy - tp.height - 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant TunelPainter old) => true;
}
