package Downthrow::Fault;
# Is the horizon broken by a fault? Tries every straight vertical fault line that splits the
# points, fits "one tilted bed, stepped down on one side" to each split, and keeps the best.
# Because the best of thousands of splits will always look a little better than one plane, the
# evidence is judged against simulated unfaulted surveys searched the same way (a parametric
# bootstrap), so the search itself is accounted for.
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
use Downthrow::Plane qw(solve);

our @EXPORT_OK = qw(best_split search MIN_POINTS MAX_POINTS);

use constant MIN_POINTS => 8;     # at least 3 a side plus a few to spare
use constant MAX_POINTS => 120;   # keeps the bootstrap search to a few seconds
use constant STEP       => 2;     # degrees between trial fault directions
use constant SIMS       => 99;
use constant PI         => 4 * atan2(1, 1);

# Best single split of points (x, y, z already centred) into two sides. Returns undef if none.
# The model z = a + b x + c y + d s (s = 1 on one side) is fitted from running sums, so each
# split costs one 4 x 4 solve however many points there are.
sub best_split {
    my ($pts, $want_range) = @_;
    my $n = @$pts;
    my %S = (n => $n);
    for my $p (@$pts) {
        my ($x, $y, $z) = @$p{qw(x y z)};
        $S{x} += $x; $S{y} += $y; $S{z} += $z;
        $S{xx} += $x * $x; $S{xy} += $x * $y; $S{yy} += $y * $y;
        $S{xz} += $x * $z; $S{yz} += $y * $z; $S{zz} += $z * $z;
    }
    my ($best, %per);
    for (my $theta = 0; $theta < 180; $theta += STEP) {
        # The fault line runs along azimuth theta; points are ordered across it.
        my $t = $theta * PI / 180;
        my ($nx, $ny) = (cos($t), -sin($t));
        my @order = sort { $a->[0] <=> $b->[0] } map { [ $_->{x} * $nx + $_->{y} * $ny, $_ ] } @$pts;
        my %B = (n => 0, x => 0, y => 0, z => 0);
        for my $k (reverse 1 .. $n - 1) {
            my $p = $order[$k][1];
            $B{n}++; $B{x} += $p->{x}; $B{y} += $p->{y}; $B{z} += $p->{z};
            next if $B{n} < 3 || $n - $B{n} < 3;
            next if $order[$k][0] - $order[$k - 1][0] < 1e-9;   # can't split between equal positions
            my $A = [
                [ $S{n}, $S{x},  $S{y},  $B{n} ],
                [ $S{x}, $S{xx}, $S{xy}, $B{x} ],
                [ $S{y}, $S{xy}, $S{yy}, $B{y} ],
                [ $B{n}, $B{x},  $B{y},  $B{n} ],
            ];
            my $rhs = [ $S{z}, $S{xz}, $S{yz}, $B{z} ];
            my $beta = solve($A, $rhs) or next;
            my $rss = $S{zz};
            $rss -= $beta->[$_] * $rhs->[$_] for 0 .. 3;
            $rss = 0 if $rss < 0;
            if (!$best || $rss < $best->{rss}) {
                $best = { rss => $rss, theta => $theta, beta => $beta, cut => ($order[$k][0] + $order[$k - 1][0]) / 2,
                          normal => [ $nx, $ny ], high_side => $B{n} };
            }
            # Remember which split each direction found, to report how well the trend is pinned down.
            if ($want_range && (!$per{$theta} || $rss < $per{$theta}{rss})) {
                $per{$theta} = { rss => $rss, high => [ map { $_->[1] } @order[$k .. $n - 1] ] };
            }
        }
    }
    if ($best && $want_range) {
        # The same split of the points from other directions is the same evidence: the true trend
        # could be any of them. A split is named by the side that holds the first point.
        my %index = map { ($pts->[$_] => $_) } 0 .. $n - 1;
        my $key = sub {
            my %high = map { ($index{$_} => 1) } @{ $_[0] };
            return join ',', grep { ($high{$_} ? 1 : 0) == ($high{0} ? 1 : 0) } 0 .. $n - 1;
        };
        my $target = $key->($per{ $best->{theta} }{high});
        my @same = sort { $a <=> $b } grep { $key->($per{$_}{high}) eq $target } keys %per;
        $best->{trend_range} = _circular_range(\@same);
    }
    return $best;
}

# The tightest arc (on a 180-degree circle of line directions) holding all the given angles.
sub _circular_range {
    my ($angles) = @_;
    return [ $angles->[0], $angles->[0] ] if @$angles == 1;
    my ($gap, $after) = (-1, 0);
    for my $i (0 .. $#$angles) {
        my $next = $i == $#$angles ? $angles->[0] + 180 : $angles->[ $i + 1 ];
        if ($next - $angles->[$i] > $gap) { $gap = $next - $angles->[$i]; $after = $i }
    }
    my $start = $angles->[ ($after + 1) % @$angles ];
    return [ $start, $angles->[$after] ];
}

# A small, seeded random number generator, so reports are repeatable everywhere.
sub _rng {
    my $state = shift;
    return sub {
        $state = ($state * 1103515245 + 12345) % 2147483648;
        return ($state + 0.5) / 2147483648;
    };
}

# Full search with significance. $fit is the single-plane fit (Plane::fit_plane) of $points.
sub search {
    my ($points, $fit, %opt) = @_;
    my $n = @$points;
    return { tested => 0, reason => 'needs at least 8 points' } if $n < MIN_POINTS;
    return { tested => 0, reason => 'skipped above 120 points' } if $n > MAX_POINTS;
    my @c = map { { x => $_->{x} - $fit->{x0}, y => $_->{y} - $fit->{y0}, z => $_->{z} } } @$points;
    my $best = best_split(\@c, 1) or return { tested => 0, reason => 'no usable split' };
    my $F = _f_stat($fit->{rss}, $best->{rss}, $n);

    # How big an F does the search find in surveys that have no fault at all?
    my $sims = $opt{sims} // SIMS;
    my $rand = _rng($opt{seed} // 20261028);
    my $exceed = 0;
    for (1 .. $sims) {
        my @sim = map {
            my ($u1, $u2) = ($rand->(), $rand->());
            my $noise = $fit->{sigma} * sqrt(-2 * log($u1)) * cos(2 * PI * $u2);
            { x => $_->{x}, y => $_->{y}, z => $fit->{a} + $fit->{b} * $_->{x} + $fit->{c} * $_->{y} + $noise }
        } @c;
        my ($rss1) = _plane_rss(\@sim);
        my $b = best_split(\@sim) or next;
        $exceed++ if _f_stat($rss1, $b->{rss}, $n) >= $F;
    }
    my $p = (1 + $exceed) / (1 + $sims);

    # Covariance shape of the faulted model, for prediction errors.
    my @XtX = map { [0, 0, 0, 0] } 1 .. 4;
    for my $q (@c) {
        my @r = (1, $q->{x}, $q->{y}, side_of({ normal => $best->{normal}, cut => $best->{cut} }, { x0 => 0, y0 => 0 }, $q->{x}, $q->{y}));
        for my $i (0 .. 3) { $XtX[$i][$_] += $r[$i] * $r[$_] for 0 .. 3 }
    }
    my $inv = Downthrow::Plane::_inverse(\@XtX);
    my $throw = $best->{beta}[3];
    my ($nx, $ny) = @{ $best->{normal} };
    return {
        tested => 1, F => $F, p => $p, sims => $sims, theta => $best->{theta}, trend_range => $best->{trend_range},
        upthrown_ids => undef,
        throw => abs($throw),
        # The side that moved down: towards the normal if the high side's step is negative.
        down_azimuth => _azimuth($throw < 0 ? ($nx, $ny) : (-$nx, -$ny)),
        point => [ $fit->{x0} + $best->{cut} * $nx, $fit->{y0} + $best->{cut} * $ny ],
        rss => $best->{rss}, beta => $best->{beta}, normal => $best->{normal}, cut => $best->{cut},
        sigma => sqrt($best->{rss} / ($n - 4)), inv => $inv,
    };
}

sub _f_stat {
    my ($rss1, $rss2, $n) = @_;
    return 1e12 if $rss2 <= 1e-12 * ($rss1 + 1e-300);
    return (($rss1 - $rss2) / 1) / ($rss2 / ($n - 4));
}

sub _plane_rss {
    my ($pts) = @_;
    my $fit = Downthrow::Plane::fit_plane([ map { { %$_ } } @$pts ]);
    return $fit ? $fit->{rss} : 0;
}

sub _azimuth {
    my ($dx, $dy) = @_;
    my $a = atan2($dx, $dy) * 180 / PI;
    return $a < 0 ? $a + 360 : $a;
}

# Elevation of the faulted surface at (x, y), with the standard error of a new observation.
sub predict {
    my ($f, $fit, $x, $y) = @_;
    my @r = (1, $x - $fit->{x0}, $y - $fit->{y0}, side_of($f, $fit, $x, $y));
    my $z = 0;
    $z += $f->{beta}[$_] * $r[$_] for 0 .. 3;
    my $q = 0;
    for my $i (0 .. 3) { $q += $r[$i] * $f->{inv}[$i][$_] * $r[$_] for 0 .. 3 }
    return ($z, $f->{sigma} * sqrt(1 + $q));
}

# Which side of the fault (x, y) is on: 1 on the side that the step d applies to.
sub side_of {
    my ($f, $fit, $x, $y) = @_;
    my $q = ($x - $fit->{x0}) * $f->{normal}[0] + ($y - $fit->{y0}) * $f->{normal}[1];
    return $q > $f->{cut} ? 1 : 0;
}

1;
