import 'package:flutter/material.dart';

import '../data/almacen.dart';
import '../data/util.dart';
import 'import_screen.dart';
import 'registro_screen.dart';
import 'tema.dart';
import 'tunel_screen.dart';

/// Pantalla de entrada con las 3 opciones.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Almacen.i,
          builder: (context, _) {
            final a = Almacen.i;
            final k = a.kpi;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: [
                const Text('CONTROL DE AVANCE',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                const SizedBox(height: 4),
                Text('TÚNEL 0 · Gemelo digital operativo',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.7))),
                const SizedBox(height: 20),
                _Resumen(a: a),
                const SizedBox(height: 20),
                _Opcion(
                  icono: Icons.view_in_ar,
                  color: Tema.verde,
                  titulo: 'VISTA DE AVANCE',
                  detalle: a.hayDatos
                      ? 'Modelo 3D · ${fmtNum(k.avanceTotal)} % de avance total'
                      : 'Modelo 3D del túnel por módulos',
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const TunelScreen())),
                ),
                const SizedBox(height: 14),
                _Opcion(
                  icono: Icons.edit_note,
                  color: Tema.acento,
                  titulo: 'CARGAR ACTIVIDADES DEL DÍA',
                  detalle: 'Concreto, malla, formaleta, geomembrana, viga base…',
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const RegistroScreen())),
                ),
                const SizedBox(height: 14),
                _Opcion(
                  icono: Icons.upload_file,
                  color: Tema.primario,
                  titulo: 'IMPORTAR REPORTE DIARIO',
                  detalle: 'Leer el Excel y actualizar el avance automáticamente',
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const ImportScreen())),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  final Almacen a;
  const _Resumen({required this.a});

  @override
  Widget build(BuildContext context) {
    final k = a.kpi;
    final sinDatos = !a.hayDatos;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Tema.tarjeta,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Dato('Módulos', '${a.modulos.length}'),
              _Dato('Longitud', '${fmtNum(k.longitudTotal, dec: 0)} m'),
              _Dato('Avance', sinDatos ? '—' : '${fmtNum(k.avanceTotal)} %'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            sinDatos
                ? 'Aún no hay datos.'
                : 'Corte al ${k.fechaReferencia == null ? '—' : fmtFecha(k.fechaReferencia!)}'
                    '${a.hayExcel ? ' · Excel: ${a.nombreArchivo ?? ''}' : ' · línea base (sin Excel importado)'}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _Dato(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(valor, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      Text(etiqueta, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
    ]);
  }
}

class _Opcion extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String detalle;
  final VoidCallback onTap;
  const _Opcion({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.detalle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tema.tarjeta,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.55)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: color, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(detalle, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7))),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ]),
        ),
      ),
    );
  }
}
