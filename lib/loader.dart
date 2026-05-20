// Flutter Loader: Golden Fish Diving into Moonlit Sea (8 seconds)
// Использует ваши картинки как ассеты.
//
// СТРУКТУРА ПРОЕКТА:
//   fish_loader/
//     lib/
//       main.dart                <- этот файл
//     assets/
//       background.png           <- картинка с луной и морем
//       fish.png                 <- золотая рыбка (PNG с прозрачным фоном)
//     pubspec.yaml               <- см. ниже
//
// pubspec.yaml (раздел flutter):
//   flutter:
//     uses-material-design: true
//     assets:
//       - assets/background.png
//       - assets/fish.png
//
// ЗАПУСК:
//   flutter create fish_loader
//   cd fish_loader
//   # заменить lib/main.dart этим файлом
//   # создать папку assets и положить туда обе картинки
//   # обновить pubspec.yaml (добавить assets, как выше)
//   flutter pub get
//   flutter run

import 'dart:math' as math;
import 'package:flutter/material.dart';



class FishLoaderScreen extends StatefulWidget {
  const FishLoaderScreen({super.key});

  @override
  State<FishLoaderScreen> createState() => _FishLoaderScreenState();
}

class _FishLoaderScreenState extends State<FishLoaderScreen>
    with TickerProviderStateMixin {
  // Основной 8-секундный контроллер — полный цикл "ныряния"
  late final AnimationController _dive;
  // Постоянное мерцание/всплеск ряби
  late final AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    _dive = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _dive.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          // Линия моря на фоновой картинке (примерно ~55% сверху)
          final horizonY = h * 0.55;

          return AnimatedBuilder(
            animation: Listenable.merge([_dive, _ambient]),
            builder: (context, _) {
              final p = _dive.value;
              final fishTransform = _computeFishTransform(p, w, h, horizonY);

              return Stack(
                fit: StackFit.expand,
                children: [
                  // 1) Фон — ваша картинка с луной и морем
                  Image.asset(
                    'assets/background.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),

                  // 2) Лёгкое движение волн (наложение прозрачного слоя)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: WaterShimmerPainter(
                          ambient: _ambient.value,
                          horizonY: horizonY,
                        ),
                      ),
                    ),
                  ),

                  // 3) Рыбка — ваша картинка
                  Positioned(
                    left: fishTransform.x - fishTransform.size / 2,
                    top: fishTransform.y - fishTransform.size / 2,
                    child: Opacity(
                      opacity: fishTransform.opacity,
                      child: Transform.rotate(
                        angle: fishTransform.rotation,
                        child: SizedBox(
                          width: fishTransform.size,
                          height: fishTransform.size,
                          child: Image.asset(
                            'assets/fish.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 4) Всплеск и круги от воды (поверх рыбки и фона)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: SplashPainter(
                          diveProgress: p,
                          ambient: _ambient.value,
                          horizonY: horizonY,
                        ),
                      ),
                    ),
                  ),

                  // 5) Надпись "Загрузка..."
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _LoadingText(progress: p),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Рассчитывает позицию/поворот/прозрачность/размер рыбки в зависимости
  /// от прогресса (0..1) внутри 8-секундного цикла.
  _FishTransform _computeFishTransform(
      double p, double w, double h, double horizonY) {
    final centerX = w * 0.5;
    final baseSize = w * 0.32; // базовый размер рыбки

    // Опорные точки:
    final startY = horizonY * 0.55;             // около луны
    final hoverY = horizonY - baseSize * 0.05;  // парит над водой
    final waterY = horizonY + baseSize * 0.10;  // момент входа в воду
    final deepY = horizonY + (h - horizonY) * 0.55; // под водой

    double x = centerX;
    double y;
    double rotation;
    double opacity = 1.0;
    double size = baseSize;

    if (p < 0.18) {
      // Фаза 1: появляется у луны и плавно слетает вниз
      final t = p / 0.18;
      final e = _easeOutCubic(t);
      y = _lerp(startY, hoverY, e);
      rotation = _lerp(-0.35, -0.05, e); // лёгкий наклон
      opacity = t;
      // лёгкое горизонтальное смещение
      x = centerX + math.sin(t * math.pi) * w * 0.05;
      size = baseSize * (0.7 + 0.3 * e);
    } else if (p < 0.55) {
      // Фаза 2: парит, рисует "восьмёрку" над водой
      final t = (p - 0.18) / 0.37;
      x = centerX + math.sin(t * math.pi * 2) * w * 0.10;
      y = hoverY + math.sin(t * math.pi * 4) * baseSize * 0.08;
      rotation = math.sin(t * math.pi * 2) * 0.25;
    } else if (p < 0.78) {
      // Фаза 3: разворачивается носом вниз и ныряет
      final t = (p - 0.55) / 0.23;
      final e = _easeInCubic(t);
      x = _lerp(centerX + math.sin(math.pi * 2) * w * 0.10, centerX, e);
      y = _lerp(hoverY, waterY, e);
      // Рыбка на картинке смотрит ВПРАВО, нос вниз = поворот на +π/2
      rotation = _lerp(0.0, math.pi / 2, e);
      size = baseSize * (1.0 - 0.05 * e);
    } else if (p < 0.94) {
      // Фаза 4: погружается в глубину, тает
      final t = (p - 0.78) / 0.16;
      final e = _easeInCubic(t);
      x = centerX;
      y = _lerp(waterY, deepY, e);
      rotation = math.pi / 2;
      opacity = 1.0 - t * 0.95;
      size = baseSize * (1.0 - 0.45 * t);
    } else {
      // Фаза 5: пауза, вода успокаивается, цикл рестартует
      x = centerX;
      y = deepY;
      rotation = math.pi / 2;
      opacity = 0.0;
      size = baseSize * 0.5;
    }

    return _FishTransform(
      x: x,
      y: y,
      size: size,
      rotation: rotation,
      opacity: opacity,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static double _easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();
  static double _easeInCubic(double t) => t * t * t;
}

class _FishTransform {
  final double x;
  final double y;
  final double size;
  final double rotation;
  final double opacity;
  const _FishTransform({
    required this.x,
    required this.y,
    required this.size,
    required this.rotation,
    required this.opacity,
  });
}

/// Лёгкое мерцание воды поверх фоновой картинки
class WaterShimmerPainter extends CustomPainter {
  final double ambient;
  final double horizonY;
  WaterShimmerPainter({required this.ambient, required this.horizonY});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final paint = Paint();
    for (int i = 0; i < 30; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = horizonY + rnd.nextDouble() * (size.height - horizonY);
      final twinkle =
          0.5 + 0.5 * math.sin(ambient * 2 * math.pi + i * 1.1);
      paint.color = const Color(0xFFB6F2FF).withOpacity(0.05 + 0.25 * twinkle);
      canvas.drawCircle(Offset(x, y), 1.5 + twinkle * 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WaterShimmerPainter old) =>
      old.ambient != ambient;
}

/// Всплеск воды в момент ныряния
class SplashPainter extends CustomPainter {
  final double diveProgress;
  final double ambient;
  final double horizonY;
  SplashPainter({
    required this.diveProgress,
    required this.ambient,
    required this.horizonY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = diveProgress;
    if (p < 0.72 || p > 0.95) return;
    final t = (p - 0.72) / 0.23;
    final centerX = size.width * 0.5;
    final centerY = horizonY + 6;

    // Растущие кольца от удара о воду
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (int i = 0; i < 3; i++) {
      final localT = (t - i * 0.18).clamp(0.0, 1.0);
      if (localT <= 0) continue;
      final r = size.width * 0.04 + localT * size.width * 0.22;
      ring.color = const Color(0xFFB6F2FF).withOpacity((1 - localT) * 0.75);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(centerX, centerY),
          width: r * 2,
          height: r * 0.55,
        ),
        ring,
      );
    }

    // Брызги
    final drop = Paint();
    final rnd = math.Random(99);
    for (int i = 0; i < 14; i++) {
      final angle =
          -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.0;
      final dist = size.width * 0.04 +
          t * size.width * 0.10 +
          rnd.nextDouble() * 10;
      final dx = math.cos(angle) * dist;
      final dy = math.sin(angle) * dist - t * 16;
      drop.color = const Color(0xFFE6FAFF).withOpacity((1 - t) * 0.9);
      canvas.drawCircle(
        Offset(centerX + dx, centerY + dy),
        1.4 + (1 - t) * 1.6,
        drop,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SplashPainter old) =>
      old.diveProgress != diveProgress || old.ambient != ambient;
}

class _LoadingText extends StatelessWidget {
  final double progress;
  const _LoadingText({required this.progress});

  @override
  Widget build(BuildContext context) {
    final dotCount = ((progress * 8).floor() % 4);
    final dots = '.' * dotCount;
    return Text(
      'Загрузка$dots',
      style: TextStyle(
        color: Colors.tealAccent.withOpacity(0.9),
        fontSize: 18,
        letterSpacing: 2,
        shadows: const [
          Shadow(color: Colors.tealAccent, blurRadius: 14),
        ],
      ),
    );
  }
}
