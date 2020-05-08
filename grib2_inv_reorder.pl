#!/usr/bin/env perl

# Change small grib file inventory order to desired order

use strict;
use warnings;
use utf8;

use Data::Dumper;

# Enumerate all atmospheric(?) levels from 1000 mb to 700 mb
sub layers
{
    my @vars = @_;
    my @m;
    for my $v (@vars) {
        for (my $z = 1000; $z >= 700; $z -= 25) {
            push @m, "$v:${z}mb";
        }
    }
    return @m;
}

my %msgs;
my $features_in = 0;
while (<>) {
    chomp();
    my ($var, $z) = ( split /:/ )[3,4];
    $z =~ s/ above ground$/AG/;
    $z =~ s/\s+//g;
    $msgs{"$var:$z"} = $_;
    $features_in++;
}

my @msgs_out = ();
push @msgs_out, qw( UGRD:10mAG VGRD:10mAG ), layers( qw(UGRD VGRD VVEL TKE) ), 'TMP:surface', 'TMP:2mAG', layers('TMP', 'RH'), 'DPT:2mAG', 'FRICV:surface', 'VIS:surface', 'RH:2mAG', 'PRES:surface';
my $count = scalar @msgs_out;
die "?Inventory count mismatch between input ($features_in) and output ($count), dying horribly...\n" unless ($features_in == $count);
print map { "$msgs{$_}\n"; } @msgs_out;
