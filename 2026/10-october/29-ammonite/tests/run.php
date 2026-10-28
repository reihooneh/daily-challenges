<?php

declare(strict_types=1);

// A tiny test runner, so the project needs nothing beyond PHP itself.
// Run with:  php tests/run.php

use Ammonite\Cli;
use Ammonite\FishGroup;
use Ammonite\Model;
use Ammonite\Planner;
use Ammonite\Report;
use Ammonite\Tank;
use Ammonite\TankException;

foreach (['Tank', 'Model', 'Planner', 'Report', 'Cli'] as $file) {
    require_once __DIR__ . "/../src/$file.php";
}

$passed = 0;
$failed = 0;

function check(bool $condition, string $what): void
{
    global $passed, $failed;
    if ($condition) {
        $passed++;
    } else {
        $failed++;
        echo "FAIL  $what\n";
    }
}

function near(float $got, float $want, float $tol, string $what): void
{
    check(abs($got - $want) <= $tol, sprintf('%s (got %.5g, want %.5g)', $what, $got, $want));
}

function rejects(string $text, string $part): void
{
    try {
        Tank::parse($text);
        check(false, "should reject: $part");
    } catch (TankException $e) {
        check(str_contains($e->getMessage(), $part), "message for '$part' was: " . $e->getMessage());
        check(!str_contains($e->getMessage(), '<'), 'errors never echo the input');
    }
}

function tank(string $extra = '', string $fish = "fish Neon x 10 length 3\n"): Tank
{
    return Tank::parse("volume 60 L\ntemperature 25 C\nph 7.0\n$extra$fish");
}

$dir = dirname(__DIR__);

// ---------- Chemistry ----------
$t = tank();
near($t->freeFraction(), 0.00564, 0.0002, 'free ammonia at 25 °C, pH 7 is about 0.56% (Emerson table)');
$t->ph = 8.0;
near($t->freeFraction(), 0.0538, 0.002, 'and about 5.4% at pH 8: ten times the pH 7 figure, give or take');
$t->celsius = 30;
check($t->freeFraction() > 0.0538, 'warmer water holds more of it as free ammonia');
near(FishGroup::wasteFromLength(3), 0.012 * 27 * 0.02 * 0.45 * 0.16 * 0.5 * 1000, 1e-9, 'waste from length');
check(FishGroup::wasteFromLength(12) > 50 * FishGroup::wasteFromLength(3), 'waste grows with the cube of length');

// ---------- The model ----------
$t = tank();
$empty = Model::run($t, [], 30);
check(end($empty['rows'])['tan'] === 0.0 && end($empty['rows'])['nitrate'] === 0.0, 'no fish, no dosing: nothing appears');

// Mass balance: with no water changes, every milligram of nitrogen put in is still there as
// ammonia, nitrite or nitrate.
$r = Model::run($t, [0 => [0]], 60);
$end = end($r['rows']);
$input = $t->fish[0]->load() / $t->litres * 60;
near($end['tan'] + $end['nitrite'] + $end['nitrate'], $input, 1e-6, 'nitrogen is conserved');
check($end['nitrate'] > 0.9 * $input, 'after two months almost all of it has become nitrate');

// Water changes take nitrogen out.
$wc = Model::run(tank("water-change 50% every 7 days\n"), [0 => [0]], 60);
check(end($wc['rows'])['nitrate'] < 0.5 * $end['nitrate'], 'weekly 50% water changes keep nitrate down');

// A new filter shows the textbook cycle: ammonia rises first, then nitrite, then both fall.
$heavy = tank('', "fish Big x 4 length 12\n");
$r = Model::run($heavy, [0 => [0]], 70);
check($r['peakFreeDay'] < $r['peakNitriteDay'], 'the ammonia peak comes before the nitrite peak');
$last = end($r['rows']);
check($last['tan'] < 0.2 && $last['nitrite'] < 0.2, 'after ten weeks the tank has cycled');

// A seeded filter clears the same load at once.
$seeded = Tank::parse("volume 60 L\ntemperature 25 C\nph 7.0\nfilter seeded 2\nfish Big x 4 length 12\n");
$rs = Model::run($seeded, [0 => [0]], 70);
check($rs['peakFree'] < $r['peakFree'] / 5 && $rs['peakNitrite'] < $r['peakNitrite'] / 5, 'a seeded filter avoids the spikes');

// Cold and acid water slow the bacteria.
$cold = Tank::parse("volume 60 L\ntemperature 15 C\nph 7.0\nfish Big x 4 length 12\n");
check(Model::run($cold, [0 => [0]], 90)['peakNitriteDay'] > $r['peakNitriteDay'], 'a cold tank cycles more slowly');
$acid = Tank::parse("volume 60 L\ntemperature 25 C\nph 6.2\nfish Big x 4 length 12\n");
check(Model::run($acid, [0 => [0]], 90)['peakNitriteDay'] > $r['peakNitriteDay'], 'an acid tank cycles more slowly');

// Too much ammonia holds back the nitrite stage (free ammonia inhibits NOB).
$light = Model::run(tank(), [], 40, 1.0, 40);
$over = Model::run(Tank::parse("volume 60 L\ntemperature 25 C\nph 8.2\nfish Neon x 10 length 3\n"), [], 40, 8.0, 40);
check($over['rows'][20]['nitrite'] > 20 && $over['rows'][20]['nitrite'] > $over['rows'][20]['nitrate'], 'an over-dosed cycle at high pH stalls with nitrite piling up');
check($light['rows'][20]['nitrite'] < 0.5, 'a modest dose has cycled through to nitrate by then');

// ---------- The planner ----------
foreach (['community', 'seeded', 'goldfish'] as $name) {
    $tankX = Tank::parse((string) file_get_contents("$dir/examples/$name.txt"));
    $plan = Planner::plan($tankX);
    check($plan['ok'], "$name: a plan is found");
    check(Model::safe($tankX, $plan['result']), "$name: the plan keeps the fish within the limits");
    $sorted = $plan['days'];
    sort($sorted);
    check($sorted === $plan['days'], "$name: groups go in the order listed");
    check(count($plan['days']) === count($tankX->fish), "$name: every group is placed");
    // Placing any group a day earlier must break the limits (unless it is already on its earliest possible day).
    foreach ($plan['days'] as $g => $day) {
        $prev = $g > 0 ? $plan['days'][$g - 1] : ($plan['cycleDays'] > 0 ? 7 : 0);
        if ($day <= $prev || ($g === 0 && $plan['cycleDays'] > 0)) {
            continue;
        }
        $adds = [];
        foreach ($plan['days'] as $h => $d) {
            if ($h < $g) {
                $adds[$d][] = $h;
            }
        }
        $adds[$day - 1][] = $g;
        $earlier = Model::run($tankX, $adds, $day - 1 + Planner::WATCH, $plan['dose'], $plan['cycleDays']);
        check(!Model::safe($tankX, $earlier), "$name: group $g can't go in a day earlier");
    }
}
$community = Tank::parse((string) file_get_contents("$dir/examples/community.txt"));
$seededT = Tank::parse((string) file_get_contents("$dir/examples/seeded.txt"));
check(!Model::safe($community, Planner::allAtOnce($community)), 'all at once in a new tank is unsafe');
check(max(Planner::plan($seededT)['days']) < max(Planner::plan($community)['days']), 'a seeded filter lets the fish in sooner');
$gold = Planner::plan(Tank::parse((string) file_get_contents("$dir/examples/goldfish.txt")));
check($gold['cycleDays'] >= 14 && $gold['dose'] > 0, 'big fish in a new tank need a fishless cycle first');
$impossible = Planner::plan(Tank::parse("volume 10 L\ntemperature 25 C\nph 8.5\nfish Koi x 5 length 40\n"));
check(!$impossible['ok'], 'an impossible stocking is reported, not hidden');
check(str_contains(Report::render(Tank::parse("volume 10 L\ntemperature 25 C\nph 8.5\nfish Koi x 5 length 40\n"), $impossible, Planner::allAtOnce(Tank::parse("volume 10 L\nfish Koi x 5 length 40\n"))), 'No safe plan'), 'and the report says so');

// ---------- The file ----------
$ok = "volume 60 L\nfish Neon x 10 length 3\n";
rejects('', "needs a 'volume' line");
rejects("volume 60 L\n", "at least one 'fish'");
rejects("volume 1e3 L\n" . "fish A x 1 length 3\n", 'plain number');
rejects("volume -5 L\nfish A x 1 length 3\n", 'plain number');
rejects("volume 3 L\nfish A x 1 length 3\n", 'between 5 and 2000');
rejects("volume 60 gallons\nfish A x 1 length 3\n", "'volume 60 L'");
rejects($ok . "volume 50 L\n", "comes once");
rejects($ok . "ph 12\n", 'between 5.5 and 9');
rejects($ok . "temperature 26\n", "'temperature 26 C'");
rejects($ok . "filter magic\n", "'filter new'");
rejects($ok . "water-change 90% every 7 days\n", 'between 5 and 75');
rejects($ok . "water-change weekly\n", "'water-change 25% every 7 days'");
rejects($ok . "limits free-ammonia 2 nitrite 0.5\n", 'between 0.005 and 0.5');
rejects($ok . "fish Neon tetras\n", "write fish like");
rejects($ok . "fish <b>Neon</b> x 3 length 3\n", 'fish names');
rejects($ok . "fish Neon x 0 length 3\n", '1 to 200');
rejects($ok . "fish Neon x 3 length 99\n", 'between 1 and 60');
rejects($ok . "tank <script>\n", 'tank names');
rejects($ok . "salinity 35\n", 'lines start with');
rejects($ok . "tank A\x1b[2J\n", 'control or hidden');
rejects($ok . "tank A\u{202E}B\n", 'control or hidden');
rejects($ok . "tank A\xff\n", 'not valid UTF-8');
rejects($ok . str_repeat('#', 300) . "\n", 'longer than 200');
rejects(str_repeat("\n", 40000), 'larger than 32 KB');
$many = $ok;
for ($i = 0; $i < 20; $i++) {
    $many .= "fish F$i x 1 length 3\n";
}
rejects($many, 'at most 20 groups');
$parsed = Tank::parse("\u{FEFF}tank Shrimp & snail jar\nvolume 20 L\nfilter seeded 0.5\nfish Cherry shrimp x 20 waste 0.02\n");
check($parsed->name === 'Shrimp & snail jar' && $parsed->seed === 0.5 && $parsed->fish[0]->waste === 0.02, 'a byte-order mark, a seeded filter and a direct waste figure');

// ---------- The command line ----------
function cli(array $args, ?string $stdin = null): array
{
    $out = fopen('php://memory', 'w+');
    $err = fopen('php://memory', 'w+');
    $in = fopen('php://memory', 'w+');
    if ($stdin !== null) {
        fwrite($in, $stdin);
        rewind($in);
    }
    $code = Cli::run($args, $out, $err, $in);
    rewind($out);
    rewind($err);
    return [$code, stream_get_contents($out), stream_get_contents($err)];
}
[$code, $out] = cli(["$dir/examples/community.txt"]);
check($code === 0 && str_contains($out, 'AMMONITE  River community') && str_contains($out, 'Plan:'), 'the example runs');
[$code2, $out2] = cli(['-'], (string) file_get_contents("$dir/examples/community.txt"));
check($code2 === 0 && $out2 === $out, 'standard input gives the same plan');
check(cli([])[0] === 2 && cli(['--help'])[0] === 2 && cli(['a', 'b'])[0] === 2, 'usage errors exit 2');
[$c3, , $e3] = cli([$dir . '/examples']);
check($c3 === 2 && str_contains($e3, 'could not be read'), 'a folder is refused');
[$c4, , $e4] = cli(['secret-name-zz.txt']);
check($c4 === 2 && !str_contains($e4, 'secret-name'), "errors don't echo the path");
[$c5, , $e5] = cli(['-'], str_repeat('#', 100000));
check($c5 === 2 && str_contains($e5, '32 KB'), 'big input is cut off');
[$c6, , $e6] = cli(["x\0y"]);
check($c6 === 2, 'a path with a NUL byte is refused');

echo "$passed passed, $failed failed\n";
exit($failed === 0 ? 0 : 1);
