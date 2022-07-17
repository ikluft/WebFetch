#!perl -T

use strict;
use warnings;
use Test::More;
use Try::Tiny;

# always test these modules can load
my @modules = qw(
    WebFetch
    WebFetch::Data::Store
    WebFetch::Data::Record
    WebFetch::Input::PerlStruct
    WebFetch::Input::SiteNews
    WebFetch::Output::Dump
);

# only test these modules can load if their dependency exists on the system
my %dependencies = (
    "WebFetch::Input::Atom" => "XML::Atom::Client",
    "WebFetch::Input::RSS" => "XML::RSS",
    "WebFetch::Output::TT" => "Template",
    "WebFetch::Output::TWiki" => "TWiki",
);

# count tests
plan tests => (int(@modules) + int(keys %dependencies));

# test loading modules
foreach my $mod (@modules) {
    use_ok($mod);
}

# check conditional module dependencies - skip module load test if not present
my %dep_found;
foreach my $mod (sort keys %dependencies) {
    $dep_found{$mod} = 1;
    try {
        ## no critic (BuiltinFunctions::ProhibitStringyEval)
        eval "use $dependencies{$mod}";
    } catch {
        $dep_found{$mod} = 0;
    };

    SKIP: {
        skip "Optional module '$dependencies{$mod}' not installed", 1 unless $dep_found{$mod};
        use_ok($mod);
    }
}

require WebFetch;
diag( "Testing WebFetch $WebFetch::VERSION, Perl $], $^X" );
