#!/usr/bin/env perl
# t/020-sitenews.t - unit tests for WebFetch::Input::SiteNews
use strict;
use warnings;
use utf8;
use autodie;
use open ':std', ':encoding(utf8)';
use Carp;
use Data::Dumper;
use File::Temp;
use File::Basename;
use Readonly;
use YAML::XS;

use Test::More;
use Test::Exception;
use WebFetch;
use WebFetch::Input::SiteNews;

# configuration & constants
Readonly::Scalar my $classname => "WebFetch::Input::SiteNews";
Readonly::Scalar my $service_name => "sitenews";
Readonly::Scalar my $debug_mode => (exists $ENV{WEBFETCH_TEST_DEBUG} and $ENV{WEBFETCH_TEST_DEBUG}) ? 1 : 0;
Readonly::Scalar my $input_dir => "t/test-inputs/".basename($0, ".t");
Readonly::Scalar my $yaml_file => "test.yaml";
Readonly::Scalar my $basic_tests => 9;
Readonly::Hash my %test_ops => (

);

# count tests from data file
sub count_tests
{
    my $test_data = shift;
    my $count = 0;
    foreach my $file (@{$test_data->{files}}) {
        next if ref $file ne "ARRAY";
        $count += int(@$file);
    }
    return $count;
}

#
# main
#

# initialization
WebFetch::debug_mode($debug_mode);
my $temp_dir = File::Temp->newdir(CLEANUP => ($debug_mode ? 0 : 1)); # temporary directory required by WebFetch

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

#
# basic tests
#

# verify WebFetch module registry settings arrived from WebFetch::Input::SiteNews
my $cmdline_reg = $classname->_module_registry("cmdline");
my $input_reg = $classname->_module_registry("input");
is((grep {/^$classname$/} @$cmdline_reg), 1, "$classname registered as a cmdline module");
ok(exists $input_reg->{$service_name}, "$classname registered '$service_name' as an input module");
is((grep {/^$classname$/} @{$input_reg->{$service_name}}), 1, "$classname registered as input:$service_name module");

# compare Options and Usage from WebFetch::Config with those in WebFetch::Input::SiteNews symbol table
ok(WebFetch->has_config("Options"), "Options has been set in WebFetch::Config");
ok(WebFetch->has_config("Usage"), "Usage has been set in WebFetch::Config");
{
    my $config_params = $classname->_config_params();
    my $got = $classname->config('Options');
    my $expected = $config_params->{Options};
    for (my $entry=0; $entry < int(@$expected); $entry++) {
        my $value = $expected->[$entry];
        is($got->[$entry], $value,
            "$classname Options data[$entry] matches ".(defined $value ? $value : "undef")." in WebFetch::Config");
    }
    foreach my $field (qw(Usage num_links)) {
        is($classname->config($field), $config_params->{$field},
            "$classname $field matches ".$config_params->{$field}." in WebFetch::Config");
    }
}

#
# file-based tests
#

# TBD
