use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Encode qw(decode encode);
use File::Temp qw(tempdir);

use Dryleg::Route qw(parse_route clock_minutes format_clock);
use Dryleg::Plan qw(temperature drink_rate walk plan best_start);
use Dryleg::CLI qw(run);

my $EXAMPLE = do {
    open my $fh, '<:encoding(UTF-8)', "$FindBin::Bin/../examples/ridge-walk.txt" or die;
    local $/;
    <$fh>;
};

sub route { parse_route(join "\n", @_) }

subtest 'clock times' => sub {
    is(clock_minutes('07:30'), 450);
    is(clock_minutes('0:05'), 5);
    is(clock_minutes($_), undef, "rejects $_") for ('24:00', '7:3', '07:60', '', 'noon', '07:30:00');
    is(format_clock(450), '07:30');
    is(format_clock(1440 + 75), '01:15 (+1 day)');
};

subtest 'temperature through the day' => sub {
    my $r = { low => 10, high => 30 };
    is(sprintf('%.6f', temperature($r, 6 * 60)), '10.000000', 'coolest at dawn');
    is(sprintf('%.6f', temperature($r, 15 * 60)), '30.000000', 'hottest mid-afternoon');
    my $prev = -1;
    for (my $t = 360; $t <= 900; $t += 15) {
        my $x = temperature($r, $t);
        ok($x >= $prev, "rising at $t") or last;
        $prev = $x;
    }
    ok(abs(temperature($r, 1439.999) - temperature($r, 0)) < 0.01, 'smooth across midnight');
    is(sprintf('%.6f', temperature($r, 1440 + 6 * 60)), '10.000000', 'the next morning too');
};

subtest 'how fast you drink' => sub {
    is(drink_rate(15), 0.5);
    is(drink_rate(20), 0.5);
    is(sprintf('%.2f', drink_rate(30)), '1.10');
    is(drink_rate(45), 1.5, 'capped');
};

subtest 'walking time and water' => sub {
    my $r = route('temp 20 20', 'pace 4', 'water A 0 reliable', 'end B 4 +600');
    my $legs = walk($r, 8 * 60);
    is(sprintf('%.3f', $legs->[0]{minutes}), '120.000', '4 km at 4 km/h, plus an hour per 600 m of climb');
    is(sprintf('%.6f', $legs->[0]{litres}), '1.000000', 'two hours at half a litre an hour');
};

subtest 'which sources count' => sub {
    my @lines = ('temp 20 20', 'reserve 0.5', 'capacity 10', 'water Start 0 reliable', 'water Seasonal 4 seasonal',
                 'water Doubtful 8 unreliable', 'water Tank 12 reliable', 'end End 16');
    my $p = plan(route(@lines), 8 * 60);
    is(scalar @{ $p->{fills} }, 2, 'fill at the start and the tank');
    is($p->{fills}[0]{to}{name}, 'Tank');
    is_deeply([map { $_->{name} } @{ $p->{fills}[0]{passing} }], ['Seasonal', 'Doubtful']);
    is(sprintf('%.2f', $p->{fills}[0]{litres}), '2.00', '3 hours at 0.5 L, plus the reserve');
    my $t = plan(route(@lines, 'trust seasonal'), 8 * 60);
    is(scalar @{ $t->{fills} }, 3, 'trusting seasonal sources adds a fill-up');
    is_deeply([map { $_->{at}{name} } @{ $t->{fills} }], ['Start', 'Seasonal', 'Tank'], 'but never the unreliable one');
};

subtest 'warnings' => sub {
    my $heavy = plan(route('temp 30 40', 'capacity 2', 'water A 0 reliable', 'end B 20'), 12 * 60);
    ok($heavy->{too_heavy}, 'more than you can carry');
    my $late = plan(route('dark 18:00', 'water A 0 reliable', 'end B 30'), 12 * 60);
    ok($late->{after_dark}, 'arrives after dark');
};

subtest 'the best start time' => sub {
    my $r = parse_route($EXAMPLE);
    my $best = best_start($r);
    ok($best->{start} >= $r->{light} && $best->{start} <= 13 * 60, 'between first light and 13:00');
    ok(!$best->{after_dark}, 'finishes in daylight');
    for (my $s = $r->{light}; $s <= 13 * 60; $s += 15) {
        my $p = plan($r, $s);
        next if $p->{after_dark};
        ok(sprintf('%.1f', $best->{most}) <= sprintf('%.1f', $p->{most}), 'no daylight start has a lighter heaviest carry')
            or diag("start $s carries $p->{most}");
    }
};

subtest 'bad and hostile route files' => sub {
    my %cases = (
        ''                                                       => 'needs at least a start and an end',
        "water A 0 reliable\n"                                   => 'needs at least a start and an end',
        "point A 0\nend B 5\n"                                   => 'must start at a water source',
        "water A 0 reliable\npoint B 5\n"                        => 'finish with an end line',
        "water A 2 reliable\nend B 5\n"                          => 'must start at km 0',
        "water A 0 reliable\nend B 5\nend C 6\n"                 => 'nothing can come after the end',
        "water A 0 reliable\npoint B 5\nend C 4\n"               => 'must be in order',
        "water A 0 reliable\npoint a 5\nend A 9\n"               => 'same name',
        "water A 0 sometimes\nend B 5\n"                         => 'reliable, seasonal or unreliable',
        "water <script> 0 reliable\nend B 5\n"                   => 'place name must be',
        "temp 30 10\nwater A 0 reliable\nend B 5\n"              => 'must not be below the low',
        "pace 40\nwater A 0 reliable\nend B 5\n"                 => 'pace (km/h) must be',
        "start-time 25:00\nwater A 0 reliable\nend B 5\n"        => 'must be a time',
        "capacity 1\nreserve 2\nwater A 0 reliable\nend B 5\n"   => 'reserve must be less',
        "trust everything\nwater A 0 reliable\nend B 5\n"        => 'trust must be',
        "swim A 0\n"                                             => 'start the line with',
        "water A\x1b[2J 0 reliable\nend B 5\n"                   => 'control or invisible',
        "water A\x{202E} 0 reliable\nend B 5\n"                  => 'control or invisible',
        ('x' x 300)                                              => 'longer than 200',
        ("#\n" x 9000)                                           => 'larger than 16 KB',
        join('', "water W 0 reliable\n", map { "point P$_ $_\n" } 1 .. 60) => 'more than 60 places',
    );
    for my $text (sort keys %cases) {
        my $ok = eval { parse_route($text); 1 };
        my $err = $@;
        ok(!$ok && index($err, $cases{$text}) >= 0, "refused: $cases{$text}") or diag($err);
        unlike($err, qr/script|\x1b/, 'the message does not repeat the input');
    }
};

sub cli {
    my ($args, $stdin_text) = @_;
    my ($out, $err) = ('', '');
    open my $in, '<', \(encode('UTF-8', $stdin_text // '')) or die;
    open my $o, '>', \$out or die;
    open my $e, '>', \$err or die;
    binmode $_, ':encoding(UTF-8)' for $o, $e;
    my $code = run($args, $in, $o, $e);
    close $_ for $o, $e;
    return ($code, decode('UTF-8', $out), decode('UTF-8', $err));
}

subtest 'command line' => sub {
    my ($code, $out, $err) = cli(["$FindBin::Bin/../examples/ridge-walk.txt"]);
    is($code, 1, 'the example is too heavy as planned');
    like($out, qr/<< more than you can carry/);
    like($out, qr/Better: leave at 05:50/);
    like($out, qr/16 to 34 °C/, 'UTF-8 degree sign');
    is($err, '');

    ($code, $out) = cli(['-'], "temp 15 22\ncapacity 3\nwater Hut 0 reliable\nend Peak 8 +400\n");
    is($code, 0, 'an easy day from standard input');
    like($out, qr/Hut\s+[\d.]+ L\s+Peak/);

    my $dir = tempdir(CLEANUP => 1);
    my $big = "$dir/big.txt";
    open my $fh, '>', $big or die;
    print {$fh} "#\n" x 20000;
    close $fh;
    my $bad = "$dir/bad.txt";
    open $fh, '>:raw', $bad or die;
    print {$fh} "water \xff\xfe 0 reliable\n";
    close $fh;
    for my $args ([], ['a', 'b'], ['--bogus'], ['/no/such/file'], [$dir], [$big], ['/dev/zero'], [$bad],
                  ["\e]0;owned\a\$(reboot)"]) {
        my ($c, $o, $e) = cli($args);
        is($c, 2, 'exit 2 for ' . join(' ', map { length > 30 ? 'long' : $_ } @$args));
        is($o, '');
        like($e, qr/\Adryleg: /);
        unlike($e, qr/owned|reboot/);
    }
    my $odd = "$dir/route\e[31m.txt";
    open $fh, '>:encoding(UTF-8)', $odd or die;
    print {$fh} $EXAMPLE;
    close $fh;
    ($code, $out) = cli([$odd]);
    unlike($out, qr/\e/, 'file name escape codes are not printed');
    like($out, qr/route\?\[31m\.txt|route\?\?31m\.txt/);
};

done_testing();
