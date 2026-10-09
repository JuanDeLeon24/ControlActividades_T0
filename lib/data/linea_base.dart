import 'modelos.dart';

/// LÍNEA BASE declarada por el equipo de obra (corte 2026-10-09).
///
/// Es lo que ya está ejecutado y no se quiere volver a digitar. Se suma al Excel y a lo
/// que se cargue desde la app. Para cambiarla basta editar esta función.
///
///  - Viga base: 100 % en los 137 módulos, ambos lados (acero, encofrado, concreto, desencofrado).
///  - Geomembrana: instalada desde el portal (K7+173) hasta la abscisa K6+562.
///  - Revestimiento, módulos 1 a 7: malla (solo donde aplica), formaleta, concreto y desencofrado al 100 %.
///    Vaciados de concreto: módulo 1 = 2 oct, 2 = 3 oct, 3 = 4 oct, 4 = 5 oct, 5 = 6 oct, 6 = 7 oct, 7 = 8 oct.
///  - Malla de revestimiento al 100 % en los módulos 1, 2, 3 y 17 (el 17 es nicho).
const double kGeomembranaHastaPk = 6562;
const List<int> kModulosMallaBase = [1, 2, 3, 17];
const int kUltimoModuloRevestidoBase = 7;

List<Registro> lineaBase(List<Modulo> modulos) {
  if (modulos.isEmpty) return <Registro>[];
  var pkMin = modulos.first.pkMin;
  var pkMax = modulos.first.pkMax;
  for (final m in modulos) {
    if (m.pkMin < pkMin) pkMin = m.pkMin;
    if (m.pkMax > pkMax) pkMax = m.pkMax;
  }
  const nota = 'Línea base';
  final out = <Registro>[];

  // Viga base completa, ambos lados
  const vigas = <String>[
    'Viga base - Instalación de acero',
    'Viga base - Encofrado',
    'Viga base - Vaciado de concreto',
    'Viga base - Desencofrado',
  ];
  for (final nombre in vigas) {
    for (final lado in const ['HD', 'HI']) {
      out.add(Registro(
        fecha: null,
        turno: '',
        actividad: '$nombre (línea base)',
        lado: lado,
        grupo: 'Viga base',
        pkA: pkMax,
        pkB: pkMin,
        origen: 'BASE',
        nota: nota,
      ));
    }
  }

  // Geomembrana hasta K6+562
  out.add(Registro(
    fecha: null,
    turno: '',
    actividad: 'Geomembrana en bóveda (línea base)',
    grupo: 'Impermeabilización',
    pkA: pkMax,
    pkB: kGeomembranaHastaPk,
    unidad: 'm',
    origen: 'BASE',
    nota: nota,
  ));

  Modulo? mod(int n) {
    for (final m in modulos) {
      if (m.numero == n) return m;
    }
    return null;
  }

  // Revestimiento módulos 1..7
  for (var n = 1; n <= kUltimoModuloRevestidoBase; n++) {
    final m = mod(n);
    if (m == null) continue;
    out.add(Registro(
      fecha: DateTime(2026, 10, n + 1), // M1 -> 2 oct ... M7 -> 8 oct
      turno: '',
      actividad: 'Revestimiento - Vaciado de concreto en bóveda (línea base) M$n',
      grupo: 'Revestimiento',
      pkA: m.pkMax,
      pkB: m.pkMin,
      origen: 'BASE',
      nota: nota,
    ));
    out.add(Registro(
      fecha: null,
      turno: '',
      actividad: 'Revestimiento - Instalación de formaleta (línea base) M$n',
      grupo: 'Revestimiento',
      pkA: m.pkMax,
      pkB: m.pkMin,
      origen: 'BASE',
      nota: nota,
    ));
    out.add(Registro(
      fecha: null,
      turno: '',
      actividad: 'Revestimiento - Desencofrado de formaleta (línea base) M$n',
      grupo: 'Revestimiento',
      pkA: m.pkMax,
      pkB: m.pkMin,
      origen: 'BASE',
      nota: nota,
    ));
  }

  // Malla de revestimiento: módulos 1, 2, 3 y 17 (nicho)
  for (final n in kModulosMallaBase) {
    final m = mod(n);
    if (m == null) continue;
    out.add(Registro(
      fecha: null,
      turno: '',
      actividad: 'Revestimiento - Instalación de acero / malla electrosoldada (línea base) M$n',
      grupo: 'Revestimiento',
      pkA: m.pkMax,
      pkB: m.pkMin,
      origen: 'BASE',
      nota: nota,
    ));
  }
  return out;
}
