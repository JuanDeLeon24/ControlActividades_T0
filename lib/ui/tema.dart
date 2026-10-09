import 'package:flutter/material.dart';

import '../data/calculo.dart';

class Tema {
  static const Color fondo = Color(0xFF0D1117);
  static const Color superficie = Color(0xFF161B22);
  static const Color tarjeta = Color(0xFF1F262E);
  static const Color acento = Color(0xFFFF8F00);
  static const Color primario = Color(0xFF2F6FB5);

  // Escala de avance (3D) tal como se definió: 0 gris, 1-25 rojo, 26-50 naranja,
  // 51-75 amarillo, 76-99 azul, 100 verde.
  static const Color gris = Color(0xFF8E9399);
  static const Color rojo = Color(0xFFE53935);
  static const Color naranja = Color(0xFFFB8C00);
  static const Color amarillo = Color(0xFFFDD835);
  static const Color azul = Color(0xFF1E88E5);
  static const Color verde = Color(0xFF43A047);

  static Color colorAvance(double pct) {
    if (pct <= 0) return gris;
    if (pct <= 25) return rojo;
    if (pct <= 50) return naranja;
    if (pct <= 75) return amarillo;
    if (pct < 99.5) return azul;
    return verde;
  }

  static const List<(String, Color)> leyendaAvance = [
    ('0 %', gris),
    ('1 – 25 %', rojo),
    ('26 – 50 %', naranja),
    ('51 – 75 %', amarillo),
    ('76 – 99 %', azul),
    ('100 %', verde),
  ];

  // Estado operativo (barra longitudinal inferior)
  static Color colorEstado(EstadoModulo e) {
    switch (e) {
      case EstadoModulo.terminado:
        return verde;
      case EstadoModulo.enEjecucion:
        return amarillo;
      case EstadoModulo.retrasado:
        return rojo;
      case EstadoModulo.noIniciado:
        return gris;
    }
  }

  static String textoEstado(EstadoModulo e) {
    switch (e) {
      case EstadoModulo.terminado:
        return 'Terminado';
      case EstadoModulo.enEjecucion:
        return 'En ejecución';
      case EstadoModulo.retrasado:
        return 'Retrasado (sin registros recientes)';
      case EstadoModulo.noIniciado:
        return 'No iniciado';
    }
  }

  static ThemeData oscuro() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primario,
        brightness: Brightness.dark,
        surface: superficie,
      ),
      scaffoldBackgroundColor: fondo,
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: superficie,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}
