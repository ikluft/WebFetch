#!/usr/bin/env perl
# t/012-config-wrappers.t - test WebFetch wrapper functions around WebFetch::Data::Config
use strict;
use warnings;
use utf8;
use Carp;
use open ':std', ':encoding(utf8)';
use Test::More;
use Test::Exception;
use WebFetch;

# test data
my %samples = (
    "foo" => "bar",
    "🙈" => "see no evil",
    "🙉" => "hear no evil",
    "🙊" => "speak no evil",
);

# count test cases
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDERR, ":encoding(UTF-8)");
plan tests => 2 + int(keys %samples) * 6;

# test reading and writing configuration data

# insert and verify samples
foreach my $key (sort keys %samples) {
    is(WebFetch->has_config($key), 0, "entry '$key' should not exist prior to add");
    my $value = $samples{$key};
    lives_ok(sub {WebFetch->config($key, $value);}, "insert '$key' -> '$value'");
    is(WebFetch->has_config($key), 1, "entry '$key' should exist after add");
    is(WebFetch->config($key), $value, "verify '$key' -> '$value'");
}
is_deeply([sort WebFetch->keys_config()], [sort keys %samples], "verify instance keys from samples after insertion");

# delete and verify config entries
foreach my $key (sort keys %samples) {
    lives_ok(sub {WebFetch->del_config($key);}, "delete '$key'");
    is(WebFetch->has_config($key), 0, "entry '$key' should not exist after delete");
}
is_deeply([sort WebFetch->keys_config()], [], "verify instance keys empty after deletion");

