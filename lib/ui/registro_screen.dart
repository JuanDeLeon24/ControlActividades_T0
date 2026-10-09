import 'package:flutter/material.dart';

import '../data/almacen.dart';
import '../data/modelos.dart';
import '../data/util.dart';
import 'tema.dart';

/// Carga manual de actividades por día: cualquier actividad del catálogo, por módulos o por abscisa.
class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _form = GlobalKey<FormState>();
  final _cantidad = TextEditingController();
  final _pkIni = TextEditingController();
  final _pkFin = TextEditingController();
  final _responsable = TextEditingController();
  final _obs = TextEditingController();

  String _idAct = 'rev_conc';
  DateTime _fecha = DateTime.now();
  String _turno = 'Día';
  String _lado = 'Ambos'; // HD, HI, Ambos (solo viga base)
  bool _porModulos = true;
  int? _desde;
  int? _hasta;

  @override
  void dispose() {
    _cantidad.dispose();
    _pkIni.dispose();
    _pkFin.dispose();
    _responsable.dispose();
    _obs.dispose();
    super.dispose();
  }

  DefActividad get _def => defPorId(_idAct)!;

  static const Map<String, String> _nombreRegistro = {
    'imp': 'Geomembrana en bóveda',
    'vb_acero': 'Viga base - Instalación de acero',
    'vb_enc': 'Viga base - Encofrado',
    'vb_conc': 'Viga base - Vaciado de concreto',
    'vb_desenc': 'Viga base - Desencofrado',
    'rev_malla': 'Revestimiento - Instalación de acero / malla electrosoldada',
    'rev_form': 'Revestimiento - Instalación de formaleta',
    'rev_conc': 'Revestimiento - Vaciado de concreto en bóveda',
    'rev_desenc': 'Revestimiento - Desencofrado de formaleta',
  };

  void _cambiarActividad(String id) {
    setState(() {
      _idAct = id;
      final d = defPorId(id)!;
      _porModulos = d.porModulo || id == 'rev_malla';
      _cantidad.clear();
      _sugerirPk();
    });
  }

  /// Sugiere como "desde" el frente actual de la actividad (donde se quedó).
  void _sugerirPk() {
    final f = Almacen.i.frenteActual(_idAct);
    final ms = Almacen.i.modulos;
    var mayor = ms.first.pkMax;
    for (final m in ms) {
      if (m.pkMax > mayor) mayor = m.pkMax;
    }
    _pkIni.text = (f ?? mayor).toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    _pkFin.clear();
  }

  Future<void> _elegirFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _fecha = d);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final a = Almacen.i;
    double hi, lo;
    String donde;
    if (_porModulos) {
      final m1 = a.modulos.firstWhere((m) => m.numero == _desde);
      final m2 = a.modulos.firstWhere((m) => m.numero == (_hasta ?? _desde));
      hi = m1.pkMax > m2.pkMax ? m1.pkMax : m2.pkMax;
      lo = m1.pkMin < m2.pkMin ? m1.pkMin : m2.pkMin;
      donde = m1.numero == m2.numero ? 'M${m1.numero}' : 'M${m1.numero}–M${m2.numero}';
    } else {
      final p1 = parsePk(_pkIni.text)!;
      final p2 = parsePk(_pkFin.text)!;
      hi = p1 > p2 ? p1 : p2;
      lo = p1 < p2 ? p1 : p2;
      donde = '${fmtPk(hi)} → ${fmtPk(lo)}';
    }
    final cant = aNumero(_cantidad.text) ?? 0;
    final nota = <String>[
      if (_responsable.text.trim().isNotEmpty) 'Resp.: ${_responsable.text.trim()}',
      if (_obs.text.trim().isNotEmpty) _obs.text.trim(),
    ].join(' · ');
    final lados = _def.dosLados ? (_lado == 'Ambos' ? ['HD', 'HI'] : [_lado]) : [''];
    final dia = DateTime(_fecha.year, _fecha.month, _fecha.day);
    for (final l in lados) {
      await a.agregarManual(Registro(
        fecha: dia,
        turno: _turno,
        actividad: '${_nombreRegistro[_idAct]} (app) $donde',
        lado: l,
        grupo: _def.grupo,
        pkA: hi,
        pkB: lo,
        // si se registran ambos lados, la cantidad se reparte
        cantidad: lados.length > 1 ? cant / lados.length : cant,
        unidad: _def.unidad,
        origen: 'APP',
        nota: nota,
      ));
    }
    if (!mounted) return;
    _cantidad.clear();
    _obs.clear();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guardado: ${_def.nombre} · $donde')));
    setState(_sugerirPk);
  }

  @override
  void initState() {
    super.initState();
    _sugerirPk();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cargar actividades del día')),
      body: ListenableBuilder(
        listenable: Almacen.i,
        builder: (context, _) {
          final a = Almacen.i;
          final recientes = a.manuales.reversed.take(15).toList();
          final frente = a.frenteActual(_idAct);
          final d = _def;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Se suma a la línea base y al Excel importado. Si luego el Excel trae la misma '
                'actividad ese día en ese tramo, se usa la del Excel (no se duplica).',
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.65)),
              ),
              const SizedBox(height: 16),
              Form(
                key: _form,
                child: Column(children: [
                  DropdownButtonFormField<String>(
                    value: _idAct,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Actividad', border: OutlineInputBorder()),
                    items: [
                      for (final x in kActividades)
                        DropdownMenuItem(value: x.id, child: Text(x.nombre, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      if (v != null) _cambiarActividad(v);
                    },
                  ),
                  if (frente != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Frente actual de esta actividad: ${fmtPk(frente)}',
                            style: const TextStyle(fontSize: 12, color: Tema.acento)),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _elegirFecha,
                        icon: const Icon(Icons.event),
                        label: Text(fmtFecha(_fecha)),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Día', label: Text('Día')),
                        ButtonSegment(value: 'Noche', label: Text('Noche')),
                      ],
                      selected: {_turno},
                      onSelectionChanged: (s) => setState(() => _turno = s.first),
                    ),
                  ]),
                  if (d.dosLados) ...[
                    const SizedBox(height: 14),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'HD', label: Text('Hastial der.')),
                        ButtonSegment(value: 'HI', label: Text('Hastial izq.')),
                        ButtonSegment(value: 'Ambos', label: Text('Ambos')),
                      ],
                      selected: {_lado},
                      onSelectionChanged: (s) => setState(() => _lado = s.first),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Por módulos'), icon: Icon(Icons.view_module_outlined)),
                      ButtonSegment(value: false, label: Text('Por abscisa'), icon: Icon(Icons.straighten)),
                    ],
                    selected: {_porModulos},
                    onSelectionChanged: (s) => setState(() => _porModulos = s.first),
                  ),
                  const SizedBox(height: 14),
                  if (_porModulos)
                    Row(children: [
                      Expanded(child: _selectorModulo('Desde módulo', _desde, (v) => setState(() => _desde = v))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _selectorModulo('Hasta módulo (opcional)', _hasta, (v) => setState(() => _hasta = v),
                              obligatorio: false)),
                    ])
                  else
                    Row(children: [
                      Expanded(
                        child: TextFormField(
                          controller: _pkIni,
                          keyboardType: TextInputType.text,
                          decoration: const InputDecoration(
                              labelText: 'Desde PK', hintText: '7173 o K7+173', border: OutlineInputBorder()),
                          validator: (v) => parsePk(v ?? '') == null ? 'PK inválido' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _pkFin,
                          keyboardType: TextInputType.text,
                          decoration: const InputDecoration(
                              labelText: 'Hasta PK (por dónde vamos)', hintText: '6562', border: OutlineInputBorder()),
                          validator: (v) => parsePk(v ?? '') == null ? 'PK inválido' : null,
                        ),
                      ),
                    ]),
                  if (d.unidad.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _cantidad,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Cantidad (${d.unidad}) — opcional', border: const OutlineInputBorder()),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = aNumero(v);
                        return (n == null || n < 0) ? 'Cantidad inválida' : null;
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _responsable,
                    decoration: const InputDecoration(
                        labelText: 'Responsable (opcional)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _obs,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Observaciones (opcional)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _guardar,
                      icon: const Icon(Icons.save),
                      label: const Text('Guardar actividad'),
                      style: FilledButton.styleFrom(
                          backgroundColor: Tema.acento, padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ),
                ]),
              ),
              if (recientes.isNotEmpty) ...[
                const SizedBox(height: 26),
                Text('Últimas actividades cargadas', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final r in recientes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.task_alt),
                    title: Text(r.actividad.replaceAll(' (app)', '') + (r.lado.isEmpty ? '' : ' · ${r.lado}'),
                        style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(
                        '${r.fecha == null ? '' : fmtFecha(r.fecha!)} · ${r.turno}'
                        '${r.cantidad > 0 ? ' · ${fmtNum(r.cantidad)} ${r.unidad}' : ''}'
                        '${r.nota.isEmpty ? '' : '\n${r.nota}'}'),
                    isThreeLine: r.nota.isNotEmpty,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => Almacen.i.eliminarManual(r),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _selectorModulo(String etiqueta, int? valor, void Function(int?) alCambiar, {bool obligatorio = true}) {
    return DropdownButtonFormField<int>(
      value: valor,
      isExpanded: true,
      decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder()),
      items: [
        for (final m in Almacen.i.modulos)
          DropdownMenuItem(value: m.numero, child: Text('M${m.numero} · ${fmtPk(m.pkMax)}', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: alCambiar,
      validator: (v) => (obligatorio && v == null) ? 'Requerido' : null,
    );
  }
}
