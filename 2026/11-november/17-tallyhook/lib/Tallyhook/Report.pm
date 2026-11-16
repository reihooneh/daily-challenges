package Tallyhook::Report;
# The report: each round's count, whether it checks out, how it shapes the piece, and a
# silhouette of the piece drawn from the counts (a ball looks like a ball).
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
use Tallyhook::Parse qw(clean);
our @EXPORT_OK = qw(report);

use constant WIDTH => 40;

sub report {
    my ($res, $name) = @_;
    my @lines;
    my $errors = grep { @{ $_->{errors} } } @$res;
    my $max = 1;
    $max = $_->{made} > $max ? $_->{made} : $max for @$res;
    my $scale = $max > WIDTH ? WIDTH / $max : 1;
    push @lines, 'Tallyhook: ' . clean($name), '';
    push @lines, sprintf('  %-10s %13s  %-3s %-22s %s', 'round', 'stitches', '', 'shape', 'silhouette');
    for my $r (@$res) {
        my $count = defined $r->{from} ? sprintf('%5d -> %-5d', $r->{from}, $r->{made}) : sprintf('%5s -> %-5d', '', $r->{made});
        my $mark = @{ $r->{errors} } ? '!!' : defined $r->{stated} ? 'ok' : '..';
        my $w = int($r->{made} * $scale + 0.5);
        $w = 1 if $w < 1 && $r->{made} > 0;
        my $pad = ' ' x int((WIDTH - $w) / 2);
        push @lines, sprintf('  %-10s %s  %-3s %-22s %s', $r->{label}, $count, $mark, $r->{shape}, $pad . ('#' x $w));
    }
    push @lines, '', "  ok = matches the count the pattern gives; .. = no count given; !! = a problem", '';
    my @problems;
    for my $r (@$res) {
        push @problems, map { "  $r->{label} (line $r->{line}): $_" } @{ $r->{errors} };
    }
    my @notes;
    for my $r (@$res) {
        push @notes, map { "  $r->{label}: $_" } @{ $r->{notes} };
    }
    if (@problems) {
        push @lines, scalar(@problems) == 1 ? '1 problem:' : scalar(@problems) . ' problems:', @problems, '';
    } else {
        push @lines, 'Every round works out.', '';
    }
    push @lines, 'Worth knowing:', @notes, '' if @notes;
    my $total = 0;
    $total += $_->{made} for @$res;
    push @lines, "$total stitches in " . scalar(@$res) . ' ' . (@$res == 1 ? $res->[0]{kind} : $res->[0]{kind} . 's') . '.';
    return join("\n", @lines) . "\n";
}

1;
