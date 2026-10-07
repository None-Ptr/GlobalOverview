/**
 * 网页版线框地球：移植自 App 的 lib/widgets/go_globe.dart（同一套向量 / 自转 / 倾斜 / 裁剪 / 光点公式）。
 * 无依赖、无外部请求（陆地数据内联在 land.js 里）。
 *
 * 取不到 canvas 或 JS 出错时，Hero 里那张静态 SVG 会保留 —— 页面不会变成空一块。
 */
(function () {
  var canvas = document.getElementById('globe-canvas');
  if (!canvas || !canvas.getContext) return;

  var PRIMARY = [139, 92, 246]; // Go.primary   #8B5CF6
  var SECONDARY = [65, 224, 208]; // Go.secondary #41E0D0
  var BASE_OPACITY = 0.16; // 与 App 的 _baseOpacity 一致
  var TILT = (23.5 * Math.PI) / 180;
  var PERIOD_MS = 105000; // 自转一圈 105s，与 App 的 _turns 一致
  // 初始相位：App 里 θ=0 正对本初子午线（北京在背面）。网页是给中文用户看的，
  // 起始就把东亚转到正面（θ=-110° 时 z' = cos(lat)·cos(lon+θ)，lon=110°E 取最大）。
  var PHASE0 = (-110 * Math.PI) / 180;
  var FPS = 20; // App 也是降到约 20fps，肉眼无差别但省一大截开销

  var TURN = Math.PI * 2;
  var CT = Math.cos(TILT);
  var ST = Math.sin(TILT);

  // 主要城市 (lat, lon)：与 App 的 _cities 完全一致
  var CITIES = [
    [39.9, 116.4], [31.2, 121.5], [22.3, 114.2], [25.0, 121.5], [35.7, 139.7], [37.6, 127.0],
    [1.35, 103.8], [13.75, 100.5], [21.0, 105.8], [14.6, 121.0], [-6.2, 106.85], [28.6, 77.2],
    [19.1, 72.9], [24.9, 67.0], [23.8, 90.4], [25.2, 55.3], [35.7, 51.4], [24.7, 46.7],
    [55.75, 37.6], [41.0, 29.0], [39.9, 32.9], [52.2, 21.0], [52.5, 13.4], [48.2, 16.4],
    [48.85, 2.35], [51.5, -0.13], [53.35, -6.25], [52.37, 4.9], [47.4, 8.5], [41.9, 12.5],
    [38.0, 23.7], [40.4, -3.7], [38.7, -9.1], [59.3, 18.1], [30.0, 31.2], [33.6, -7.6],
    [-1.29, 36.8], [6.5, 3.4], [-26.2, 28.0], [-33.9, 18.4], [24.7, 46.7], [40.7, -74.0],
    [34.05, -118.2], [41.88, -87.6], [47.6, -122.3], [25.8, -80.2], [43.65, -79.4], [49.3, -123.1],
    [19.4, -99.1], [23.1, -82.4], [4.7, -74.1], [-0.18, -78.5], [-12.05, -77.05], [-23.5, -46.6],
    [-34.6, -58.4], [-34.9, -56.2], [-33.45, -70.7], [-33.87, 151.2], [-37.8, 145.0], [-36.85, 174.8],
  ];

  // 球面上的基准单位向量（自转=0、未倾斜），只算一次
  function base(lat, lon) {
    var la = (lat * Math.PI) / 180;
    var lo = (lon * Math.PI) / 180;
    var ca = Math.cos(la);
    return { x: ca * Math.sin(lo), y: Math.sin(la), z: ca * Math.cos(lo) };
  }

  var MERIDIANS = [];
  for (var lon = -180; lon < 180; lon += 15) {
    var m = [];
    for (var la = -90; la <= 90; la += 5) m.push(base(la, lon));
    MERIDIANS.push(m);
  }
  var PARALLELS = [];
  for (var la2 = -75; la2 <= 75; la2 += 15) {
    var p = [];
    for (var lo2 = -180; lo2 <= 180; lo2 += 5) p.push(base(la2, lo2));
    PARALLELS.push(p);
  }
  var EQUATOR = [];
  for (var lo3 = -180; lo3 <= 180; lo3 += 5) EQUATOR.push(base(0, lo3));

  var CITY_V = CITIES.map(function (c) {
    return base(c[0], c[1]);
  });

  var landRings = (window.GO_LAND || []).map(function (ring) {
    var out = [];
    for (var i = 0; i + 1 < ring.length; i += 2) out.push(base(ring[i + 1], ring[i]));
    return out;
  });

  var ctx = canvas.getContext('2d');
  if (!ctx) return;

  // canvas 真的能画，才把底下那张静态 SVG 撤掉（避免 JS 半途失败导致两个都没了）
  var fallback = document.getElementById('globe-static');
  if (fallback) fallback.style.display = 'none';

  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var dpr = Math.min(window.devicePixelRatio || 1, 2);
  var W = 0;
  var H = 0;

  function rgba(c, a) {
    return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a.toFixed(3) + ')';
  }

  function resize() {
    var rect = canvas.getBoundingClientRect();
    W = Math.max(1, Math.round(rect.width));
    H = Math.max(1, Math.round(rect.height));
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  // a、b 之间 z=0 的交点（与 App 的 _cross 一致）
  function cross(a, b) {
    var t = a.z / (a.z - b.z);
    return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, z: 0 };
  }

  function drawPolyline(pts, cx, cy, r) {
    var pen = false;
    ctx.beginPath();
    for (var i = 0; i + 1 < pts.length; i++) {
      var a = pts[i];
      var b = pts[i + 1];
      var af = a.z > 0;
      var bf = b.z > 0;
      if (!af && !bf) {
        pen = false;
        continue;
      }
      if (af && bf) {
        if (pen) ctx.lineTo(cx + a.x * r, cy - a.y * r);
        else ctx.moveTo(cx + a.x * r, cy - a.y * r);
        ctx.lineTo(cx + b.x * r, cy - b.y * r);
        pen = true;
      } else if (af) {
        var oc = cross(a, b);
        if (pen) ctx.lineTo(cx + a.x * r, cy - a.y * r);
        else ctx.moveTo(cx + a.x * r, cy - a.y * r);
        ctx.lineTo(cx + oc.x * r, cy - oc.y * r);
        pen = false;
      } else {
        var oc2 = cross(a, b);
        ctx.moveTo(cx + oc2.x * r, cy - oc2.y * r);
        ctx.lineTo(cx + b.x * r, cy - b.y * r);
        pen = true;
      }
    }
    ctx.stroke();
  }

  function draw(timeMs) {
    if (!W || !H) resize();
    ctx.clearRect(0, 0, W, H);
    var cx = W / 2;
    var cy = H / 2;
    // 与兜底 SVG 的球半径比例一致（SVG 里 r=78 / viewBox 200），保证两版大小相同
    var r = Math.min(W, H) * 0.39;
    if (r <= 4) return;

    var th = PHASE0 + ((timeMs % PERIOD_MS) / PERIOD_MS) * TURN;
    var c = Math.cos(th);
    var s = Math.sin(th);

    // 基准向量 → 自转 + 倾斜（纯乘加，无三角函数）
    function ap(b) {
      var x = b.x * c + b.z * s;
      var z = b.z * c - b.x * s;
      var y = b.y;
      return { x: x * CT - y * ST, y: x * ST + y * CT, z: z };
    }

    // 球缘辉光 + 边线（对应 App 的 _rim）
    var g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r * 1.18);
    g.addColorStop(0, rgba(SECONDARY, 0));
    g.addColorStop(0.8, rgba(SECONDARY, 0));
    g.addColorStop(1, rgba(SECONDARY, 0.2));
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 1.18, 0, TURN);
    ctx.fill();

    ctx.lineWidth = 1.1;
    ctx.strokeStyle = rgba(SECONDARY, 0.42);
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, TURN);
    ctx.stroke();

    // 经纬网
    ctx.lineWidth = 0.8;
    ctx.strokeStyle = rgba(SECONDARY, BASE_OPACITY * 0.62);
    MERIDIANS.forEach(function (m) {
      drawPolyline(m.map(ap), cx, cy, r);
    });
    PARALLELS.forEach(function (p2) {
      drawPolyline(p2.map(ap), cx, cy, r);
    });
    // 赤道略亮
    ctx.lineWidth = 1.0;
    ctx.strokeStyle = rgba(SECONDARY, BASE_OPACITY * 0.95);
    drawPolyline(EQUATOR.map(ap), cx, cy, r);

    // 陆地：整环都在前半球的才填色，轮廓始终描边
    ctx.lineWidth = 1.0;
    ctx.strokeStyle = rgba(PRIMARY, BASE_OPACITY);
    ctx.fillStyle = rgba(PRIMARY, BASE_OPACITY * 0.35);
    landRings.forEach(function (ring) {
      var pts = ring.map(ap);
      var allFront = true;
      for (var i = 0; i < pts.length; i++) {
        if (pts[i].z <= 0) {
          allFront = false;
          break;
        }
      }
      ctx.beginPath();
      var started = false;
      for (var j = 0; j < pts.length; j++) {
        var px = cx + pts[j].x * r;
        var py = cy - pts[j].y * r;
        if (j === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
        started = true;
      }
      if (!started) return;
      ctx.closePath();
      if (allFront) ctx.fill();
      ctx.stroke();
    });

    // 城市光点：只画前半球，带轻微闪烁（与 App 的 twinkle 一致）
    var dotR = Math.max(1.1, r * 0.008);
    for (var i = 0; i < CITY_V.length; i++) {
      var pv = ap(CITY_V[i]);
      if (pv.z <= 0.05) continue;
      var tw = 0.5 + 0.5 * Math.sin(th * 2 + i * 1.7);
      var a = 0.3 + 0.45 * tw;
      // Color.lerp(secondary, white, 0.6)
      var col = [
        Math.round(SECONDARY[0] + (255 - SECONDARY[0]) * 0.6),
        Math.round(SECONDARY[1] + (255 - SECONDARY[1]) * 0.6),
        Math.round(SECONDARY[2] + (255 - SECONDARY[2]) * 0.6),
      ];
      ctx.fillStyle = rgba(col, a);
      ctx.beginPath();
      ctx.arc(cx + pv.x * r, cy - pv.y * r, dotR, 0, TURN);
      ctx.fill();
    }
  }

  var last = 0;
  function frame(t) {
    if (t - last >= 1000 / FPS) {
      last = t;
      if (!document.hidden) draw(Date.now());
    }
    requestAnimationFrame(frame);
  }

  function boot() {
    resize();
    draw(Date.now());
    if (!reduce) requestAnimationFrame(frame);
  }

  window.addEventListener('resize', function () {
    resize();
    draw(Date.now());
  });
  window.addEventListener('pageshow', boot);

  boot();
})();
