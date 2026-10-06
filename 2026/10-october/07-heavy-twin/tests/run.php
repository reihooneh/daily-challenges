<?php

declare(strict_types=1);

// A tiny test runner, so the project needs nothing beyond PHP itself.
// Run with:  php tests/run.php

use HeavyTwin\Cli;
use HeavyTwin\Elements;
use HeavyTwin\Formula;
use HeavyTwin\FormulaException;
use HeavyTwin\Pattern;
use HeavyTwin\Reader;

foreach (['Elements', 'Formula', 'Pattern', 'Reader', 'Cli'] as $file) {
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

function near(float $actual, float $expected, float $tolerance, string $what): void
{
    check(abs($actual - $expected) <= $tolerance, "$what: expected $expected, got $actual");
}

function rejects(string $formula, string $expectedPart): void
{
    try {
        Formula::parse($formula);
        check(false, 'should reject: ' . substr($formula, 0, 30));
    } catch (FormulaException $e) {
        check(str_contains($e->getMessage(), $expectedPart), 'message for ' . substr($formula, 0, 30) . ' was: ' . $e->getMessage());
    }
}

/** @return array{int, string, string} exit code, stdout, stderr */
function cli(string ...$args): array
{
    $out = fopen('php://memory', 'w+');
    $err = fopen('php://memory', 'w+');
    $code = Cli::run(array_values($args), $out, $err);
    rewind($out);
    rewind($err);
    return [$code, stream_get_contents($out), stream_get_contents($err)];
}

// ---- the isotope table ----------------------------------------------------------

foreach (Elements::ISOTOPES as $symbol => $isotopes) {
    near(array_sum(array_column($isotopes, 2)), 1.0, 1e-4, "$symbol abundances add up to 1");
    // Selenium's official weight was revised and sits 0.012 from the isotope average.
    near(Elements::averageMass($symbol), Elements::STANDARD_WEIGHTS[$symbol], $symbol === 'Se' ? 0.02 : 0.005, "$symbol matches the periodic table");
    $previous = 0;
    foreach ($isotopes as [$massNumber, $mass]) {
        check($massNumber > $previous, "$symbol isotopes are listed lightest first");
        near($mass, (float) $massNumber, 0.1, "$symbol-$massNumber exact mass is close to its mass number");
        $previous = $massNumber;
    }
}
check(count(Elements::ISOTOPES) === count(Elements::STANDARD_WEIGHTS), 'every element has a reference weight');

// ---- parsing --------------------------------------------------------------------

check(Formula::parse('H2O') === ['H' => 2, 'O' => 1], 'water');
check(Formula::parse('C8H10N4O2') === ['C' => 8, 'H' => 10, 'N' => 4, 'O' => 2], 'caffeine');
check(Formula::parse('Ca(OH)2') === ['Ca' => 1, 'O' => 2, 'H' => 2], 'brackets with a multiplier');
check(Formula::parse('K4[Fe(CN)6]') === ['K' => 4, 'Fe' => 1, 'C' => 6, 'N' => 6], 'nested brackets');
check(Formula::parse('CuSO4.5H2O') === ['Cu' => 1, 'S' => 1, 'O' => 9, 'H' => 10], 'a hydrate');
check(Formula::parse("CuSO4\u{00B7}5H2O") === Formula::parse('CuSO4.5H2O'), 'a pasted middle dot');
check(Formula::parse(' C2 H5 OH ') === ['C' => 2, 'H' => 6, 'O' => 1], 'spaces and repeated elements');
check(Formula::parse('CH3(CH2)4CH3') === ['C' => 6, 'H' => 14], 'a condensed structural formula');
check(Formula::parse('((((H))))') === ['H' => 1], 'deep but legal nesting');
check(Formula::parse('CO') === ['C' => 1, 'O' => 1], 'CO is carbon monoxide, not cobalt');
check(Formula::parse('Cl2') === ['Cl' => 2], 'two-letter symbols');

rejects('', 'empty');
rejects('   ', 'empty');
rejects('h2o', 'expected an element symbol at position 1');
rejects('H2O)', 'unexpected character at position 4');
rejects('(H2O', 'never closed');
rejects('(H2O]', 'never closed');
rejects('()', 'expected an element symbol');
rejects('2H2O', 'expected an element symbol at position 1');
rejects('H0', 'counts must be');
rejects('H12345', 'counts must be');
rejects('Xx2', 'unknown or unsupported element "Xx"');
rejects('Uue', 'unknown or unsupported element');
rejects('H2O.', 'expected an element symbol');
rejects('H2O..H2O', 'expected an element symbol');
rejects('C9999H9999', 'more than 10000 atoms');
rejects('(C9999)9999', 'more than 10000 atoms');
rejects(str_repeat('(', 11) . 'H' . str_repeat(')', 11), 'nested more than 10 deep');
rejects(str_repeat('C', 201), 'longer than 200');

// Hostile text: rejected by the character allow-list, and never echoed back.
foreach (['<script>alert(1)</script>', 'H2O; rm -rf ~', '$(id)', '`id`', '../../etc/passwd', "H2O\n", "H\0O", "\e[2JH2O",
    'H2O%s%n', 'C{6}', 'H₂O', 'Ｈ2O', "H2O' OR '1'='1", 'C-C', 'H+'] as $attack) {
    try {
        Formula::parse($attack);
        check(false, 'accepted hostile input');
    } catch (FormulaException $e) {
        check($e->getMessage() === 'a formula may only contain letters, digits, brackets and a dot', 'hostile input gets the generic message');
    }
}

// ---- masses against published values --------------------------------------------

$mono = static fn (string $f): float => Pattern::monoisotopicMass(Formula::parse($f));
$avg = static fn (string $f): float => Pattern::averageMass(Formula::parse($f));
near($mono('H2O'), 18.010565, 1e-5, 'water monoisotopic');
near($mono('C8H10N4O2'), 194.080376, 1e-5, 'caffeine monoisotopic');
near($mono('C6H12O6'), 180.063388, 1e-5, 'glucose monoisotopic');
near($mono('C9H8O4'), 180.042259, 1e-5, 'aspirin monoisotopic');
near($mono('NaCl'), 57.958622, 1e-5, 'salt monoisotopic');
near($avg('H2O'), 18.015, 0.002, 'water average');
near($avg('C8H10N4O2'), 194.19, 0.01, 'caffeine average');
near($avg('NaCl'), 58.44, 0.01, 'salt average');
near($avg('CuSO4.5H2O'), 249.68, 0.02, 'copper sulfate pentahydrate average');

// ---- isotope patterns -----------------------------------------------------------

$heights = static fn (string $f): array => array_map(static fn (array $peak): float => $peak[0], Pattern::relative(Formula::parse($f), 0.01));

foreach (['H2O', 'C8H10N4O2', 'CH2Cl2', 'K4[Fe(CN)6]', 'C60', 'C254H377N65O75S6', 'Se3'] as $formula) {
    near(array_sum(array_column(Pattern::distribution(Formula::parse($formula)), 0)), 1.0, 1e-6, "$formula probabilities add up to 1");
}
near($heights('NaCl')[2], 100 * 0.2424 / 0.7576, 0.01, 'one chlorine: M+2 is 32% of M');
near($heights('C6H5Br')[2], 97.5, 0.3, 'one bromine: M+2 nearly equals M');
// Two chlorines follow the binomial 9 : 6 : 1 (as 0.7576^2 : 2ab : 0.2424^2).
near($heights('Cl2')[2], 100 * 2 * 0.2424 / 0.7576, 0.01, 'Cl2 M+2');
near($heights('Cl2')[4], 100 * (0.2424 / 0.7576) ** 2, 0.01, 'Cl2 M+4');
near($heights('Br2')[0], 51.4, 0.1, 'Br2: the middle peak is the tallest, so M is about half of it');
near($heights('Br2')[2], 100.0, 1e-9, 'Br2 M+2 is the tallest peak');
near($heights('C60')[1], 64.9, 0.2, 'buckminsterfullerene M+1 (60 carbons)');
near($heights('C8H10N4O2')[1], 10.3, 0.2, 'caffeine M+1');
check(array_key_first($heights('K4[Fe(CN)6]')) === -2, 'iron-54 puts a peak two units BELOW M');
check(max(Pattern::relative(Formula::parse('Br2'))[2][0], 100.0) === 100.0, 'the tallest peak is scaled to exactly 100');

// Each peak's mass is the true mass of that isotope mix, not M plus a guess.
$bromobenzene = Pattern::relative(Formula::parse('C6H5Br'));
near($bromobenzene[0][1], 155.95746, 1e-4, 'bromobenzene M mass');
near($bromobenzene[2][1], 157.9554, 2e-4, 'bromobenzene M+2 is the bromine-81 mass');

// Repeated squaring must agree with doing it the slow way.
$slow = [0 => [1.0, 0.0]];
for ($i = 0; $i < 37; $i++) {
    $slow = Pattern::convolve($slow, Pattern::single('S'));
}
$fast = Pattern::power(Pattern::single('S'), 37);
$same = true;
foreach ($slow as $offset => [$p, $m]) {
    if ($p > 1e-8) { // tiny peaks may be pruned at different moments
        $same = $same && isset($fast[$offset]) && abs($fast[$offset][0] - $p) < 1e-9 && abs($fast[$offset][1] - $m) < 1e-6;
    }
}
check($same, 'fast exponentiation matches repeated convolution');

$notes = implode(' ', Pattern::explain(Formula::parse('C6H5Br')));
check(str_contains($notes, 'bromine-81') && str_contains($notes, '6 carbons'), 'the explanation names bromine and counts carbons');
check(str_contains(implode(' ', Pattern::explain(Formula::parse('NaF'))), 'stands almost alone'), 'single-isotope elements are explained too');

// ---- reading a pattern backwards ------------------------------------------------

$read = static fn (float $m1, float $m2): string => implode(' ', Reader::read($m1, $m2));
check(str_contains($read(6.5, 97.5), 'one bromine') && str_contains($read(6.5, 97.5), 'about 6 carbon'), 'bromobenzene is read back');
check(str_contains($read(1.1, 64.0), 'two chlorine'), 'dichloromethane is read back');
check(str_contains($read(7.6, 32.0), 'one chlorine') && str_contains($read(7.6, 32.0), 'about 7 carbon'), 'chlorotoluene is read back');
check(str_contains($read(8.9, 4.9), '1 sulfur'), 'a sulfur compound is read back');
check(str_contains($read(10.3, 0.9), 'no chlorine, bromine or sulfur') || str_contains($read(10.3, 0.9), 'oxygen'), 'caffeine has no halogens');
check(str_contains($read(0.0, 0.0), 'few or no carbon'), 'an empty pattern');
// Round trip: predict a pattern, then read it; the carbon count must come back.
foreach (['C4H10' => 4, 'C10H22' => 10, 'C20H42' => 20] as $formula => $carbons) {
    $h = $heights($formula);
    check(str_contains($read($h[1], $h[2] ?? 0.0), "about $carbons carbon"), "$formula carbon count survives the round trip");
}
foreach ([[-1.0, 5.0], [5.0, 1001.0], [NAN, 1.0], [INF, 1.0]] as [$a, $b]) {
    try {
        Reader::read($a, $b);
        check(false, 'accepted an impossible peak height');
    } catch (FormulaException) {
        check(true, 'impossible peak heights are rejected');
    }
}

// ---- command line ---------------------------------------------------------------

[$code, $out, $err] = cli('C6H5Br');
check($code === 0 && $err === '' && str_contains($out, 'Monoisotopic mass:  155.95746') && str_contains($out, 'M+2    157.9554    97.5'), 'report for bromobenzene');
[$code, $out] = cli('C6H12O6', '--charge', '+1');
check($code === 0 && str_contains($out, 'm/z at charge +1:   180.06284'), 'a positive ion is lighter by one electron');
[$code, $out] = cli('C6H12O6', '--charge', '-2');
check($code === 0 && str_contains($out, 'm/z at charge -2:   90.03224'), 'a doubly charged negative ion');
[$code, $out] = cli('--read', '6.5', '97.5');
check($code === 0 && str_contains($out, 'one bromine'), '--read');
[$code, $out] = cli('--elements');
check($code === 0 && str_contains($out, 'Br') && str_contains($out, 'Se'), '--elements');
check(cli('--help')[0] === 0 && cli()[0] === 2, 'help exits 0, no arguments exits 2');

foreach ([['H2O', 'extra'], ['H2O', '--charge', '0'], ['H2O', '--charge', '99'], ['H2O', '--charge', 'x'], ['H2O', '--bogus', '1'],
    ['--read'], ['--read', '5'], ['--read', 'abc', '1'], ['--read', '1e3', '1'], ['--read', '-5', '1'], ['--read', '5', '99999'],
    ['<img src=x onerror=alert(1)>'], ["\e]0;owned\x07"], ['--read', '5', '1; rm -rf ~']] as $args) {
    [$code, $out, $err] = cli(...$args);
    check($code === 2 && $out === '' && str_starts_with($err, 'heavytwin: ') && substr_count($err, "\n") === 1, 'bad usage gives one clean line: ' . json_encode($args));
    check(!preg_match('/owned|img|onerror|rm -rf|\e|\x07/', $err), 'and does not echo the input');
}

// The real program, started without a shell.
$process = proc_open([PHP_BINARY, __DIR__ . '/../bin/heavytwin', 'CH2Cl2'], [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
$stdout = stream_get_contents($pipes[1]);
check(proc_close($process) === 0 && str_contains($stdout, 'M+4') && str_contains($stdout, '2 chlorine atoms'), 'bin/heavytwin runs end to end');

// ---- limits ---------------------------------------------------------------------

$started = microtime(true);
Pattern::relative(Formula::parse('C4000H5000Se999'));
Pattern::relative(Formula::parse('(Ca9Zn9Fe9Se9S9Mg9K9Cl9Br9Si9)99'));
check(microtime(true) - $started < 5.0, 'the largest formulas finish quickly');
$started = microtime(true);
$huge = Pattern::distribution(Formula::parse('Se9999'));
near(array_sum(array_column($huge, 0)), 1.0, 1e-6, 'the worst-case formula still adds up to 1');
check(count($huge) < 5000 && microtime(true) - $started < 20.0, 'and its peaks and running time stay bounded');

echo "$passed passed, $failed failed\n";
exit($failed === 0 ? 0 : 1);
