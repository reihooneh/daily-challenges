package Strandbox::Codec;

# Bytes <-> DNA, one oligo at a time.
#
# The mapping is the "rotating code" from Goldman et al. (2013). A byte is
# written as six base-3 digits (trits). Each trit then picks one of the three
# bases that differ from the previous base. The same base can therefore never
# appear twice in a row, which matters because DNA synthesis and sequencing
# both make most of their mistakes on runs of a repeated base.

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(bytes_to_dna dna_to_bytes crc16 crc32 whiten gc_fraction longest_run);

use constant TRITS_PER_BYTE => 6;    # 3**6 = 729 >= 256

# For each previous base, the three bases a trit 0, 1 or 2 can select.
my %NEXT = (
    A => [qw(C G T)],
    C => [qw(G T A)],
    G => [qw(T A C)],
    T => [qw(A C G)],
);

# The reverse lookup: $TRIT{previous}{base} = trit.
my %TRIT;
for my $prev ( keys %NEXT ) {
    $TRIT{$prev}{ $NEXT{$prev}[$_] } = $_ for 0 .. 2;
}

# Every oligo starts as if the base before it were an A.
use constant START => 'A';

sub bytes_to_dna {
    my ($bytes) = @_;
    my $prev    = START;
    my $dna     = '';
    for my $value ( unpack 'C*', $bytes ) {
        my @trits;
        for ( 1 .. TRITS_PER_BYTE ) {
            unshift @trits, $value % 3;
            $value = int( $value / 3 );
        }
        for my $trit (@trits) {
            $prev = $NEXT{$prev}[$trit];
            $dna .= $prev;
        }
    }
    return $dna;
}

# Returns the bytes, or undef if the DNA is not something bytes_to_dna could
# have produced (wrong letters, a repeated base, wrong length, value over 255).
sub dna_to_bytes {
    my ($dna) = @_;
    return undef if length($dna) % TRITS_PER_BYTE;
    return undef if $dna =~ /[^ACGT]/;
    my $prev  = START;
    my $bytes = '';
    my ( $value, $count ) = ( 0, 0 );
    for my $base ( split //, $dna ) {
        my $trit = $TRIT{$prev}{$base};
        return undef unless defined $trit;    # same base twice in a row
        $value = $value * 3 + $trit;
        $prev  = $base;
        if ( ++$count == TRITS_PER_BYTE ) {
            return undef if $value > 255;
            $bytes .= chr $value;
            ( $value, $count ) = ( 0, 0 );
        }
    }
    return $bytes;
}

# CRC-16/CCITT-FALSE: a short checksum that catches damaged oligos.
sub crc16 {
    my ($bytes) = @_;
    my $crc = 0xFFFF;
    for my $byte ( unpack 'C*', $bytes ) {
        $crc ^= $byte << 8;
        for ( 1 .. 8 ) {
            $crc = $crc & 0x8000 ? ( ( $crc << 1 ) ^ 0x1021 ) & 0xFFFF : ( $crc << 1 ) & 0xFFFF;
        }
    }
    return $crc;
}

# CRC-32 (the one used by zip and PNG): checks the whole file at the end.
sub crc32 {
    my ($bytes) = @_;
    my $crc = 0xFFFFFFFF;
    for my $byte ( unpack 'C*', $bytes ) {
        $crc ^= $byte;
        for ( 1 .. 8 ) {
            $crc = $crc & 1 ? ( $crc >> 1 ) ^ 0xEDB88320 : $crc >> 1;
        }
    }
    return $crc ^ 0xFFFFFFFF;
}

# Whitening: XOR the data with a fixed pseudo-random pattern that depends on
# the oligo's number. Real files are full of repetition (zeros, spaces), and
# repetitive DNA is hard to make and hard to read. After whitening, every
# oligo looks random, which keeps the mix of bases balanced. Applying it a
# second time undoes it. This is NOT encryption: the pattern is public.
sub whiten {
    my ( $bytes, $seed ) = @_;
    my $state = ( ( $seed + 1 ) * 2654435761 ) & 0xFFFFFFFF;
    $state ||= 1;
    my $out = '';
    for my $byte ( unpack 'C*', $bytes ) {
        $state ^= ( $state << 13 ) & 0xFFFFFFFF;    # xorshift32
        $state ^= $state >> 17;
        $state ^= ( $state << 5 ) & 0xFFFFFFFF;
        $out .= chr( $byte ^ ( $state & 0xFF ) );
    }
    return $out;
}

sub gc_fraction {
    my ($dna) = @_;
    return 0 unless length $dna;
    my $gc = () = $dna =~ /[GC]/g;
    return $gc / length $dna;
}

sub longest_run {
    my ($dna) = @_;
    my $longest = 0;
    while ( $dna =~ /((.)\2*)/g ) {
        $longest = length $1 if length $1 > $longest;
    }
    return $longest;
}

1;
