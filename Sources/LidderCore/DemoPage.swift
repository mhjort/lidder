// The built-in demo game served at `/`. It is compiled into the binary so
// `lidder` works after being copied anywhere, without a resource bundle.
//
// This is a raw string: backslashes and quotes are literal, so the HTML and
// JavaScript can be edited as-is.
let demoPageHTML = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>lidder — lid-angle demo game</title>
<style>
  :root { color-scheme: dark; }
  body {
    margin: 0; font: 15px/1.4 -apple-system, system-ui, sans-serif;
    background: #0d1117; color: #e6edf3; display: flex; flex-direction: column;
    align-items: center; gap: 14px; padding: 20px;
  }
  h1 { margin: 4px 0 0; font-size: 18px; font-weight: 600; }
  canvas { background: #161b22; border-radius: 10px; box-shadow: 0 4px 24px rgba(0,0,0,.4); }
  .hud { display: flex; gap: 22px; font-variant-numeric: tabular-nums; }
  .hud b { color: #58a6ff; }
  .status { font-size: 13px; color: #8b949e; min-height: 1.2em; }
  kbd { background:#21262d; border-radius:4px; padding:1px 5px; font-size:12px; }
</style>
</head>
<body>
  <h1>lidder · lid-angle flyer</h1>
  <canvas id="c" width="640" height="360"></canvas>
  <div class="hud">
    <span>angle <b id="angle">–</b>°</span>
    <span>velocity <b id="vel">–</b>°/s</span>
    <span>score <b id="score">0</b></span>
  </div>
  <div class="status" id="status">connecting…</div>
  <div class="status">Tilt the lid to move the flyer up/down. A fast flick (high velocity) gives a boost. Avoid the pillars.</div>

<script>
const cv = document.getElementById('c'), ctx = cv.getContext('2d');
const W = cv.width, H = cv.height;
const $ = id => document.getElementById(id);

// Latest sensor sample.
let angle = 90, velocity = 0, haveData = false;

// EventSource → live lid data.
const es = new EventSource('/stream');
es.onopen = () => $('status').textContent = 'connected — streaming lid angle';
es.onerror = () => $('status').textContent = 'disconnected — is `lidder serve` running?';
es.onmessage = e => {
  try {
    const d = JSON.parse(e.data);
    if (typeof d.angle === 'number') { angle = d.angle; velocity = d.velocity; haveData = true; }
  } catch {}
};

// --- tiny game ----------------------------------------------------------
// Map lid angle (roughly 0–180°) to a target height; velocity adds a kick.
const ANGLE_MIN = 20, ANGLE_MAX = 160;
let y = H / 2, vy = 0, score = 0, dead = false, deadAt = 0;
let pillars = [];
let spawnT = 0;

function targetY() {
  const t = (angle - ANGLE_MIN) / (ANGLE_MAX - ANGLE_MIN);
  const clamped = Math.max(0, Math.min(1, t));
  // Larger angle (lid open) = flyer higher up.
  return H - clamped * (H - 40) - 20;
}

function reset() {
  y = H / 2; vy = 0; score = 0; pillars = []; spawnT = 0; dead = false;
}

function step(dt) {
  if (dead) {
    if (performance.now() - deadAt > 1200) reset();
    return;
  }
  // Spring the flyer toward the lid-angle target, plus a velocity boost.
  const ty = targetY();
  vy += (ty - y) * 0.012;
  vy -= Math.sign(y - ty) * Math.min(velocity, 80) * 0.04; // flick boost
  vy *= 0.88;
  y += vy;
  y = Math.max(12, Math.min(H - 12, y));

  // Pillars.
  spawnT -= dt;
  if (spawnT <= 0) {
    const gap = 120, top = 40 + Math.random() * (H - 80 - gap);
    pillars.push({ x: W + 20, top, gap, scored: false });
    spawnT = 1.4;
  }
  for (const p of pillars) {
    p.x -= 150 * dt;
    if (!p.scored && p.x < 90) { p.scored = true; score++; }
    // Collision with flyer at x≈90.
    if (p.x < 110 && p.x > 64) {
      if (y < p.top || y > p.top + p.gap) { dead = true; deadAt = performance.now(); }
    }
  }
  pillars = pillars.filter(p => p.x > -40);
}

function draw() {
  ctx.clearRect(0, 0, W, H);
  // Pillars.
  ctx.fillStyle = '#2ea04360';
  for (const p of pillars) {
    ctx.fillRect(p.x, 0, 46, p.top);
    ctx.fillRect(p.x, p.top + p.gap, 46, H - p.top - p.gap);
  }
  // Flyer.
  ctx.fillStyle = dead ? '#f85149' : '#58a6ff';
  ctx.beginPath();
  ctx.arc(90, y, 12, 0, Math.PI * 2);
  ctx.fill();
  if (!haveData) {
    ctx.fillStyle = '#8b949e';
    ctx.font = '14px system-ui';
    ctx.fillText('waiting for lid data…', 20, 28);
  }
  if (dead) {
    ctx.fillStyle = '#e6edf3';
    ctx.font = 'bold 22px system-ui';
    ctx.fillText('crash! restarting…', W/2 - 90, H/2);
  }
}

let last = performance.now();
function loop(now) {
  const dt = Math.min((now - last) / 1000, 0.05);
  last = now;
  step(dt);
  draw();
  $('angle').textContent = angle.toFixed(1);
  $('vel').textContent = velocity.toFixed(1);
  $('score').textContent = score;
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
</script>
</body>
</html>
"""#
