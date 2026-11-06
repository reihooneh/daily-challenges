package Tubewise::Font;
# A single-stroke capital font for neon: each glyph is a few polylines on a grid 4 units wide and
# 6 tall (y up). Strokes may cross or touch; the graph builder splits them where they meet.
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
our @EXPORT_OK = qw(glyph glyph_chars layout ADVANCE);

use constant ADVANCE => 5.5;    # grid units from one letter's left edge to the next

my %GLYPH = (
    'A' => ['0,0 2,6 4,0', '1,3 3,3'],
    'B' => ['0,0 0,6 3,6 4,5 4,4 3,3 0,3', '3,3 4,2 4,1 3,0 0,0'],
    'C' => ['4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1'],
    'D' => ['0,0 0,6 2,6 4,4 4,2 2,0 0,0'],
    'E' => ['4,6 0,6 0,0 4,0', '0,3 3,3'],
    'F' => ['4,6 0,6 0,0', '0,3 3,3'],
    'G' => ['4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1 4,3 2,3'],
    'H' => ['0,0 0,6', '4,0 4,6', '0,3 4,3'],
    'I' => ['1,6 3,6', '2,6 2,0', '1,0 3,0'],
    'J' => ['4,6 4,1 3,0 1,0 0,1'],
    'K' => ['0,0 0,6', '4,6 0,2', '1,3 4,0'],
    'L' => ['0,6 0,0 4,0'],
    'M' => ['0,0 0,6 2,3 4,6 4,0'],
    'N' => ['0,0 0,6 4,0 4,6'],
    'O' => ['1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0'],
    'P' => ['0,0 0,6 3,6 4,5 4,4 3,3 0,3'],
    'Q' => ['1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0', '2,2 4,0'],
    'R' => ['0,0 0,6 3,6 4,5 4,4 3,3 0,3', '2,3 4,0'],
    'S' => ['4,5 3,6 1,6 0,5 0,4 1,3 3,3 4,2 4,1 3,0 1,0 0,1'],
    'T' => ['0,6 4,6', '2,6 2,0'],
    'U' => ['0,6 0,1 1,0 3,0 4,1 4,6'],
    'V' => ['0,6 2,0 4,6'],
    'W' => ['0,6 1,0 2,4 3,0 4,6'],
    'X' => ['0,0 4,6', '0,6 4,0'],
    'Y' => ['0,6 2,3 4,6', '2,3 2,0'],
    'Z' => ['0,6 4,6 0,0 4,0'],
    '0' => ['1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0', '0,1 4,5'],
    '1' => ['1,5 2,6 2,0', '1,0 3,0'],
    '2' => ['0,5 1,6 3,6 4,5 4,4 0,0 4,0'],
    '3' => ['0,5 1,6 3,6 4,5 4,4 3,3 4,2 4,1 3,0 1,0 0,1', '1,3 3,3'],
    '4' => ['3,0 3,6 0,2 4,2'],
    '5' => ['4,6 0,6 0,3 3,3 4,2 4,1 3,0 0,0'],
    '6' => ['4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1 4,2 3,3 0,3'],
    '7' => ['0,6 4,6 1,0'],
    '8' => ['1,3 0,4 0,5 1,6 3,6 4,5 4,4 3,3 1,3 0,2 0,1 1,0 3,0 4,1 4,2 3,3'],
    '9' => ['0,1 1,0 3,0 4,1 4,5 3,6 1,6 0,5 0,4 1,3 4,3'],
    '-' => ['1,3 3,3'],
    '!' => ['2,6 2,2', '2,1 2,0'],
    '.' => ['1.5,0 2.5,0'],
);

sub glyph_chars { return join '', sort keys %GLYPH }

# The glyph's strokes as lists of [x, y] points, in grid units.
sub glyph {
    my ($ch) = @_;
    return [] if $ch eq ' ';
    my $g = $GLYPH{$ch} or return;
    return [ map { [ map { [ split /,/ ] } split / / ] } @$g ];
}

# Strokes for a line of text: [ [x, y], ... ] polylines in millimetres, each tagged with the index
# of its character, at the given cap height (mm).
sub layout {
    my ($text, $height) = @_;
    my $unit = $height / 6;
    my @strokes;
    my $i = 0;
    for my $ch (split //, $text) {
        my $g = glyph($ch);
        my $x0 = $i * ADVANCE;
        for my $s (@$g) {
            push @strokes, { char => $i, points => [ map { [ ($x0 + $_->[0]) * $unit, $_->[1] * $unit ] } @$s ] };
        }
        $i++;
    }
    return \@strokes;
}

1;
