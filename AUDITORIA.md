# Auditoría del proyecto ControlConcreto

## 1. Por qué falla la compilación en GitHub
1. **Error directo**: `excel_service.dart` usa `rawValue.value` / `valor.valor` sobre `CellValue`.
   En `excel 4.x` `CellValue` es una clase sellada (TextCellValue, IntCellValue, DoubleCellValue,
   DateCellValue, FormulaCellValue…) y no tiene getter `value`. Es el error de las líneas 193 y 214.
2. **Problema de fondo**: el paquete `excel` 4.x no es fiable para este libro: las celdas con fórmula
   se leen como fórmula, no como el valor calculado, y el reporte diario es casi todo fórmulas.
   Solución aplicada: lector propio (`xlsx_reader.dart`) que lee el valor en caché de cada celda; funciona con .xlsm.
3. **Carpeta `android/` incompleta y escrita a mano**: faltan `MainActivity.kt`, `res/` (estilos
   LaunchTheme/NormalTheme que el manifest referencia, ícono) y mezcla AGP 8.1.0 + Kotlin 1.9.0 +
   compileSdk 35 + Java 1.8. Habría fallado justo después de corregir el error de Dart.
   Solución: el workflow regenera `android/` con la plantilla oficial de Flutter 3.24.5.
4. **Repositorio mezclado**: en la raíz conviven un proyecto Kotlin nativo (`app/`, `build.gradle.kts`) y uno
   Flutter (`lib/`, `android/`), con dos workflows; `compilar-apk.yml` corre `gradle assembleRelease`
   en cada push a main sobre el proyecto equivocado. Hay además copias anidadas
   (`control_concretos_CEC/ControlConcreto/ControlConcreto/...`) y una app web/iPhone con `.git` propio dentro del zip.

## 2. Seguridad
- `app/build.gradle.kts` (proyecto Kotlin) trae `condor.jks` y las contraseñas de firma en texto plano
  (`condor2026`). Si el repo es público o se comparte, esa llave está expuesta: rotarla y moverla a GitHub Secrets.
- El release Flutter se firmaba con la llave de debug.

## 3. Lógica de la app (versión anterior)
- El avance de todos los módulos quedaba en 0: `_calcularAvances()` estaba vacío.
- KPIs inventados fijos en código (47.2 %, 477 m³, 15.5, 62.0, 7.5 m/día).
- "Cargar jornada" e "Importar" abrían la misma pantalla; la importación leía datos y luego los descartaba
  (`inicializarModulos()` reiniciaba todo).
- Lectura del Excel por posición fija de columna; el avance por módulo se sacaba con una regex de números
  del nombre de la actividad y sumando porcentajes (incorrecto).
- Umbrales de color distintos a los definidos (25 caía en naranja, no en rojo).
- La "vista 3D" era un dibujo pseudo-3D sin cámara ni selección real.

## 4. Qué cambió en esta versión
- Proyecto único y limpio, 5 dependencias, workflow que genera `android/`.
- Lectura del Excel por nombre de encabezado (con respaldo por posición) de: Módulos_VB, BD_Actividades,
  Avances_Diarios, Matriz cant. (solo Túnel 0). Informa qué hojas halló y advertencias.
- Avance por módulo = cobertura por PK de cada actividad, ponderada (pesos en `modelos.dart`, `kActividades`).
- Persistencia: guarda el último Excel y las jornadas manuales; al abrir ya está coloreado.
- Vista 3D con cámara orbital, 6 vistas, filtro por actividad (resto transparente), vuelo de cámara
  desde la barra longitudinal inferior, ficha del módulo, dashboard con curva S real.

## 5. Pendiente / supuestos a validar
- No compilado ni probado aquí (sin SDK de Flutter): revisar el primer build en GitHub.
- No tuve el .xlsm ni los planos en el zip: columnas y significado de "% avance" sin validar con datos reales.
- Pesos por actividad y regla de "retrasado" (7 días sin registros) son provisionales.
- Sección transversal genérica: faltan cotas de planos (viga base, bordillo, ménsula, cárcamo, MH).
- Fase siguiente: consultas en lenguaje natural/IA, fotos por módulo, roles y backend.

---
## 6. Versión 2 (con el Excel real)
Corregido tras importar `1__Reporte_Diario_Tuneles.xlsx`:
- **Advertencias de importación**: la búsqueda de encabezados usaba "contiene" y se enganchaba con los títulos de las
  filas 1-2 ("BASE DE DATOS DE ACTIVIDADES"…). Ahora exige coincidencia exacta (Fecha, Actividad, Módulo, TRAMO…).
- **450 registros sin PK**: consecuencia de lo anterior.
- **m³ de concreto**: la unidad viene como `m³` (carácter ³); no se reconocía y los volúmenes no sumaban.
- **Doble conteo**: `Avances_Diarios` es un resumen de `BD_Actividades` (columna "Fila BD"); ahora solo se usa de respaldo.
- **Filtro de frente**: solo `TUNEL 0` se grafica; `TUNEL 4` se ignora y `G-T0` (galería) se avisa (falta su geometría).
- **Desencofrado de viga base** se confundía con encofrado; ahora tiene su propia actividad.
- **Malla**: solo cuenta donde Módulos_VB dice SI o ya se instaló (nichos); si no, "No aplica" y no resta avance.
- **Matriz cant.**: sus columnas son semanas + SUMA (no acumulado/semanal/mensual); se muestra última semana y total.
- **% avance de Avances_Diarios** = acumulado de todo el túnel (geomembrana 7173→6562 = 611 m ≈ 61.4 %); no se usa para el cálculo.
- **Línea base** (`lib/data/linea_base.dart`): lo ya ejecutado, declarado por obra.
- **Cargar actividades del día**: cualquier actividad, por módulos o por abscisa ("por dónde vamos"), con lado en viga base.
