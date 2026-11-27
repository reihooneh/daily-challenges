package Farswell::Geo;
# Great circles on a spherical Earth, and finding the storm: the point whose
# distance to every buoy matches what each buoy's swell says (trilateration),
# nudged by the direction each buoy saw the swell come from, if it reported one.
use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(R_EARTH gc_dist bearing destination along locate ang_diff);

use constant R_EARTH => 6_371_000;
use constant PI      => 4 * atan2(1, 1);
use constant D2R     => PI / 180;

sub _asin {
    my ($x) = @_;
    $x = 1 if $x > 1;
    $x = -1 if $x < -1;
    return atan2($x, sqrt(1 - $x * $x));
}

sub gc_dist {    # haversine, metres
    my ($la1, $lo1, $la2, $lo2) = @_;
    my ($p1, $p2) = ($la1 * D2R, $la2 * D2R);
    my $dp = $p2 - $p1;
    my $dl = ($lo2 - $lo1) * D2R;
    my $h = sin($dp / 2)**2 + cos($p1) * cos($p2) * sin($dl / 2)**2;
    return 2 * R_EARTH * _asin(sqrt($h));
}

sub bearing {    # initial bearing from point 1 to point 2, degrees 0..360
    my ($la1, $lo1, $la2, $lo2) = @_;
    my ($p1, $p2) = ($la1 * D2R, $la2 * D2R);
    my $dl = ($lo2 - $lo1) * D2R;
    my $y = sin($dl) * cos($p2);
    my $x = cos($p1) * sin($p2) - sin($p1) * cos($p2) * cos($dl);
    my $brg = atan2($y, $x) / D2R;
    return $brg < 0 ? $brg + 360 : $brg;
}

sub destination {    # from a point, along a bearing, for a distance
    my ($la, $lo, $brg, $d) = @_;
    my $p1 = $la * D2R;
    my $th = $brg * D2R;
    my $dr = $d / R_EARTH;
    my $p2 = _asin(sin($p1) * cos($dr) + cos($p1) * sin($dr) * cos($th));
    my $l2 = $lo * D2R
      + atan2(sin($th) * sin($dr) * cos($p1), cos($dr) - sin($p1) * sin($p2));
    my $lon = $l2 / D2R;
    $lon -= 360 while $lon > 180;
    $lon += 360 while $lon < -180;
    return ($p2 / D2R, $lon);
}

sub along {    # point a fraction of the way along the great circle
    my ($la1, $lo1, $la2, $lo2, $frac) = @_;
    my $d = gc_dist($la1, $lo1, $la2, $lo2);
    return ($la1, $lo1) if $d < 1;
    return destination($la1, $lo1, bearing($la1, $lo1, $la2, $lo2), $d * $frac);
}

sub ang_diff {    # smallest difference between two compass angles
    my ($x, $y) = @_;
    my $d = abs($x - $y);
    $d -= 360 while $d >= 360;
    return $d > 180 ? 360 - $d : $d;
}

# Misfit of a candidate storm position, in "standard deviations squared".
sub _cost {
    my ($la, $lo, $obs) = @_;
    my $c = 0;
    for my $o (@$obs) {
        my $e = (gc_dist($o->{lat}, $o->{lon}, $la, $lo) - $o->{d}) / $o->{sd};
        $c += $e * $e;
        if (defined $o->{dir}) {
            my $ea = ang_diff(bearing($o->{lat}, $o->{lon}, $la, $lo), $o->{dir})
              / $o->{dir_sd};
            $c += $ea * $ea;
        }
    }
    return $c;
}

# Compass (pattern) search downhill from a start point, step halving.
sub _refine {
    my ($la, $lo, $obs, $step) = @_;
    my $c = _cost($la, $lo, $obs);
    while ($step > 0.0005) {
        my $moved = 0;
        for my $d ([1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]) {
            my $nla = $la + $d->[0] * $step;
            next if $nla > 89.9 || $nla < -89.9;
            my $nlo = $lo + $d->[1] * $step / (cos($nla * D2R) || 1e-3);
            $nlo -= 360 while $nlo > 180;
            $nlo += 360 while $nlo < -180;
            my $nc = _cost($nla, $nlo, $obs);
            if ($nc < $c) { ($la, $lo, $c, $moved) = ($nla, $nlo, $nc, 1); last }
        }
        $step /= 2 unless $moved;
    }
    return { lat => $la, lon => $lo, cost => $c };
}

# Finds the best storm position and, if the geometry allows two answers (a
# mirror image across the line of buoys), the runner-up too.
#   $obs: [{lat, lon, d (m), sd (m), dir (deg or undef), dir_sd}]
#   $start: optional {lat, lon} to only refine (used by the bootstrap)
sub locate {
    my ($obs, $start) = @_;
    return _refine($start->{lat}, $start->{lon}, $obs, 1.0) if $start;
    my @grid;
    for (my $la = -80; $la <= 80; $la += 2) {
        for (my $lo = -180; $lo < 180; $lo += 2) {
            push @grid, [$la, $lo, _cost($la, $lo, $obs)];
        }
    }
    @grid = sort { $a->[2] <=> $b->[2] } @grid;
    my @found;
    for my $g (@grid[0 .. 59]) {
        next if grep { gc_dist($_->{lat}, $_->{lon}, $g->[0], $g->[1]) < 1_500_000 } @found;
        my $r = _refine($g->[0], $g->[1], $obs, 1.0);
        next if grep { gc_dist($_->{lat}, $_->{lon}, $r->{lat}, $r->{lon}) < 1_500_000 } @found;
        push @found, $r;
        last if @found >= 2;
    }
    @found = sort { $a->{cost} <=> $b->{cost} } @found;
    my $best = $found[0];
    # A rival only counts if it is about as good (within 4 units, roughly two
    # standard deviations).
    my $alt = (@found > 1 && $found[1]{cost} < $best->{cost} + 4) ? $found[1] : undef;
    return { %$best, alt => $alt };
}

1;
