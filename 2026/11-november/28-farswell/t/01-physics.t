use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More;
use Farswell::Physics qw(G group_speed theil_sen fit_buoy joint_fit
  distance_from_slope arrival_time median rng);

my $PI = 4 * atan2(1, 1);

# Deep-water group speed: a 16 s swell moves at about 12.5 m/s (45 km/h)
cmp_ok(abs(group_speed(16) - 12.486), '<', 0.01, '16 s group speed');
cmp_ok(abs(group_speed(20) / group_speed(10) - 2), '<', 1e-12, 'speed is proportional to period');

# arrival_time and distance_from_slope are inverses of each other
my $d  = 3_000_000;
my $t0 = 1_800_000_000;
my @t  = map { arrival_time($t0, $d, $_) } 20, 18, 16, 14, 12;
my $slope = (1 / 12 - 1 / 20) / ($t[-1] - $t[0]);
cmp_ok(abs(distance_from_slope($slope) - $d), '<', 1, 'slope gives back the distance');
ok(!defined distance_from_slope(0),  'zero slope has no distance');
ok(!defined distance_from_slope(-1), 'falling frequency has no distance');

is(median(3, 1, 2), 2, 'median odd');
is(median(4, 1, 3, 2), 2.5, 'median even');
ok(!defined median(), 'median of nothing');

# Theil-Sen shrugs off wild points; least squares would not
my @x = 0 .. 19;
my @y = map { 2 * $_ + 1 } @x;
$y[3] = 500; $y[11] = -400; $y[17] = 900;
my ($a1, $b1) = theil_sen(\@x, \@y);
cmp_ok(abs($a1 - 2), '<', 1e-9, 'Theil-Sen slope ignores 3 wild points');
cmp_ok(abs($b1 - 1), '<', 1e-9, 'Theil-Sen intercept ignores them too');
eval { theil_sen([5, 5, 5], [1, 2, 3]) };
like($@, qr/two or more different times/, 'all readings at one time is refused');

# fit_buoy flags a local wind sea reading as an outlier
my @obs = map { { t => arrival_time($t0, $d, $_), T => $_ } } 21, 19, 17, 15, 13, 12;
push @obs, { t => arrival_time($t0, $d, 16), T => 7.5 };
@obs = sort { $a->{t} <=> $b->{t} } @obs;
my $f = fit_buoy({ name => 'X', obs => \@obs }, $obs[0]{t});
is($f->{nin}, 6, 'six readings agree');
is((grep { !$_->{inlier} } @obs)[0]{T}, 7.5, 'the 7.5 s reading is the outlier');
cmp_ok(abs($f->{dist} - $d) / $d, '<', 1e-6, 'single-buoy distance exact on clean data');
cmp_ok(abs($f->{t0} - $t0), '<', 1, 'single-buoy storm time exact');

# Rising periods (a swell going away, or readings in the wrong order) are refused
my @bad = map { { t => $t0 + $_ * 3600, T => 10 + $_ } } 1 .. 6;
eval { fit_buoy({ name => 'Bad', obs => \@bad }, $t0) };
like($@, qr/not falling/, 'rising period refused');

# Joint fit: two buoys, one storm time, two distances
my @sets;
for my $dist (2_000_000, 3_500_000) {
    my @tt = map { arrival_time($t0, $dist, $_) } 22, 19, 16, 14, 12;
    push @sets, { t => \@tt, f => [map { 1 / $_ } 22, 19, 16, 14, 12] };
}
my $j = joint_fit(\@sets);
cmp_ok(abs($j->{t0} - $t0), '<', 60, 'joint storm time within a minute');
cmp_ok(abs($j->{dists}[0] - 2_000_000), '<', 1000, 'near buoy distance');
cmp_ok(abs($j->{dists}[1] - 3_500_000), '<', 1000, 'far buoy distance');
ok(!$j->{edge}, 'answer is inside the search window');

# The generator repeats exactly from a seed and stays in [0,1)
my ($r1, $r2, $r3) = (rng(42), rng(42), rng(43));
my @s1 = map { $r1->() } 1 .. 1000;
my @s2 = map { $r2->() } 1 .. 1000;
is_deeply(\@s1, \@s2, 'same seed, same numbers');
isnt($r3->(), $s1[0], 'different seed, different numbers');
ok(!(grep { $_ < 0 || $_ >= 1 } @s1), 'numbers lie in [0,1)');
my $mean = 0; $mean += $_ / 1000 for @s1;
cmp_ok(abs($mean - 0.5), '<', 0.05, 'roughly uniform');
ok(defined rng(0)->(), 'seed 0 still works');

done_testing;
