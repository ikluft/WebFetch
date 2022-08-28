#!/usr/bin/env perl
# t/020-sitenews.t - unit tests for WebFetch::Input::SiteNews
use strict;
use warnings;
use utf8;
use autodie;
use open ':std', ':encoding(utf8)';
use Carp qw(croak);
use Data::Dumper;
use String::Interpolate::Named;
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
Readonly::Scalar my $file_init_tests => 2;
Readonly::Scalar my $tmpdir_template => "WebFetch-XXXXXXXXXX";

#
# internal WebFetch::Output::Capture class captures SiteNews data read by WebFetch
#
package WebFetch::Output::Capture;
use base 'WebFetch';
use Try::Tiny;
use Data::Dumper;

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

#
# test operations functions op_* used for tests specified in YAML data
#

# autopass test just does a pass() - for starter tests to check test infrastructure runs
sub op_autopass
{
    my ($test_index, $name, $item, $news, $data) = @_;
    pass("autopass: $name ($test_index)"); # don't test anything - just do a pass
    return;
}

# autofail test just does a fail() - called in case of an op with missing implementation function
# this may appear in test data with intentional skip to test skipping
sub op_autofail
{
    my ($test_index, $name, $item, $news, $data) = @_;
    fail("autofail: $name ($test_index)"); # don't test anything - just do a fail
    return;
}

# test: count data records
sub op_record_count
{
    my ($test_index, $name, $item, $news, $data) = @_;
    my $expected_count = $item->{count};
    my $found_count = exists $data->{webfetch}{data}{records} ? int( @{$data->{webfetch}{data}{records}} ) : 0;
    is($found_count, $expected_count, "record count: $name / expect $expected_count ($test_index)");
    return;
}

# from test operation name get function name & ref
# returns a ref to the test operation function, or undef if it doesn't exist
sub test_op
{
    my $op_name = shift;
    my $func_name = "op_".$op_name;
    return main->can($func_name);
}

# count tests from data file
sub count_tests
{
    my $test_data = shift;
    my $count = 0;
    foreach my $file (keys %{$test_data->{files}}) {
        next if ref $test_data->{files}{$file} ne "ARRAY";
        $count += $file_init_tests + int(@{$test_data->{files}{$file}});
    }
    return $count;
}

# call WebFetch to process a SiteNews feed
# uses test_probe option of WebFetch->run() so we can inspect WebFetch::Input::SiteNews object and errors
sub capture_feed
{
    my ($dir, $sn_file) = @_;

    # generate short and long output file names
    my $short_name = basename($sn_file, ".webfetch")."-short.out";
    my $long_name = basename($sn_file, ".webfetch")."-long.out";

    # set up WebFetch->new() options
    WebFetch::debug "capture_feed: sn_file=$sn_file short_name=$short_name long_name=$long_name";
    my %test_probe;
    my %Options = (
        dir => $dir,
        source_format => "sitenews",
        source => $sn_file,
        short_path => $short_name,
        long_path => $long_name,
        dest => "capture",
        dest_format => "capture",
        test_probe => \%test_probe,
        debug => $debug_mode,
    );

    # run WebFetch
    try {
        my $result = $classname->run(\%Options);
        $test_probe{result} = $result;
    } catch {
        WebFetch::debug "capture_feed: $classname->run() threw exception: ".Dumper($_);
        $test_probe{exception} = $_;
    };

    return \%test_probe;
}


# initialize debug mode setting and temporary directory for WebFetch
# In debug mode the temp directory is not cleaned up (deleted) so that its contents can be examined.
WebFetch::debug_mode($debug_mode);
my $temp_dir = File::Temp->newdir(TEMPLATE => $tmpdir_template, CLEANUP => ($debug_mode ? 0 : 1), TMPDIR => 1);

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

# run file-based tests from YAML data
my $test_index = 0;
foreach my $file (sort keys %{$test_data->{files}}) {
    next if ref $test_data->{files}{$file} ne "ARRAY";

    # process file as a SiteNews feed
    WebFetch::debug "capture_feed($temp_dir, $input_dir/$file)";
    my $capture_data = capture_feed($temp_dir, "$input_dir/$file");
    WebFetch::debug "WebFetch run: ".Dumper($capture_data);
    my @news_items = WebFetch::Output::Capture::news_items();
    WebFetch::debug "news items: ".Dumper(\@news_items);

    # per-file initial tests
    ok(not (exists $capture_data->{webfetch}{data}{exception}), "no exceptions in $file ($test_index)");
    $test_index++;
    is($capture_data->{result}, 0, "exitcode 0 expected from $file ($test_index)");
    $test_index++;

    # run tests specified in YAML
    foreach my $test_item (@{$test_data->{files}{$file}}) {
        my $int = String::Interpolate::Named->new( { args => {
            file => $file,
            index => $test_index,
            %$test_item,
        }});
        SKIP: {
            my ($skip_reason, $op_func);
            my $op = $test_item->{op};
            my $name = (exists $test_item->{name}) ? $int->interpolate($test_item->{name}) : "unnamed test";
            if (not defined $op) {
                $skip_reason = "test operation not specified: $name ($test_index)";
            } elsif (exists $test_item->{skip}) {
                $skip_reason = $test_item->{skip}.": $name ($test_index)";
            } else {
                $op_func = test_op($op);
                if (not defined $op_func) {
                    $skip_reason = "test operation $op not implemented: $name ($test_index)";
                }
            }
            skip $skip_reason, 1 if defined $skip_reason;

            if (defined $op_func) {
                $op_func->($test_index, $name, $test_item, \@news_items, $capture_data);
            } else {
                op_autofail($test_index, $name, $test_item, \@news_items, $capture_data);
            }
        }
        $test_index++;
    }
}
