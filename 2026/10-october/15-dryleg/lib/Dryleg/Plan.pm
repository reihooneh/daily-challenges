package Dryleg::Plan;
# Time, temperature and water along the route, the carry plan, and the best start time.
use strict;
use warnings;
use Exporter qw(import);
use POSIX qw(floor);

our @EXPORT_OK = qw(temperature drink_rate walk plan best_start);

use constant {
    PI         => 4 * atan2(1, 1),
    COOLEST    => 6 * 60,     # the day's low, around dawn
    HOTTEST    => 15 * 60,    # the day's high, mid-afternoon
    CLIMB_RATE => 600,        # Naismith: an extra hour for every 600 m of climbing
    STEP       => 1,          # minutes per step when adding up water
};

# Air temperature at a time of day (minutes, may run past midnight): a smooth rise from
# the low at dawn to the high mid-afternoon, then a slower fall through the night.
sub temperature {
    my ($r, $t) = @_;
    my $tm = $t - 1440 * floor($t / 1440);
    my ($lo, $hi) = ($r->{low}, $r->{high});
    if ($tm >= COOLEST && $tm <= HOTTEST) {
        return $lo + ($hi - $lo) * (1 - cos(PI * ($tm - COOLEST) / (HOTTEST - COOLEST))) / 2;
    }
    my $since = $tm - HOTTEST;
    $since += 1440 if $since < 0;
    my $x = $since / (1440 - (HOTTEST - COOLEST));
    return $hi - ($hi - $lo) * (1 - cos(PI * $x)) / 2;
}

# Litres per hour while walking: about half a litre in mild weather, rising with the heat.
sub drink_rate {
    my ($temp) = @_;
    my $rate = 0.5 + 0.06 * ($temp > 20 ? $temp - 20 : 0);
    return $rate > 1.5 ? 1.5 : $rate;
}

# Walks the route from a start time: for each leg, when it starts and ends, the water
# drunk, and the coolest and hottest moments.
sub walk {
    my ($r, $start) = @_;
    my $pts = $r->{points};
    my $t = $start;
    my @legs;
    for my $i (1 .. $#$pts) {
        my ($a, $b) = @$pts[$i - 1, $i];
        my $minutes = 60 * (($b->{km} - $a->{km}) / $r->{pace} + $b->{up} / CLIMB_RATE);
        my ($litres, $tmin, $tmax) = (0, 999, -999);
        for (my $m = 0; $m < $minutes; $m += STEP) {
            my $step = $minutes - $m < STEP ? $minutes - $m : STEP;
            my $temp = temperature($r, $t + $m + $step / 2);
            $litres += drink_rate($temp) * $step / 60;
            $tmin = $temp if $temp < $tmin;
            $tmax = $temp if $temp > $tmax;
        }
        push @legs, { from => $a, to => $b, start => $t, minutes => $minutes, litres => $litres,
                      tmin => $tmin, tmax => $tmax };
        $t += $minutes;
    }
    return \@legs;
}

# A source you can count on: always the start, then reliable ones (and seasonal ones if
# you said to trust them). Unreliable sources are never counted on.
sub trusted {
    my ($r, $p, $is_start) = @_;
    return 1 if $is_start;
    return 0 unless $p->{kind} eq 'water';
    return 1 if $p->{reliability} eq 'reliable';
    return $r->{trust} eq 'seasonal' && $p->{reliability} eq 'seasonal';
}

# The carry plan: at each source you can count on, how much to carry to reach the next one.
sub plan {
    my ($r, $start) = @_;
    my $legs = walk($r, $start);
    my @fills;
    my $current;
    for my $i (0 .. $#$legs) {
        my $leg = $legs->[$i];
        if (trusted($r, $leg->{from}, $i == 0)) {
            $current = { at => $leg->{from}, litres => $r->{reserve}, minutes => 0, start => $leg->{start},
                         tmin => 999, tmax => -999, passing => [] };
            push @fills, $current;
        } elsif ($leg->{from}{kind} eq 'water') {
            push @{ $current->{passing} }, $leg->{from};
        }
        $current->{litres}  += $leg->{litres};
        $current->{minutes} += $leg->{minutes};
        $current->{to}       = $leg->{to};
        $current->{tmin} = $leg->{tmin} if $leg->{tmin} < $current->{tmin};
        $current->{tmax} = $leg->{tmax} if $leg->{tmax} > $current->{tmax};
    }
    my ($most, $total) = (0, 0);
    $total += $_->{litres} for @$legs;
    for (@fills) { $most = $_->{litres} if $_->{litres} > $most }
    my $arrive = $start + ($legs->[-1]{start} - $start) + $legs->[-1]{minutes};
    return { start => $start, legs => $legs, fills => \@fills, most => $most, drunk => $total,
             arrive => $arrive, too_heavy => $most > $r->{capacity} + 1e-9, after_dark => $arrive > $r->{dark} };
}

# Tries every start from first light to 13:00 in quarter hours (no stumbling about in the
# dark). Best: finish before dark if possible, then the lightest heaviest carry, then the
# least water, then the latest start (more sleep).
sub best_start {
    my ($r) = @_;
    my $best;
    my $last = $r->{light} > 13 * 60 ? $r->{light} : 13 * 60;
    for (my $s = $r->{light}; $s <= $last; $s += 15) {
        my $p = plan($r, $s);
        my $key = sub { my ($q) = @_; ($q->{after_dark} ? 1 : 0, sprintf('%.1f', $q->{most}) + 0, $q->{drunk}) };
        if (!$best) { $best = $p; next }
        my @a = $key->($p);
        my @b = $key->($best);
        my $cmp = $a[0] <=> $b[0] || $a[1] <=> $b[1] || ($a[2] < $b[2] - 0.05 ? -1 : $a[2] > $b[2] + 0.05 ? 1 : 0);
        $best = $p if $cmp < 0 || $cmp == 0;    # ties: the later start wins
    }
    return $best;
}

1;
