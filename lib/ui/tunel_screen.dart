import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/almacen.dart';
import '../data/calculo.dart';
import '../data/modelos.dart';
import '../data/util.dart';
import 'dashboard_screen.dart';
import 'ficha_modulo.dart';
import 'tema.dart';
import 'tunel_painter.dart';

enum Vista { d3, iso, longitudinal, planta, transversal, recorrido }

String _nombreVista(Vista v) {
  switch (v) {
    case Vista.d3:
      return '3D';
    case Vista.iso:
      return 'Isométrica';
    case Vista.longitudinal:
      return 'Longitudinal';
    case Vista.planta:
      return 'Planta';
    case Vista.transversal:
      return 'Transversal';
    case Vista.recorrido:
      return 'Recorrido';
  }
}

class TunelScreen extends StatefulWidget {
  const TunelScreen({super.key});

  @override
  State<TunelScreen> createState() => _TunelScreenState();
}

class _TunelScreenState extends State<TunelScreen> with SingleTickerProviderStateMixin {
  static const double _escalaVista = 4.0; // exageración de la sección (el túnel mide ~1 km)

  Vista _vista = Vista.d3;
  double _yaw = -0.6;
  double _pitch = 0.45;
  double _dist = 700;
  double _tz = 500;
  double _escala = _escalaVista;
  int? _sel;
  String _filtro = '';
  bool _reproduciendo = false;

  final List<HitModulo> _hits = <HitModulo>[];
  late final AnimationController _anim;
  VoidCallback? _vuelo;
  Timer? _timer;
  double _dist0 = 700;
  double _ancho = 400;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
    final g = _geom();
    _tz = g.largo / 2;
    _dist = g.largo * 0.75;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  ({double pk0, double largo}) _geom() {
    final ms = Almacen.i.modulos;
    var lo = ms.first.pkMin;
    var hi = ms.first.pkMax;
    for (final m in ms) {
      if (m.pkMin < lo) lo = m.pkMin;
      if (m.pkMax > hi) hi = m.pkMax;
    }
    return (pk0: lo, largo: hi - lo);
  }

  void _volar({double? yaw, double? pitch, double? dist, double? tz, double? escala}) {
    if (_vuelo != null) _anim.removeListener(_vuelo!);
    final y0 = _yaw, p0 = _pitch, d0 = _dist, t0 = _tz, e0 = _escala;
    final y1 = yaw ?? _yaw;
    final p1 = pitch ?? _pitch;
    final d1 = dist ?? _dist;
    final t1 = tz ?? _tz;
    final e1 = escala ?? _escala;
    _vuelo = () {
      final t = Curves.easeInOutCubic.transform(_anim.value);
      setState(() {
        _yaw = y0 + (y1 - y0) * t;
        _pitch = p0 + (p1 - p0) * t;
        _dist = d0 * math.pow(d1 / d0, t).toDouble();
        _tz = t0 + (t1 - t0) * t;
        _escala = e0 + (e1 - e0) * t;
      });
    };
    _anim.addListener(_vuelo!);
    _anim.forward(from: 0);
  }

  void _aplicarVista(Vista v) {
    _timer?.cancel();
    final g = _geom();
    final selMod = _sel == null ? null : Almacen.i.modulos.where((m) => m.numero == _sel).firstOrNull;
    final tzSel = selMod == null ? _tz : selMod.pkMedio - g.pk0;
    setState(() {
      _vista = v;
      _reproduciendo = false;
    });
    switch (v) {
      case Vista.d3:
        _volar(yaw: -0.6, pitch: 0.45, dist: g.largo * 0.75, tz: g.largo / 2, escala: _escalaVista);
        break;
      case Vista.iso:
        _volar(yaw: math.pi / 4, pitch: 0.6155, dist: g.largo * 0.85, tz: g.largo / 2, escala: _escalaVista);
        break;
      case Vista.longitudinal:
        _volar(yaw: math.pi / 2, pitch: 0, dist: g.largo * 0.95, tz: g.largo / 2, escala: _escalaVista);
        break;
      case Vista.planta:
        _volar(yaw: math.pi / 2, pitch: math.pi / 2, dist: g.largo * 0.95, tz: g.largo / 2, escala: _escalaVista);
        break;
      case Vista.transversal:
        _volar(yaw: 0, pitch: 0, dist: 48, tz: tzSel, escala: _escalaVista);
        break;
      case Vista.recorrido:
        _volar(yaw: 0, pitch: 0.04, dist: 14, tz: tzSel, escala: 1.0);
        break;
    }
  }

  void _alternarRecorrido() {
    final g = _geom();
    setState(() => _reproduciendo = !_reproduciendo);
    _timer?.cancel();
    if (_reproduciendo) {
      _timer = Timer.periodic(const Duration(milliseconds: 40), (_) {
        if (!mounted) return;
        setState(() {
          _tz += 0.35;
          if (_tz >= g.largo) {
            _tz = g.largo;
            _reproduciendo = false;
            _timer?.cancel();
          }
        });
      });
    }
  }

  void _irAModulo(int numero, {bool abrirFicha = true}) {
    final g = _geom();
    final m = Almacen.i.modulos.firstWhere((x) => x.numero == numero);
    setState(() => _sel = numero);
    if (_vista == Vista.recorrido) {
      _volar(tz: m.pkMedio - g.pk0);
    } else if (_vista == Vista.longitudinal || _vista == Vista.planta) {
      _volar(tz: m.pkMedio - g.pk0, dist: 70, yaw: -0.5, pitch: 0.35);
      setState(() => _vista = Vista.d3);
    } else {
      _volar(tz: m.pkMedio - g.pk0, dist: 55, yaw: _vista == Vista.transversal ? 0 : -0.5,
          pitch: _vista == Vista.transversal ? 0 : 0.35);
    }
    if (abrirFicha) mostrarFichaModulo(context, numero);
  }

  void _alTocar(Offset pos) {
    for (var i = _hits.length - 1; i >= 0; i--) {
      if (_hits[i].path.contains(pos)) {
        final n = _hits[i].numero;
        setState(() => _sel = n);
        mostrarFichaModulo(context, n);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vista de avance · Túnel 0'),
        actions: [
          IconButton(
            tooltip: 'Dashboard',
            icon: const Icon(Icons.dashboard_outlined),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Almacen.i,
        builder: (context, _) {
          final a = Almacen.i;
          final g = _geom();
          final ordenados = List<Modulo>.from(a.modulos)..sort((x, y) => x.pkMin.compareTo(y.pkMin));
          final progs = <ProgresoModulo>[
            for (final m in ordenados)
              if (a.progreso(m.numero) != null) a.progreso(m.numero)!,
          ];
          return Column(
            children: [
              _barraVistas(),
              _barraFiltro(),
              Expanded(
                child: Stack(
                  children: [
                    LayoutBuilder(builder: (context, c) {
                      _ancho = c.maxWidth;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (_) {
                          _dist0 = _dist;
                          if (_anim.isAnimating) _anim.stop();
                        },
                        onScaleUpdate: (d) {
                          setState(() {
                            if (d.pointerCount >= 2) {
                              _dist = (_dist0 / d.scale).clamp(8.0, g.largo * 3).toDouble();
                              final paso = d.focalPointDelta.dx * math.sin(_yaw) * _dist / (_ancho * 0.9);
                              _tz = (_tz - paso).clamp(0.0, g.largo).toDouble();
                            } else {
                              _yaw += d.focalPointDelta.dx * 0.008;
                              _pitch = (_pitch + d.focalPointDelta.dy * 0.008)
                                  .clamp(-0.05, math.pi / 2)
                                  .toDouble();
                            }
                          });
                        },
                        onTapUp: (d) => _alTocar(d.localPosition),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: TunelPainter(
                            progs: progs,
                            pk0: g.pk0,
                            yaw: _yaw,
                            pitch: _pitch,
                            dist: _dist,
                            tz: _tz,
                            escala: _escala,
                            seleccion: _sel,
                            filtro: _filtro,
                            hits: _hits,
                          ),
                        ),
                      );
                    }),
                    Positioned(top: 8, right: 8, child: _leyenda()),
                    if (!a.hayDatos)
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Sin datos de avance: importa el reporte diario para colorear el túnel.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    if (_sel != null) Positioned(left: 8, bottom: 8, child: _chipSeleccion(a)),
                    if (_vista == Vista.recorrido) Positioned(left: 0, right: 0, bottom: 8, child: _controlesRecorrido(g.largo)),
                    if (_vista == Vista.transversal)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 8,
                        child: Text(
                          'Vista a lo largo del eje. Sección esquemática: pendiente de cotas de planos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.55)),
                        ),
                      ),
                  ],
                ),
              ),
              _BarraLongitudinal(
                modulos: ordenados,
                pk0: g.pk0,
                largo: g.largo,
                tz: _tz,
                seleccion: _sel,
                estadoDe: (m) => a.progreso(m.numero)?.estado ?? EstadoModulo.noIniciado,
                onTapModulo: (n) => _irAModulo(n),
                onScrub: (z) => setState(() => _tz = z.clamp(0.0, g.largo).toDouble()),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _barraVistas() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          for (final v in Vista.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(_nombreVista(v)),
                selected: _vista == v,
                onSelected: (_) => _aplicarVista(v),
              ),
            ),
        ],
      ),
    );
  }

  Widget _barraFiltro() {
    final opciones = <String>[
      '',
      'g:Impermeabilización',
      'g:Viga base',
      'g:Revestimiento',
      for (final d in kActividades) d.id,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(children: [
        const Icon(Icons.filter_alt_outlined, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButton<String>(
            value: _filtro,
            isExpanded: true,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final o in opciones)
                DropdownMenuItem(value: o, child: Text(etiquetaFiltro(o), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _filtro = v ?? ''),
          ),
        ),
      ]),
    );
  }

  Widget _leyenda() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Text(etiquetaFiltro(_filtro),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        for (final e in Tema.leyendaAvance)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, color: e.$2),
            const SizedBox(width: 6),
            Text(e.$1, style: const TextStyle(fontSize: 11)),
          ]),
        if (_filtro.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Transparente: sin avance\nen esta actividad',
                style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.65))),
          ),
      ]),
    );
  }

  Widget _chipSeleccion(Almacen a) {
    final p = a.progreso(_sel!);
    if (p == null) return const SizedBox.shrink();
    return InkWell(
      onTap: () => mostrarFichaModulo(context, _sel!),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Tema.colorAvance(p.total)),
        ),
        child: Text('M${p.modulo.numero} · ${fmtNum(p.total)} %  (ver ficha)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _controlesRecorrido(double largo) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(_reproduciendo ? Icons.pause : Icons.play_arrow),
            onPressed: _alternarRecorrido,
          ),
          SizedBox(
            width: 220,
            child: Slider(
              value: _tz.clamp(0.0, largo).toDouble(),
              min: 0,
              max: largo,
              onChanged: (v) => setState(() => _tz = v),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Barra inferior: un bloque por módulo, de menor a mayor PK.
class _BarraLongitudinal extends StatelessWidget {
  final List<Modulo> modulos;
  final double pk0;
  final double largo;
  final double tz;
  final int? seleccion;
  final EstadoModulo Function(Modulo) estadoDe;
  final void Function(int numero) onTapModulo;
  final void Function(double z) onScrub;

  const _BarraLongitudinal({
    required this.modulos,
    required this.pk0,
    required this.largo,
    required this.tz,
    required this.seleccion,
    required this.estadoDe,
    required this.onTapModulo,
    required this.onScrub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Tema.superficie,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(fmtPk(pk0), style: const TextStyle(fontSize: 11)),
          Row(children: [
            for (final e in [
              ('Terminado', Tema.verde),
              ('En ejecución', Tema.amarillo),
              ('Retrasado', Tema.rojo),
              ('No iniciado', Tema.gris),
            ])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Row(children: [
                  Container(width: 8, height: 8, color: e.$2),
                  const SizedBox(width: 3),
                  Text(e.$1, style: const TextStyle(fontSize: 9)),
                ]),
              ),
          ]),
          Text(fmtPk(pk0 + largo), style: const TextStyle(fontSize: 11)),
        ]),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          int moduloEn(double dx) {
            final pk = pk0 + (dx / w).clamp(0.0, 1.0) * largo;
            for (final m in modulos) {
              if (pk >= m.pkMin && pk <= m.pkMax) return m.numero;
            }
            return modulos.last.numero;
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => onTapModulo(moduloEn(d.localPosition.dx)),
            onHorizontalDragUpdate: (d) => onScrub((d.localPosition.dx / w).clamp(0.0, 1.0) * largo),
            child: CustomPaint(
              size: Size(w, 34),
              painter: _BarraPainter(modulos, pk0, largo, tz, seleccion, estadoDe),
            ),
          );
        }),
      ]),
    );
  }
}

class _BarraPainter extends CustomPainter {
  final List<Modulo> modulos;
  final double pk0;
  final double largo;
  final double tz;
  final int? seleccion;
  final EstadoModulo Function(Modulo) estadoDe;

  _BarraPainter(this.modulos, this.pk0, this.largo, this.tz, this.seleccion, this.estadoDe);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    const alto = 22.0;
    for (final m in modulos) {
      final x0 = (m.pkMin - pk0) / largo * w;
      final x1 = (m.pkMax - pk0) / largo * w;
      final r = Rect.fromLTRB(x0 + 0.4, 0, math.max(x0 + 1.0, x1 - 0.4), alto);
      canvas.drawRect(r, Paint()..color = Tema.colorEstado(estadoDe(m)));
      if (seleccion == m.numero) {
        canvas.drawRect(
          r.inflate(0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white,
        );
      }
    }
    // cursor de la cámara
    final xc = (tz / largo).clamp(0.0, 1.0) * w;
    final tri = Path()
      ..moveTo(xc, alto + 1)
      ..lineTo(xc - 5, alto + 10)
      ..lineTo(xc + 5, alto + 10)
      ..close();
    canvas.drawPath(tri, Paint()..color = Tema.acento);
  }

  @override
  bool shouldRepaint(covariant _BarraPainter old) => true;
}
