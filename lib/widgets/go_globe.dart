import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:global_overview/theme/go_tokens.dart';

/// 程序化线框地球（无贴图）。经纬网 + 陆地轮廓 + 城市光点 + 球缘辉光，
/// 自转见 [GoGlobe]；上方叠一层径向暗色晕影保证内容可读。
///
/// 仅用于深色主题；浅色主题下不绘制。
class GoGlobe extends StatefulWidget {
  /// 所在页面当前是否可见（切走的 Tab / 被覆盖的路由应传 false，动画随之暂停）。
  final bool active;

  /// 相对视口宽度的球半径系数。
  final double radiusFactor;

  const GoGlobe({super.key, this.active = true, this.radiusFactor = 0.58});

  @override
  State<GoGlobe> createState() => _GoGlobeState();
}

class _GoGlobeState extends State<GoGlobe> with SingleTickerProviderStateMixin {
  static const _turns = Duration(seconds: 105);
  late final AnimationController _c = AnimationController(vsync: this, duration: _turns)..repeat();
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;
  bool _reduceMotion = false;
  List<List<Offset>>? _rings;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        final fg = s == AppLifecycleState.resumed;
        if (fg != _foreground) {
          _foreground = fg;
          _sync();
        }
      },
    );
    _load();
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (rm != _reduceMotion) {
      _reduceMotion = rm;
      _sync();
    }
  }

  @override
  void didUpdateWidget(covariant GoGlobe old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) _sync();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _c.dispose();
    super.dispose();
  }

  void _sync() {
    final run = widget.active && _foreground && !_reduceMotion;
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c.stop();
    }
  }

  Future<void> _load() async {
    final rings = await landRings();
    if (mounted) setState(() => _rings = rings);
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.light) return const SizedBox.shrink();
    final rings = _rings;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (rings != null)
            RepaintBoundary(
              child: CustomPaint(
                painter: _GlobePainter(anim: _c, rings: rings, radiusFactor: widget.radiusFactor),
                size: Size.infinite,
              ),
            ),
          const _GlobeVignette(),
        ],
      ),
    );
  }
}

/// 内容下方的径向暗色晕影（中心透明 → 四周背景色），压住球体保可读。
class _GlobeVignette extends StatelessWidget {
  const _GlobeVignette();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.95,
            colors: [Go.bg.withValues(alpha: 0.0), Go.bg.withValues(alpha: 0.82)],
            stops: const [0.30, 1.0],
          ),
        ),
      );
}

// ===================== 数据 =====================

Future<List<List<Offset>>>? _landCache;

/// 陆地轮廓（每环为 [lon, lat] 序列），进程内只解析一次。
Future<List<List<Offset>>> landRings() => _landCache ??= _parseLand();

Future<List<List<Offset>>> _parseLand() async {
  final raw = await rootBundle.loadString('assets/geo/world_land.json');
  final map = jsonDecode(raw) as Map<String, dynamic>;
  return [
    for (final ring in map['polys'] as List)
      [for (final p in ring as List) Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())],
  ];
}

/// 主要城市 (lat, lon)，仅作装饰性光点。
const List<(double, double)> _cities = [
  (39.9, 116.4), (31.2, 121.5), (22.3, 114.2), (25.0, 121.5), (35.7, 139.7), (37.6, 127.0),
  (1.35, 103.8), (13.75, 100.5), (21.0, 105.8), (14.6, 121.0), (-6.2, 106.85), (28.6, 77.2),
  (19.1, 72.9), (24.9, 67.0), (23.8, 90.4), (25.2, 55.3), (35.7, 51.4), (24.7, 46.7),
  (55.75, 37.6), (41.0, 29.0), (39.9, 32.9), (52.2, 21.0), (52.5, 13.4), (48.2, 16.4),
  (48.85, 2.35), (51.5, -0.13), (53.35, -6.25), (52.37, 4.9), (47.4, 8.5), (41.9, 12.5),
  (38.0, 23.7), (40.4, -3.7), (38.7, -9.1), (59.3, 18.1), (30.0, 31.2), (33.6, -7.6),
  (-1.29, 36.8), (6.5, 3.4), (-26.2, 28.0), (-33.9, 18.4), (24.7, 46.7), (40.7, -74.0),
  (34.05, -118.2), (41.88, -87.6), (47.6, -122.3), (25.8, -80.2), (43.65, -79.4), (49.3, -123.1),
  (19.4, -99.1), (23.1, -82.4), (4.7, -74.1), (-0.18, -78.5), (-12.05, -77.05), (-23.5, -46.6),
  (-34.6, -58.4), (-34.9, -56.2), (-33.45, -70.7), (-33.87, 151.2), (-37.8, 145.0), (-36.85, 174.8),
];

// ===================== 绘制 =====================

typedef _P3 = ({double x, double y, double z});

const double _tilt = 23.5 * math.pi / 180;
const double _gridStep = 15; // 经纬网间隔（度）
const double _baseOpacity = 0.16; // 球体整体不透明度（真机微调入口）

class _GlobePainter extends CustomPainter {
  final Animation<double> anim;
  final List<List<Offset>> rings;
  final double radiusFactor;

  _GlobePainter({required this.anim, required this.rings, required this.radiusFactor}) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * radiusFactor;
    final spin = anim.value; // 0..1 圈

    _rim(canvas, center, r);

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Go.secondary.withValues(alpha: _baseOpacity * 0.62);
    final land = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Go.primary.withValues(alpha: _baseOpacity);
    final landFill = Paint()
      ..style = PaintingStyle.fill
      ..color = Go.primary.withValues(alpha: _baseOpacity * 0.35);

    // 经纬网
    for (double lon = -180; lon < 180; lon += _gridStep) {
      canvas.drawPath(_polyPath(_meridian(lon, spin), center, r), grid);
    }
    for (double lat = -75; lat <= 75; lat += _gridStep) {
      canvas.drawPath(_polyPath(_parallel(lat, spin), center, r), grid);
    }
    // 赤道略亮
    final eq = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Go.secondary.withValues(alpha: _baseOpacity * 0.95);
    canvas.drawPath(_polyPath(_parallel(0, spin), center, r), eq);

    // 陆地
    for (final ring in rings) {
      final pts = [for (final p in ring) _to3d(p.dy, p.dx, spin)];
      var allFront = true;
      for (final p in pts) {
        if (p.z <= 0) {
          allFront = false;
          break;
        }
      }
      final path = _polyPath(pts, center, r);
      if (allFront) canvas.drawPath(path, landFill);
      canvas.drawPath(path, land);
    }

    // 城市光点
    final dot = Paint()..style = PaintingStyle.fill;
    final t = spin * math.pi * 2;
    for (var i = 0; i < _cities.length; i++) {
      final c = _cities[i];
      final p = _to3d(c.$1, c.$2, spin);
      if (p.z <= 0.05) continue;
      final o = _screen(p, center, r);
      final twinkle = 0.5 + 0.5 * math.sin(t * 2 + i * 1.7);
      dot.color = Color.lerp(Go.secondary, Colors.white, 0.6)!.withValues(alpha: 0.30 + 0.45 * twinkle);
      canvas.drawCircle(o, math.max(1.1, r * 0.008), dot);
    }
  }

  void _rim(Canvas canvas, Offset c, double r) {
    final outer = Paint()
      ..shader = RadialGradient(
        colors: [Go.secondary.withValues(alpha: 0.0), Go.secondary.withValues(alpha: 0.0), Go.secondary.withValues(alpha: 0.20)],
        stops: const [0, 0.80, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r * 1.18));
    canvas.drawCircle(c, r * 1.18, outer);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Go.secondary.withValues(alpha: 0.42);
    canvas.drawCircle(c, r, edge);
  }

  List<_P3> _meridian(double lon, double spin) => [
        for (double lat = -90; lat <= 90; lat += 5) _to3d(lat, lon, spin),
      ];

  List<_P3> _parallel(double lat, double spin) => [
        for (double lon = -180; lon <= 180; lon += 5) _to3d(lat, lon, spin),
      ];

  _P3 _to3d(double lat, double lon, double spin) {
    final la = lat * math.pi / 180;
    final lo = (lon + spin * 360) * math.pi / 180;
    final x = math.cos(la) * math.sin(lo);
    final y = math.sin(la);
    final z = math.cos(la) * math.cos(lo);
    final ct = math.cos(_tilt), st = math.sin(_tilt);
    return (x: x * ct - y * st, y: x * st + y * ct, z: z);
  }

  Offset _screen(_P3 p, Offset c, double r) => Offset(c.dx + p.x * r, c.dy - p.y * r);

  /// 折线投影，按 z>0 的前半球裁剪（与球缘精确相交）。
  Path _polyPath(List<_P3> pts, Offset c, double r) {
    final path = Path();
    var pen = false;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      final af = a.z > 0, bf = b.z > 0;
      if (!af && !bf) {
        pen = false;
        continue;
      }
      if (af && bf) {
        final oa = _screen(a, c, r), ob = _screen(b, c, r);
        if (pen) {
          path.lineTo(oa.dx, oa.dy);
        } else {
          path.moveTo(oa.dx, oa.dy);
        }
        path.lineTo(ob.dx, ob.dy);
        pen = true;
      } else if (af) {
        final oa = _screen(a, c, r), oc = _screen(_cross(a, b), c, r);
        if (pen) {
          path.lineTo(oa.dx, oa.dy);
        } else {
          path.moveTo(oa.dx, oa.dy);
        }
        path.lineTo(oc.dx, oc.dy);
        pen = false;
      } else {
        final oc = _screen(_cross(a, b), c, r), ob = _screen(b, c, r);
        path.moveTo(oc.dx, oc.dy);
        path.lineTo(ob.dx, ob.dy);
        pen = true;
      }
    }
    return path;
  }

  /// a、b 之间 z=0 的交点。
  _P3 _cross(_P3 a, _P3 b) {
    final t = a.z / (a.z - b.z);
    return (x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, z: 0);
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) => old.rings != rings || old.radiusFactor != radiusFactor;
}
