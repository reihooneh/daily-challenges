package Farswell::Physics;
# Swell dispersion: in deep water a wave of period T travels in a group at
#   c_g = g T / (4 pi).
# A storm at distance d that made waves of every period at time t0 sends each
# period to the buoy at t = t0 + d / c_g, which rearranges to a straight line
#   f = 1/T = (g / (4 pi d)) * (t - t0).
# The slope gives the distance, the x-intercept gives when the storm blew.
use strict;
use warnings;
use Carp qw(croak);
use Exporter qw(import);

our @EXPORT_OK = qw(G group_speed theil_sen fit_buoy joint_fit bootstrap
  distance_from_slope arrival_time median rng);

use constant G  => 9.80665;
use constant PI => 4 * atan2(1, 1);

sub group_speed { my ($T) = @_; return G * $T / (4 * PI) }    # m/s

sub distance_from_slope {    # slope in Hz per second -> metres
    my ($slope) = @_;
    return unless $slope > 0;
    return G / (4 * PI * $slope);
}

sub arrival_time {    # epoch seconds
    my ($t0, $d, $T) = @_;
    return $t0 + $d / group_speed($T);
}

sub median {
    my @v = @_;
    my @s = sort { $a <=> $b } @v;
    return unless @s;
    my $m = int(@s / 2);
    return @s % 2 ? $s[$m] : ($s[$m - 1] + $s[$m]) / 2;
}

# Theil-Sen: the median of all pairwise slopes. Up to 29% of the points can
# be wild (a local wind sea, a second swell) without moving the line.
sub theil_sen {
    my ($x, $y) = @_;
    my $n = @$x;
    my @s;
    for my $i (0 .. $n - 2) {
        for my $j ($i + 1 .. $n - 1) {
            my $dx = $x->[$j] - $x->[$i];
            push @s, ($y->[$j] - $y->[$i]) / $dx if $dx != 0;
        }
    }
    croak 'need readings at two or more different times' unless @s;
    my $slope = median(@s);
    my $icpt  = median(map { $y->[$_] - $slope * $x->[$_] } 0 .. $n - 1);
    return ($slope, $icpt);
}

# Fits one buoy alone: robust line, then flags readings far from it.
sub fit_buoy {
    my ($buoy, $tref) = @_;
    my @x = map { $_->{t} - $tref } @{ $buoy->{obs} };
    my @y = map { 1 / $_->{T} } @{ $buoy->{obs} };
    my ($sa, $sb) = theil_sen(\@x, \@y);
    my @r   = map { $y[$_] - ($sa * $x[$_] + $sb) } 0 .. $#x;
    my $mad = 1.4826 * median(map { abs } @r);
    # A floor: buoys report periods to ~0.1 s, so never call a reading an
    # outlier for being off by less than about that.
    my $floor = 0.002;
    my $cut   = 3.5 * ($mad > $floor / 3.5 ? $mad : $floor / 3.5);
    $cut = $floor if $cut < $floor;
    my @in = map { abs($r[$_]) <= $cut ? 1 : 0 } 0 .. $#x;
    my $nin = grep { $_ } @in;
    croak "buoy $buoy->{name}: too few readings agree on one swell" if $nin < 3;
    croak "buoy $buoy->{name}: period is not falling over time, so this is not "
      . 'one arriving swell (wrong order of readings, or a local sea?)'
      unless $sa > 0;
    $_->{inlier} = shift @in for @{ $buoy->{obs} };
    return {
        slope => $sa,
        t0    => $tref - $sb / $sa,
        dist  => scalar distance_from_slope($sa),
        nin   => $nin,
    };
}

# All buoys saw the same storm, so they share one start time t0 while each has
# its own distance. For a fixed t0 each slope is a one-line least squares
# answer, so we only search one number: t0.
sub _slopes_for {
    my ($sets, $t0) = @_;
    my ($sse, @a) = (0);
    for my $s (@$sets) {
        my ($sxy, $sxx) = (0, 0);
        for my $k (0 .. $#{ $s->{t} }) {
            my $x = $s->{t}[$k] - $t0;
            $sxy += $x * $s->{f}[$k];
            $sxx += $x * $x;
        }
        my $sl = $sxy / $sxx;
        push @a, $sl;
        for my $k (0 .. $#{ $s->{t} }) {
            my $e = $s->{f}[$k] - $a[-1] * ($s->{t}[$k] - $t0);
            $sse += $e * $e;
        }
    }
    return ($sse, \@a);
}

sub joint_fit {
    my ($sets) = @_;    # [{t=>[...], f=>[...]}] inliers only
    my $tmin;
    for my $s (@$sets) {
        for (@{ $s->{t} }) { $tmin = $_ if !defined $tmin || $_ < $tmin }
    }
    my $hi = $tmin - 3600;           # storm blew at least an hour earlier
    my $lo = $tmin - 20 * 86400;     # and no more than 20 days (~half the globe)
    my $steps = 400;
    my ($best, $bt);
    for my $i (0 .. $steps) {
        my $t0 = $lo + ($hi - $lo) * $i / $steps;
        my ($e) = _slopes_for($sets, $t0);
        ($best, $bt) = ($e, $t0) if !defined $best || $e < $best;
    }
    # golden-section refinement inside the neighbouring grid cells
    my $h = ($hi - $lo) / $steps;
    my ($x0, $x1) = ($bt - $h, $bt + $h);
    $x0 = $lo if $x0 < $lo;
    $x1 = $hi if $x1 > $hi;
    my $gr = (sqrt(5) - 1) / 2;
    for (1 .. 60) {
        my $c = $x1 - $gr * ($x1 - $x0);
        my $d = $x0 + $gr * ($x1 - $x0);
        my ($ec) = _slopes_for($sets, $c);
        my ($ed) = _slopes_for($sets, $d);
        if ($ec < $ed) { $x1 = $d } else { $x0 = $c }
    }
    my $t0 = ($x0 + $x1) / 2;
    my ($sse, $a) = _slopes_for($sets, $t0);
    my $n = 0;
    $n += @{ $_->{t} } for @$sets;
    my $dof = $n - @$sets - 1;
    return {
        t0    => $t0,
        slopes => $a,
        dists => [map { scalar distance_from_slope($_) } @$a],
        rms   => sqrt($sse / ($dof > 0 ? $dof : 1)),
        edge  => ($t0 - $lo < 2 * $h || $hi - $t0 < 2 * $h) ? 1 : 0,
    };
}

# Small deterministic generator (xorshift64*) so bootstrap runs repeat exactly.
sub rng {
    my ($seed) = @_;
    my $s = ($seed // 1) & 0xFFFFFFFF;
    $s = 0x9E3779B9 if $s == 0;
    my @st = ($s, $s ^ 0x5DEECE66, 0x2545F491, 0x6C078965);
    return sub {    # xorshift128 on 32-bit words, returns [0,1)
        my $t = $st[3];
        $t ^= ($t << 11) & 0xFFFFFFFF;
        $t ^= $t >> 8;
        @st[1 .. 3] = @st[0 .. 2];
        $st[0] = ($t ^ $st[0] ^ ($st[0] >> 19)) & 0xFFFFFFFF;
        return $st[0] / 4294967296;
    };
}

# Residual bootstrap: keep the fitted lines, reshuffle each buoy's own
# misfits, fit again. The spread of the refits is the honest uncertainty.
sub bootstrap {
    my ($sets, $fit, $reps, $seed) = @_;
    my $r = rng($seed);
    my @out;
    my @res;
    for my $i (0 .. $#$sets) {
        my $s = $sets->[$i];
        push @res, [map {
            $s->{f}[$_] - $fit->{slopes}[$i] * ($s->{t}[$_] - $fit->{t0})
        } 0 .. $#{ $s->{t} }];
    }
    for (1 .. $reps) {
        my @ns;
        for my $i (0 .. $#$sets) {
            my $s  = $sets->[$i];
            my $rr = $res[$i];
            push @ns, {
                t => $s->{t},
                f => [map {
                    $fit->{slopes}[$i] * ($s->{t}[$_] - $fit->{t0})
                      + $rr->[int($r->() * @$rr)]
                } 0 .. $#{ $s->{t} }],
            };
        }
        my $bf = joint_fit(\@ns);
        next if grep { !defined } @{ $bf->{dists} };
        push @out, $bf;
    }
    return \@out;
}

1;
