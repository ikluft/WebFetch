#!/usr/bin/env perl
# 020-spec-samples.t - test WebFetch::Input::RSS with examples from various versions of RSS specifications
# Copyright (c) 2022 by Ian Kluft

use strict;
use warnings;
use utf8;
use autodie;
use Readonly;
use File::Temp;
use File::Basename qw(basename);
use File::Compare;
use YAML::XS;
use WebFetch "0.15.1";
use WebFetch::Input::RSS;
use WebFetch::Output::Capture;
use Test::More;
use Data::Dumper;    # TODO remove

# configuration & constants
Readonly::Scalar my $classname       => "WebFetch::Input::SiteNews";
Readonly::Scalar my $src_format      => "rss";
Readonly::Scalar my $dest_format     => "capture";
Readonly::Scalar my $debug_mode      => ( exists $ENV{WEBFETCH_TEST_DEBUG} and $ENV{WEBFETCH_TEST_DEBUG} ) ? 1 : 0;
Readonly::Scalar my $input_dir       => "t/test-inputs/" . basename( $0, ".t" );
Readonly::Scalar my $tmpdir_template => "WebFetch-XXXXXXXXXX";
Readonly::Array my @test_files       => qw(
    rss-0.90-sample.xml rss-0.91-complete.xml rss-0.91-from-2.0-spec.xml rss-0.91-intl.xml rss-0.91-simple.xml
    rss-0.92-from-2.0-spec.xml rss-1.0-modules.xml rss-1.0-simple.xml rss-2.0-sample.xml
);

# count tests from entries in @test_files array
sub count_tests
{
    return int @test_files;
}

# read and return input data from RSS/XML file
sub read_in_data
{
    my $params = shift;
    my %test_probe;
    my %Options = (
        dir           => $params->{temp_dir},
        source_format => $src_format,
        source        => "file://" . $input_dir . "/" . $params->{in},
        dest_format   => $dest_format,
        dest          => "",                                             # unused
        debug         => $debug_mode,
    );
    WebFetch::Input::RSS->run( \%Options );
    return WebFetch::Output::Capture::data_records();
}

# read and return expected data from YAML file
sub read_exp_data
{
    my $params = shift;
}

# test a single RSS input file against its expected output
sub do_test_file
{
    my $params = shift;
    $params->{exp} = basename( $params->{in}, ".xml" ) . "-expected.yml";
SKIP: {
        if ( not -f $input_dir . "/" . $params->{in} ) {
            skip $params->{in} . ": test data file not found", 1;
        }
        if ( not -f $input_dir . "/" . $params->{exp} ) {
            skip $params->{in} . ": expected output data file not found - nothing to compare", 1;
        }
        my $in_data  = read_in_data($params);
        my $exp_data = read_exp_data($params);
        is_deeply( $in_data, $exp_data, "compare " . $params->{in} . " vs " . $params->{exp} );
    }
}

# run tests - compare each RSS input file to expected output
sub do_tests
{
    my $temp_dir = shift;
    foreach my $in_file (@test_files) {
        my %test_params = ( temp_dir => $temp_dir, in => $in_file );
        do_test_file( \%test_params );
    }
}

#
# mainline
#

# initialize debug mode setting and temporary directory for WebFetch
# In debug mode the temp directory is not cleaned up (deleted) so that its contents can be examined.
# For later manual cleanup, the temp dirs are easy to find named WebFetch-... in the system's temp dir location.
WebFetch::debug_mode($debug_mode);
my $temp_dir = File::Temp->newdir(
    TEMPLATE => $tmpdir_template,
    CLEANUP  => ( $debug_mode ? 0 : 1 ),
    TMPDIR   => 1
);

# run tests
plan tests => count_tests();
do_tests($temp_dir);
