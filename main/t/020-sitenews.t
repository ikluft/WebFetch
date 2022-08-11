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
    ok => \&op_ok,
);

# no-op test just does an ok() to get started
sub op_ok
{
    my ($item, $data, $name);
    ok(1); # don't test anything - just do an ok
}

# count tests from data file
sub count_tests
{
    my $test_data = shift;
    my $count = 0;
    foreach my $file (keys %{$test_data->{files}}) {
        next if ref $test_data->{files}{$file} ne "ARRAY";
        $count += int(@{$test_data->{files}{$file}});
    }
    return $count;
}

#
# create WebFetch::Output::Capture to capture SiteNews data read by WebFetch
#
package WebFetch::Output::Capture;
use base 'WebFetch';
use Try::Tiny;

__PACKAGE__->module_register( "output:capture" );
my @news_items;

# "capture" format handler
# capture function stashes all the received data records from SiteNews for inspection
sub fmt_handler_capture
{
    my ( $self, $filename ) = @_;

    WebFetch::debug "fetch: ".Dumper($self->{data});
    $self->no_savables_ok(); # rather than let WebFetch save the data, we'll take it here
    if (exists $self->{data}{records}) {
        push @news_items, @{$self->{data}{records}};
    }
    return 1;
}

# return the file list
sub news_items
{
    return @news_items;
}

#
# main
#

# back to main package
package main;
use Try::Tiny;

# call WebFetch to process a SiteNews feed
# uses test_probe option of WebFetch->run() so we can inspect WebFetch::Input::SiteNews object and errors
sub capture_feed
{
    my ($dir, $sn_file) = @_;

    # set up WebFetch->new() options
    my %test_probe;
    my %Options = (
        dir => $dir,
        source_format => "sitenews",
        source => $sn_file,
        dest => "capture",
        dest_format => "capture",
        test_probe => \%test_probe,
    );

    # run WebFetch
    try {
        $classname->run(\%Options);
    } catch {
        $test_probe{exception} = $_;
    }

    return \%test_probe;
}


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
            "SiteNews Options[$entry] matches ".(defined $value ? $value : "undef")." in config");
    }
    foreach my $field (qw(Usage num_links)) {
        is($classname->config($field), $config_params->{$field},
            "SiteNews $field matches ".$config_params->{$field}." in config");
    }
}

#
# file-based tests
#

foreach my $file (sort keys %{$test_data->{files}}) {
    next if ref $test_data->{files}{$file} ne "ARRAY";

    # process file as a SiteNews feed
    my $test_data = capture_feed($temp_dir, $file);
    WebFetch::debug "WebFetch run: ".Dumper($test_data);

    # run tests specified in YAML
    foreach my $test_item (@{$test_data->{files}{$file}}) {
        SKIP: {
            my $skip_reason;
            if (not exists $test_item->{op}) {
                $skip_reason = "test operation not specified";
            } elsif (not main->can($test_item->{op})) {
                $skip_reason = "test operation ".$test_item->{op}." not implemented";
            }
            SKIP $skip_reason, 1 if defined $skip_reason;

            my $op = $test_item->{op};
            if (exists $test_ops{$op}) {
                $test_ops{$op}->($test_item, $test_data, "found $file data");
            } else {
                fail("found $file data");
            }
        }
    }
}
