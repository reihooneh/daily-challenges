#!/usr/bin/perl
# Tests for Downthrow. Run from the project folder:  prove -l t
use strict;
use warnings FATAL => 'all';
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use FindBin ();
use lib "$FindBin::Bin/../lib";
use Downthrow::Parse qw(parse_survey);
use Downthrow::Plane qw(solve fit_plane attitude apparent_dip predict compass);
use Downthrow::Fault ();
use Downthrow::Report qw(analyse render);
use Downthrow::App qw(run read_bounded);

use constant PI => 4 * atan2(1, 1);
sub near { my ($got, $want, $tol, $what) = @_; ok(abs($got - $want) <= $tol, "$what (got $got, want $want)") }

# A seeded generator for synthetic surveys (independent of the one inside Fault.pm).
my $state = 7;
sub rnd { $state = ($state * 69069 + 1) % 4294967296; return ($state + 0.5) / 4294967296 }
sub gauss { return sqrt(-2 * log(rnd())) * cos(2 * PI * rnd()) }

# Points on a bed dipping $dip degrees towards $dir, with an optional vertical fault.
sub survey_text {
    my (%o) = @_;
    my $g = sin($o{dip} * PI / 180) / cos($o{dip} * PI / 180);
    my ($dx, $dy) = (sin($o{dir} * PI / 180), cos($o{dir} * PI / 180));
    my $text = "survey Test\nhorizon top of the test bed\n";
    for my $i (1 .. $o{n}) {
        my ($x, $y) = (1000 + 800 * rnd(), 2000 + 800 * rnd());
        my $z = 50 - $g * (($x - 1400) * $dx + ($y - 2400) * $dy) + $o{noise} * gauss();
        if ($o{throw}) {
            my ($nx, $ny) = (cos($o{trend} * PI / 180), -sin($o{trend} * PI / 180));
            $z -= $o{throw} if ($x - 1400) * $nx + ($y - 2400) * $ny > 0;
        }
        $text .= sprintf("point P%02d %.1f %.1f %.3f\n", $i, $x, $y, $z);
    }
    return $text;
}

subtest 'linear algebra' => sub {
    my $x = solve([ [ 2, 1, 0 ], [ 1, 3, 1 ], [ 0, 1, 4 ] ], [ 3, 5, 5 ]);
    near($x->[$_], 1, 1e-12, "solution $_") for 0 .. 2;
    ok(!defined solve([ [ 1, 2 ], [ 2, 4 ] ], [ 1, 2 ]), 'singular systems are reported');
};

subtest 'attitude of a plane' => sub {
    # The textbook three-point problem: z falls 50 m over 100 m northwards.
    my $fit = fit_plane([ { x => 0, y => 0, z => 100 }, { x => 100, y => 0, z => 100 }, { x => 0, y => 100, z => 50 } ]);
    my $a = attitude($fit->{b}, $fit->{c});
    near($a->{dip}, atan2(0.5, 1) * 180 / PI, 1e-9, 'dip is atan(0.5)');
    near($a->{dipdir}, 0, 1e-9, 'dips north');
    near($a->{strike}, 270, 1e-9, 'strike by the right-hand rule');
    is($fit->{df}, 0, 'three points leave nothing over');

    my $text = survey_text(n => 12, dip => 30, dir => 120, noise => 0);
    my $f = fit_plane(parse_survey($text)->{points});
    my $b = attitude($f->{b}, $f->{c});
    near($b->{dip}, 30, 0.01, 'recovers a 30° dip');
    near($b->{dipdir}, 120, 0.01, 'towards 120°');
    near($b->{strike}, 30, 0.01, 'strike 030°');
    near(apparent_dip(30, 120, 120), 30, 1e-9, 'apparent dip along the dip direction is the true dip');
    near(apparent_dip(30, 120, 30), 0, 1e-9, 'and zero along strike');
    near(apparent_dip(30, 120, 300), -30, 1e-9, 'and rises the other way');
    is(compass(0), 'N', 'compass N');
    is(compass(250), 'WSW', 'compass WSW');
    is(compass(359), 'N', 'compass wraps');
};

subtest 'big map coordinates are handled' => sub {
    my $pts = [ map { { x => 6_300_000 + $_->[0], y => 5_800_000 + $_->[1], z => 10 + 0.1 * $_->[0] } } ([0, 0], [100, 0], [0, 100], [100, 100], [50, 30]) ];
    my $f = fit_plane($pts);
    near($f->{b}, 0.1, 1e-9, 'slope east');
    near($f->{c}, 0, 1e-9, 'no slope north');
};

subtest 'predictions are less certain far from the data' => sub {
    my $s = parse_survey(survey_text(n => 15, dip => 10, dir => 200, noise => 1));
    my $f = fit_plane($s->{points});
    my (undef, $near) = predict($f, 1400, 2400);
    my (undef, $far) = predict($f, 9000, 9000);
    ok($far > 2 * $near, 'the error bar widens away from the boreholes');
};

subtest 'finds a hidden fault' => sub {
    my $s = parse_survey(survey_text(n => 24, dip => 8, dir => 300, noise => 0.5, throw => 12, trend => 40));
    my $r = analyse($s, sims => 49);
    ok($r->{faulted}, 'fault detected');
    cmp_ok($r->{fault}{p}, '<=', 0.05, 'and significant after allowing for the search');
    near($r->{fault}{throw}, 12, 1.5, 'throw');
    near($r->{attitude}{dip}, 8, 1, 'dip once the fault is allowed for');
    my ($lo, $hi) = @{ $r->{fault}{trend_range} };
    my $in = $lo <= $hi ? ($lo <= 40 && 40 <= $hi) : (40 >= $lo || 40 <= $hi);
    ok($in, "the fan of possible trends ($lo–$hi) holds the true 040°");
    near($r->{fault}{down_azimuth}, 130, 50, 'the right side is down (towards 130°)');
    like(render($r), qr/FAULT LIKELY/, 'and the report says so');
};

subtest 'no fault where there is none' => sub {
    my $false = 0;
    for my $trial (1 .. 8) {
        my $s = parse_survey(survey_text(n => 16, dip => 15, dir => 80, noise => 1));
        $false++ if analyse($s, sims => 39, seed => $trial)->{faulted};
    }
    cmp_ok($false, '<=', 1, "plain planes rarely look faulted ($false of 8)");
    my $small = analyse(parse_survey(survey_text(n => 5, dip => 15, dir => 80, noise => 1)));
    ok(!$small->{fault}{tested}, 'too few points: no search');
    like(render($small), qr/needs at least 8 points/, 'and the report says why');
};

subtest 'odd points are flagged' => sub {
    my $text = survey_text(n => 12, dip => 5, dir => 10, noise => 0.2);
    $text =~ s/^(point P05 \S+ \S+ )(\S+)/$1 . ($2 + 25)/me;
    like(render(analyse(parse_survey($text), sims => 9)), qr/Check point P05/, 'a 25 m slip is flagged');
};

subtest 'the survey format is strict' => sub {
    my $ok = "point A 0 0 1\npoint B 10 0 2\npoint C 0 10 3\n";
    my @bad = (
        [ '', 'at least 3 points' ],
        [ "point A 0 0 1\npoint B 10 0 2\n", 'at least 3 points' ],
        [ $ok . "point A 5 5 5\n", 'already listed' ],
        [ $ok . "point D 0 0 9\n", 'same place' ],
        [ $ok . "point D 1e3 0 9\n", 'plain number' ],
        [ $ok . "point D NaN 0 9\n", 'plain number' ],
        [ $ok . "point D 0 0 999999\n", 'within 100000' ],
        [ $ok . "point D 0 0\n", "write 'point" ],
        [ $ok . "point \$(rm) 1 1 1\n", 'point ids' ],
        [ $ok . "section 400\n", 'whole-degree bearing' ],
        [ $ok . "section 45.5\n", 'whole-degree bearing' ],
        [ $ok . "predict X 1 1 ground\n", "write 'predict" ],
        [ $ok . "units furlongs\n", "'m' or 'ft'" ],
        [ "survey <script>\n" . $ok, 'survey names' ],
        [ "survey A\nsurvey B\n" . $ok, 'comes once' ],
        [ $ok . "dip 30\n", 'lines start with' ],
        [ "survey A\x{1b}[2J\n" . $ok, 'control or hidden' ],
        [ "survey A\x{202e}B\n" . $ok, 'control or hidden' ],
        [ '#' x 301 . "\n" . $ok, 'longer than 300' ],
        [ '#' x (70 * 1024), 'larger than 64 KB' ],
    );
    for my $case (@bad) {
        my ($text, $want) = @$case;
        my $ok_ = eval { parse_survey($text); 1 };
        my $msg = ref $@ eq 'HASH' ? $@->{input} : "$@";
        ok(!$ok_ && index($msg, $want) >= 0, "rejects: $want (got: $msg)");
    }
    my $s = parse_survey("\x{FEFF}survey Cafe trial\n" . $ok . "section 045\npredict H1 5 5 ground 20\n");
    is(scalar @{ $s->{points} }, 3, 'three points');
    is($s->{sites}[0]{ground}, 20, 'ground elevation');
    my $line = eval { analyse(parse_survey("point A 0 0 1\npoint B 10 10 2\npoint C 20 20 3\n")); 1 };
    like(ref $@ eq 'HASH' ? $@->{input} : '', qr/straight line/, 'points in a line are refused');
};

subtest 'command line' => sub {
    my $run = sub {
        my ($args, $stdin) = @_;
        my ($out, $err) = ('', '');
        open my $in, '<', \($stdin // '') or die;
        open my $o, '>', \$out or die;
        open my $e, '>', \$err or die;
        my $code = run($args, $in, $o, $e);
        close $o; close $e;
        return ($code, $out, $err);
    };
    my ($code, $out, $err) = $run->(['examples/ridge-farm.txt']);
    is($code, 0, "the example runs ($err)");
    like($out, qr/FAULT LIKELY/, 'and finds its fault');
    open my $fh, '<:raw', 'examples/ridge-farm.txt' or die;
    my $raw = do { local $/; <$fh> };
    my (undef, $out2) = $run->(['-'], $raw);
    is($out2, $out, 'standard input gives the same, repeatable report');
    is(($run->([]))[0], 2, 'usage errors exit 2');
    is(($run->(['--help']))[0], 2, '--help exits 2');
    my ($c3, undef, $e3) = $run->(['examples']);
    ok($c3 == 2 && $e3 =~ /could not be read/, 'a folder is refused');
    my ($c4, undef, $e4) = $run->(['secret-name-zz.txt']);
    ok($c4 == 2 && $e4 !~ /secret-name/, "errors don't echo the path");
    my ($c5, undef, $e5) = $run->(['-'], '#' x 200_000);
    ok($c5 == 2 && $e5 =~ /64 KB/, 'endless input is cut off');
    my ($c6, undef, $e6) = $run->(['-'], "survey A\xff\n");
    ok($c6 == 2 && $e6 =~ /not valid UTF-8/, 'invalid UTF-8 is refused');
    my ($c7, undef, $e7) = $run->(['-'], "survey <img>\n");
    ok($c7 == 2 && $e7 !~ /<img>/, "errors don't echo the input");
    my $dir = tempdir(CLEANUP => 1);
    my $pipe = "$dir/|echo pwned";
    my ($c8) = $run->([$pipe]);
    is($c8, 2, 'a path that looks like a command is just a missing file');
    # The real executable, under taint mode, as a user would run it.
    my $exe = `$^X -T bin/downthrow examples/ridge-farm.txt 2>&1`;
    like($exe, qr/DOWNTHROW  Ridge Farm/, 'bin/downthrow runs under taint mode');
};

done_testing;
