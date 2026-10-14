package Dryleg::Report;
use strict;
use warnings;
use utf8;
use Exporter qw(import);
use Dryleg::Route qw(format_clock);

our @EXPORT_OK = qw(render);

sub duration {
    my ($minutes) = @_;
    my $m = int($minutes + 0.5);
    return sprintf('%dh%02d', int($m / 60), $m % 60);
}

sub litres { sprintf('%.1f L', $_[0]) }

sub render {
    my ($r, $plan, $best, $name) = @_;
    my @out;
    my $pts = $r->{points};
    my ($up) = (0);
    $up += $_->{up} for @$pts;
    push @out, sprintf('DRYLEG  %s  (%s: %.1f km, +%d m, %d to %d °C)', $name, $r->{trail}, $pts->[-1]{km}, $up,
        $r->{low}, $r->{high});
    push @out, '';
    push @out, sprintf('Leave %s, arrive at %s about %s (%s walking).', format_clock($plan->{start}),
        $pts->[-1]{name}, format_clock($plan->{arrive}), duration($plan->{arrive} - $plan->{start}));
    push @out, '';

    my $width = 9;
    for (@{ $plan->{fills} }) { $width = length $_->{at}{name} if length $_->{at}{name} > $width }
    push @out, sprintf("  %-${width}s  %7s   %-*s  %5s   %s", 'Fill up at', 'Carry', $width, 'To reach', 'Walk', 'Heat');
    for my $f (@{ $plan->{fills} }) {
        push @out, sprintf("  %-${width}s  %7s   %-*s  %5s   %.0f to %.0f °C%s", $f->{at}{name}, litres($f->{litres}),
            $width, $f->{to}{name}, duration($f->{minutes}), $f->{tmin}, $f->{tmax},
            $f->{litres} > $r->{capacity} + 1e-9 ? '   << more than you can carry' : '');
        for my $s (@{ $f->{passing} }) {
            push @out, "  " . (' ' x $width) . "            passes $s->{name} ($s->{reliability}): a bonus if it's flowing, not counted on";
        }
    }
    push @out, '';
    push @out, sprintf('Heaviest carry %s (you can carry %s; both include the %s you keep spare).', litres($plan->{most}),
        litres($r->{capacity}), litres($r->{reserve}));
    push @out, sprintf('You will drink about %s over the whole walk.', litres($plan->{drunk}));

    my @warn;
    if ($plan->{too_heavy}) {
        push @warn, 'You can\'t carry enough for the longest dry stretch. Start in the cooler hours, cache water beforehand, '
            . 'carry more bottles, or shorten the day.';
    }
    push @warn, sprintf('You\'d arrive after dark (last light %s).', format_clock($r->{dark})) if $plan->{after_dark};
    if (@warn) {
        push @out, '', 'WARNINGS';
        push @out, "  - $_" for @warn;
    }

    if ($best && $best->{start} != $plan->{start}) {
        my $saving = $plan->{most} - $best->{most};
        if ($saving >= 0.2 || ($plan->{too_heavy} && !$best->{too_heavy}) || ($plan->{after_dark} && !$best->{after_dark})) {
            push @out, '', sprintf('Better: leave at %s. The heaviest carry drops to %s (%s lighter) and you arrive about %s.',
                format_clock($best->{start}), litres($best->{most}), litres($saving), format_clock($best->{arrive}));
        }
    }
    push @out, '', 'A planning aid, not a guarantee: drink to thirst, never ration, and carry more on hotter days.';
    return join("\n", @out) . "\n";
}

1;
