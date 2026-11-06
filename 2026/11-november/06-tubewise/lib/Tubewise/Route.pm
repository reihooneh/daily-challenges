package Tubewise::Route;
# Plans the glass: one continuous route through every lit stroke, with as little blacked-out tube as
# possible, then cut into tubes no longer than a bender can handle.
#
# A tube traces each stroke once. Where the route has to go somewhere without lighting it, the glass
# is painted black: either doubling back along a stroke already lit, or a "jumper" straight across.
# That is the route inspection (Chinese postman) problem: the strokes form a graph, and a route that
# uses every edge exactly once exists only if at most two nodes have an odd number of strokes. Odd
# nodes are paired up with the cheapest blacked-out connections (minimum-weight perfect matching),
# leaving the two ends of the tube free.
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
our @EXPORT_OK = qw(plan);
use Tubewise::Graph qw(dist segments_cross);

use constant { EXACT_LIMIT => 16, INF => 9**9**9 };

# ---------- Small helpers ----------

sub _find { my ($p, $x) = @_; $p->[$x] = _find($p, $p->[$x]) if $p->[$x] != $x; return $p->[$x] }

# A jumper from node a to node b may not cross or run along any lit stroke (painted glass in front of
# a lit letter would show), except where it starts and ends.
sub _jumper_ok {
    my ($g, $a, $b) = @_;
    my ($pa, $pb) = ($g->{nodes}[$a], $g->{nodes}[$b]);
    for my $e (@{ $g->{edges} }) {
        return 0 if segments_cross($pa, $pb, $g->{nodes}[ $e->{u} ], $g->{nodes}[ $e->{v} ]);
    }
    return 1;
}

# Dijkstra from one node over the lit strokes (doubling back) and the given jumpers. Returns the
# distance and the edge used to reach each node.
sub _dijkstra {
    my ($n, $adj, $src) = @_;
    my @d = (INF) x $n;
    my @via;
    $d[$src] = 0;
    my @heap = ([ 0, $src ]);
    while (@heap) {
        # A binary heap would be faster; with a few hundred nodes a sorted pop is plenty.
        my $top = 0;
        for my $i (1 .. $#heap) { $top = $i if $heap[$i][0] < $heap[$top][0] }
        my ($du, $u) = @{ splice @heap, $top, 1 };
        next if $du > $d[$u];
        for my $a (@{ $adj->[$u] }) {
            my $nd = $du + $a->{cost};
            if ($nd < $d[ $a->{to} ] - 1e-9) {
                $d[ $a->{to} ] = $nd;
                $via[ $a->{to} ] = { %$a, from => $u };
                push @heap, [ $nd, $a->{to} ];
            }
        }
    }
    return (\@d, \@via);
}

# Minimum-weight perfect matching of an even number of points, given a cost function. Exact by
# dynamic programming over subsets for up to EXACT_LIMIT points; otherwise greedy plus 2-opt swaps.
sub _match {
    my ($n, $cost) = @_;
    return ([], 1) if $n == 0;
    if ($n <= EXACT_LIMIT) {
        my $full = (1 << $n) - 1;
        my (@best, @choice);
        $best[0] = 0;
        for my $mask (1 .. $full) {
            next if _bits($mask) % 2;
            my $i = 0;
            $i++ until $mask & (1 << $i);
            my $rest = $mask & ~(1 << $i);
            my $b = INF;
            for my $j ($i + 1 .. $n - 1) {
                next unless $rest & (1 << $j);
                my $c = $cost->($i, $j) + $best[ $rest & ~(1 << $j) ];
                ($b, $choice[$mask]) = ($c, $j) if $c < $b;
            }
            $best[$mask] = $b;
        }
        my (@pairs, $mask);
        $mask = $full;
        while ($mask) {
            my $i = 0;
            $i++ until $mask & (1 << $i);
            my $j = $choice[$mask];
            push @pairs, [ $i, $j ];
            $mask &= ~((1 << $i) | (1 << $j));
        }
        return (\@pairs, 1);
    }
    my @all;
    for my $i (0 .. $n - 1) { for my $j ($i + 1 .. $n - 1) { push @all, [ $cost->($i, $j), $i, $j ] } }
    my (%used, @pairs);
    for my $p (sort { $a->[0] <=> $b->[0] } @all) {
        next if $used{ $p->[1] } || $used{ $p->[2] };
        $used{ $p->[1] } = $used{ $p->[2] } = 1;
        push @pairs, [ $p->[1], $p->[2] ];
    }
    my $improved = 1;
    while ($improved) {
        $improved = 0;
        for my $x (0 .. $#pairs) {
            for my $y ($x + 1 .. $#pairs) {
                my ($a, $b) = @{ $pairs[$x] };
                my ($c, $d) = @{ $pairs[$y] };
                my $now = $cost->($a, $b) + $cost->($c, $d);
                for my $alt ([ [ $a, $c ], [ $b, $d ] ], [ [ $a, $d ], [ $b, $c ] ]) {
                    my $new = $cost->(@{ $alt->[0] }) + $cost->(@{ $alt->[1] });
                    if ($new < $now - 1e-9) {
                        ($pairs[$x], $pairs[$y]) = @$alt;
                        $improved = 1;
                        last;
                    }
                }
            }
        }
    }
    return (\@pairs, 0);
}

sub _bits { my ($m) = @_; my $c = 0; while ($m) { $c += $m & 1; $m >>= 1 } return $c }

# ---------- The plan ----------

# opts: max_tube (mm), bend (mm of extra glass for each jumper's two bends)
sub plan {
    my ($g, %opt) = @_;
    my $bend = $opt{bend} // 20;
    my $max = $opt{max_tube} // 2000;
    my $n = @{ $g->{nodes} };
    die "the sign has no strokes\n" unless @{ $g->{edges} };

    # 1. Strokes that already touch form one piece of glass.
    my @parent = (0 .. $n - 1);
    for my $e (@{ $g->{edges} }) { $parent[ _find(\@parent, $e->{u}) ] = _find(\@parent, $e->{v}) }
    my (%members, %chars);
    for my $e (@{ $g->{edges} }) {
        my $r = _find(\@parent, $e->{u});
        $members{$r}{ $e->{u} } = $members{$r}{ $e->{v} } = 1;
        $chars{$r}{ $e->{char} } = 1;
    }
    my @comps = sort { $a <=> $b } keys %members;
    my $pieces = @comps;

    # 2. Join the pieces with the shortest jumpers that don't cross lit glass (a minimum spanning tree),
    # trying neighbouring letters first.
    my @jumpers;
    my @cand;
    for my $neighbours (1, 0) {
        @cand = ();
        for my $x (0 .. $#comps) {
            for my $y ($x + 1 .. $#comps) {
                my ($cx, $cy) = ($comps[$x], $comps[$y]);
                if ($neighbours) {
                    my $near = 0;
                    for my $a (keys %{ $chars{$cx} }) { for my $b (keys %{ $chars{$cy} }) { $near = 1 if abs($a - $b) <= 1 } }
                    next unless $near;
                }
                my @pairs;
                for my $a (keys %{ $members{$cx} }) {
                    for my $b (keys %{ $members{$cy} }) { push @pairs, [ dist($g->{nodes}[$a], $g->{nodes}[$b]), $a, $b ] }
                }
                for my $p (sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] } @pairs) {
                    if (_jumper_ok($g, $p->[1], $p->[2])) { push @cand, [ $p->[0], $cx, $cy, $p->[1], $p->[2] ]; last }
                }
            }
        }
        my @p2 = (0 .. $n - 1);
        my @chosen;
        for my $c (sort { $a->[0] <=> $b->[0] } @cand) {
            my ($ra, $rb) = (_find(\@p2, $c->[1]), _find(\@p2, $c->[2]));
            next if $ra == $rb;
            $p2[$ra] = $rb;
            push @chosen, $c;
        }
        if (@chosen == $#comps) { @jumpers = @chosen; last }
        die "the strokes can't all be joined without crossing lit glass\n" unless $neighbours;
    }

    # 3. The route's graph so far: lit strokes and the joining jumpers. Find the odd nodes.
    my @E = map { { u => $_->{u}, v => $_->{v}, len => $_->{len}, char => $_->{char}, kind => 'lit' } } @{ $g->{edges} };
    push @E, map { { u => $_->[3], v => $_->[4], len => $_->[0], char => -1, kind => 'jump' } } @jumpers;
    my @deg = (0) x $n;
    for my $e (@E) { $deg[ $e->{u} ]++; $deg[ $e->{v} ]++ }
    my @odd = grep { $deg[$_] % 2 } 0 .. $n - 1;

    # 4. Blacked-out connections between odd nodes: double back along strokes, or a new jumper.
    my @adj = map { [] } 1 .. $n;
    for my $i (0 .. $#E) {
        my $e = $E[$i];
        my $cost = $e->{len} + ($e->{kind} eq 'jump' ? $bend : 0);
        my $kind = $e->{kind} eq 'jump' ? 'jump' : 'double';
        push @{ $adj[ $e->{u} ] }, { to => $e->{v}, cost => $cost, kind => $kind, len => $e->{len}, char => $e->{char} };
        push @{ $adj[ $e->{v} ] }, { to => $e->{u}, cost => $cost, kind => $kind, len => $e->{len}, char => $e->{char} };
    }
    for my $x (0 .. $#odd) {
        for my $y ($x + 1 .. $#odd) {
            my ($a, $b) = ($odd[$x], $odd[$y]);
            next unless _jumper_ok($g, $a, $b);
            my $len = dist($g->{nodes}[$a], $g->{nodes}[$b]);
            push @{ $adj[$a] }, { to => $b, cost => $len + $bend, kind => 'jump', len => $len, char => -1 };
            push @{ $adj[$b] }, { to => $a, cost => $len + $bend, kind => 'jump', len => $len, char => -1 };
        }
    }
    my (@D, @VIA);
    for my $x (0 .. $#odd) { ($D[$x], $VIA[$x]) = _dijkstra($n, \@adj, $odd[$x]) }

    # 5. Pair the odd nodes; two extra free points take the tube's two ends at no cost.
    my $k = @odd;
    my $m = $k ? $k + 2 : 0;
    my $cost = sub {
        my ($i, $j) = @_;
        return INF if $i >= $k && $j >= $k;
        return 0 if $i >= $k || $j >= $k;
        return $D[$i][ $odd[$j] ];
    };
    my ($pairs, $exact) = _match($m, $cost);
    my @ends;
    for my $p (@$pairs) {
        my ($i, $j) = @$p;
        if ($i >= $k || $j >= $k) { push @ends, $odd[ $i < $k ? $i : $j ]; next }
        # Walk the shortest connection back from odd[j] to odd[i], adding its pieces as black glass.
        my $at = $odd[$j];
        while ($at != $odd[$i]) {
            my $a = $VIA[$i][$at] or die "internal: no way back\n";
            push @E, { u => $a->{from}, v => $at, len => $a->{len}, char => $a->{char}, kind => $a->{kind} };
            $at = $a->{from};
        }
    }

    # 6. One continuous route through every piece exactly once (Hierholzer's algorithm).
    my @inc = map { [] } 1 .. $n;
    for my $i (0 .. $#E) { push @{ $inc[ $E[$i]{u} ] }, $i; push @{ $inc[ $E[$i]{v} ] }, $i }
    my $start = @ends ? (sort { $g->{nodes}[$a][0] <=> $g->{nodes}[$b][0] || $g->{nodes}[$a][1] <=> $g->{nodes}[$b][1] } @ends)[0] : $E[0]{u};
    my (@used, @ptr, @stack, @out);
    @stack = ([ $start, undef ]);
    while (@stack) {
        my ($v) = @{ $stack[-1] };
        $ptr[$v] //= 0;
        $ptr[$v]++ while $ptr[$v] < @{ $inc[$v] } && $used[ $inc[$v][ $ptr[$v] ] ];
        if ($ptr[$v] < @{ $inc[$v] }) {
            my $ei = $inc[$v][ $ptr[$v] ];
            $used[$ei] = 1;
            my $w = $E[$ei]{u} == $v ? $E[$ei]{v} : $E[$ei]{u};
            push @stack, [ $w, $ei ];
        } else {
            push @out, pop @stack;
        }
    }
    @out = reverse @out;
    die "internal: the route missed some glass\n" unless @out == @E + 1;
    my @steps;
    for my $i (1 .. $#out) {
        my ($from, $to, $e) = ($out[ $i - 1 ][0], $out[$i][0], $E[ $out[$i][1] ]);
        push @steps, { from => $g->{nodes}[$from], to => $g->{nodes}[$to], len => $e->{len}, kind => $e->{kind}, char => $e->{char} };
    }

    # 7. Cut into tubes no longer than max_tube, inside black glass where possible.
    my ($units, $visible) = _cut(\@steps, $max);

    my %sum = (lit => 0, double => 0, jump => 0);
    $sum{ $_->{kind} } += $_->{len} for @steps;
    my $jumps = grep { $_->{kind} eq 'jump' } @steps;
    return {
        steps => \@steps, units => $units, visible_joints => $visible, exact => $exact,
        lit => $sum{lit}, double => $sum{double}, jump => $sum{jump}, jumps => $jumps, bend => $bend,
        glass => $sum{lit} + $sum{double} + $sum{jump} + $jumps * $bend, pieces => $pieces, odd => $k, max_tube => $max,
    };
}

sub _part {
    my ($s, $from_frac, $to_frac) = @_;
    my $at = sub { my ($f) = @_; return [ map { $s->{from}[$_] + ($s->{to}[$_] - $s->{from}[$_]) * $f } 0, 1 ] };
    return { %$s, from => $at->($from_frac), to => $at->($to_frac), len => $s->{len} * ($to_frac - $from_frac) };
}

sub _cut {
    my ($steps, $max) = @_;
    my (@units, @cur);
    my $len = 0;
    my $visible = 0;
    my @queue = @$steps;
    while (@queue) {
        my $s = shift @queue;
        if ($len + $s->{len} <= $max + 1e-9) { push @cur, $s; $len += $s->{len}; next }
        my $room = $max - $len;
        if ($s->{kind} ne 'lit' && $room > 1e-6) {
            # Cut inside this black piece: the joint and its electrodes hide in the blackout.
            my $f = $room / $s->{len};
            push @cur, _part($s, 0, $f);
            push @units, { pieces => [@cur], hidden_end => 1 };
            @cur = ();
            $len = 0;
            unshift @queue, _part($s, $f, 1);
            next;
        }
        # Cut in the middle of a black piece already in this tube, if what follows the cut then fits
        # with this piece; the latest such black piece keeps this tube as full as possible.
        my $cut;
        my $after = $s->{len};
        for my $d (reverse 0 .. $#cur) {
            if ($cur[$d]{kind} ne 'lit' && $after + $cur[$d]{len} / 2 <= $max + 1e-9) { $cut = $d; last }
            $after += $cur[$d]{len};
        }
        if (defined $cut) {
            my $b = $cur[$cut];
            push @units, { pieces => [ @cur[ 0 .. $cut - 1 ], _part($b, 0, 0.5) ], hidden_end => 1 };
            @cur = (_part($b, 0.5, 1), @cur[ $cut + 1 .. $#cur ], $s);
            $len = 0;
            $len += $_->{len} for @cur;
            next;
        }
        if (!@cur) {
            # A single lit stroke longer than a tube: it has to be joined where it shows.
            my $f = $max / $s->{len};
            push @units, { pieces => [ _part($s, 0, $f) ], hidden_end => 0 };
            unshift @queue, _part($s, $f, 1);
            $visible++;
            next;
        }
        push @units, { pieces => [@cur], hidden_end => 0 };
        $visible++;
        @cur = ();
        $len = 0;
        unshift @queue, $s;
    }
    push @units, { pieces => [@cur], hidden_end => 1 } if @cur;
    for my $u (@units) {
        $u->{length} = 0;
        $u->{length} += $_->{len} for @{ $u->{pieces} };
    }
    return (\@units, $visible);
}

1;
