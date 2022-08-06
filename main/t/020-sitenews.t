#!/usr/bin/env perl
# t/020-sitenews.t - unit tests for WebFetch::Input::SiteNews
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

use Test::More;
use Test::Exception;
use WebFetch;
use WebFetch::Input::SiteNews;

# configuration & constants
Readonly::Scalar my $input_dir => "t/test-inputs/".basename($0, ".t");
Readonly::Scalar my $yaml_file => "test.yaml";
Readonly::Scalar my $basic_tests => 1;

# count tests from data file
sub count_tests
{
    my $test_data = shift;

    return $test_data->{tests};
}

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
my $total_tests = $basic_tests + count_tests($test_data);
plan tests =>  $total_tests;

print STDERR Dumper($test_data); # while under construction, dump the YAML content

# basic tests
ok(defined $test_data, "test data loaded"); # placeholder until more tests keep $basic_tests nonzero
