package Downthrow::Plane;
# Least-squares planes through survey points, and how to read them as a geologist would:
# dip (how steeply the bed tilts), dip direction (which way it goes down) and strike.
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
use POSIX qw(floor);

our @EXPORT_OK = qw(solve fit_plane attitude attitude_errors apparent_dip predict compass);

use constant PI => 4 * atan2(1, 1);
sub _deg { return $_[0] * 180 / PI }
sub _rad { return $_[0] * PI / 180 }

# Gaussian elimination with partial pivoting. Returns the solution, or undef if (nearly) singular.
sub solve {
    my ($A, $b) = @_;
    my $n = @$b;
    my @m = map { [ @{ $A->[$_] }, $b->[$_] ] } 0 .. $n - 1;
    my $scale = 0;
    for my $row (@$A) { for (@$row) { $scale = abs($_) if abs($_) > $scale } }
    return undef if $scale == 0;
    for my $col (0 .. $n - 1) {
        my $p = $col;
        for my $r ($col + 1 .. $n - 1) { $p = $r if abs($m[$r][$col]) > abs($m[$p][$col]) }
        return undef if abs($m[$p][$col]) < 1e-10 * $scale;
        @m[$col, $p] = @m[$p, $col];
        for my $r (0 .. $n - 1) {
            next if $r == $col;
            my $f = $m[$r][$col] / $m[$col][$col];
            next if $f == 0;
            $m[$r][$_] -= $f * $m[$col][$_] for $col .. $n;
        }
    }
    return [ map { $m[$_][$n] / $m[$_][$_] } 0 .. $n - 1 ];
}

sub _inverse {
    my ($A) = @_;
    my $n = @$A;
    my @cols;
    for my $k (0 .. $n - 1) {
        my $col = solve($A, [ map { $_ == $k ? 1 : 0 } 0 .. $n - 1 ]) or return undef;
        push @cols, $col;
    }
    return [ map { my $i = $_; [ map { $cols[$_][$i] } 0 .. $n - 1 ] } 0 .. $n - 1 ];
}

# Fits z = a + b (x - x0) + c (y - y0) to the points. Coordinates are centred first so that big
# map coordinates (hundreds of thousands of metres) don't swamp the arithmetic.
sub fit_plane {
    my ($points) = @_;
    my $n = @$points;
    my ($x0, $y0) = (0, 0);
    $x0 += $_->{x} / $n for @$points;
    $y0 += $_->{y} / $n for @$points;
    my @XtX = ([0, 0, 0], [0, 0, 0], [0, 0, 0]);
    my @Xtz = (0, 0, 0);
    for my $p (@$points) {
        my @r = (1, $p->{x} - $x0, $p->{y} - $y0);
        for my $i (0 .. 2) {
            $Xtz[$i] += $r[$i] * $p->{z};
            $XtX[$i][$_] += $r[$i] * $r[$_] for 0 .. 2;
        }
    }
    my $inv = _inverse(\@XtX) or return undef;
    my @beta = map { my $i = $_; my $s = 0; $s += $inv->[$i][$_] * $Xtz[$_] for 0 .. 2; $s } 0 .. 2;
    my ($rss, $zbar, $tss) = (0, 0, 0);
    $zbar += $_->{z} / $n for @$points;
    for my $p (@$points) {
        my $r = $p->{z} - ($beta[0] + $beta[1] * ($p->{x} - $x0) + $beta[2] * ($p->{y} - $y0));
        $rss += $r * $r;
        $tss += ($p->{z} - $zbar)**2;
        $p->{residual} = $r;
    }
    my $df = $n - 3;
    my $sigma = $df > 0 ? sqrt($rss / $df) : 0;
    return {
        a => $beta[0], b => $beta[1], c => $beta[2], x0 => $x0, y0 => $y0,
        rss => $rss, sigma => $sigma, n => $n, df => $df, inv => $inv,
        r2 => $tss > 0 ? 1 - $rss / $tss : 1,
    };
}

# Dip, dip direction (degrees clockwise from north, the way the bed goes down) and strike
# (right-hand rule: dip direction minus 90) from the plane's slopes east (b) and north (c).
sub attitude {
    my ($b, $c) = @_;
    my $m = sqrt($b * $b + $c * $c);
    my $dip = _deg(atan2($m, 1));
    my $dir = $m > 0 ? _deg(atan2(-$b, -$c)) : 0;
    $dir -= 360 * floor($dir / 360);
    $dir = 0 if $dir > 360 - 1e-9;
    my $strike = $dir - 90;
    $strike += 360 if $strike < 0;
    return { dip => $dip, dipdir => $dir, strike => $strike, gradient => $m };
}

# Uncertainty of dip and dip direction from the slopes' covariance (the delta method).
sub attitude_errors {
    my ($fit) = @_;
    return (undef, undef) unless $fit->{df} > 0;
    my ($b, $c) = ($fit->{b}, $fit->{c});
    my $m = sqrt($b * $b + $c * $c);
    return (undef, undef) if $m == 0;
    my $s2 = $fit->{sigma}**2;
    my @V = ([ $s2 * $fit->{inv}[1][1], $s2 * $fit->{inv}[1][2] ], [ $s2 * $fit->{inv}[2][1], $s2 * $fit->{inv}[2][2] ]);
    my @u = ($b / $m, $c / $m);       # along the gradient
    my @v = (-$c / $m, $b / $m);      # across it
    my $quad = sub { my @w = @_; return $w[0] * ($V[0][0] * $w[0] + $V[0][1] * $w[1]) + $w[1] * ($V[1][0] * $w[0] + $V[1][1] * $w[1]) };
    my $sd_m = sqrt($quad->(@u));
    my $sd_dip = _deg($sd_m / (1 + $m * $m));
    my $sd_dir = _deg(sqrt($quad->(@v)) / $m);
    return ($sd_dip, $sd_dir);
}

# The dip you'd see in a vertical cross-section along a bearing.
sub apparent_dip {
    my ($dip, $dipdir, $bearing) = @_;
    return _deg(atan2(tan_deg($dip) * cos(_rad($bearing - $dipdir)), 1));
}

sub tan_deg { my $r = _rad($_[0]); return sin($r) / cos($r) }

# Elevation of the plane at (x, y), with the standard error of a new observation there.
sub predict {
    my ($fit, $x, $y) = @_;
    my @r = (1, $x - $fit->{x0}, $y - $fit->{y0});
    my $z = $fit->{a} + $fit->{b} * $r[1] + $fit->{c} * $r[2];
    my $q = 0;
    for my $i (0 .. 2) { $q += $r[$i] * $fit->{inv}[$i][$_] * $r[$_] for 0 .. 2 }
    return ($z, $fit->{sigma} * sqrt(1 + $q));
}

# 0-360 degrees to one of 16 compass points.
sub compass {
    my ($deg) = @_;
    my @p = qw(N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW);
    return $p[ floor(($deg % 360) / 22.5 + 0.5) % 16 ];
}

1;
