#!/usr/bin/env perl
# t/013-sitenews.t - unit tests for WebFetch::Input::SiteNews
use strict;
use warnings;
use utf8;
use autodie;
use open ':std', ':encoding(utf8)';
use Carp;
use Data::Dumper;
use File::Basename;
use Readonly;
use YAML::XS;

use Test::More skip_all => "under construction";
use Test::Exception;
use WebFetch;
use WebFetch::Input::SiteNews;

# test input files configuration
Readonly::Scalar my $input_dir => "t/test-inputs/".basename($0, ".t");
Readonly::Scalar my $yaml_file => "test.yaml";

#
# main
#

# locate YAML file with test data
if (! -d $input_dir) {
        BAIL_OUT("can't find test inputs directory: expected $input_dir");
}
my $yaml_path = $input_dir."/".$yaml_file;
if ( not -e $yaml_path) {
        BAIL_OUT("can't find YAML test input $yaml_path");
}

# load test data from YAML
my @yaml_docs = YAML::XS::LoadFile($yaml_path);
my $test_data = $yaml_docs[0];
my $total_tests = 0 + $test_data->{basic_tests};
plan tests => $total_tests;

print Dumper($test_data); # while under construction, dump the YAML content

# basic tests
is(defined $test_data, "test data loaded");
