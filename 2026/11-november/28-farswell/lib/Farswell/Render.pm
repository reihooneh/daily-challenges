package Farswell::Render;
# Plain-text output: a frequency-time chart (the straight lines the physics
# predicts), a table per buoy, a text map of buoys and storm, and a forecast.
use strict;
use warnings;
use POSIX qw(strftime floor);
use Exporter qw(import);
use Farswell::Geo qw(along);
use Farswell ();

our @EXPORT_OK = qw(report fmt_time chart map_text);

sub fmt_time {
    my ($t, $tz) = @_;
    $tz //= 0;
    my $s = strftime('%a %d %b %H:%M', gmtime($t + $tz * 3600));
    return $s . ($tz ? sprintf(' UTC%+g', $tz) : ' UTC');
}

sub _symbols {
    my ($buoys) = @_;
    my (%used, @sym);
    for my $bu (@$buoys) {
        my ($c) = grep { !$used{$_} } (uc substr($bu->{name}, 0, 1)), 'A' .. 'Z';
        $used{$c} = 1;
        push @sym, $c;
    }
    return @sym;
}

# Frequency (mHz) up the side, hours along the bottom. A single swell from a
# single storm is a straight line through the storm time on the axis.
sub chart {
    my ($res, $tz, $W, $H) = @_;
    ($W, $H) = (60, 14) unless $W;
    my $buoys = $res->{buoys};
    my @sym   = _symbols($buoys);
    my $t0    = $res->{fit}{t0};
    my ($tmin, $tmax, $fmin, $fmax);
    for my $bu (@$buoys) {
        for my $o (@{ $bu->{obs} }) {
            my $f = 1000 / $o->{T};
            $tmin = $o->{t} if !defined $tmin || $o->{t} < $tmin;
            $tmax = $o->{t} if !defined $tmax || $o->{t} > $tmax;
            $fmin = $f if !defined $fmin || $f < $fmin;
            $fmax = $f if !defined $fmax || $f > $fmax;
        }
    }
    my $pad = ($fmax - $fmin) * 0.08 || 1;
    ($fmin, $fmax) = ($fmin - $pad, $fmax + $pad);
    $tmax = $tmin + 3600 if $tmax <= $tmin;
    my @g = map { [(' ') x $W] } 1 .. $H;
    my $col = sub { my $c = int(($_[0] - $tmin) / ($tmax - $tmin) * ($W - 1) + 0.5); $c };
    my $row = sub { my $r = int(($fmax - $_[0]) / ($fmax - $fmin) * ($H - 1) + 0.5); $r };
    for my $i (0 .. $#$buoys) {    # fitted lines first, points on top
        my $a = $res->{fit}{slopes}[$i];
        for my $c (0 .. $W - 1) {
            my $t = $tmin + ($tmax - $tmin) * $c / ($W - 1);
            my $r = $row->(1000 * $a * ($t - $t0));
            $g[$r][$c] = '.' if $r >= 0 && $r < $H && $g[$r][$c] eq ' ';
        }
    }
    for my $i (0 .. $#$buoys) {
        for my $o (@{ $buoys->[$i]{obs} }) {
            my ($r, $c) = ($row->(1000 / $o->{T}), $col->($o->{t}));
            next if $r < 0 || $r >= $H || $c < 0 || $c >= $W;
            $g[$r][$c] = $o->{inlier} ? $sym[$i] : 'x';
        }
    }
    my @out;
    push @out, '  mHz  period';
    for my $r (0 .. $H - 1) {
        my $f = $fmax - ($fmax - $fmin) * $r / ($H - 1);
        my $lab = ($r % 3 == 0) ? sprintf('%5.1f %5.1fs |', $f, 1000 / $f) : (' ' x 13) . '|';
        push @out, $lab . join('', @{ $g[$r] });
    }
    push @out, (' ' x 13) . '+' . ('-' x $W);
    my $hrs = ($tmax - $tmin) / 3600;
    my $mid = sprintf('%.0f h', $hrs / 2);
    my $end = sprintf('%.0f h', $hrs);
    my $axis = '0 h' . (' ' x (int($W / 2) - 3 - int(length($mid) / 2))) . $mid;
    $axis .= ' ' x ($W - length($axis) - length($end)) . $end;
    push @out, (' ' x 14) . $axis . '   after ' . fmt_time($tmin, $tz);
    push @out, '              ' . join('  ', map { "$sym[$_] $buoys->[$_]{name}" } 0 .. $#$buoys)
      . '   x outlier   . fitted line';
    return join("\n", @out) . "\n";
}

# Equirectangular text map around everything we know about.
sub map_text {
    my ($res, $beach, $W, $H) = @_;
    ($W, $H) = (64, 22) unless $W;
    my $w = $res->{where} or return '';
    my $buoys = $res->{buoys};
    my @sym = _symbols($buoys);
    my $lon0 = $w->{lon};    # unwrap longitudes around the storm
    my $u = sub { my $l = $_[0]; $l += 360 while $l - $lon0 > 180; $l -= 360 while $l - $lon0 < -180; $l };
    my @pts = ([$w->{lat}, $w->{lon}]);
    push @pts, map { [$_->{lat}, $_->{lon}] } @$buoys;
    push @pts, [$beach->{lat}, $beach->{lon}] if $beach;
    push @pts, [$w->{alt}{lat}, $w->{alt}{lon}] if $w->{alt};
    my ($la1, $la2, $lo1, $lo2) = (90, -90, 1e9, -1e9);
    for my $p (@pts) {
        my $lo = $u->($p->[1]);
        $la1 = $p->[0] if $p->[0] < $la1;
        $la2 = $p->[0] if $p->[0] > $la2;
        $lo1 = $lo if $lo < $lo1;
        $lo2 = $lo if $lo > $lo2;
    }
    $la1 = floor(($la1 - 4) / 5) * 5;
    $la2 = floor(($la2 + 4) / 5 + 1) * 5;
    $lo1 = floor(($lo1 - 6) / 5) * 5;
    $lo2 = floor(($lo2 + 6) / 5 + 1) * 5;
    my @g = map { [(' ') x $W] } 1 .. $H;
    my $put = sub {
        my ($la, $lo, $ch, $soft) = @_;
        $lo = $u->($lo);
        my $c = int(($lo - $lo1) / ($lo2 - $lo1) * ($W - 1) + 0.5);
        my $r = int(($la2 - $la) / ($la2 - $la1) * ($H - 1) + 0.5);
        return if $r < 0 || $r >= $H || $c < 0 || $c >= $W;
        return if $soft && $g[$r][$c] ne ' ' && $g[$r][$c] ne '.';
        $g[$r][$c] = $ch;
    };
    for my $r (0 .. $H - 1) {    # faint graticule every 10 degrees
        for my $c (0 .. $W - 1) {
            my $la = $la2 - ($la2 - $la1) * $r / ($H - 1);
            my $lo = $lo1 + ($lo2 - $lo1) * $c / ($W - 1);
            my $step_la = ($la2 - $la1) / ($H - 1) / 2;
            my $step_lo = ($lo2 - $lo1) / ($W - 1) / 2;
            my $on_la = abs($la - 10 * floor($la / 10 + 0.5)) < $step_la;
            my $on_lo = abs($lo - 10 * floor($lo / 10 + 0.5)) < $step_lo;
            $g[$r][$c] = $on_la && $on_lo ? '+' : ' ';
        }
    }
    for my $bu (@$buoys, ($beach ? $beach : ())) {    # swell paths
        for my $k (1 .. 59) {
            $put->(along($w->{lat}, $w->{lon}, $bu->{lat}, $bu->{lon}, $k / 60), '.', 1);
        }
    }
    $put->($_->[0], $_->[1], 'o', 1) for @{ $w->{cloud} || [] };
    $put->($w->{alt}{lat}, $w->{alt}{lon}, '?') if $w->{alt};
    $put->($beach->{lat}, $beach->{lon}, '@') if $beach;
    $put->($buoys->[$_]{lat}, $buoys->[$_]{lon}, $sym[$_]) for 0 .. $#$buoys;
    $put->($w->{lat}, $w->{lon}, '*');
    my @out;
    for my $r (0 .. $H - 1) {
        my $la = $la2 - ($la2 - $la1) * $r / ($H - 1);
        my $lab = ($r == 0 || $r == $H - 1 || $r == int($H / 2))
          ? sprintf('%6.1f%s |', abs($la), $la < 0 ? 'S' : 'N') : (' ' x 7) . ' |';
        push @out, $lab . join('', @{ $g[$r] }) . '|';
    }
    my $fl = sub { my $l = $_[0]; $l -= 360 while $l > 180; $l += 360 while $l <= -180;
                   sprintf('%.0f%s', abs($l), $l < 0 ? 'W' : 'E') };
    my $bot = (' ' x 9) . $fl->($lo1);
    my $right = $fl->($lo2);
    $bot .= ' ' x (9 + $W - length($bot) - length($right)) . $right;
    push @out, (' ' x 8) . '+' . ('-' x $W) . '+', $bot;
    push @out, '         * storm   o bootstrap refits   . swell path'
      . ($beach ? '   @ ' . $beach->{name} : '') . ($w->{alt} ? '   ? mirror fit' : '')
      . '   + 10-degree grid';
    return join("\n", @out) . "\n";
}

sub _ll {
    my ($la, $lo) = @_;
    return sprintf('%.1f%s %.1f%s', abs($la), $la < 0 ? 'S' : 'N', abs($lo), $lo < 0 ? 'W' : 'E');
}

sub report {
    my ($res, %o) = @_;
    my $tz = $o{tz} // 0;
    my $buoys = $res->{buoys};
    my $fit = $res->{fit};
    my @L;
    push @L, 'FARSWELL - where the swell came from', '';
    push @L, 'Frequency against time. Each swell from one storm is a straight line;',
      'the steeper the line, the closer the storm.', '';
    push @L, chart($res, $tz);
    push @L, '', 'BUOYS';
    push @L, sprintf('  %-12s %8s %8s  %-21s  %s', 'buoy', 'readings', 'outliers', 'storm distance', '90% range');
    for my $i (0 .. $#$buoys) {
        my $bu = $buoys->[$i];
        my $n = @{ $bu->{obs} };
        my $out = $n - $res->{single}[$i]{nin};
        my $d = $fit->{dists}[$i] / 1000;
        my $rng = defined $res->{dlo}[$i]
          ? sprintf('%5.0f - %5.0f km', $res->{dlo}[$i] / 1000, $res->{dhi}[$i] / 1000) : 'n/a';
        push @L, sprintf('  %-12s %8d %8d  %6.0f km (%4.0f h at 16 s) %s',
            $bu->{name}, $n, $out, $d, $d * 1000 / (9.80665 * 16 / (4 * 3.14159265358979)) / 3600, $rng);
    }
    push @L, '';
    push @L, sprintf('STORM  made this swell at %s', fmt_time($fit->{t0}, $tz));
    push @L, sprintf('       90%% range %s  to  %s', fmt_time($res->{t0lo}, $tz), fmt_time($res->{t0hi}, $tz))
      if defined $res->{t0lo};
    if (my $w = $res->{where}) {
        push @L, sprintf('       near %s%s', _ll($w->{lat}, $w->{lon}),
            defined $w->{r90} ? sprintf(', within %.0f km in 9 of 10 refits', $w->{r90} / 1000) : '');
        push @L, sprintf('       or near %s (mirror image)', _ll($w->{alt}{lat}, $w->{alt}{lon})) if $w->{alt};
        push @L, '', 'MAP', map_text($res, $o{beach});
    } else {
        push @L, '       position needs a second buoy or a swell direction';
    }
    if ($o{beach} && $res->{where}) {
        my $fc = Farswell::forecast($res, $o{beach}, @{ $o{periods} || [22, 20, 18, 16, 14, 12, 10] });
        push @L, '', sprintf('FORECAST for %s (%.0f km from the storm)', $o{beach}{name}, $fc->{dist} / 1000);
        push @L, sprintf('  %-7s %-26s %s', 'period', 'arrives', '90% window');
        for my $r (@{ $fc->{rows} }) {
            push @L, sprintf('  %4.0f s  %-26s %s', $r->{T}, fmt_time($r->{t}, $tz),
                defined $r->{lo} ? sprintf('%+.1f h / %+.1f h', ($r->{lo} - $r->{t}) / 3600, ($r->{hi} - $r->{t}) / 3600) : '');
        }
        push @L, '  (great-circle path; land in the way is not checked)';
    }
    if (@{ $res->{warn} }) {
        push @L, '', 'WARNINGS';
        push @L, map { "  - $_" } @{ $res->{warn} };
    }
    push @L, '', sprintf('Bootstrap: %d refits. Deep-water swell, spherical Earth, storm treated as one '
        . 'point in space and time.', $res->{reps});
    return join("\n", @L) . "\n";
}

1;
