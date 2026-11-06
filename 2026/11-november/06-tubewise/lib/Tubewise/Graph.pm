package Tubewise::Graph;
# Turns the strokes of a sign into a graph: a node wherever strokes end, bend, cross or touch, and
# an edge for each straight piece of lit tube between nodes.
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
our @EXPORT_OK = qw(build dist segments_cross);

use constant EPS => 1e-7;

sub dist { my ($p, $q) = @_; return sqrt(($p->[0] - $q->[0])**2 + ($p->[1] - $q->[1])**2) }

sub _cross { my ($o, $a, $b) = @_; return ($a->[0] - $o->[0]) * ($b->[1] - $o->[1]) - ($a->[1] - $o->[1]) * ($b->[0] - $o->[0]) }

# Where segment ab meets segment cd, as parameters along each (0..1), or undef. Touching counts;
# overlapping collinear pieces are reported by their end points.
sub _meet {
    my ($a, $b, $c, $d) = @_;
    my ($rx, $ry) = ($b->[0] - $a->[0], $b->[1] - $a->[1]);
    my ($sx, $sy) = ($d->[0] - $c->[0], $d->[1] - $c->[1]);
    my $den = $rx * $sy - $ry * $sx;
    my ($qx, $qy) = ($c->[0] - $a->[0], $c->[1] - $a->[1]);
    if (abs($den) < EPS) {
        return if abs($qx * $ry - $qy * $rx) > EPS;    # parallel, apart
        # Collinear: split each at the other's end points that lie inside it.
        my @hits;
        my $rr = $rx * $rx + $ry * $ry;
        my $ss = $sx * $sx + $sy * $sy;
        for my $p ($c, $d) {
            my $t = (($p->[0] - $a->[0]) * $rx + ($p->[1] - $a->[1]) * $ry) / $rr;
            push @hits, [ $t, undef ] if $t > EPS && $t < 1 - EPS;
        }
        for my $p ($a, $b) {
            my $u = (($p->[0] - $c->[0]) * $sx + ($p->[1] - $c->[1]) * $sy) / $ss;
            push @hits, [ undef, $u ] if $u > EPS && $u < 1 - EPS;
        }
        return @hits;
    }
    my $t = ($qx * $sy - $qy * $sx) / $den;
    my $u = ($qx * $ry - $qy * $rx) / $den;
    return if $t < -EPS || $t > 1 + EPS || $u < -EPS || $u > 1 + EPS;
    return [ $t, $u ];
}

# Whether segment ab crosses or touches segment cd anywhere other than at a shared end point.
sub segments_cross {
    my ($a, $b, $c, $d) = @_;
    for my $h (_meet($a, $b, $c, $d)) {
        my ($t, $u) = @$h;
        return 1 unless defined $t && defined $u;    # overlapping
        my $at_end = ($t < 1e-6 || $t > 1 - 1e-6) && ($u < 1e-6 || $u > 1 - 1e-6);
        return 1 unless $at_end;
    }
    return 0;
}

sub _key { my ($p) = @_; return sprintf '%.3f,%.3f', $p->[0], $p->[1] }

# strokes: [ { char => i, points => [[x, y], ...] }, ... ]
# Returns { nodes => [ [x, y], ... ], edges => [ { u, v, len, char }, ... ] }.
sub build {
    my ($strokes) = @_;
    my @segs;
    for my $s (@$strokes) {
        my $pts = $s->{points};
        for my $i (0 .. $#$pts - 1) {
            next if dist($pts->[$i], $pts->[ $i + 1 ]) < 1e-6;
            push @segs, { a => $pts->[$i], b => $pts->[ $i + 1 ], char => $s->{char}, cuts => [ 0, 1 ] };
        }
    }
    for my $i (0 .. $#segs) {
        for my $j ($i + 1 .. $#segs) {
            for my $h (_meet($segs[$i]{a}, $segs[$i]{b}, $segs[$j]{a}, $segs[$j]{b})) {
                push @{ $segs[$i]{cuts} }, $h->[0] if defined $h->[0];
                push @{ $segs[$j]{cuts} }, $h->[1] if defined $h->[1];
            }
        }
    }
    my (%id, @nodes, @edges, %seen);
    my $node = sub {
        my ($p) = @_;
        my $k = _key($p);
        $id{$k} //= do { push @nodes, [ $p->[0], $p->[1] ]; $#nodes };
        return $id{$k};
    };
    for my $s (@segs) {
        my @t = sort { $a <=> $b } map { $_ < 0 ? 0 : $_ > 1 ? 1 : $_ } @{ $s->{cuts} };
        for my $k (0 .. $#t - 1) {
            next if $t[ $k + 1 ] - $t[$k] < 1e-9;
            my @p = map { [ $s->{a}[0] + ($s->{b}[0] - $s->{a}[0]) * $_, $s->{a}[1] + ($s->{b}[1] - $s->{a}[1]) * $_ ] } $t[$k], $t[ $k + 1 ];
            my ($u, $v) = ($node->($p[0]), $node->($p[1]));
            next if $u == $v;
            my $pair = $u < $v ? "$u-$v" : "$v-$u";
            next if $seen{$pair}++;    # the same piece drawn twice is one tube
            push @edges, { u => $u, v => $v, len => dist($nodes[$u], $nodes[$v]), char => $s->{char} };
        }
    }
    return { nodes => \@nodes, edges => \@edges };
}

1;
