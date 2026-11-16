use strict;
use warnings FATAL => 'all';
use Test::More;
use File::Temp qw(tempdir);
use FindBin ();
use lib "$FindBin::Bin/../lib";
use Tallyhook::Parse qw(parse_pattern clean MAX_BYTES MAX_ROUNDS);
use Tallyhook::Count qw(tally);
use Tallyhook::App qw(run check_text);

sub counts {
    my ($text) = @_;
    my $res = tally(parse_pattern($text));
    return [ map { $_->{made} } @$res ], $res;
}

sub problem {
    my ($text) = @_;
    my (undef, $res) = counts($text);
    return join ' | ', map { @{ $_->{errors} } } @$res;
}

sub parse_error {
    my ($text) = @_;
    my $ok = eval { parse_pattern($text); 1 };
    return $ok ? '' : ref $@ ? $@->{msg} : "$@";
}

subtest 'the many ways patterns write the same thing' => sub {
    my %same = (
        'Rnd 2: inc in each st around'             => 12,
        'Rnd 2: 2 sc in each st around'             => 12,
        'Rnd 2: inc around'                          => 12,
        'Rnd 2: sc in each st around'               => 6,
        'Rnd 2: sc around'                           => 6,
        'Rnd 2: 6 sc'                                => 6,
        'Rnd 2: sc 6'                                => 6,
        'Rnd 2: sc in next 6 sts'                    => 6,
        'Rnd 2: (sc, inc) x 3'                       => 9,
        'Rnd 2: [sc, inc] 3 times'                   => 9,
        'Rnd 2: *sc, inc; rep from * 2 more times'   => 9,
        'Rnd 2: *sc, inc; rep from * around'         => 9,
        'Rnd 2: *sc in next st, 2 sc in next st* around' => 9,
        'Rnd 2: (sc, inc) around'                    => 9,
        'Rnd 2: 3 inc, 3 sc'                         => 9,
        'Rnd 2: dec around'                          => 3,
        'Rnd 2: 3 dec'                               => 3,
        'Rnd 2: (sc2tog) x 3'                        => 3,
        'Rnd 2: sc3tog, sc3tog'                      => 2,
        'Rnd 2: 3 dc in next st, sk 1, sc in next 4 sts' => 7,
        'RND 2: SC IN EACH ST AROUND, JOIN WITH SL ST TO FIRST SC.' => 6,
        'Rnd 2: sc blo in each st around'           => 6,
    );
    for my $body (sort keys %same) {
        my ($c) = counts("Rnd 1: 6 sc in magic ring\n$body\n");
        is($c->[1], $same{$body}, $body);
    }
};

subtest 'a ball: every round checks out' => sub {
    open my $fh, '<', "$FindBin::Bin/../examples/ball.txt" or die;
    my $text = do { local $/; <$fh> };
    my ($c, $res) = counts($text);
    is_deeply($c, [6, 12, 18, 24, 30, 36, (36) x 6, 30, 24, 18, 12, 6], 'counts');
    is(problem($text), '', 'no problems');
    is_deeply([ map { $_->{shape} } @$res[1, 7, 12] ], ['flat', 'straight sides', 'closing'], 'shapes');
    like(join(' ', map { @{ $_->{notes} } } @$res), qr/increases stack in the same places from Rnd 3 to Rnd 6/, 'stacked increases');
};

subtest 'staggered increases are not flagged' => sub {
    my $text = join "\n", 'Rnd 1: 6 sc in mr (6)', 'Rnd 2: inc around (12)', 'Rnd 3: (sc, inc) x 6 (18)',
        'Rnd 4: sc, inc, (2 sc, inc) x 5, sc (24)', 'Rnd 5: (3 sc, inc) x 6 (30)', 'Rnd 6: 2 sc, inc, (4 sc, inc) x 5, 2 sc (36)';
    my (undef, $res) = counts($text);
    is(problem($text), '');
    unlike(join(' ', map { @{ $_->{notes} } } @$res), qr/stack/);
};

subtest 'mistakes are found and explained' => sub {
    like(problem("Rnd 1: 6 sc in mr\nRnd 2: (sc, inc) x 6 (18)"), qr/runs out of stitches: needs 1 more than the 6 there are/);
    like(problem("Rnd 1: 6 sc in mr\nRnd 2: (sc, inc) x 2 (6)"), qr/leaves 2 of the 6 stitches unworked/);
    like(problem("Rnd 1: 6 sc in mr\nRnd 2: inc around (13)"), qr/says \(13\) but makes 12/);
    like(problem("Rnd 1: 7 sc in mr\nRnd 2: (sc, inc) around"), qr/after 3 repeats, 1 stitch is left over/);
    like(problem("Rnd 1: 7 sc in mr\nRnd 2: dec around"), qr/can't decrease over 7 stitches in pairs/);
    like(problem("Rnd 1: 6 sc in mr\nRnd 2: 6 sc in mr"), qr/magic ring only starts a piece/);
    # After a mistake the next round is judged from the count the pattern meant.
    my (undef, $res) = counts("Rnd 1: 6 sc in mr\nRnd 2: inc around (13)\nRnd 3: sc around (13)");
    is_deeply($res->[2]{errors}, [], 'carries on from the stated count');
};

subtest 'rows: a foundation chain, turning chains and short rows' => sub {
    my ($c) = counts("Row 1: ch 21, sc in 2nd ch from hook and in each ch across, turn (20)\nRows 2-3: ch 1, sc in each st across, turn (20)\nRow 4: ch 2, dc in each st across (20)");
    is_deeply($c, [20, 20, 20, 20]);
    my (undef, $res) = counts("Row 1: ch 11, sc in 2nd ch from hook and in each ch across (10)\nRow 2: ch 1, sc in next 6 sts, turn (6)");
    is_deeply($res->[1]{errors}, [], 'a short row is not an error');
    like($res->[1]{notes}[0], qr/short row/);
};

subtest 'random patterns: the tally matches counting by hand' => sub {
    srand(42);
    for my $trial (1 .. 200) {
        my $count = 4 + int rand 10;
        my @lines = ("Rnd 1: $count sc in magic ring ($count)");
        for my $rnd (2 .. 6) {
            # Build a repeat of plain stitches, increases and decreases that divides the round.
            my @divs = grep { $count % $_ == 0 } 1 .. $count;
            my $per = $divs[ int rand @divs ];
            my ($used, $make, @parts) = (0, 0);
            while ($used < $per) {
                my $left = $per - $used;
                my $pick = int rand 3;
                if ($pick == 2 && $left >= 2) { push @parts, 'dec'; $used += 2; $make += 1 }
                elsif ($pick == 1) { push @parts, 'inc'; $used += 1; $make += 2 }
                else { push @parts, 'sc'; $used += 1; $make += 1 }
            }
            my $times = $count / $per;
            my $next = $make * $times;
            last if $next < 1 || $next > 400;
            my $body = $times > 1 ? '(' . join(', ', @parts) . ") x $times" : join(', ', @parts);
            push @lines, "Rnd $rnd: $body ($next)";
            $count = $next;
        }
        my $text = join "\n", @lines;
        is(problem($text), '', "trial $trial") or diag $text;
    }
};

subtest 'hostile and broken input' => sub {
    like(parse_error("Rnd 1: 6 sc in mr\0"), qr/NUL/);
    like(parse_error('x' x (MAX_BYTES + 1)), qr/64 KB/);
    like(parse_error("just some text\n"), qr/no rounds or rows found/);
    like(parse_error(join "\n", map { "Rnd $_: sc around" } 1 .. MAX_ROUNDS + 1), qr/at most 500 rounds/);
    like(parse_error("Rnd 1: (sc, inc) x 0"), qr/from 1 to 1000/);
    like(parse_error("Rnd 1: (sc, inc) x 1001"), qr/from 1 to 1000/);
    like(parse_error("Rnd 1: (((((sc)))))"), qr/nested too deeply/);
    like(parse_error("Rnd 1: (sc, inc x 6"), qr/never closed/);
    like(parse_error("Rnd 1: sc, rep from * around"), qr/without a \*/);
    like(parse_error("Rnd 9-3: sc around"), qr/backwards/);
    my $e = parse_error("Rnd 1: frobnicate \e\x07 the yarn");
    like($e, qr/can't read "frobnicate \?\? the yarn"/, 'control characters are not echoed');
    unlike($e, qr/[\e\x07]/);
    # Doubling every round would reach 2^40 stitches; the work limit stops it.
    like(problem("Rnd 1: 6 sc in mr\nRnds 2-40: inc around"), qr/more than 200000 stitches worked in one round/);
    like(problem("Rnd 1: (((sc) x 1000) x 1000) x 1000"), qr/first round needs a magic ring/);
    is(clean('a' x 80), ('a' x 47) . '...');
};

subtest 'the command line' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $run = sub {
        my ($args, $stdin) = @_;
        my ($out, $err) = ('', '');
        open my $in, '<', \($stdin // '') or die;
        open my $o, '>', \$out or die;
        open my $e, '>', \$err or die;
        my $code = run($args, $in, $o, $e);
        return ($code, $out, $err);
    };
    my ($code, $out) = $run->(["$FindBin::Bin/../examples/ball.txt"]);
    is($code, 0);
    like($out, qr/Every round works out/);
    ($code, $out) = $run->(["$FindBin::Bin/../examples/coaster-typo.txt"]);
    is($code, 3, 'exit 3 when a round has a problem');
    like($out, qr/Rnd 5 \(line 6\): says \(40\) but makes 36/);
    ($code, $out) = $run->(['-'], "Rnd 1: 6 sc in mr (6)\nRnd 2: inc around (12)\n");
    is($code, 0, 'standard input');
    my $err;
    ($code, undef, $err) = $run->(['-'], "Rnd 1: \xff\xfe sc\n");
    is($code, 1);
    like($err, qr/not valid UTF-8/);
    symlink("$FindBin::Bin/../examples/ball.txt", "$dir/link.txt") or die;
    ($code, undef, $err) = $run->(["$dir/link.txt"]);
    like($err, qr/plain file/);
    ($code, undef, $err) = $run->([$dir]);
    like($err, qr/plain file/);
    ($code, undef, $err) = $run->(["$dir/none.txt"]);
    like($err, qr/not found/);
    ($code) = $run->([]);
    is($code, 2);
    # The real script, in taint mode.
    my $got = `$^X -T $FindBin::Bin/../bin/tallyhook $FindBin::Bin/../examples/dishcloth.txt`;
    like($got, qr/Row 25 +20 -> 18 +ok/, 'runs in taint mode');
};

done_testing;
