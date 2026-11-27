use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More;
use File::Temp qw(tempdir);
use POSIX qw(strftime);
use Farswell qw(analyse forecast);
use Farswell::Input qw(parse_text parse_time);
use Farswell::Physics qw(arrival_time rng);
use Farswell::Geo qw(gc_dist bearing);
use Farswell::Render qw(report);

# Make readings the way a real buoy would report them: every 3 hours,
# periods rounded to 0.1 s, a little noise.
sub synth {
    my (%o) = @_;
    my $r = rng($o{seed} // 5);
    my $text = '';
    for my $b (@{ $o{buoys} }) {
        my ($name, $la, $lo, $storm) = @$b;
        $storm //= $o{storm};
        my ($sla, $slo, $t0) = @$storm;
        my $d = gc_dist($la, $lo, $sla, $slo);
        my $dir = bearing($la, $lo, $sla, $slo);
        $text .= "buoy $name $la $lo\n";
        my $t = 10800 * int(arrival_time($t0, $d, 21) / 10800 + 1);
        while (1) {
            my $T = 4 * 3.14159265358979 * $d / (9.80665 * ($t - $t0));
            last if $T < 11.5;
            my $n = ($r->() + $r->() - 1) * ($o{noise} // 0.2);
            $text .= sprintf "%s %.1f%s\n", strftime('%Y-%m-%dT%H:%MZ', gmtime $t), $T + $n,
              $o{dirs} ? sprintf(' %.0f', $dir) : '';
            $t += 10800;
        }
    }
    return $text;
}

my $t0 = parse_time('2026-11-17T18:00Z');
my @storm = (-52, 162, $t0);
my @nsw = (['Byron', -28.82, 153.72], ['Sydney', -33.77, 151.42], ['Eden', -37.30, 150.18]);

my $res = analyse(parse_text(synth(storm => \@storm, buoys => \@nsw, dirs => 1)), reps => 50);
cmp_ok(abs($res->{fit}{t0} - $t0) / 3600, '<', 3, 'storm time within 3 h');
my $miss = gc_dist($res->{where}{lat}, $res->{where}{lon}, @storm[0, 1]);
cmp_ok($miss, '<', 150_000, 'storm place within 150 km');
ok($res->{t0lo} <= $res->{t0hi}, 'time range is ordered');
is($res->{reps}, 50, 'all refits used');
is_deeply($res->{warn}, [], 'no warnings on a clean storm');

my $fc = forecast($res, { name => 'Newcastle', lat => -32.93, lon => 151.78 }, 20, 15, 10);
my @rt = map { $_->{t} } @{ $fc->{rows} };
ok($rt[0] < $rt[1] && $rt[1] < $rt[2], 'long periods arrive first');
my $true = arrival_time($t0, gc_dist(-32.93, 151.78, @storm[0, 1]), 15);
cmp_ok(abs($rt[1] - $true) / 3600, '<', 4, '15 s arrives at Newcastle within 4 h of truth');
ok($fc->{rows}[0]{lo} <= $fc->{rows}[0]{hi}, 'forecast window ordered');

# Same seed, same answer
my $again = analyse(parse_text(synth(storm => \@storm, buoys => \@nsw, dirs => 1)), reps => 50);
is($again->{where}{r90}, $res->{where}{r90}, 'bootstrap repeats with the same seed');

# Two buoys, no directions: the mirror image must be admitted
my $two = analyse(parse_text(synth(storm => [-45, 175, $t0], buoys => [@nsw[0, 2]])), reps => 0);
ok($two->{where}{alt}, 'mirror reported for two buoys and no direction');
ok((grep { /mirror/ } @{ $two->{warn} }), 'and warned about');

# Different storms at different buoys: warn instead of pretending
my $mixed = synth(buoys => [
    ['Byron', -28.82, 153.72, [-52, 162, $t0]],
    ['Eden', -37.30, 150.18, [-50, 170, $t0 + 3 * 86400]],
]);
my $mres = analyse(parse_text($mixed), reps => 0);
ok((grep { /different storms/ } @{ $mres->{warn} }), 'different storms flagged');

# One buoy, no direction: distance and time, but no position
my $one = analyse(parse_text(synth(storm => \@storm, buoys => [$nsw[1]])), reps => 20);
ok(!$one->{where}, 'no position from one buoy alone');
like(report($one), qr/needs a second buoy or a swell direction/, 'report says why');

# Report has every section
my $rep = report($res, tz => 11, beach => { name => 'Newcastle', lat => -32.93, lon => 151.78 });
like($rep, qr/^FARSWELL/, 'title');
like($rep, qr/BUOYS/, 'buoy table');
like($rep, qr/MAP/, 'map');
like($rep, qr/FORECAST for Newcastle/, 'forecast');
like($rep, qr/UTC\+11/, 'time zone shown');
unlike($rep, qr/\t/, 'no tabs');
ok(!(grep { length > 110 } split /\n/, $rep), 'lines fit a wide terminal');

eval { analyse(parse_text(synth(storm => \@storm, buoys => [$nsw[1]])), reps => 5000) };
like($@, qr/reps/, 'too many refits refused');

# The command line
my $dir = tempdir(CLEANUP => 1);
my $file = "$dir/r.txt";
open my $fh, '>', $file or die; print $fh synth(storm => \@storm, buoys => \@nsw, dirs => 1); close $fh;
my $bin = "$RealBin/../bin/farswell";
my $out = qx{$^X "$bin" --reps 10 --beach Bondi:-33.89:151.27 "$file" 2>&1};
is($? >> 8, 0, 'CLI runs');
like($out, qr/FORECAST for Bondi/, 'CLI forecast');
for my $args (['--tz', '99', $file], ['--reps', '-1', $file], ['--reps', '1;id', $file],
              ['--seed', 'abc', $file], ['--beach', 'x', $file], [], ["$dir/nope"], [$dir]) {
    my $o = qx{$^X "$bin" @{[ map { "'$_'" } @$args ]} 2>&1};
    is($? >> 8, 2, "CLI refuses: @$args");
    unlike($o, qr/ at \S+\.pm line \d+/, 'no Perl internals in the message');
}
like(qx{$^X "$bin" --help}, qr/usage: farswell/, 'help');

done_testing;
