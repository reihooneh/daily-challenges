<?php

declare(strict_types=1);

// A tiny test runner, so the project needs nothing beyond PHP itself.
// Run with:  php tests/run.php

use Grassline\Bowls;
use Grassline\Cli;
use Grassline\InputError;
use Grassline\Log;
use Grassline\Physics;
use Grassline\Report;
use Grassline\Shot;

foreach (['Physics', 'Shot', 'Log', 'Report', 'Cli'] as $file) {
    require_once __DIR__ . "/../src/$file.php";
}

$passed = 0;
$failed = 0;
function check(bool $ok, string $what): void
{
    global $passed, $failed;
    if ($ok) {
        $passed++;
    } else {
        $failed++;
        echo "FAIL: $what\n";
    }
}
function near(float $a, float $b, float $tol): bool
{
    return abs($a - $b) <= $tol;
}
function cli(array $args, string $stdin = ''): array
{
    $in = fopen('php://memory', 'w+');
    fwrite($in, $stdin);
    rewind($in);
    $out = fopen('php://memory', 'w+');
    $err = fopen('php://memory', 'w+');
    $code = Cli::run($args, $in, $out, $err);
    rewind($out);
    rewind($err);
    return [$code, stream_get_contents($out), stream_get_contents($err)];
}

// ---------- The physics ----------

// The closed form agrees with brute-force integration of dθ/dt = K/v, across bowls and greens.
mt_srand(11);
$worst = 0.0;
for ($i = 0; $i < 40; $i++) {
    $a = 0.15 + 0.3 * mt_rand() / mt_getrandmax();
    $c = 0.05 + 0.3 * mt_rand() / mt_getrandmax();
    $v0 = 2.5 + 2 * mt_rand() / mt_getrandmax();
    $exact = Physics::rest($v0, $a, $c);
    $num = Physics::integrate($v0, $a, $c * $a, 0.002);
    $worst = max($worst, hypot($exact['x'] - $num['x'], $exact['y'] - $num['y']));
}
check($worst < 0.005, "closed form matches Runge–Kutta to 5 mm (worst $worst m)");

// Along the path: speed falls linearly in time, distance travelled is (v0² − v²)/2a.
$p = Physics::at(3.6, 0.28, 0.16, 0.5);
check(near($p['v'], 3.6 * exp(-0.5), 1e-12) && near($p['s'], (3.6 ** 2 - $p['v'] ** 2) / 0.56, 1e-12), 'speed and distance along the path');
$q = Physics::at(3.6, 0.28, 0.16, 30);
$r = Physics::rest(3.6, 0.28, 0.16);
check(near($q['x'], $r['x'], 1e-9) && near($q['y'], $r['y'], 1e-9), 'the path ends where rest() says');

// With no bias the bowl runs straight, and stops after v0²/2a.
$s = Physics::rest(3.0, 0.3, 0.0);
check(near($s['x'], 9 / 0.6, 1e-12) && near($s['y'], 0, 1e-12), 'no bias: straight, stopping distance v²/2a');

// The aiming angle is the same at every length (de Mestre's result for this model).
$bowls = Bowls::preset('medium');
$angles = array_map(static fn ($L) => (new Shot($bowls, 14, $L))->angle, [20, 25, 30, 35, 40]);
check(max($angles) - min($angles) < 1e-12, 'the angle of aim does not change with length');

// A heavy or light bowl on the right line finishes on the line, long or short.
$shot = new Shot($bowls, 14, 25);
$heavy = Physics::rest($shot->v0 * 1.05, $shot->a, $shot->c);
check(near(atan2($heavy['y'], $heavy['x']), $shot->angle, 1e-12), 'wrong weight: still on line');
check(near(hypot($heavy['x'], $heavy['y']), 25 * 1.05 ** 2, 1e-9), 'and 10.25% long for 5% heavy');

// The presets reproduce their widths on a 14-second green at 30 yards.
foreach (Bowls::PRESETS as $name => $width) {
    $sh = new Shot(Bowls::preset($name), 14, Physics::GREEN_LENGTH);
    check(near($sh->width(), $width, 1e-6), "$name bias: $width m at 30 yards on a 14 s green");
    check(near($sh->duration(), 14, 1e-6), "$name bias: takes 14 s to a 30-yard jack");
}

// Faster greens (more seconds) need more grass; wider bias needs more grass.
$prev = 0.0;
foreach ([10, 12, 14, 16, 18, 20] as $sec) {
    $w = (new Shot($bowls, $sec, 27))->width();
    check($w > $prev, "$sec s green needs more grass than a slower one");
    $prev = $w;
}
check((new Shot(Bowls::preset('wide'), 14, 25))->width() > (new Shot(Bowls::preset('narrow'), 14, 25))->width(), 'wide bias takes more grass');

// The path: starts at the mat, finishes on the jack, bulges to the aiming side, and its time matches.
$path = $shot->path(400);
check(near($path[0]['along'], 0, 1e-12) && near($path[0]['across'], 0, 1e-12), 'path starts at the mat');
$end = end($path);
check(near($end['along'], 25, 1e-3) && near($end['across'], 0, 1e-3), 'path finishes on the jack');
check(near($end['t'], $shot->duration(), 1e-3), 'path time matches the duration');
$sh = $shot->shoulder();
check($sh['across'] > 0.3 && $sh['across'] < $shot->width() && $sh['along'] > 8 && $sh['along'] < 25, 'the shoulder is on the aiming side, between mat and jack');
$inside = true;
foreach ($path as $pt) {
    // The bowl is always between the centre line and the aiming line.
    $aim = $pt['along'] * tan($shot->angle);
    $inside = $inside && $pt['across'] >= -1e-9 && $pt['across'] <= $aim + 1e-9;
}
check($inside, 'the bowl stays between the centre line and the aiming line');

// The green's deceleration from its speed in seconds round-trips.
$a = Physics::decelerationFor(14.5, $bowls->k);
check(near(Physics::duration(Physics::GREEN_LENGTH, $a, $bowls->k / $a), 14.5, 1e-6), 'green speed round-trips');

// ---------- Calibrating from a log ----------

$log = Log::parse("green 14\ndraw 25 2.0\ndraw 30 2.4  # longer\n");
$fit = $log->fit();
$slope = (25 * 2.0 + 30 * 2.4) / (25 ** 2 + 30 ** 2);
check(near(tan(deg2rad($fit['angle'])), $slope, 1e-12), 'least-squares slope through the origin');
$back = new Shot($fit['bowls'], $fit['seconds'], 25);
check(near($back->width(), $slope * 25, 1e-6), 'the fitted bowls reproduce the fitted width');

// A log generated from known bowls gives those bowls back (to 0.1%: the log rounds widths to millimetres).
$truth = Bowls::fromWidth(2.3, 27.432, 15.0, 'truth');
$lines = [];
foreach ([22, 25, 28, 31, 34] as $L) {
    $lines[] = sprintf('draw %d %.3f', $L, (new Shot($truth, 15, $L))->width());
}
$tsh = new Shot($truth, 15, 27);
$lines[] = sprintf('timed 27 %.3f', $tsh->duration());
$f2 = Log::parse(implode("\n", $lines))->fit();
check(near($f2['bowls']->k, $truth->k, 1e-3 * $truth->k) && near($f2['seconds'], 15, 0.01), 'a generated log recovers the bowls and green');

$bad = [
    ['', "at least one 'draw"],
    ["draw 25 2\n", "the green's speed"],
    ["green 14\ngreen 15\ndraw 25 2\n", 'given twice'],
    ["green 14\ndraw 25 12\n", 'from 0.2 to 6'],
    ["green 14\ndraw 15 5.5\n", 'not a draw shot'],
    ["green 14\ndraw 1e3 2\n", 'a number like'],
    ["green 14\ndraw -25 2\n", 'a number like'],
    ["green 99\ndraw 25 2\n", 'from 8 to 25'],
    ["green 14\nrm -rf SECRET\n", "lines are 'green"],
    ["green 14\ndraw 25 2\u{202E}SECRET\n", 'invisible'],
    ["green 14\x1b[2J\ndraw 25 2\n", 'control'],
    ["green 14\n# " . str_repeat('x', 300) . "\ndraw 25 2\n", 'longer than 200'],
    ["green 14\n" . str_repeat("draw 25 2\n", 201), 'at most 200'],
    ["green 14\ndraw 25 2\xff\n", 'UTF-8'],
    [str_repeat('#', 70000), '64 KB'],
];
foreach ($bad as [$text, $want]) {
    try {
        Log::parse($text);
        check(false, "should reject: $want");
    } catch (InputError $e) {
        check(str_contains($e->getMessage(), $want) && !str_contains($e->getMessage(), 'SECRET'), "rejects ($want): " . $e->getMessage());
    }
}

// ---------- The command line ----------

[$code, $out] = cli(['--jack', '27', '--green', '15']);
check($code === 0 && str_starts_with($out, "GRASSLINE  forehand, medium bias, 15.0-second green, jack at 27.0 m\n"), 'the plan');
check(str_contains($out, 'Aim 5.25° right of the centre line:'), 'the angle');
check(str_contains($out, '5% too heavy on the right line: finishes 2.77 m past the jack'), 'weight errors');
[, $back] = cli(['--hand', 'backhand']);
check(str_contains($back, 'left of the centre line'), 'backhand aims left');
[, $lefty] = cli(['--hand', 'backhand', '--left']);
check(str_contains($lefty, 'right of the centre line') && str_contains($lefty, 'left-handed backhand'), 'a left-hander\'s backhand aims right');
[, $svg] = cli(['--svg']);
check(str_starts_with($svg, '<svg xmlns=') && !str_contains($svg, '<script'), 'a drawing, with no script');
[$code, $out] = cli(['--log', '-', '--jack', '29'], file_get_contents(__DIR__ . '/../examples/club-green.txt'));
check($code === 0 && str_contains($out, 'your bowls (from 5 draws)'), 'calibrated from the example log');
[$code, $out] = cli(['--log', __DIR__ . '/../examples/club-green.txt']);
check($code === 0, 'the log as a file');

$dir = sys_get_temp_dir() . '/grassline-' . bin2hex(random_bytes(4));
mkdir($dir);
symlink(realpath(__DIR__ . '/../examples/club-green.txt'), "$dir/link.txt");
[$code, , $err] = cli(['--log', "$dir/link.txt"]);
check($code === 2 && str_contains($err, 'not a link'), 'a symbolic link is refused');
[$code] = cli(['--log', $dir]);
check($code === 2, 'a folder is refused');
[$code, , $err] = cli(['--log', "$dir/secret-name-zz.txt"]);
check($code === 2 && !str_contains($err, 'secret-name'), 'the path is never echoed');
unlink("$dir/link.txt");
rmdir($dir);

foreach ([['--jack', '99'], ['--jack', '25e1'], ['--jack'], ['--green', 'fast'], ['--bias', 'banana'], ['--hand', 'both'], ['--rink', '9'], ['--jack', '25', '--jack', '26'], ['--wat'], ['--log', '-', '--bias', 'wide'], ['--log']] as $args) {
    [$code] = cli($args, "green 14\ndraw 25 2\n");
    check($code === 2, 'refused: ' . implode(' ', $args));
}
[$code, , $err] = cli(['--help']);
check($code === 2 && str_starts_with($err, 'usage: grassline'), 'help');

echo "$passed checks passed, $failed failed\n";
exit($failed ? 1 : 0);
