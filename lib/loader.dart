import 'package:flutter/material.dart';
import 'dart:math';

class JoDayLoader extends StatefulWidget {
  const JoDayLoader({super.key});

  @override
  State<JoDayLoader> createState() => _JoDayLoaderState();
}

class _JoDayLoaderState extends State<JoDayLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A2F), // тёмный фон
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            final glow = 0.5 + sin(_controller.value * pi) * 0.5;

            return Stack(
              alignment: Alignment.center,
              children: [
                // 🔥 Свечение
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.6 * glow),
                        blurRadius: 60 * glow,
                        spreadRadius: 20 * glow,
                      ),
                    ],
                  ),
                ),

                // 🐟 Картинка
                Image.asset(
                  'assets/joday_fish.png',
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                ),

                // ✨ Текст поверх
                Positioned(
                  bottom: 10,
                  child: Text(
                    'JoDay',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.amber.withOpacity(0.8),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}