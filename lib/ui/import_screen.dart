import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/almacen.dart';
import '../data/parser_reporte.dart';
import '../data/util.dart';
import 'tema.dart';
import 'tunel_screen.dart';

/// Importar el Excel del reporte diario. Las hojas tienen nombres fijos, por lo
/// que el archivo se procesa solo: no hay que configurar nada.
class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  Future<void> _elegir(BuildContext context) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xlsm'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final Uint8List? bytes = f.bytes;
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo leer el archivo seleccionado.')));
      }
      return;
    }
    await Almacen.i.importar(bytes, f.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar reporte diario')),
      body: ListenableBuilder(
        listenable: Almacen.i,
        builder: (context, _) {
          final a = Almacen.i;
          final k = a.kpi;
          final importado = a.registrosExcel.isNotEmpty;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Tema.tarjeta,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Tema.primario.withOpacity(0.5)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Archivo esperado',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    'Libro .xlsx o .xlsm del reporte diario de túneles. La app lee sola las hojas: '
                    'Módulos_VB, BD_Actividades, Avances_Diarios, Matriz cant., Formato Túnel_Dia y '
                    'Formato Túnel_Noche, y actualiza el avance de cada módulo.',
                    style: TextStyle(color: Colors.white.withOpacity(0.75), height: 1.35),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: a.cargando ? null : () => _elegir(context),
                icon: a.cargando
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.folder_open),
                label: Text(a.cargando ? 'Procesando…' : 'Seleccionar archivo Excel'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Tema.acento),
              ),
              if (a.error != null) ...[
                const SizedBox(height: 14),
                _Aviso(texto: a.error!, color: Tema.rojo, icono: Icons.error_outline),
              ],
              if (importado || a.filasPorHoja.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Resultado', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _Fila('Archivo', a.nombreArchivo ?? '—'),
                _Fila('Módulos', '${a.modulos.length} (${a.modulosDelExcel ? 'del Excel' : 'de referencia'})'),
                _Fila('Registros de ejecución', '${a.registrosExcel.length}'),
                _Fila('Filas cobrables (Túnel 0)', '${a.cobrables.length}'),
                _Fila('Último reporte', a.ultimaFecha == null ? '—' : fmtFecha(a.ultimaFecha!)),
                _Fila('Avance total del túnel', '${fmtNum(k.avanceTotal)} %'),
                const SizedBox(height: 12),
                Text('Hojas', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final h in [kHojaMatriz, kHojaAvances, kHojaBd, kHojaModulos, kHojaDia, kHojaNoche])
                  _Hoja(nombre: h, filas: a.filasPorHoja[h] ?? 0),
                if (a.advertencias.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final w in a.advertencias)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _Aviso(texto: w, color: Tema.naranja, icono: Icons.warning_amber),
                    ),
                ],
                const SizedBox(height: 18),
                if (importado)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pushReplacement(
                        context, MaterialPageRoute(builder: (_) => const TunelScreen())),
                    icon: const Icon(Icons.view_in_ar),
                    label: const Text('Ver avance en el modelo 3D'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String k;
  final String v;
  const _Fila(this.k, this.v);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 4, child: Text(k, style: TextStyle(color: Colors.white.withOpacity(0.65)))),
        Expanded(flex: 5, child: Text(v, textAlign: TextAlign.right)),
      ]),
    );
  }
}

class _Hoja extends StatelessWidget {
  final String nombre;
  final int filas;
  const _Hoja({required this.nombre, required this.filas});
  @override
  Widget build(BuildContext context) {
    final ok = filas > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.cancel, size: 18, color: ok ? Tema.verde : Tema.rojo),
        const SizedBox(width: 8),
        Expanded(child: Text(nombre)),
        Text(ok ? '$filas filas' : 'no encontrada',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.55))),
      ]),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;
  final Color color;
  final IconData icono;
  const _Aviso({required this.texto, required this.color, required this.icono});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icono, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}
