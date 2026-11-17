<?php

declare(strict_types=1);

// Tests for Catchbreath: php tests/run.php
foreach (['Song', 'Planner', 'Report', 'Cli'] as $file) {
    require_once __DIR__ . "/../src/$file.php";
}

use Catchbreath\Cli;
use Catchbreath\Planner;
use Catchbreath\Song;
use Catchbreath\SongError;

$checks = 0;
$failed = 0;
function check(bool $ok, string $what): void
{
    global $checks, $failed;
    ++$checks;
    if (!$ok) {
        ++$failed;
        echo "  FAIL: $what\n";
    }
}
function error_of(string $text): string
{
    try {
        Song::parse($text);
        return '';
    } catch (SongError $e) {
        return $e->getMessage();
    }
}
function cli(array $args, string $stdin = ''): array
{
    $in = fopen('php://memory', 'r+');
    fwrite($in, $stdin);
    rewind($in);
    $out = fopen('php://memory', 'r+');
    $err = fopen('php://memory', 'r+');
    $code = Cli::run($args, $in, $out, $err);
    rewind($out);
    rewind($err);
    return [$code, stream_get_contents($out), stream_get_contents($err)];
}

echo "reading songs\n";
$s = Song::parse("title: Test\ntempo: 120\nbreath: 5\ncatch: 0.25\n# a comment\nA-:1 ma-:1 zing:2 _:1\ngrace,:2 how:1.5\n");
check($s->title === 'Test' && $s->tempo === 120.0 && $s->breath === 5.0 && $s->catch === 0.25, 'settings');
check(count($s->notes) === 6, 'six notes');
check($s->notes[0]['joins'] && $s->notes[1]['joins'] && !$s->notes[2]['joins'], 'syllables join into a word');
check($s->notes[3]['rest'] && $s->notes[3]['lineEnd'] && $s->notes[5]['lineEnd'], 'rests and line ends');
check(abs($s->seconds(3) - 1.5) < 1e-12, 'beats to seconds');
check(Song::parse("grace:2\n")->notes[0]['text'] === 'grace', 'a one-note line is a note, not a setting');

echo "refusing bad songs\n";
check(str_contains(error_of("a:1\0"), 'NUL'), 'NUL byte');
check(str_contains(error_of(str_repeat('x', Song::MAX_BYTES + 1)), '64 KB'), 'too large');
check(str_contains(error_of("a:1 \xff\xfe:1"), 'UTF-8'), 'invalid UTF-8');
check(str_contains(error_of("# nothing\n"), 'no notes'), 'no notes');
check(str_contains(error_of('grace'), "can't read"), 'no beats');
check(str_contains(error_of('grace:0'), 'more than 0'), 'zero beats');
check(str_contains(error_of('grace:33'), 'at most 32'), 'too many beats');
check(str_contains(error_of('grace:1e5'), "can't read"), 'exponent');
check(str_contains(error_of('a-:1 _:1 b:1'), 'rest in the middle of a word'), 'rest inside a word');
check(str_contains(error_of('a-:1'), 'middle of a word'), 'ends inside a word');
check(str_contains(error_of("tempo: 2000\na:1"), 'between 20 and 300'), 'tempo range');
check(str_contains(error_of("breath: lots\na:1"), 'must be a number'), 'breath not a number');
check(str_contains(error_of(str_repeat('a:1 ', Song::MAX_NOTES + 1)), 'more than 5000'), 'too many notes');
$e = error_of("frob\x1b[31m\x07nicate");
check(str_contains($e, 'frob?[31m?nicate') && !preg_match('/[\x00-\x1f]/', $e), 'control characters are not echoed');

echo "what each breath costs\n";
$song = Song::parse("A-:1 ma-:1 zing:1 grace!:2 how:1 sweet:1 the:1 sound,:2 _:1 I:0.25 once:1 was:1 lost:2\n");
$p = new Planner($song);
check($p->gapCost(0) === null && $p->gapCost(1) === null, 'never inside a word');
check($p->gapCost(3) === 2.0, 'after "grace!" (1 + 1 per breath)');
check($p->gapCost(4) === 6.0, 'between ordinary words');
check($p->gapCost(6) === 13.0, 'after "the"');
check($p->gapCost(7) === 0.0 && $p->gapCost(8) === 0.0, 'in a rest');
check($p->gapCost(9) === 21.0, 'a breath that would eat a short note ("I" is also a function word)');
check($p->gapCost(12) === 0.0, 'the end of the song');
check(Planner::word($song->notes, 2) === 'amazing', 'whole words from syllables');

echo "plans against brute force\n";
mt_srand(7);
$words = ['sing', 'the', 'morning', 'light,', 'and', 'of', 'river', 'home.', 'gold', 'a', 'sweet;'];
$worse = 0;
for ($trial = 0; $trial < 300; ++$trial) {
    $tokens = [];
    $n = mt_rand(3, 11);
    for ($k = 0; $k < $n; ++$k) {
        $roll = mt_rand(0, 9);
        $beats = [0.25, 0.5, 1, 1.5, 2, 3][mt_rand(0, 5)];
        if ($roll === 0 && $k > 0 && !str_ends_with(end($tokens) ?: '', '-:1')) {
            $tokens[] = "_:$beats";
        } elseif ($roll === 1 && $k < $n - 1) {
            $tokens[] = 'syl-:1';
        } else {
            $tokens[] = $words[mt_rand(0, count($words) - 1)] . ":$beats";
        }
    }
    $text = "tempo: 60\nbreath: " . mt_rand(2, 6) . "\n" . implode(' ', $tokens) . "\n";
    try {
        $song = Song::parse($text);
    } catch (SongError) {
        continue;
    }
    $planner = new Planner($song);
    $plan = $planner->plan();
    $notes = $song->notes;
    $count = count($notes);
    // Every way to breathe after some of the allowed gaps (the end always).
    $gaps = [];
    for ($g = 0; $g < $count - 1; ++$g) {
        if ($planner->gapCost($g) !== null) {
            $gaps[] = $g;
        }
    }
    $best = INF;
    for ($mask = 0; $mask < (1 << count($gaps)); ++$mask) {
        $chosen = [];
        foreach ($gaps as $b => $g) {
            if ($mask & (1 << $b)) {
                $chosen[] = $g;
            }
        }
        $chosen[] = $count - 1;
        $cost = 0.0;
        $start = 0;
        $ok = true;
        foreach ($chosen as $end) {
            $sung = array_filter(range($start, $end), fn ($k) => !$notes[$k]['rest']);
            if ($sung === []) {
                $ok = false;
                break;
            }
            $a = min($sung);
            $z = max($sung);
            $beats = 0.0;
            for ($k = $a; $k <= $z; ++$k) {
                $beats += $notes[$k]['beats'];
            }
            $cost += $planner->phraseCost($song->seconds($beats)) + $planner->gapCost($end);
            $start = $end + 1;
        }
        if ($ok) {
            $best = min($best, $cost);
        }
    }
    if (abs($best - $plan['cost']) > 1e-6) {
        ++$worse;
        if ($worse === 1) {
            echo "  first mismatch: $text  dp {$plan['cost']} brute $best\n";
        }
    }
    foreach ($plan['breaths'] as $b) {
        check($planner->gapCost($b) !== null, 'a breath inside a word');
    }
}
check($worse === 0, "$worse of 300 plans differ from brute force");

echo "examples\n";
[$code, $out] = cli([__DIR__ . '/../examples/amazing-grace.txt']);
check($code === 0, 'amazing grace fits');
check(str_contains($out, "Amazing grace! \u{2019} how sweet the sound \u{2019}"), 'breathes after "grace!" and at the line end');
check(!preg_match("/\u{2019} \u{2019}/u", $out), 'no doubled breath marks');
[$code, $out] = cli([__DIR__ . '/../examples/held-note.txt']);
check($code === 3 && str_contains($out, '"Ah" lasts 14.0 s'), 'a note longer than a breath is flagged');
[$code, $out] = cli([__DIR__ . '/../examples/auld-lang-syne.txt', '--breath', '20']);
check($code === 0 && str_contains($out, '20 s on one breath'), 'override the breath');
check(substr_count($out, "\u{2019}") <= 3, 'a big breath needs few breaths');

echo "command line\n";
[$code] = cli([]);
check($code === 2, 'usage');
[$code] = cli(['a.txt', 'b.txt']);
check($code === 2, 'two files');
[$code, , $err] = cli(['-'], "tempo: 60\nla:2 la:2\n");
check($code === 0, 'standard input');
[$code, , $err] = cli(['-', '--tempo', '9000'], "la:2\n");
check($code === 1 && str_contains($err, 'tempo must be between'), 'override checked');
$dir = sys_get_temp_dir() . '/catchbreath-' . getmypid();
@mkdir($dir);
symlink(__DIR__ . '/../examples/amazing-grace.txt', "$dir/link.txt");
[$code, , $err] = cli(["$dir/link.txt"]);
check($code === 1 && str_contains($err, 'plain file'), 'links refused');
[$code, , $err] = cli([$dir]);
check($code === 1 && str_contains($err, 'plain file'), 'folders refused');
[$code, , $err] = cli(["$dir/none.txt"]);
check($code === 1 && str_contains($err, 'not found'), 'missing file');
unlink("$dir/link.txt");
rmdir($dir);

echo "the biggest song\n";
$big = "tempo: 300\nbreath: 60\n" . trim(str_repeat("la-:0.25 la:0.25 sing,:0.5 home:1\n", Song::MAX_NOTES / 4)) . "\n";
$t = microtime(true);
[$code] = cli(['-'], $big);
$secs = microtime(true) - $t;
check($code === 0 && $secs < 5, sprintf('5000 notes in %.2f s', $secs));

echo "$checks checks, $failed failed\n";
exit($failed ? 1 : 0);
