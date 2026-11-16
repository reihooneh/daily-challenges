package Tallyhook::Count;
# Works each round into the one before: every stitch takes some of the previous round's
# stitches and makes new ones. Checks that the round uses up exactly what's there, that the
# count at the end matches what the pattern says, and notes where the increases fall.
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
use Tallyhook::Parse qw(MAX_TIMES);
our @EXPORT_OK = qw(tally MAX_WORK MAX_TOTAL);

use constant MAX_WORK => 200_000;     # stitches worked in one round, at most
use constant MAX_TOTAL => 1_000_000;  # in the whole pattern

sub tally {
    my ($rounds) = @_;
    my @out;
    my ($prev, $start);
    my $total = 0;
    ROUND: for my $r (@$rounds) {
        for my $k ($r->{first} .. $r->{last}) {
            my $label = ucfirst($r->{kind}) . " $k";
            my $res = work_round($r, $prev, $label, \$total);
            $start //= $res->{made} if !defined $prev;
            $res->{shape} = shape($r->{kind}, $prev, $res->{made}, $start);
            push @out, $res;
            # After a mistake, carry on from the count the pattern meant, so later rounds are
            # judged on their own.
            $prev = @{ $res->{errors} } && defined $r->{stated} ? $r->{stated} + 0 : $res->{made};
            # Past the work limit, nothing after it can be trusted: stop here.
            last ROUND if grep { /^more than \d+ stitches/ } @{ $res->{errors} };
        }
    }
    stacking(\@out);
    return \@out;
}

sub work_round {
    my ($r, $prev, $label, $total) = @_;
    my $s = { avail => $prev // 0, pos => 0, made => 0, incs => [], decs => [], work => 0, total => $total,
              first => !defined $prev, errors => [], notes => [] };
    eval { apply($s, $r->{items}, 1); 1 } or do {
        my $e = $@;
        die $e unless ref $e eq 'HASH' && $e->{stop};
        push @{ $s->{errors} }, $e->{stop};
    };
    if (!@{ $s->{errors} } && !$s->{first}) {
        my $left = $s->{avail} - $s->{pos};
        if ($left > 0) {
            my $msg = "leaves $left of the $s->{avail} stitches unworked";
            if ($r->{kind} eq 'row') { push @{ $s->{notes} }, "$msg (fine if it's a short row)" }
            else { push @{ $s->{errors} }, $msg }
        }
    }
    if (defined $r->{stated} && !@{ $s->{errors} } && $r->{stated} != $s->{made}) {
        push @{ $s->{errors} }, "says ($r->{stated}) but makes $s->{made}";
    }
    return { label => $label, line => $r->{line}, kind => $r->{kind}, from => $prev, made => $s->{made},
             stated => $r->{stated}, incs => $s->{incs}, decs => $s->{decs}, errors => $s->{errors}, notes => $s->{notes} };
}

sub stop { die { stop => $_[0] } }

sub apply {
    my ($s, $items, $times) = @_;
    for (1 .. $times) {
        for my $it (@$items) {
            if ($it->{t} eq 'group') {
                if ($it->{times} eq 'around') { around($s, $it->{items}) }
                else { apply($s, $it->{items}, $it->{times}) }
                next;
            }
            one($s, $it);
        }
    }
}

# Repeats a group until the round is used up; the last repeat must fit exactly.
sub around {
    my ($s, $items) = @_;
    stop('"around" needs a round below it to work into') if $s->{first};
    my $n = 0;
    while ($s->{pos} < $s->{avail}) {
        my $before = $s->{pos};
        # Remember where we were (cheaply: no copying of the lists) in case this repeat won't fit.
        my %saved = (pos => $s->{pos}, made => $s->{made}, avail => $s->{avail}, ni => scalar @{ $s->{incs} }, nd => scalar @{ $s->{decs} });
        my $ok = eval { apply($s, $items, 1); 1 };
        if (!$ok) {
            my $e = $@;
            die $e unless ref $e eq 'HASH' && $e->{stop};
            my $left = $saved{avail} - $saved{pos};
            $s->{pos} = $saved{pos};
            $s->{made} = $saved{made};
            splice @{ $s->{incs} }, $saved{ni};
            splice @{ $s->{decs} }, $saved{nd};
            stop("the repeat doesn't fit evenly: after $n repeats, $left " . ($left == 1 ? 'stitch is' : 'stitches are') . ' left over');
        }
        stop('a repeat "around" must work into at least one stitch') if $s->{pos} == $before;
        $n++;
    }
}

sub one {
    my ($s, $it) = @_;
    my $t = $it->{t};
    if ($t eq 'ring') {
        stop('a magic ring only starts a piece') unless $s->{first} && $s->{pos} == 0;
        $s->{made} += $it->{make};
        return;
    }
    if ($t eq 'chain') {
        # A foundation chain at the very start is what the first row works into; later chains
        # are turning chains or chain spaces, which this count leaves out.
        if ($s->{first} && $s->{made} == 0 && $s->{pos} == 0) {
            $s->{avail} = $it->{make};
            $s->{first} = 0;
        }
        return;
    }
    if ($t eq 'hook') {
        stop('"from hook" needs a foundation chain first') if $s->{first} || $s->{avail} == 0;
        stop("the chain is too short to start in the $it->{from}th chain from the hook") if $it->{from} > $s->{avail};
        $s->{pos} += $it->{from} - 1;    # the chains skipped become the turning chain
        work($s, { take => 1, make => 1 }, 1);
        one($s, { t => 'each', take => 1, make => 1 }) if $it->{each};
        return;
    }
    if ($t eq 'each') {
        stop('"in each st" needs a round below it to work into') if $s->{first};
        my $left = $s->{avail} - $s->{pos};
        stop("can't decrease over $left " . ($left == 1 ? 'stitch' : 'stitches') . ' in pairs') if $left % $it->{take};
        my $n = $left / $it->{take};
        work($s, $it, $n);
        return;
    }
    work($s, $it, $it->{rep} // 1);
}

sub work {
    my ($s, $it, $n) = @_;
    for (1 .. $n) {
        $s->{work}++;
        stop('more than ' . MAX_WORK . ' stitches worked in one round') if $s->{work} > MAX_WORK;
        stop('more than ' . MAX_TOTAL . ' stitches in the whole pattern') if ++${ $s->{total} } > MAX_TOTAL;
        stop('the first round needs a magic ring or a foundation chain to work into') if $s->{first};
        {
            my $need = $s->{pos} + $it->{take};
            stop('runs out of stitches: needs ' . ($need - $s->{avail}) . " more than the $s->{avail} there are") if $need > $s->{avail};
        }
        my $at = $s->{avail} ? ($s->{pos} + $it->{take} / 2) / $s->{avail} : 0;
        push @{ $s->{incs} }, $at if $it->{inc};
        push @{ $s->{decs} }, $at if $it->{dec};
        $s->{pos} += $it->{take};
        $s->{made} += $it->{make};
    }
}

# How a round shapes the piece, compared with a flat circle (which grows by the starting
# count every round).
sub shape {
    my ($kind, $prev, $made, $start) = @_;
    return 'start' unless defined $prev;
    my $d = $made - $prev;
    return $d == 0 ? 'straight' : $d > 0 ? 'wider' : 'narrower' if $kind eq 'row';
    return 'straight sides' if $d == 0;
    return 'closing' if $d < 0;
    my $r = $d / ($start || 1);
    return $r > 1.25 ? 'grows fast: ruffles' : $r < 0.8 ? 'grows slowly: cups' : 'flat';
}

# Increases sitting right on top of the last round's make corners (a hexagon instead of a
# circle). Flags runs of three or more such rounds.
sub stacking {
    my ($res) = @_;
    my ($run_start, $run_len) = (undef, 0);
    my $last;
    for my $i (0 .. $#$res) {
        my $r = $res->[$i];
        my $stacked = 0;
        # A round that increases in every stitch has nowhere else to put them, so it doesn't count.
        my $everywhere = @{ $r->{incs} } && defined $r->{from} && @{ $r->{incs} } >= $r->{from};
        if (!$everywhere && @{ $r->{incs} } && $last && @{ $last->{incs} } == @{ $r->{incs} } && @{ $r->{incs} } >= 3
            && @{ $r->{incs} } <= 500) {    # (real patterns have dozens; this keeps the check quick)
            my $total = 0;
            for my $p (@{ $r->{incs} }) {
                my $best = 1;
                for my $q (@{ $last->{incs} }) {
                    my $d = abs($p - $q);
                    $d = 1 - $d if $d > 0.5;
                    $best = $d if $d < $best;
                }
                $total += $best * $r->{from};
            }
            $stacked = $total / @{ $r->{incs} } < 1.0;    # within a stitch, on average
        }
        if ($stacked) {
            $run_start //= $i - 1;
            $run_len++;
        } else {
            flag($res, $run_start, $i - 1) if $run_len >= 2;
            ($run_start, $run_len) = (undef, 0);
        }
        $last = $r if @{ $r->{incs} } && !$everywhere;
    }
    flag($res, $run_start, $#$res) if $run_len >= 2;
}

sub flag {
    my ($res, $from, $to) = @_;
    push @{ $res->[$to]{notes} }, "increases stack in the same places from $res->[$from]{label} to $res->[$to]{label}: "
        . 'the piece will grow corners (a hexagon); stagger them, e.g. by moving half the repeat to the start';
}

1;
