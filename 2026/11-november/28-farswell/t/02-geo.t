use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More;
use Farswell::Geo qw(gc_dist bearing destination along locate ang_diff R_EARTH);

my $PI = 4 * atan2(1, 1);

# Sydney to Auckland is about 2,160 km
my $d = gc_dist(-33.87, 151.21, -36.85, 174.76);
cmp_ok(abs($d / 1000 - 2156), '<', 15, 'Sydney-Auckland distance');
cmp_ok(abs(gc_dist(0, 0, 0, 180) - $PI * R_EARTH), '<', 1, 'half way round the equator');
is(gc_dist(10, 20, 10, 20), 0, 'zero distance');
cmp_ok(abs(gc_dist(0, 179.5, 0, -179.5) - gc_dist(0, 0, 0, 1)), '<', 1, 'across the date line');

cmp_ok(abs(bearing(0, 0, 10, 0) - 0), '<', 1e-9, 'due north');
cmp_ok(abs(bearing(0, 0, 0, 10) - 90), '<', 1e-9, 'due east');
cmp_ok(abs(bearing(0, 0, -10, 0) - 180), '<', 1e-9, 'due south');
cmp_ok(abs(bearing(0, 0, 0, -10) - 270), '<', 1e-9, 'due west');

# destination is the inverse of distance + bearing
for my $case ([-33.8, 151.3, 160, 2_500_000], [10, -170, 280, 4_000_000], [60, 0, 45, 1_000_000]) {
    my ($la, $lo) = destination(@$case);
    cmp_ok(abs(gc_dist($case->[0], $case->[1], $la, $lo) - $case->[3]), '<', 1, "destination distance @$case");
    cmp_ok(ang_diff(bearing($case->[0], $case->[1], $la, $lo), $case->[2]), '<', 1e-6, "destination bearing @$case");
}
my ($mla, $mlo) = along(0, 0, 0, 90, 0.5);
cmp_ok(abs($mlo - 45) + abs($mla), '<', 1e-6, 'half way along the equator');

is(ang_diff(350, 10), 20, 'angle across north');
is(ang_diff(10, 350), 20, 'symmetric');
is(ang_diff(0, 180), 180, 'opposite');
is(ang_diff(720, 0), 0, 'whole turns');

# Trilateration: three buoys and exact distances find the storm
my @storm = (-50, 170);
my @buoys = ([-34, 151.5], [-28.8, 153.7], [-37.3, 150.2]);
my @obs = map {
    { lat => $_->[0], lon => $_->[1], d => gc_dist(@$_, @storm), sd => 50_000, dir_sd => 12 }
} @buoys;
my $w = locate(\@obs);
cmp_ok(gc_dist($w->{lat}, $w->{lon}, @storm), '<', 20_000, 'storm found within 20 km');

# Two buoys, no directions: two mirror answers, and both must be reported
my @two = @obs[0, 1];
my $w2 = locate(\@two);
ok($w2->{alt}, 'mirror answer reported');
my @near = sort { $a <=> $b } map { gc_dist($_->{lat}, $_->{lon}, @storm) } $w2, $w2->{alt};
cmp_ok($near[0], '<', 50_000, 'one of the two is the storm');

# ... and a direction from one buoy picks the right one
$two[0]{dir} = bearing(@{ $buoys[0] }, @storm);
my $w3 = locate(\@two);
ok(!$w3->{alt}, 'direction removes the mirror');
cmp_ok(gc_dist($w3->{lat}, $w3->{lon}, @storm), '<', 50_000, 'and keeps the storm');

# One buoy plus a direction is enough
my $w4 = locate([{ %{ $obs[0] }, dir => bearing(@{ $buoys[0] }, @storm) }]);
cmp_ok(gc_dist($w4->{lat}, $w4->{lon}, @storm), '<', 50_000, 'one buoy and a direction');

done_testing;
