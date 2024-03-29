#!/usr/bin/env perl

# Parse CSV output from wgrib2 and combine multiple variables onto single lines

use strict;
use warnings;
use utf8;
use 5.010;

use Data::Dumper;
use Time::Local;

# XXX  Depending on how many times this code is revisted, it might be
#      worth turning cache and line into an object (w/ Moo).  However,
#      this *will* impact portability and likely prevent running on the
#      HPC w/o extra software installation/configuration (pain, suffering)

# Return empty cache
sub cache_empty
{
    return {
        model_cycle => '',
        pred_time => '',
        lat => '',
        lon => '',
        var_map => { },
    };
}

# Return 0 if this line doesn't belong in the cache, 1 if it does
sub cache_match
{
    my ($cache_href, $line_href) = @_;

    return 1 if not $cache_href->{model_cycle} ; # cache empty
    for my $k (qw( model_cycle pred_time lat lon )) {
        return 0 if $cache_href->{$k} ne $line_href->{$k};
    }
    return 1;
}

# Add line to cache
sub cache_add
{
    my ($cache_href, $line_href) = @_;

    if (not $cache_href->{model_cycle}) { # cache empty
        for my $k (qw( model_cycle pred_time lat lon )) {
            $cache_href->{$k} = $line_href->{$k};
        }
    }
    my $name = join '.', map { s/(?:^"|"$)//g; $_; } $line_href->{level}, $line_href->{field};
    $cache_href->{var_map}->{$name} = $line_href->{value};
}

# Convert date string to Unix time (seconds since epoch)
sub date2sse
{
    my ($date) = @_;

    my $sse;                            # seconds since epoch
    if ( my ($year, $month, $mday, $hour) = ($date =~ m/^"(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):00:00"$/) )
    {
        $month--;
        $sse = timegm(0, 0, $hour, $mday, $month, $year);
    }
    return $sse;
}

# Output cache to stdout as single CSV line
sub cache_emit
{
    state @param_order;

    my ($href) = @_;                    # cache
    # If parameter order doesn't yet exist, generate it and output header
    if (scalar(@param_order) == 0) {
        # XXX  Numeric sort didn't produce my desired ordering (lexical, then numeric ordering), will have to customize further
        #@param_order = sort { $a <=> $b } keys %{$href->{var_map}};
        @param_order = sort keys %{$href->{var_map}};
        print qq(model_cycle_time,prediction_time,model_cycle,forecast_hour,lat,lon,") . join('","', @param_order) . qq("\n);
    }

    # Hamid needs model cycle and forecast hour in ready-to-consume format
    my $mc_gmt = date2sse($href->{model_cycle});
    my $fh_gmt = date2sse($href->{pred_time});
    my $mc_str = sprintf("%02d", ($mc_gmt % 86400)/3600);
    my $fh_str = sprintf("%02d", ($fh_gmt - $mc_gmt)/3600);
    $href->{mc_str} = $mc_str;
    $href->{fh_str} = $fh_str;

    # XXX  Parse/modify cache values before printing?  E.g., separate date, model cycle, forecast hour
    print join(',', @{$href}{qw(model_cycle pred_time mc_str fh_str lat lon)}, @{$href->{var_map}}{@param_order}) . "\n";
}


my $cache = cache_empty();
while (<>) {
    next if /^\s*$/ or /^\s*#/ ;
    chomp;

    # wgrib2 -csv output field order:
    # model cycle, prediction time, field/variable name, level, lon, lat, value
    #
    # "2018-11-05 00:00:00","2018-11-05 04:00:00","VIS.prob_<400.prob_fcst_0/8","surface",-97.0672,27.8191,0
    unless (m/^"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d"/) {
        warn "?Unexpected output from wgrib2 《$_ 》\n";
        next;
    }

    my %line;
    @line{ qw(model_cycle pred_time field level lon lat value) } = split /,/;

    # Remove 0/n in field name b/c it can vary w/in a given day
    # (e.g., different forecast hours might have 0/8 or 0/5)
    $line{field} =~ s~_\d+/\d+"$~~;

    # Check line against current cache
    # If different emit cache, clear cache
    if (not cache_match($cache, \%line)) {
        cache_emit($cache);
        $cache = cache_empty();
    }
    # Add line to cache
    cache_add($cache, \%line);
}

# Dump remaining cache contents
cache_emit($cache) if scalar(keys %{$cache->{var_map}});
