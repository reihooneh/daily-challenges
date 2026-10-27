package Downthrow::Parse;
# Reads a survey file: where a rock horizon was met in boreholes or at outcrops.
use strict;
use warnings FATAL => 'all';
use Exporter 'import';

our @EXPORT_OK = qw(parse_survey MAX_INPUT);

use constant MAX_INPUT  => 64 * 1024;
use constant MAX_POINTS => 400;
use constant MAX_SITES  => 50;

my $NAME   = qr/\A[A-Za-z0-9][A-Za-z0-9 '.,&()\/-]{0,59}\z/;
my $ID     = qr/\A[A-Za-z0-9][A-Za-z0-9._-]{0,15}\z/;
my $NUMBER = qr/\A-?\d{1,8}(?:\.\d{1,4})?\z/;

sub _fail {
    my ($line, $msg) = @_;
    die { input => ($line ? "line $line: $msg" : $msg) };
}

sub _number {
    my ($text, $limit, $line, $what) = @_;
    _fail($line, "$what must be a plain number like 120.5 (no exponents)") unless defined $text && $text =~ $NUMBER;
    my $v = 0 + $text;
    _fail($line, "$what must be within $limit of zero") if abs($v) > $limit;
    return $v;
}

# Refuses control characters (terminal escapes) and invisible direction or zero-width marks.
sub _check_text {
    my ($text) = @_;
    my $line = 1;
    for my $ch (split //, $text) {
        my $c = ord $ch;
        if ($c == 10) { $line++; next }
        next if $c == 9 || $c == 13;
        if ($c < 32 || ($c >= 0x7f && $c <= 0x9f) || ($c >= 0x200b && $c <= 0x200f)
            || ($c >= 0x202a && $c <= 0x202e) || ($c >= 0x2066 && $c <= 0x2069) || $c == 0xfeff) {
            _fail($line, 'contains a control or hidden character');
        }
    }
    return;
}

# Takes decoded text (characters, not bytes). Dies with { input => message } on any problem.
sub parse_survey {
    my ($text) = @_;
    _fail(0, 'the survey is larger than 64 KB') if length($text) > MAX_INPUT;
    $text =~ s/\A\x{FEFF}//;
    _check_text($text);

    my %s = (name => 'Survey', horizon => 'the horizon', units => 'm', points => [], sections => [], sites => []);
    my (%seen, %ids, %xy);
    my $n = 0;
    for my $raw (split /\n/, $text, -1) {
        $n++;
        _fail($n, 'is longer than 300 characters') if length($raw) > 300;
        (my $body = $raw) =~ s/#.*//;
        $body =~ s/\A\s+|\s+\z//g;
        next if $body eq '';
        my ($key, $rest) = split /\s+/, $body, 2;
        $rest //= '';
        my @w = split /\s+/, $rest;
        my $once = sub {
            _fail($n, "'$key' comes once") if $seen{$key}++;
        };
        if ($key eq 'survey' || $key eq 'horizon') {
            $once->();
            _fail($n, "$key names use letters, digits, spaces and ' . , & ( ) / - (up to 60)") unless $rest =~ $NAME;
            $s{$key eq 'survey' ? 'name' : 'horizon'} = $rest;
        }
        elsif ($key eq 'units') {
            $once->();
            _fail($n, "units are 'm' or 'ft'") unless $rest eq 'm' || $rest eq 'ft';
            $s{units} = $rest;
        }
        elsif ($key eq 'point') {
            _fail($n, "write 'point <id> <east> <north> <elevation>'") unless @w == 4;
            my ($id, @v) = @w;
            _fail($n, 'point ids are letters, digits, . _ - (up to 16)') unless $id =~ $ID;
            _fail($n, 'a point with that id is already listed') if $ids{$id}++;
            _fail($n, 'at most 400 points') if @{ $s{points} } >= MAX_POINTS;
            my $x = _number($v[0], 1e7, $n, 'east');
            my $y = _number($v[1], 1e7, $n, 'north');
            my $z = _number($v[2], 1e5, $n, 'elevation');
            _fail($n, 'another point is at the same place') if $xy{"$x,$y"}++;
            push @{ $s{points} }, { id => $id, x => $x, y => $y, z => $z, line => $n };
        }
        elsif ($key eq 'section') {
            _fail($n, "write 'section <bearing>' with a whole-degree bearing from 0 to 359")
                unless @w == 1 && $w[0] =~ /\A\d{1,3}\z/ && $w[0] < 360;
            _fail($n, 'at most 8 sections') if @{ $s{sections} } >= 8;
            push @{ $s{sections} }, 0 + $w[0];
        }
        elsif ($key eq 'predict') {
            _fail($n, "write 'predict <id> <east> <north> [ground <elevation>]'") unless @w == 3 || (@w == 5 && $w[3] eq 'ground');
            _fail($n, 'site ids are letters, digits, . _ - (up to 16)') unless $w[0] =~ $ID;
            _fail($n, 'at most 50 prediction sites') if @{ $s{sites} } >= MAX_SITES;
            my %site = (id => $w[0], x => _number($w[1], 1e7, $n, 'east'), y => _number($w[2], 1e7, $n, 'north'));
            $site{ground} = _number($w[4], 1e5, $n, 'ground elevation') if @w == 5;
            push @{ $s{sites} }, \%site;
        }
        else {
            _fail($n, 'lines start with survey, horizon, units, point, section or predict');
        }
    }
    _fail(0, 'a plane needs at least 3 points') if @{ $s{points} } < 3;
    return \%s;
}

1;
