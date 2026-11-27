package Farswell;
# Ties the pieces together: fit each buoy, fit all buoys with a shared storm
# time, locate the storm, bootstrap the uncertainty, forecast a beach.
use strict;
use warnings;
use Carp qw(croak);
use Exporter qw(import);
use Farswell::Physics qw(fit_buoy joint_fit bootstrap arrival_time median);
use Farswell::Geo qw(locate gc_dist);

our $VERSION   = '1.0.0';
our @EXPORT_OK = qw(analyse forecast percentile);

sub percentile {
    my ($p, @v) = @_;
    return unless @v;
    my @s = sort { $a <=> $b } @v;
    my $i = $p * $#s;
    my $lo = int $i;
    my $hi = $lo < $#s ? $lo + 1 : $lo;
    return $s[$lo] + ($s[$hi] - $s[$lo]) * ($i - $lo);
}

sub _obs_for_locate {
    my ($buoys, $dists, $sds) = @_;
    my @o;
    for my $i (0 .. $#$buoys) {
        my $bu   = $buoys->[$i];
        my @dirs = map { $_->{dir} } grep { $_->{inlier} && defined $_->{dir} } @{ $bu->{obs} };
        my $dir;
        if (@dirs) {    # circular mean of reported directions
            my ($sx, $sy) = (0, 0);
            for (@dirs) { $sx += cos($_ * 0.0174532925199433); $sy += sin($_ * 0.0174532925199433) }
            $dir = atan2($sy, $sx) / 0.0174532925199433;
            $dir += 360 if $dir < 0;
        }
        push @o, {
            lat => $bu->{lat}, lon => $bu->{lon}, d => $dists->[$i],
            sd  => $sds->[$i], dir => $dir, dir_sd => 12,
        };
    }
    return \@o;
}

sub analyse {
    my ($buoys, %opt) = @_;
    my $reps = $opt{reps} // 200;
    croak 'reps must be 0..1000' if $reps !~ /^\d+$/ || $reps > 1000;
    my $seed = $opt{seed} // 1;

    my $tref = $buoys->[0]{obs}[0]{t};
    my @single = map { fit_buoy($_, $tref) } @$buoys;

    my @sets = map {
        my @in = grep { $_->{inlier} } @{ $_->{obs} };
        { t => [map { $_->{t} } @in], f => [map { 1 / $_->{T} } @in] }
    } @$buoys;
    my $fit = joint_fit(\@sets);
    croak 'the readings do not fit one storm (a buoy\'s period is not falling)'
      if grep { !defined } @{ $fit->{dists} };

    my $boot = $reps ? bootstrap(\@sets, $fit, $reps, $seed) : [];
    my (@sd, @dlo, @dhi);
    for my $i (0 .. $#$buoys) {
        my @d = map { $_->{dists}[$i] } @$boot;
        my $d = $fit->{dists}[$i];
        my $s = @d > 2 ? (percentile(0.84, @d) - percentile(0.16, @d)) / 2 : 0;
        # never trust the storm position to better than 3% or 50 km: the
        # storm is hundreds of kilometres across, not a point
        my $floor = 0.03 * $d;
        $floor = 50_000 if $floor < 50_000;
        push @sd, ($s > $floor ? $s : $floor);
        push @dlo, @d ? percentile(0.05, @d) : undef;
        push @dhi, @d ? percentile(0.95, @d) : undef;
    }
    my @t0s = map { $_->{t0} } @$boot;

    my $obs  = _obs_for_locate($buoys, $fit->{dists}, \@sd);
    my $nbuoy = @$buoys;
    my $ndir  = grep { defined $_->{dir} } @$obs;
    my $where;
    if ($nbuoy >= 2 || $ndir >= 1) {
        $where = locate($obs);
        my @cloud;
        for my $bf (@$boot) {
            my $o = _obs_for_locate($buoys, $bf->{dists}, \@sd);
            my $p = locate($o, $where);
            push @cloud, [$p->{lat}, $p->{lon}, $bf->{t0}];
        }
        $where->{cloud} = \@cloud;
        my @km = map { gc_dist($_->[0], $_->[1], $where->{lat}, $where->{lon}) } @cloud;
        $where->{r90} = @km ? percentile(0.9, @km) : undef;
    }

    my @warn;
    push @warn, 'the storm time sits at the edge of the 20-day search window; '
      . 'the swell may not be from one storm' if $fit->{edge};
    my @single_t0 = map { $_->{t0} } @single;
    if (@single_t0 > 1) {
        my @s = sort { $a <=> $b } @single_t0;
        push @warn, sprintf('buoys alone disagree on the storm time by %.0f h; '
              . 'they may be seeing different storms', ($s[-1] - $s[0]) / 3600)
          if $s[-1] - $s[0] > 36 * 3600;
    }
    if ($where && $where->{alt}) {
        push @warn, 'two places fit about equally well (a mirror image across '
          . 'the line of buoys); give swell directions to choose';
    }
    if ($where && !$where->{alt} && $nbuoy >= 2) {
        my $chi = $where->{cost} / ($nbuoy + $ndir);
        push @warn, sprintf('the buoys\' distances do not quite meet at one '
              . 'point (misfit %.1f per reading); a moving storm or a wrong '
              . 'buoy position can do this', $chi) if $chi > 4;
    }

    return {
        buoys  => $buoys,
        single => \@single,
        fit    => $fit,
        sd     => \@sd,
        dlo    => \@dlo,
        dhi    => \@dhi,
        t0lo   => @t0s ? percentile(0.05, @t0s) : undef,
        t0hi   => @t0s ? percentile(0.95, @t0s) : undef,
        where  => $where,
        warn   => \@warn,
        reps   => scalar @$boot,
    };
}

# When each period reaches a beach, with a 90% band from the bootstrap cloud.
sub forecast {
    my ($res, $beach, @periods) = @_;
    my $w = $res->{where} or croak 'need a storm position to forecast a beach';
    my $d = gc_dist($w->{lat}, $w->{lon}, $beach->{lat}, $beach->{lon});
    my @rows;
    for my $T (@periods) {
        my $t = arrival_time($res->{fit}{t0}, $d, $T);
        my @bt = map {
            arrival_time($_->[2], gc_dist($_->[0], $_->[1], $beach->{lat}, $beach->{lon}), $T)
        } @{ $w->{cloud} || [] };
        push @rows, {
            T  => $T, t => $t,
            lo => @bt ? percentile(0.05, @bt) : undef,
            hi => @bt ? percentile(0.95, @bt) : undef,
        };
    }
    return { dist => $d, rows => \@rows };
}

1;
