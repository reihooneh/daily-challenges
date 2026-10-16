<?php

declare(strict_types=1);

// A tiny test runner, so the project needs nothing beyond PHP itself.
// Run with:  php tests/run.php

use Spoilheap\Cli;
use Spoilheap\Dating;
use Spoilheap\Matrix;
use Spoilheap\Record;
use Spoilheap\RecordException;
use Spoilheap\Report;

foreach (['Record', 'Matrix', 'Dating', 'Report', 'Cli'] as $file) {
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

function rejects(string $text, string $expectedPart): void
{
    try {
        Record::parse($text);
        check(false, 'should reject: ' . substr(json_encode($text, JSON_INVALID_UTF8_SUBSTITUTE), 0, 40));
    } catch (RecordException $e) {
        check(str_contains($e->getMessage(), $expectedPart), 'message for ' . substr(json_encode($text, JSON_INVALID_UTF8_SUBSTITUTE), 0, 40) . ' was: ' . $e->getMessage());
    }
}

/** @return array{Matrix, Dating} */
function analyse(string $text): array
{
    $m = new Matrix(Record::parse($text));
    return [$m, new Dating($m)];
}

/** @return array{int, string, string} */
function cli(array $args, string $stdin = ''): array
{
    $out = fopen('php://memory', 'w+');
    $err = fopen('php://memory', 'w+');
    $in = fopen('php://memory', 'w+');
    fwrite($in, $stdin);
    rewind($in);
    $code = Cli::run($args, $out, $err, $in);
    rewind($out);
    rewind($err);
    return [$code, stream_get_contents($out), stream_get_contents($err)];
}

$examples = __DIR__ . '/../examples';

// ---------- 1. Reading the record ----------
$r = Record::parse("site Test pit\n1 above 2\n3 below 2   # comment\n4 same 1\nfind 2 1850 clay pipe\nbefore 1 1900 floor\ndate 3 -50 30 Roman coin\n");
check($r->site === 'Test pit', 'site name');
check(count($r->contexts) === 4, 'four contexts');
check($r->relations[1]['later'] === '2' && $r->relations[1]['earlier'] === '3', '"below" is reversed');
check($r->clues[2]['from'] === -50 && $r->clues[2]['to'] === 30, 'BCE years are negative');
foreach (['cuts', 'fills', 'seals', 'over'] as $verb) {
    check(Record::parse("a $verb b\n")->relations[0]['later'] === 'a', "$verb means later");
}

rejects('', 'no contexts');
rejects("# only a comment\n", 'no contexts');
rejects("1 above 1\n", 'itself');
rejects("1 beside 2\n", 'unknown relation');
rejects("1 above\n", 'expected');
rejects("../etc above 2\n", 'context names');
rejects("<b> above 2\n", 'context names');
rejects(str_repeat('x', 17) . " above 2\n", 'context names');
rejects("find 1 18x0 pipe\n", 'whole numbers');
rejects("find 1 99999 pipe\n", 'between');
rejects("date 1 1800 1700 coin\n", 'ends before');
rejects("find 1 1800\n", 'expected');
rejects("find 1 1800 <script>\n", 'notes');
rejects("1 above 2\x1b[31m\n", 'control');
rejects("1 above 2 \u{202E}\n", 'hidden direction');
rejects("1 above 2\n" . str_repeat('#', 300) . "\n", 'longer than');
rejects(str_repeat("1 above 2\n", 7000), 'larger than 64 KB');
rejects("1 above 2\n\xff\xfe\n", 'UTF-8');
$many = '';
for ($i = 0; $i < 501; $i++) {
    $many .= "c$i above d$i\n";
}
rejects($many, 'more than 500 contexts');
check(Record::parse("find 1 1800 Ἀθῆναι pottery, \"stamped\" (rim)\n")->clues[0]['note'] !== '', 'notes in other scripts are fine');

// ---------- 2. The sequence ----------
[$m] = analyse("1 above 2\n2 above 3\n1 above 3\n");
check($m->cycles === [] && count($m->redundant) === 1 && $m->edges[$m->redundant[0]]['line'] === 3, 'implied relation is flagged redundant');
check($m->phase[$m->group['1']] === 3 && $m->phase[$m->group['3']] === 1, 'phases count up from the bottom');

[$m] = analyse("1 above 2\n2 above 3\n3 above 1\n");
check(count($m->cycles) === 1 && count($m->cycles[0]['drop']) === 1 && $m->cycles[0]['exact'], 'a simple loop needs one relation re-checked');

[$m] = analyse("a above b\nb above a\nc above d\nd above e\ne above c\n");
check(count($m->cycles) === 2, 'two separate loops are reported separately');

// Two loops sharing one relation: dropping the shared one fixes both.
[$m] = analyse("a above b\nb above c\nc above a\nb above d\nd above a\n");
$dropped = $m->cycles[0]['drop'];
check(count($dropped) === 1 && $m->edges[$dropped[0]]['later'] === $m->group['a'], 'shared relation is the single fix');

[$m] = analyse("1 above 2\n1 same 2\n");
check(count($m->selfContradictions) === 1, 'above and same at once is caught');

[$m] = analyse("1 above 2\n3 above 4\n2 same 3\n");
check($m->phase[$m->group['1']] === 3, '"same" joins two sequences into one');

// The dates decide which relation in a loop is the odd one out.
[$m] = analyse("top above mid\nmid above low\nlow above top\nfind top 1900 bottle\nbefore mid 1850 sealed\n");
$e = $m->edges[$m->cycles[0]['drop'][0]];
// Dropping "top above mid" would put the 1900 bottle under the 1850 seal; either other choice
// agrees with the dates, and the tie goes to the relation written last.
check(!($e['later'] === $m->group['top'] && $e['earlier'] === $m->group['mid']) && $e['line'] === 3, 'dating evidence picks the relation to question: ' . json_encode($e));

// Large loops fall back to a method that always works.
$big = '';
for ($i = 0; $i < 60; $i++) {
    $big .= "n$i above n" . (($i + 1) % 60) . "\n";
    $big .= "n$i above n" . (($i + 7) % 60) . "\n";
}
$t = microtime(true);
[$m, $d] = analyse($big);
check(count($m->cycles) === 1 && $m->cycles[0]['drop'] !== [], 'big tangle still gets a fix');
check(microtime(true) - $t < 10, 'big tangle is handled quickly');
// Whatever was dropped, what is left must be a valid order.
check(count($m->topological($m->keptEdges())) === count($m->members), 'kept relations have no loops');

// ---------- 3. Dating ----------
[$m, $d] = analyse("1 above 2\n2 above 3\nfind 3 1700 sherd\nbefore 1 1800 map\n");
check($d->window[$m->group['2']] === ['from' => 1700, 'fromClue' => 0, 'to' => 1800, 'toClue' => 1], 'window from clues above and below');
check($d->window[$m->group['3']]['to'] === 1800 && $d->window[$m->group['1']]['from'] === 1700, 'bounds travel the whole sequence');
check($d->conflicts === [], 'consistent clues');

[$m, $d] = analyse("1 above 2\nfind 2 1900 bottle\nbefore 1 1850 sealed\n");
check(count($d->conflicts) === 1 && count($d->question) === 1, 'late find under an early seal conflicts');

// A residual (old) find in a later layer is normal and is not a problem.
[$m, $d] = analyse("1 above 2\nfind 1 1200 old sherd\nfind 2 1600 pipe\n");
check($d->conflicts === [] && $d->window[$m->group['1']]['from'] === 1600, 'residual finds are fine; the latest find wins');

// One wrong find against several dates: questioning just that find is the minimum.
[$m, $d] = analyse("a above b\nb above c\nc above x\nfind x 1950 plastic\nbefore a 1800 x\nbefore b 1790 y\nbefore c 1780 z\n");
check(count($d->question) === 1 && $d->question[0]['side'] === 'low', 'one intrusive find explains three conflicts');

// König's cover matches brute force on random cases.
mt_srand(16);
$ok = true;
for ($trial = 0; $trial < 60 && $ok; $trial++) {
    $text = '';
    $n = mt_rand(3, 7);
    for ($i = 1; $i < $n; $i++) {
        $text .= 'L' . mt_rand($i + 1, $n) . " above L$i\n";
    }
    for ($c = 0; $c < mt_rand(2, 7); $c++) {
        $ctx = 'L' . mt_rand(1, $n);
        $text .= mt_rand(0, 1) ? "find $ctx " . mt_rand(1700, 1900) . " f\n" : "before $ctx " . mt_rand(1700, 1900) . " b\n";
    }
    [$m, $d] = analyse($text);
    $bounds = [];
    foreach ($d->conflicts as $c) {
        $bounds['low' . $c['low']] = true;
        $bounds['high' . $c['high']] = true;
    }
    $bounds = array_keys($bounds);
    $best = count($bounds);
    for ($mask = 0; $mask < (1 << count($bounds)); $mask++) {
        $pick = [];
        foreach ($bounds as $k => $b) {
            if ($mask & (1 << $k)) {
                $pick[$b] = true;
            }
        }
        $covers = true;
        foreach ($d->conflicts as $c) {
            if (!isset($pick['low' . $c['low']]) && !isset($pick['high' . $c['high']])) {
                $covers = false;
                break;
            }
        }
        if ($covers) {
            $best = min($best, count($pick));
        }
    }
    $ok = count($d->question) === $best;
    // After questioning, no deposit should have an impossible window.
    foreach ($d->repaired as $w) {
        if ($w['from'] !== null && $w['to'] !== null && $w['from'] > $w['to']) {
            $ok = false;
        }
    }
}
check($ok, "minimum cover equals brute force (trial $trial)");

// ---------- 4. Report and formats ----------
check(Report::year(-50) === '50 BCE' && Report::year(1850) === '1850', 'year formatting');
check(Report::window(null, null) === 'undated' && Report::window(1700, null) === 'after 1700' && Report::window(null, 5) === 'before 5', 'window wording');
[$m, $d] = analyse(file_get_contents("$examples/hollow-lane.txt"));
$text = Report::render($m, $d, 'x');
check(str_contains($text, 'consistent') && str_contains($text, 'Phase 3  1007=1010  1750 to 1790'), 'example report');
$dot = Report::dot($m);
check(str_starts_with($dot, 'digraph') && !str_contains($dot, '"g1001" -> "g1003"'), 'DOT leaves out redundant relations');

// ---------- 5. Command line ----------
[$code, $out] = cli(["$examples/hollow-lane.txt"]);
check($code === 0 && str_contains($out, 'SPOILHEAP  hollow-lane.txt'), 'clean record exits 0');
[$code, $out] = cli(["$examples/tangled.txt"]);
check($code === 1 && str_contains($out, 'line 24   1009 above 1006') && str_contains($out, 'machine-made nail in 1007: the find may be intrusive'), 'tangled record exits 1 with the right fixes');
[$code, $out] = cli(['-'], "1 above 2\n");
check($code === 0 && str_contains($out, 'standard input'), 'reads standard input');
[$code, , $err] = cli(['/dev/zero']);
check($code === 2 && str_contains($err, 'regular file'), 'devices are refused');
[$code, , $err] = cli(['/no/such/file']);
check($code === 2, 'missing file exits 2');
[$code, , $err] = cli(['-'], "1 above 2\n\x1b]0;pwned\x07\n");
check($code === 2 && !str_contains($err, 'pwned'), 'errors never echo the input');
[$code] = cli(['a', 'b']);
check($code === 2, 'two files are refused');
[$code] = cli(['--rm-rf']);
check($code === 2, 'unknown option is refused');
[$code, $out] = cli(['--help']);
check($code === 0 && str_contains($out, 'Usage'), 'help');
[$code, $out] = cli(["$examples/tangled.txt", '--dot']);
check(str_contains($out, 'color=red') && str_contains($out, 'check line 24'), 'DOT marks the relation to re-check');
$tmp = sys_get_temp_dir() . "/sp\x1b[31mheap-" . getmypid() . '.txt';
file_put_contents($tmp, "1 above 2\n");
[, $out] = cli([$tmp]);
unlink($tmp);
check(!str_contains($out, "\x1b"), 'file names are cleaned before printing');

echo "\n$passed passed, $failed failed\n";
exit($failed ? 1 : 0);
