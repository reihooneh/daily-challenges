package Tubewise::Report;
# The plan in words for the bender, and as an SVG drawing.
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
our @EXPORT_OK = qw(render svg);

sub _mm {
    my ($v) = @_;
    my $s = sprintf '%.0f', $v;
    1 while $s =~ s/^(\d+)(\d{3})/$1,$2/;
    return $s;
}

sub _pt { my ($p) = @_; return sprintf '(%s, %s)', _mm($p->[0]), _mm($p->[1]) }

# Groups a tube's pieces into readable steps: consecutive lit pieces of one letter, black pieces.
sub _steps {
    my ($pieces, $label) = @_;
    my @out;
    for my $p (@$pieces) {
        my $what = $p->{kind} eq 'lit' ? 'light ' . $label->($p->{char}) : $p->{kind} eq 'double' ? 'black, back along ' . $label->($p->{char}) : 'black jumper';
        if (@out && $out[-1]{what} eq $what && $p->{kind} ne 'jump') { $out[-1]{len} += $p->{len}; $out[-1]{to} = $p->{to}; next }
        push @out, { what => $what, len => $p->{len}, to => $p->{to} };
    }
    return @out;
}

sub render {
    my ($title, $chars, $height, $plan) = @_;
    my $label = sub { my ($i) = @_; return $i >= 0 && $i < @$chars ? "'$chars->[$i]'" : 'the shape' };
    my @u = @{ $plan->{units} };
    my $tubes = @u;
    my $black = $plan->{double} + $plan->{jump};
    my @o;
    push @o, "TUBEWISE  $title" . (defined $height ? "  (letters ${height} mm tall)" : '');
    push @o, sprintf 'Lit glass: %s mm, in %d separate piece%s of lettering.', _mm($plan->{lit}), $plan->{pieces}, $plan->{pieces} == 1 ? '' : 's';
    push @o, '';
    push @o, sprintf 'Plan: %d tube%s, %d electrodes%s.', $tubes, $tubes == 1 ? '' : 's', 2 * $tubes,
        $plan->{visible_joints} ? sprintf('; %d joint%s fall on lit glass and will show', $plan->{visible_joints}, $plan->{visible_joints} == 1 ? '' : 's') : $tubes > 1 ? ', every joint hidden in black glass' : '';
    push @o, sprintf '  Black glass: %s mm (%s mm doubling back along strokes, %s mm in %d jumper%s), plus %s mm for the jumpers\' bends.',
        _mm($black), _mm($plan->{double}), _mm($plan->{jump}), $plan->{jumps}, $plan->{jumps} == 1 ? '' : 's', _mm($plan->{jumps} * $plan->{bend});
    push @o, sprintf '  Glass to bend: %s mm, in tubes of at most %s mm.', _mm($plan->{glass}), _mm($plan->{max_tube});
    push @o, sprintf '  Bent as separate pieces, it would take %d tube%s and %d electrodes.', $plan->{pieces}, $plan->{pieces} == 1 ? '' : 's', 2 * $plan->{pieces}
        if $plan->{pieces} > $tubes;
    push @o, $plan->{exact}
        ? '  The blackout is the least possible for these strokes (exact matching of the odd points).'
        : sprintf('  With %d odd points the pairing is greedy with swaps, not proven least (exact up to %d).', $plan->{odd}, 14);
    for my $i (0 .. $#u) {
        my $p = $u[$i]{pieces};
        push @o, '', sprintf 'Tube %d (%s mm): electrode at %s', $i + 1, _mm($u[$i]{length}), _pt($p->[0]{from});
        for my $s (_steps($p, $label)) {
            push @o, sprintf '  %-26s %6s mm  to %s', $s->{what}, _mm($s->{len}), _pt($s->{to});
        }
        push @o, sprintf '  electrode at %s%s', _pt($p->[-1]{to}), $u[$i]{hidden_end} || $i == $#u ? '' : ' (on lit glass: this joint shows)';
    }
    return join("\n", @o) . "\n";
}

sub _esc {
    my ($s) = @_;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    $s =~ s/'/&#39;/g;
    return $s;
}

sub svg {
    my ($title, $plan) = @_;
    my @all = map { ($_->{from}, $_->{to}) } @{ $plan->{steps} };
    my ($x0, $x1, $y0, $y1) = (9**9, -9**9, 9**9, -9**9);
    for my $p (@all) {
        $x0 = $p->[0] if $p->[0] < $x0;
        $x1 = $p->[0] if $p->[0] > $x1;
        $y0 = $p->[1] if $p->[1] < $y0;
        $y1 = $p->[1] if $p->[1] > $y1;
    }
    my $m = 40;
    my ($w, $h) = ($x1 - $x0 + 2 * $m, $y1 - $y0 + 2 * $m);
    my $X = sub { sprintf '%.1f', $_[0][0] - $x0 + $m };
    my $Y = sub { sprintf '%.1f', $y1 - $_[0][1] + $m };    # the plan's y runs up
    my @o = (sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.1f %.1f" width="%.0fmm" height="%.0fmm">', $w, $h, $w, $h),
        '<title>' . _esc("Tubewise: $title") . '</title>', sprintf('<rect width="%.1f" height="%.1f" fill="#16121c"/>', $w, $h));
    my @lit = grep { $_->{kind} eq 'lit' } @{ $plan->{steps} };
    for my $pass ([ 18, '#ff4f9a', '0.18' ], [ 8, '#ff7fb6', '0.45' ], [ 3, '#fff0f6', '1' ]) {
        my ($sw, $col, $op) = @$pass;
        push @o, sprintf '<g stroke="%s" stroke-width="%d" stroke-opacity="%s" stroke-linecap="round" fill="none">', $col, $sw, $op;
        push @o, map { sprintf '<line x1="%s" y1="%s" x2="%s" y2="%s"/>', $X->($_->{from}), $Y->($_->{from}), $X->($_->{to}), $Y->($_->{to}) } @lit;
        push @o, '</g>';
    }
    push @o, '<g stroke="#8a8494" stroke-width="2.5" stroke-dasharray="7 5" fill="none">';
    for my $s (grep { $_->{kind} ne 'lit' } @{ $plan->{steps} }) {
        my ($dx, $dy) = ($s->{to}[0] - $s->{from}[0], $s->{to}[1] - $s->{from}[1]);
        my $l = sqrt($dx * $dx + $dy * $dy) || 1;
        # Doubled-back glass runs beside the lit tube, so draw it a little to one side.
        my $off = $s->{kind} eq 'double' ? 9 : 0;
        my ($ox, $oy) = (-$dy / $l * $off, $dx / $l * $off);
        push @o, sprintf '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>', $X->($s->{from}) + $ox, $Y->($s->{from}) - $oy, $X->($s->{to}) + $ox, $Y->($s->{to}) - $oy;
    }
    push @o, '</g>';
    my $n = 0;
    for my $u (@{ $plan->{units} }) {
        $n++;
        for my $p ($u->{pieces}[0]{from}, $u->{pieces}[-1]{to}) {
            push @o, sprintf '<circle cx="%s" cy="%s" r="7" fill="#f2c230" stroke="#16121c" stroke-width="2"/>', $X->($p), $Y->($p);
        }
        my $s = $u->{pieces}[0]{from};
        push @o, sprintf '<text x="%s" y="%.1f" fill="#f2c230" font-family="sans-serif" font-size="18" text-anchor="middle">%d</text>', $X->($s), $Y->($s) + 26, $n;
    }
    push @o, '</svg>';
    return join("\n", @o) . "\n";
}

1;
