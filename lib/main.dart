import 'package:flutter/material.dart';
import 'data/almacen.dart';
import 'ui/home_screen.dart';
import 'ui/tema.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Almacen.i.iniciar();
  runApp(const ControlTunelApp());
}

class ControlTunelApp extends StatelessWidget {
  const ControlTunelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control de Avance - Túnel 0',
      debugShowCheckedModeBanner: false,
      theme: Tema.oscuro(),
      home: const HomeScreen(),
    );
  }
}
