package Downthrow::Report;
# Puts it all together and writes the report.
use strict;
use utf8;
use warnings FATAL => 'all';
use Exporter 'import';
use Downthrow::Plane qw(fit_plane attitude attitude_errors apparent_dip predict compass);
use Downthrow::Fault ();

our @EXPORT_OK = qw(analyse render);

use constant SIGNIFICANT => 0.05;

sub analyse {
    my ($survey, %opt) = @_;
    my $points = $survey->{points};
    my $fit = fit_plane($points)
        or die { input => 'the points lie on (or almost on) one straight line; a plane needs them spread out' };
    my $fault = Downthrow::Fault::search($points, $fit, %opt);
    my $faulted = $fault->{tested} && $fault->{p} < SIGNIFICANT;
    my $att = attitude($faulted ? @{ $fault->{beta} }[1, 2] : ($fit->{b}, $fit->{c}));
    return { survey => $survey, fit => $fit, fault => $fault, faulted => $faulted, attitude => $att };
}

sub render {
    my ($r) = @_;
    my ($s, $fit, $f, $att) = @$r{qw(survey fit fault attitude)};
    my $u = $s->{units};
    my @o;
    my $line = sub { push @o, sprintf(shift, @_) };
    $line->('DOWNTHROW  %s: %s', $s->{name}, $s->{horizon});
    $line->('%d points. Bearings are degrees clockwise from north; elevations in %s.', scalar @{ $s->{points} }, $u);
    $line->('');

    my $plane = attitude($fit->{b}, $fit->{c});
    my ($sd_dip, $sd_dir) = attitude_errors($fit);
    $line->('One plane through every point:');
    if (defined $sd_dip) {
        $line->('  dips %.1f° (± %.1f) towards %03.0f° (%s, ± %.0f°); strike %03.0f°', $plane->{dip}, $sd_dip,
            $plane->{dipdir}, compass($plane->{dipdir}), $sd_dir, $plane->{strike});
        $line->('  scatter about the plane: %.2f %s (R² %.3f)', $fit->{sigma}, $u, $fit->{r2});
    } else {
        $line->('  dips %.1f° towards %03.0f° (%s); strike %03.0f°  (exactly three points: no error estimate)',
            $plane->{dip}, $plane->{dipdir}, compass($plane->{dipdir}), $plane->{strike});
    }
    $line->('');

    if (!$f->{tested}) {
        $line->('Fault search: %s.', $f->{reason});
    } else {
        $line->('Fault search: every straight fault line every 2°, scored against %d simulated unfaulted surveys.', $f->{sims});
        if ($r->{faulted}) {
            my ($lo, $hi) = @{ $f->{trend_range} };
            my $trend = $lo == $hi ? sprintf('trending %03.0f°', $lo)
                : sprintf('trending somewhere between %03.0f° and %03.0f° (the points allow any line in that fan)', $lo, $hi);
            $line->('  FAULT LIKELY (p = %.2f): %s,', $f->{p}, $trend);
            $line->('  passing near (%.0f, %.0f);', @{ $f->{point} });
            $line->('  throw %.1f %s, %s side down. Scatter drops from %.2f to %.2f %s.',
                $f->{throw}, $u, compass($f->{down_azimuth}), $fit->{sigma}, $f->{sigma}, $u);
            $line->('  Allowing for the fault, the bed dips %.1f° towards %03.0f° (%s); strike %03.0f°.',
                $att->{dip}, $att->{dipdir}, compass($att->{dipdir}), $att->{strike});
        } else {
            $line->('  no convincing fault (p = %.2f): the best split (trend %03.0f°, step %.1f %s)', $f->{p}, $f->{theta}, $f->{throw}, $u);
            $line->('  is no better than splits found in surveys that have no fault.');
        }
    }
    $line->('');

    # The worst-fitting point, judged against a plane fitted without it (so it can't hide by
    # dragging the plane towards itself).
    my @worst = sort { abs($b->{residual}) <=> abs($a->{residual}) } @{ $s->{points} };
    if (!$r->{faulted} && @worst >= 6) {
        my $w = $worst[0];
        my $rest = fit_plane([ map { { %$_ } } grep { $_ != $w } @{ $s->{points} } ]);
        if ($rest) {
            my ($z, $se) = predict($rest, $w->{x}, $w->{y});
            my $off = $w->{z} - $z;
            if (abs($off) > 4 * $se && abs($off) > 1e-6) {
                $line->('Check point %s (line %d): %.1f %s off the plane the other points make. A survey slip, or a local fold?',
                    $w->{id}, $w->{line}, $off, $u);
                $line->('');
            }
        }
    }

    if (@{ $s->{sections} }) {
        $line->('Apparent dip in cross-sections:');
        for my $b (@{ $s->{sections} }) {
            my $a = apparent_dip($att->{dip}, $att->{dipdir}, $b);
            $line->('  along %03d°: %.1f° %s', $b, abs($a), $a >= 0.05 ? 'down' : $a <= -0.05 ? 'up' : '(level: along strike)');
        }
        $line->('');
    }

    if (@{ $s->{sites} }) {
        $line->('Predicted %s:', $s->{horizon});
        for my $site (@{ $s->{sites} }) {
            my ($z, $se) = $r->{faulted}
                ? Downthrow::Fault::predict($f, $fit, $site->{x}, $site->{y})
                : predict($fit, $site->{x}, $site->{y});
            my $txt = sprintf('  %-10s at %.1f %s', $site->{id}, $z, $u);
            $txt .= sprintf(' (± %.1f, 95%%)', 2 * $se) if $fit->{df} > 0;
            if (defined $site->{ground}) {
                my $depth = $site->{ground} - $z;
                $txt .= $depth >= 0 ? sprintf('; about %.1f %s below the ground', $depth, $u)
                    : sprintf('; that is %.1f %s above the ground, so here it has likely been eroded away', -$depth, $u);
            }
            if ($r->{faulted}) {
                my $down = Downthrow::Fault::side_of($f, $fit, $site->{x}, $site->{y}) == ($f->{beta}[3] < 0 ? 1 : 0);
                $txt .= $down ? ' [downthrown side]' : ' [upthrown side]';
            }
            push @o, $txt;
        }
        $line->('');
    }
    $line->('A straight-line, planar model: real beds fold, and faults curve. Use it to plan the next borehole, not to replace it.');
    return join("\n", @o) . "\n";
}

1;
