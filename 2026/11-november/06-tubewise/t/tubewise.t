use strict;
use warnings FATAL => 'all';
use Test::More;
use File::Temp qw(tempdir);
use FindBin ();
use lib "$FindBin::Bin/../lib";
use Tubewise::Font qw(glyph glyph_chars layout);
use Tubewise::Graph qw(build dist segments_cross);
use Tubewise::Route qw(plan);
use Tubewise::App qw(run parse_design check_text);
use Tubewise::Report qw(svg);

my $EX = "$FindBin::Bin/../examples";

sub near { my ($a, $b, $tol) = @_; return abs($a - $b) <= ($tol // 1e-6) }

sub run_cli {
    my ($args, $in) = @_;
    $in //= '';
    my ($out, $err) = ('', '');
    open my $i, '<', \$in or die;
    open my $o, '>', \$out or die;
    open my $e, '>', \$err or die;
    my $code = run($args, $i, $o, $e);
    return ($code, $out, $err);
}

# Checks a plan against the graph without trusting the planner: every lit stroke once, a continuous
# path, jumpers clear of lit glass, tubes no longer than allowed.
sub check_plan {
    my ($g, $p, $max, $what) = @_;
    my %lit;
    $lit{ join ' ', sort map { sprintf '%.3f,%.3f', @$_ } $g->{nodes}[ $_->{u} ], $g->{nodes}[ $_->{v} ] }++ for @{ $g->{edges} };
    my %seen;
    for my $s (grep { $_->{kind} eq 'lit' } @{ $p->{steps} }) {
        $seen{ join ' ', sort map { sprintf '%.3f,%.3f', @$_ } $s->{from}, $s->{to} }++;
    }
    is_deeply(\%seen, \%lit, "$what: every lit stroke exactly once");
    my $joined = 1;
    for my $i (1 .. $#{ $p->{steps} }) { $joined &&= dist($p->{steps}[ $i - 1 ]{to}, $p->{steps}[$i]{from}) < 1e-6 }
    ok($joined, "$what: one continuous route");
    my $clear = 1;
    for my $s (grep { $_->{kind} eq 'jump' } @{ $p->{steps} }) {
        for my $e (@{ $g->{edges} }) { $clear &&= !segments_cross($s->{from}, $s->{to}, $g->{nodes}[ $e->{u} ], $g->{nodes}[ $e->{v} ]) }
    }
    ok($clear, "$what: no jumper crosses lit glass");
    my $fits = 1;
    for my $u (@{ $p->{units} }) {
        $fits &&= $u->{length} <= $max + 1e-6;
        for my $i (1 .. $#{ $u->{pieces} }) { $fits &&= dist($u->{pieces}[ $i - 1 ]{to}, $u->{pieces}[$i]{from}) < 1e-6 }
    }
    ok($fits, "$what: every tube is continuous and at most $max mm");
}

subtest 'the font' => sub {
    is(length glyph_chars(), 39, 'A-Z, 0-9 and - ! .');
    for my $c (split //, glyph_chars()) {
        my $g = glyph($c);
        ok(@$g >= 1, "'$c' has strokes");
        my $inside = 1;
        for my $s (@$g) { for my $p (@$s) { $inside &&= $p->[0] >= 0 && $p->[0] <= 4 && $p->[1] >= 0 && $p->[1] <= 6 } }
        ok($inside, "'$c' stays on its grid");
    }
    ok(!defined glyph('a'), 'only capitals');
    my $s = layout('IT', 300);
    is($s->[0]{points}[0][1], 300, 'the height in millimetres');
    ok(near($s->[-1]{points}[-1][0], (5.5 + 2) * 50), 'the second letter starts 5.5 units along');
};

subtest 'strokes become a graph' => sub {
    my $x = build(layout('X', 60));
    is(scalar @{ $x->{edges} }, 4, 'crossing strokes split into four at the middle');
    my $a = build(layout('A', 60));
    is(scalar @{ $a->{nodes} }, 5, "A's crossbar meets its legs: 5 nodes");
    is(scalar @{ $a->{edges} }, 5, 'and 5 pieces');
    my $dup = build([ { char => 0, points => [ [ 0, 0 ], [ 10, 0 ] ] }, { char => 0, points => [ [ 10, 0 ], [ 0, 0 ] ] } ]);
    is(scalar @{ $dup->{edges} }, 1, 'a stroke drawn twice is one tube');
    my $over = build([ { char => 0, points => [ [ 0, 0 ], [ 10, 0 ] ] }, { char => 0, points => [ [ 5, 0 ], [ 15, 0 ] ] } ]);
    is(scalar @{ $over->{edges} }, 3, 'overlapping strokes split where each ends');
    ok(segments_cross([ 0, 0 ], [ 10, 10 ], [ 0, 10 ], [ 10, 0 ]), 'crossing');
    ok(!segments_cross([ 0, 0 ], [ 10, 0 ], [ 10, 0 ], [ 10, 10 ]), 'meeting at an end is not crossing');
    ok(segments_cross([ 0, 0 ], [ 10, 0 ], [ 5, 0 ], [ 5, 10 ]), 'touching the middle counts');
    ok(segments_cross([ 0, 0 ], [ 10, 0 ], [ 5, 0 ], [ 20, 0 ]), 'running along counts');
};

subtest 'least blackout, worked by hand' => sub {
    my $u = 200 / 6;
    my $o = plan(build(layout('O', 200)));
    ok(near($o->{double} + $o->{jump}, 0), 'O is a loop: no black glass');
    my $l = plan(build(layout('L', 200)));
    ok(near($l->{double} + $l->{jump}, 0), 'L is a path: no black glass');
    # H: six odd points. Free two feet, double back down the top half of each leg: 2 x 100 mm.
    my $h = plan(build(layout('H', 200)));
    ok(near($h->{double}, 200, 1e-6) && near($h->{jump}, 0), "H: 200 mm doubling back ($h->{double}, $h->{jump})");
    # T: the bar's two ends and the stem's foot are odd, with the junction. Double back along half the bar.
    my $t = plan(build(layout('T', 200)));
    ok(near($t->{double} + $t->{jump}, 2 * $u, 1e-6), 'T: one half-bar of black glass');
    # A jumper costs its bends: with huge bends doubling back is chosen, with none the straight jumper.
    my $cheap = plan(build(layout('H', 200)), bend => 0);
    my $dear = plan(build(layout('H', 200)), bend => 200);
    ok($dear->{jumps} == 0, 'expensive bends: no jumpers');
    ok($cheap->{double} + $cheap->{jump} <= $h->{double} + $h->{jump} + 1e-9, 'cheaper bends never cost more');
};

subtest 'the exact pairing is the best pairing' => sub {
    # Compare the subset dynamic programme with trying every pairing, on random costs.
    srand 7;
    for my $round (1 .. 60) {
        my $n = 2 * (1 + int rand 5);
        my @c = map { [ map { 0 } 1 .. $n ] } 1 .. $n;
        for my $i (0 .. $n - 1) { for my $j ($i + 1 .. $n - 1) { $c[$i][$j] = $c[$j][$i] = int rand 100 } }
        my $cost = sub { $c[ $_[0] ][ $_[1] ] };
        my ($pairs, $exact) = Tubewise::Route::_match($n, $cost);
        my $got = 0;
        $got += $cost->(@$_) for @$pairs;
        my $best;
        my $try;
        $try = sub {
            my ($left, $sum) = @_;
            if (!@$left) { $best = $sum if !defined $best || $sum < $best; return }
            my ($i, @rest) = @$left;
            for my $k (0 .. $#rest) { $try->([ @rest[ grep { $_ != $k } 0 .. $#rest ] ], $sum + $cost->($i, $rest[$k])) }
        };
        $try->([ 0 .. $n - 1 ], 0);
        ok($exact && $got == $best, "round $round: $n points, $got = $best") or last;
    }
};

subtest 'every glyph and some signs plan correctly' => sub {
    for my $c (split //, glyph_chars()) {
        my $g = build(layout($c, 150));
        check_plan($g, plan($g, max_tube => 2000), 2000, "'$c'");
    }
    for my $text ('OPEN', 'HOTEL', 'BAR & GRILL' =~ s/&/-/r, 'OPEN 24 HOURS', 'NO VACANCY!') {
        for my $max (400, 2000) {
            my $g = build(layout($text, 200));
            my $p = plan($g, max_tube => $max);
            check_plan($g, $p, $max, "$text, $max mm tubes");
            # With long tubes every joint can hide in black glass; with short ones a lit run longer than
            # a tube (the O alone is 589 mm) has to be joined where it shows, and the plan says so.
            if ($max == 2000) { is($p->{visible_joints}, 0, "$text: every joint hidden") }
            else { ok($p->{visible_joints} > 0 && $p->{visible_joints} <= @{ $p->{units} }, "$text, $max mm tubes: $p->{visible_joints} joints show, and are counted") }
        }
    }
};

subtest 'text and design files are checked strictly' => sub {
    is(check_text('open late'), 'OPEN LATE', 'lower case is read as capitals');
    for my $bad ('', '   ', '<script>', 'OPEN' x 7, "OPEN\x{202E}SECRET", "OPEN\e[2J", 'CAFÉ') {
        my $ok = eval { check_text($bad); 1 };
        ok(!$ok && ref $@ eq 'HASH' && $@->{msg} !~ /SECRET|script/, 'refused: ' . ($bad =~ s/[^ -~]/?/gr));
    }
    my ($name, $s) = parse_design("name Heart & arrow\nstroke 0,0 10,10 20,0 # a vee\n\nstroke 0,20 20,20\n");
    is($name, 'Heart & arrow');
    is(scalar @$s, 2, 'two strokes');
    my @bad = (
        [ "stroke 0,0\n", '2 to 50 points' ],
        [ "stroke 0,0 1e9,0\n", 'points are x,y' ],
        [ "stroke 0,0 -5,0\n", 'points are x,y' ],
        [ "stroke 0,0 9000,0\n", 'within 5000' ],
        [ "rm -rf SECRET\n", "lines are 'name" ],
        [ "name <b>\nstroke 0,0 1,1\n", 'the name' ],
        [ "name A\x{202E}SECRET\nstroke 0,0 1,1\n", 'invisible' ],
        [ "stroke 0,0 1,1\x00\n", 'control' ],
        [ '# ' . ('x' x 400) . "\nstroke 0,0 1,1\n", 'longer than 300' ],
        [ "stroke 0,0 1,1\n" x 401, 'at most 400' ],
        [ "\xff\xfe\n", 'UTF-8' ],
        [ "# nothing\n", 'no strokes' ],
        [ '#' x 70000, '64 KB' ],
    );
    for my $b (@bad) {
        my ($text, $want) = @$b;
        my $bytes = utf8::is_utf8($text) ? do { my $c = $text; utf8::encode($c); $c } : $text;
        my $ok = eval { parse_design($bytes); 1 };
        ok(!$ok && ref $@ eq 'HASH' && index($@->{msg}, $want) >= 0 && $@->{msg} !~ /SECRET/, "refused: $want") or diag(ref $@ ? $@->{msg} : $@);
    }
};

subtest 'the command line' => sub {
    my ($code, $out) = run_cli([ 'open' ]);
    is($code, 0, 'a sign plans');
    like($out, qr/^TUBEWISE  "OPEN"  \(letters 200 mm tall\)\n/, 'the title');
    like($out, qr/Plan: 2 tubes, 4 electrodes, every joint hidden in black glass\./, 'the plan');
    like($out, qr/Bent as separate pieces, it would take 4 tubes and 8 electrodes\./, 'against bending each piece');
    ($code, $out) = run_cli([ '--svg', '--height', '120', 'HI' ]);
    is($code, 0);
    like($out, qr/^<svg xmlns=/, 'a drawing');
    unlike($out, qr/<script/i, 'with no script');
    ($code, $out) = run_cli([ '--design', '-', '--svg' ], "name Fish & chips\nstroke 0,0 50,50 100,0 0,0\n");
    like($out, qr{<title>Tubewise: Fish &amp; chips</title>}, 'names are escaped in the drawing');
    ($code, $out) = run_cli([ '--design', "$EX/heart.txt" ]);
    is($code, 0, 'the example design');
    like($out, qr/^TUBEWISE  Heart\n/, 'its name');
    my $dir = tempdir(CLEANUP => 1);
    symlink "$EX/heart.txt", "$dir/link.txt" or die;
    my ($c2, undef, $e2) = run_cli([ '--design', "$dir/link.txt" ]);
    ok($c2 == 2 && $e2 =~ /not a link/, 'a symbolic link is refused');
    ($c2, undef, $e2) = run_cli([ '--design', $dir ]);
    is($c2, 2, 'a folder is refused');
    ($c2, undef, $e2) = run_cli([ '--design', "$dir/secret-name-zz.txt" ]);
    ok($c2 == 2 && $e2 !~ /secret-name/, 'the path is never echoed');
    for my $args ([], [ '--height', '9999', 'OPEN' ], [ '--height', 'abc', 'OPEN' ], [ '--max-tube', '100', 'OPEN' ], [ 'A', 'B' ], [ '--design', '-', 'OPEN' ], [ '--wat', 'OPEN' ]) {
        my ($c) = run_cli($args);
        is($c, 2, 'refused: ' . join(' ', @$args));
    }
    ($c2, undef, $e2) = run_cli([ "OPEN\xE2\x80\xAE" ]);
    ok($c2 == 2 && $e2 =~ /invisible/, 'hidden characters in the text are refused');
};

done_testing;
