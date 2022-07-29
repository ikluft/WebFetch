# WebFetch
# ABSTRACT: Perl module to download/fetch and save information from the Web
# This module hierarchy is infrastructure for downloading ("fetching") information from
# various sources around the Internet or the local system in order to
# present them for display, or to export local information to other sites
# on the Internet
#
# Copyright (c) 1998-2022 Ian Kluft. This program is free software; you can
# redistribute it and/or modify it under the terms of the GNU General Public
# License Version 3. See  https://www.gnu.org/licenses/gpl-3.0-standalone.html

# pragmas to silence some warnings from Perl::Critic
## no critic (Modules::RequireExplicitPackage)
# This solves a catch-22 where parts of Perl::Critic want both package and use-strict to be first
use strict;
use warnings;
use utf8;
## use critic (Modules::RequireExplicitPackage)

package WebFetch;

=encoding utf8

=head1 SYNOPSIS

  use WebFetch;

=head1 DESCRIPTION

The WebFetch module is a framework for downloading and saving
information from the web, and for saving or re-displaying it.
It provides a generalized interface for saving to a file
while keeping the previous version as a backup.
This is mainly intended for use in a cron-job to acquire
periodically-updated information.

WebFetch allows the user to specify a source and destination, and
the input and output formats.  It is possible to write new Perl modules
to the WebFetch API in order to add more input and output formats.

The currently-provided input formats are Atom, RSS, WebFetch "SiteNews" files
and raw Perl data structures.

The currently-provided output formats are RSS, WebFetch "SiteNews" files,
the Perl Template Toolkit, and export into a TWiki site.

Some modules which were specific to pre-RSS/Atom web syndication formats
have been deprecated.  Those modules can be found in the CPAN archive
in WebFetch 0.10.  Those modules are no longer compatible with changes
in the current WebFetch API.

=head1 INSTALLATION

After unpacking and the module sources from the tar file, run

C<perl Makefile.PL>

C<make>

C<make install>

Or from a CPAN shell you can simply type "C<install WebFetch>"
and it will download, build and install it for you.

If you need help setting up a separate area to install the modules
(i.e. if you don't have write permission where perl keeps its modules)
then see the Perl FAQ.

To begin using the WebFetch modules, you will need to test your
fetch operations manually, put them into a crontab, and then
use server-side include (SSI) or a similar server configuration to 
include the files in a live web page.

=head2 MANUALLY TESTING A FETCH OPERATION

Select a directory which will be the storage area for files created
by WebFetch.  This is an important administrative decision -
keep the volatile automatically-generated files in their own directory
so they'll be separated from manually-maintained files.

Choose the specific WebFetch-derived modules that do the work you want.
See their particular manual/web pages for details on command-line arguments.
Test run them first before committing to a crontab.

=head2 SETTING UP CRONTAB ENTRIES

If needed, see the manual pages for crontab(1), crontab(5) and any
web sites or books on Unix system administration.

Since WebFetch command lines are usually very long, the user may prefer
to make one or more scripts as front-ends so crontab entries aren't so big.

Try not to run crontab entries too often - be aware if the site you're
accessing has any resource constraints, and how often their information
gets updated.  If they request users not to access a feed more often
than a certain interval, respect it.  (It isn't hard to find violators
in server logs.)  If in doubt, try every 30 minutes until more information
becomes available.

=head1 WebFetch FUNCTIONS AND METHODS

The following function definitions assume B<C<$obj>> is a blessed
reference to a module that is derived from (inherits from) WebFetch.

=over 4

=cut

use Carp qw(croak);
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Request;
use Date::Calc;
use WebFetch::Data::Config;

# define exceptions/errors
use Try::Tiny;
use Exception::Class (
	'WebFetch::Exception',
	'WebFetch::TracedException' => {
                isa => 'WebFetch::Exception',
	},

	'WebFetch::Exception::DataWrongType' => {
                isa => 'WebFetch::TracedException',
		alias => 'throw_data_wrongtype',
                description => "provided data must be a WebFetch::Data::Store",
        },

	'WebFetch::Exception::IncompatibleClass' => {
        isa => 'WebFetch::Exception',
        alias => 'throw_incompatible_class',
        description => "class method called for class outside WebFetch hierarchy",
    },

	'WebFetch::Exception::GetoptError' => {
                isa => 'WebFetch::Exception',
		alias => 'throw_getopt_error',
                description => "software error during command line processing",
        },

	'WebFetch::Exception::Usage' => {
                isa => 'WebFetch::Exception',
		alias => 'throw_cli_usage',
		description => "command line processing failed",
	},

	'WebFetch::Exception::Save' => {
                isa => 'WebFetch::Exception',
		alias => 'throw_save_error',
		description => "an error occurred while saving the data",
	},

	'WebFetch::Exception::NoSave' => {
                isa => 'WebFetch::Exception',
		alias => 'throw_no_save',
		description => "unable to save: no data or nowhere to save it",
	},

	'WebFetch::Exception::NoHandler' => {
                isa => 'WebFetch::Exception',
		alias => 'throw_no_handler',
		description => "no handler was found",
	},

	'WebFetch::Exception::MustOverride' => {
                isa => 'WebFetch::TracedException',
		alias => 'throw_abstract',
		description => "A WebFetch function was called which is "
			."supposed to be overridden by a subclass",
	},

	'WebFetch::Exception::NetworkGet' => {
                isa => 'WebFetch::Exception',
                description => "Failed to access RSS feed",
        },

	'WebFetch::Exception::ModLoadFailure' => {
                isa => 'WebFetch::Exception',
		alias => 'throw_mod_load_failure',
                description => "failed to load a WebFetch Perl module",
        },

	'WebFetch::Exception::ModRunFailure' => {
                isa => 'WebFetch::Exception',
		alias => 'throw_mod_run_failure',
                description => "failed to run a WebFetch module",
        },

	'WebFetch::Exception::ModNoRunModule' => {
                isa => 'WebFetch::Exception',
		alias => 'throw_no_run',
                description => "no module was found to run the request",
        },

	'WebFetch::Exception::AutoloadFailure' => {
                isa => 'WebFetch::TracedException',
		alias => 'throw_autoload_fail',
                description => "AUTOLOAD failed to handle function call",
        },

);

# initialize class variables
my %default_modules = (
	"input" => {
		"rss" => "WebFetch::Input::RSS",
		"sitenews" => "WebFetch::Input::SiteNews",
		"perlstruct" => "WebFetch::Input::PerlStruct",
		"atom" => "WebFetch::Input::Atom",
		"dump" => "WebFetch::Input::Dump",
	},
	"output" => {
		"rss" => "WebFetch::Output:RSS",
		"atom" => "WebFetch::Output:Atom",
		"tt" => "WebFetch::Output:TT",
		"perlstruct" => "WebFetch::Output::PerlStruct",
		"dump" => "WebFetch::Output::Dump",
	}
);
my %modules;
our $AUTOLOAD;
my $debug;

sub debug
{
    my @args = @_;
	$debug and print STDERR "debug: ".join( " ", @args )."\n";
    return;
}

=item WebFetch->config( $key, [$value])

This class method is the read/write accessor to WebFetch's key/value configuration store.
If $value is not provided (or is undefied) then this is a read accessor, returning the value of the
configuration entry named by $key.
If $value is defined then this is a write accessor, assigning $value to the configuration entry named by $key.

=cut

# wrapper for WebFetch::Data::Config read/write accessor
sub config
{
    my ($class, $key, $value) = @_;
    if (not $class->isa("WebFetch")) {
        throw_incompatible_class("invalid config() call for '$class': not in the WebFetch hierarchy");
    }
    return WebFetch::Data::Config->accessor($key, $value);
}

=item WebFetch->has_config($key)

This class method returns a boolean value which is true if the configuration entry named by $key exists
in the WebFetch key/value configuration store. Otherwise it returns false.

=cut

# wrapper for WebFetch::Data::Config existence-test method
sub has_config
{
    my ($class, $key) = @_;
    if (not $class->isa("WebFetch")) {
        throw_incompatible_class("invalid has_config() call for '$class': not in the WebFetch hierarchy");
    }
    return WebFetch::Data::Config->contains($key);
}

=item WebFetch->del_config($key)

This class method deletes the configuration entry named by $key.

=cut

# wrapper for WebFetch::Data::Config existence-test method
sub del_config
{
    my ($class, $key) = @_;
    if (not $class->isa("WebFetch")) {
        throw_incompatible_class("invalid del_config() call for '$class': not in the WebFetch hierarchy");
    }
    return WebFetch::Data::Config->del($key);
}

=item WebFetch->import_config(\%hashref)

This class method imports all the key/value pairs from %hashref into the WebFetch configuration.

=cut

sub import_config
{
    my ($class, $hashref) = @_;
    if (not $class->isa("WebFetch")) {
        throw_incompatible_class("invalid import_config() call for '$class': not in the WebFetch hierarchy");
    }

    # import config entries
    foreach my $key (%$hashref) {
        WebFetch::Data::Config->accessor($key, $hashref->{$key});
    }
    return;
}

=item WebFetch->keys_config()

This class method returns a list of the keys in the WebFetch configuration store.
This method was made for testing purposes. That is currently its only foreseen use case.

=cut

sub keys_config
{
    my ($class) = @_;
    if (not $class->isa("WebFetch")) {
        throw_incompatible_class("invalid import_config() call for '$class': not in the WebFetch hierarchy");
    }
    my $instance = WebFetch::Data::Config->instance();
    return keys %$instance;
}

=item WebFetch::module_register( $module, @capabilities );

This function allows a Perl module to register itself with the WebFetch API
as able to perform various capabilities.

For subclasses of WebFetch, it can be called as a class method.
   C<__PACKAGE__-&gt;module_register( @capabilities );>

For the $module parameter, the Perl module should provide its own
name, usually via the __PACKAGE__ string.

@capabilities is an array of strings as needed to list the
capabilities which the module performs for the WebFetch API.

If the first entry of @capabilities is a hash reference, its key/value
pairs are all imported to the WebFetch configuration.

The currently-recognized capabilities are "cmdline", "input" and "output".
"config", "filter", "save" and "storage" are reserved for future use.  The
function will save all the capability names that the module provides, without
checking whether any code will use it.

For example, the WebFetch::Output::TT module registers itself like this:
   C<__PACKAGE__-&gt;module_register( "cmdline", "output:tt" );>
meaning that it defines additional command-line options, and it provides an
output format handler for the "tt" format, the Perl Template Toolkit.

=cut

sub module_register
{
	my ( $module, @capabilities ) = @_;

    # import configuration entries if 1st entry in @capabilities is a hashref
    if (ref $capabilities[0] eq 'HASH') {
        my $config_ref = shift @capabilities;
        WebFetch->import_config($config_ref);
    }

	# each string provided is a capability the module provides
	foreach my $capability ( @capabilities ) {
		# A ":" if present delimits a group of capabilities
		# such as "input:rss" for and "input" capability of "rss"
		if ( $capability =~ /([^:]+):([^:]+)/x ) {
			# A ":" was found so process a 2nd-level group entry
			my $group = $1;
			my $subcap = $2;
			if ( not exists $modules{$group}) {
				$modules{$group} = {};
			}
			if ( not exists $modules{$group}{$subcap}) {
				$modules{$group}{$subcap} = [];
			}
			push @{$modules{$group}{$subcap}}, $module;
		} else {
			# just a simple capbility name so store it
			if ( not exists $modules{$capability}) {
				$modules{$capability} = [];
			}
			push @{$modules{$capability}}, $module;
		}
	}
    return;
}

# module selection - choose WebFetch module based on selected file format
# for WebFetch internal use only
sub module_select
{
	my $capability = shift;
	my $is_optional = shift;

	debug "module_select($capability,$is_optional)";
	# parse the capability string
	my ( $group, $topic );
	if ( $capability =~ /([^:]*):(.*)/x ) {
		$group = $1;
		$topic = $2
	} else {
		$topic = $capability;
	}
	
	# check for modules to handle the specified source_format
	my ( @handlers, %handlers );

	# consider whether a group is in use (single or double-level scan)
	if ( $group ) {
		# double-level scan

		# if the group exists, search in it
		if (( exists $modules{$group}{$topic} )
			and ( ref $modules{$group}{$topic} eq "ARRAY" ))
		{
			# search group for topic
			foreach my $handler (@{$modules{$group}{$topic}})
			{
				if ( not exists $handlers{$handler}) {
					push @handlers, $handler;
					$handlers{$handler} = 1;
				}
			}

		# otherwise check the defaults
		} elsif ( exists $default_modules{$group}{$topic} ) {
			# check default handlers
			my $def_handler = $default_modules{$group}{$topic};
			if ( not exists $handlers{$def_handler}) {
				push @handlers, $def_handler;
				$handlers{$def_handler} = 1;
			}
		}
	} else {
		# single-level scan

		# if the topic exists, the search is a success
		if (( exists $modules{$topic})
			and ( ref $modules{$topic} eq "ARRAY" ))
		{
			@handlers = @{$modules{$topic}};
		}
	}
	
	# check if any handlers were found for this format
	if ( not @handlers and not $is_optional ) {
		throw_no_handler( "handler not found for $capability" );
	}

	debug "module_select: ".join( " ", @handlers );
	return @handlers;
}

# satisfy POD coverage test - but don't put this function in the user manual
=pod
=cut

# if no input or output format was specified, but only 1 is registered, pick it
# $group parameter should be config group to search, i.e. "input" or "output"
# returns the format string which will be provided
sub singular_handler
{
	my $group = shift;

	debug "singular_handler($group)";
	my $count = 0;
	my $last_entry;
	foreach my $entry ( keys %{$modules{$group}} ) {
		if ( ref $modules{$group}{$entry} eq "ARRAY" ) {
			my $entry_count = scalar @{$modules{$group}{$entry}};
			$count += $entry_count;
			if ( $count > 1 ) {
				return;
			}
			if ( $entry_count == 1 ) {
				$last_entry = $entry;
			}
		}
	}

	# if there's only one registered, that's the one to use
	debug "singular_handler: count=$count last_entry=$last_entry";
	return $count == 1 ? $last_entry : undef;
}


=item fetch_main

This function is exported into the main package.
For all modules which registered with an "input" capability for the requested
file format at the time this is called, it will call the run() function on
behalf of each of the packages.

=cut

# Find and run all the fetch_main functions in packages under WebFetch.
# This eliminates the need for the sub-packages to export their own
# fetch_main(), which users found conflicted with each other when
# loading more than one WebFetch-derived module.

# fetch_main - try/catch wrapper for fetch_main2 to catch and display errors
sub main::fetch_main
{
	# run fetch_main2 in a try/catch wrapper to handle exceptions
	try {
        &WebFetch::fetch_main2;
    } catch {
        # process any error/exception that we may have gotten
		my $ex = $_;

		# determine if there's an error message available to display
		my $pkg = __PACKAGE__;
		if ( ref $ex ) {
			if ( my $ex_cap = Exception::Class->caught(
				"WebFetch::Exception"))
			{
				if ( $ex_cap->isa( "WebFetch::TracedException" )) {
					warn $ex_cap->trace->as_string, "\n";
				}

				croak "$pkg: ".$ex_cap->error."\n";
			}
			if ( $ex->can("stringify")) {
				# Error.pm, possibly others
				croak "$pkg: ".$ex->stringify."\n";
			} elsif ( $ex->can("as_string")) {
				# generic - should work for many classes
				croak "$pkg: ".$ex->as_string."\n";
			} else {
				croak "$pkg: unknown exception of type "
					.(ref $ex)."\n";
			}
		} else {
			croak "pkg: $_\n";
		}
	};

	# success
	return 0;
}

# Search for modules which have registered "cmdline" capability.
# Collect command-line options and usage info from modules.
sub collect_cmdline
{
	my ( @mod_options, @mod_usage );
	if (( exists $modules{cmdline} ) and ( ref $modules{cmdline} eq "ARRAY" )) {
		foreach my $cli_mod ( @{$modules{cmdline}}) {
            # obtain ref to module symbol table for backward compatibility with old @Options/$Usage interface
            my $symtab;
            {
                ## no critic (TestingAndDebugging::ProhibitNoStrict)
                no strict 'refs';
                $symtab = \%{$cli_mod."::"};
            }

            # get command line options - try WebFetch config first (preferred), otherwise module symtab (deprecated)
            if (WebFetch->has_config("Options")) {
                push @mod_options, WebFetch->config("Options");
            } elsif ((exists $symtab->{Options}) and int @{$symtab->{Options}}) {
				push @mod_options, @{$symtab->{Options}};
			}

            # get command line usage - try WebFetch config first (preferred), otherwise module symtab (deprecated)
            if (WebFetch->has_config("Usage")) {
                push @mod_usage, WebFetch->config("Usage");
            } elsif ((exists $symtab->{Usage}) and defined ${$symtab->{Usage}}) {
				push @mod_usage, ${$symtab->{Usage}};
			}
		}
	}
    return (\@mod_options, \@mod_usage);
}

# mainline which fetch_main() calls in an exception catching wrapper
sub fetch_main2
{
	# search for modules which have registered "cmdline" capability
	# collect their command line options
	my ( @mod_options, @mod_usage );
    {
        my ($mod_options_ref, $mod_usage_ref) = collect_cmdline();
        @mod_options = @$mod_options_ref;
        @mod_usage = $mod_usage_ref;
    }

	# process command line
	my ($options_result, %options);
	try {
        $options_result = GetOptions ( \%options,
            "dir:s", "group:s", "mode:s", "source=s", "source_format:s", "dest=s",
            "dest_format:s", "fetch_urls", "quiet", "debug",
            @mod_options )
    } catch {
		throw_getopt_error ( "command line processing failed: $_" );
	};
    if ( not $options_result ) {
		throw_cli_usage ( "usage: $0 --dir dirpath "
			."[--group group] [--mode mode] "
			."[--source file] [--source_format fmt-string] "
			."[--dest file] [--dest_format fmt-string] "
			."[--fetch_urls] [--quiet] "
			.join( " ", @mod_usage ));
	}

	# set debugging mode
	if (( exists $options{debug}) and $options{debug}) {
		$debug = 1;
	}
	debug "fetch_main2";

	# if either source/input or dest/output formats were not provided,
	# check if only one handler is registered - if so that's the default
	if ( not exists $options{source_format}) {
		if ( my $fmt = singular_handler( "input" )) {
			$options{source_format} = $fmt;
		}
	}
	if ( not exists $options{dest_format}) {
		if ( my $fmt = singular_handler( "output" )) {
			$options{dest_format} = $fmt;
		}
	}

	# check for modules to handle the specified source_format
	my ( @handlers, %handlers );
	if (( exists $modules{input}{ $options{source_format}} )
		and ( ref $modules{input}{ $options{source_format}}
			eq "ARRAY" ))
	{
		foreach my $handler (@{$modules{input}{$options{source_format}}})
		{
			if ( not exists $handlers{$handler}) {
				push @handlers, $handler;
				$handlers{$handler} = 1;
			}
		}
	}
	if ( exists $default_modules{ $options{source_format}} ) {
		my $handler = $default_modules{ $options{source_format}};
		if ( not exists $handlers{$handler}) {
			push @handlers, $handler;
			$handlers{$handler} = 1;
		}
	}
	
	# check if any handlers were found for this input format
	if ( not @handlers ) {
		throw_no_handler( "input handler not found for "
			.$options{source_format});
	}

	# run the available handlers until one succeeds or none are left
	my $run_count = 0;
	foreach my $pkgname ( @handlers ) {
		debug "running for $pkgname";
		try {
            &WebFetch::run( $pkgname, \%options )
        } catch {
			print STDERR "WebFetch: run exception: $_\n";
		} finally {
            if (not @_) {
                $run_count++;
                last;
            }
		}
	}
	if ( $run_count == 0 ) {
		throw_no_run( "no handlers were able or available to process "
			." source format" );
	}
    return 1;
}

=item $obj = WebFetch::new( param => "value", [...] )

Generally, the new function should be inherited and used from a derived
class.  However, WebFetch provides an AUTOLOAD function which will catch
wayward function calls from a subclass, and redirect it to the appropriate
function in the calling class, if it exists.

The AUTOLOAD feature is needed because, for example, when an object is
instantiated in a WebFetch::Input::* class, it will later be passed to
a WebFetch::Output::* class, whose data method functions can be accessed
this way as if the WebFetch object had become a member of that class.

=cut

# allocate a new object
sub new
{
	my ($class, @args) = @_;
	my $self = {};
	bless $self, $class;

	# initialize the object parameters
    $self->init(@args);

	# go fetch the data
	# this function must be provided by a derived module
	# non-fetching modules (i.e. data) must define $self->{no_fetch}=1
	if (( not exists $self->{no_fetch}) or not $self->{no_fetch}) {
		require WebFetch::Data::Store;
		if ( exists $self->{data}) {
			$self->{data}->isa( "WebFetch::Data::Store" )
				or throw_data_wrongtype "object data must be "
					."a WebFetch::Data::Store";
		} else {
			$self->{data} = WebFetch::Data::Store->new();
		}
		$self->fetch();
	}

	# the object has been created
	return $self;
}

=item $obj->init( ... )

This is called from the C<new> function that modules inherit from WebFetch.
If subclasses override it, they should still call it before completion.
It takes "name" => "value" pairs which are all placed verbatim as
attributes in C<$obj>.

=cut

# initialize attributes of new objects
sub init
{
	my ($self, @args) = @_;
	if ( @args ) {
		my %params = @args;
		@$self{keys %params} = values %params;
	}
    return;
}

=item WebFetch::mod_load ( $class )

This specifies a WebFetch module (Perl class) which needs to be loaded.
In case of an error, it throws an exception.

=cut

sub mod_load
{
	my $pkg = shift;

	# make sure we have the run package loaded
    ## no critic (BuiltinFunctions::ProhibitStringyEval)
    try {
        eval "require $pkg" or croak $@;
    } catch {
		throw_mod_load_failure( "failed to load $pkg: $_" );
	};
    return;
}

=item WebFetch::run

This function can be called by the C<main::fetch_main> function
provided by WebFetch or by another user function.
This handles command-line processing for some standard options,
calling the module-specific fetch function and WebFetch's $obj->save
function to save the contents to one or more files.

The command-line processing for some standard options are as follows:

=over 4

=item --dir I<directory>

(required) the directory in which to write output files

=item --group I<group>

(optional) the group ID to set the output file(s) to

=item --mode I<mode>

(optional) the file mode (permissions) to set the output file(s) to

=item --save_file I<save-file-path>

(optional) save a copy of the fetched info
in the file named by this parameter.
The contents of the file are determined by the C<--dest_format> parameter.
If C<--dest_format> isn't defined but only one module has registered a
file format for saving, then that will be used by default.

=item --quiet

(optional) suppress printed warnings for HTTP errors
I<(applies only to modules which use the WebFetch::get() function)>
in case they are not desired for cron outputs

=item --debug

(optional) print verbose debugging outputs,
only useful for developers adding new WebFetch-based modules
or finding/reporting a bug in an existing module

=back

Modules derived from WebFetch may add their own command-line options
that WebFetch::run() will use by defining a WebFetch configuration entry
called "Options",
containing the name/value pairs defined in Perl's Getopts::Long module.
Derived modules can also add to the command-line usage error message by
defining a configuration entry called "Usage" with a string of the additional
parameters, as they should appear in the usage message.
See the WebFetch->module_register() and WebFetch->config() class methods
for setting configuration entries.

For backward compatibility, WebFetch also looks for @Options and $Usage
in the calling module's symbol table if they aren't found in the WebFetch
configuration. However this method is deprecated and should not be used in
new code. Perl coding best practices have evolved to recommend against using
package variables in the years since the API was first defined.

=cut

# command-line handling for WebFetch-derived classes
sub run
{
	my $run_pkg = shift;
	my $options_ref = shift;
	my $obj;

	debug "entered run for $run_pkg";

	# make sure we have the run package loaded
	mod_load $run_pkg;

	# Note: in order to add WebFetch-embedding capability, the fetch
	# routine saves its raw data without any HTML/XML/etc formatting
	# in @{$obj->{data}} and data-to-savable conversion routines in
	# %{$obj->{actions}}, which contains several structures with key
	# names matching software processing features.  The purpose of
	# this is to externalize the captured data so other software can
	# use it too.

	# create the new object
	# this also calls the $obj->fetch() routine for the module which
	# has inherited from WebFetch to do this
	debug "run before new";
    try {
        $obj = $run_pkg->new(%$options_ref);
    } catch {
		throw_mod_run_failure( "module run failure in $run_pkg: ".$_ );
	};

	# if the object had data for the WebFetch-embedding API,
	# then data processing is external to the fetch routine
	# (This externalizes the data for other software to capture it.)
	debug "run before output";
	my $dest_format = $obj->{dest_format};
	if ( not exists $obj->{actions}) {
		$obj->{actions} = {};
	}
	if (( exists $obj->{data})) {
		if ( exists $obj->{dest}) {
			if (not exists $obj->{actions}{$dest_format}) {
				$obj->{actions}{$dest_format} = [];
			}
			push @{$obj->{actions}{$dest_format}}, [ $obj->{dest} ];
		}

		# perform requested actions on the data
		$obj->do_actions();
	} else {
		throw_no_save( "save failed: no data or nowhere to save it" );
	}

	debug "run before save";
	my $result = $obj->save();

	# check for errors, throw exception to report errors per savable item
	if (not $result) {
		my @errors;
		foreach my $savable ( @{$obj->{savable}}) {
			(ref $savable eq "HASH") or next;
			if ( exists $savable->{error}) {
				push @errors, "file: ".$savable->{file}
					."error: " .$savable->{error};
			}
		}
		if (@errors) {
			throw_save_error( "error saving results in "
				.$obj->{dir}
				."\n".join( "\n", @errors )."\n" );
		}
	}

	return $result ? 0 : 1;
}

=item $obj->do_actions

I<C<do_actions> was added in WebFetch 0.10 as part of the
WebFetch Embedding API.>
Upon entry to this function, $obj must contain the following attributes:

=over 4

=item data

is a reference to a hash containing the following three (required)
keys:

=over 4

=item fields

is a reference to an array containing the names of the fetched data fields
in the order they appear in the records of the I<data> array.
This is necessary to define what each field is called
because any kind of data can be fetched from the web.

=item wk_names

is a reference to a hash which maps from
a key string with a "well-known" (to WebFetch) field type
to a field name used in this table.
The well-known names are defined as follows:

=over 4

=item title

a one-liner banner or title text
(plain text, no HTML tags)

=item url

URL or file path (as appropriate) to the news source

=item id

unique identifier string for the entry

=item date

a date stamp,
which must be program-readable
by Perl's Date::Calc module in the Parse_Date() function
in order to support timestamp-related comparisons
and processing that some users have requested.
If the date cannot be parsed by Date::Calc,
either translate it when your module captures it,
or do not define this "well-known" field
because it wouldn't fit the definition.
(plain text, no HTML tags)

=item summary

a paragraph of summary text in HTML

=item comments

number of comments/replies at the news site
(plain text, no HTML tags)

=item author

a name, handle or login name representing the author of the news item
(plain text, no HTML tags)

=item category

a word or short phrase representing the category, topic or department
of the news item
(plain text, no HTML tags)

=item location

a location associated with the news item
(plain text, no HTML tags)

=back

The field names for this table are defined in the I<fields> array.

The hash only maps for the fields available in the table.
If no field representing a given well-known name is present
in the data fields,
that well-known name key must not be defined in this hash.

=item records

an array containing the data records.
Each record is itself a reference to an array of strings which are
the data fields.
This is effectively a two-dimensional array or a table.

Only one table-type set of data is permitted per fetch operation.
If more are needed, they should be arranged as separate fetches
with different parameters.

=back

=item actions

is a reference to a hash.
The hash keys are names for handler functions.
The WebFetch core provides internal handler functions called
I<fmt_handler_html> (for HTML output), 
I<fmt_handler_xml> (for XML output), 
I<fmt_handler_wf> (for WebFetch::General format), 
However, WebFetch modules may provide additional
format handler functions of their own by prepending
"fmt_handler_" to the key string used in the I<actions> array.

The values are array references containing
I<"action specs">,
which are themselves arrays of parameters
that will be passed to the handler functions
for generating output in a specific format.
There may be more than one entry for a given format if multiple outputs
with different parameters are needed.

The presence of values in this field mean that output is to be
generated in the specified format.
The presence of these would have been chosed by the WebFetch module that
created them - possibly by default settings or by a command-line argument
that directed a specific output format to be used.

For each valid action spec,
a separate "savable" (contents to be placed in a file)
will be generated from the contents of the I<data> variable.

The valid (but all optional) keys are

=over 4

=item html

the value must be a reference to an array which specifies all the
HTML generation (html_gen) operations that will take place upon the data.
Each entry in the array is itself an array reference,
containing the following parameters for a call to html_gen():

=over 4

=item filename

a file name or path string
(relative to the WebFetch output directory unless a full path is given)
for output of HTML text.

=item params

a hash reference containing optional name/value parameters for the
HTML format handler.

=over 4

=item filter_func

(optional)
a reference to code that, given a reference to an entry in
@{$self->{data}{records}},
returns true (1) or false (0) for whether it will be included in the
HTML output.
By default, all records are included.

=item sort_func

(optional)
a reference to code that, given references to two entries in
@{$self->{data}{records}},
returns the sort comparison value for the order they should be in.
By default, no sorting is done and all records (subject to filtering)
are accepted in order.

=item format_func

(optional)
a refernce to code that, given a reference to an entry in
@{$self->{data}{records}},
stores a savable representation of the string.

=back

=back

=back

Additional valid keys may be created by modules that inherit from WebFetch
by supplying a method/function named with "fmt_handler_" preceding the
string used for the key.
For example, for an "xyz" format, the handler function would be
I<fmt_handler_xyz>.
The value (the "action spec") of the hash entry
must be an array reference.
Within that array are "action spec entries",
each of which is a reference to an array containing the list of
parameters that will be passed verbatim to the I<fmt_handler_xyz> function.

When the format handler function returns, it is expected to have
created entries in the $obj->{savables} array
(even if they only contain error messages explaining a failure),
which will be used by $obj->save() to save the files and print the
error messages.

For coding examples, use the I<fmt_handler_*> functions in WebFetch.pm itself.

=back

=cut

sub do_actions
{
	my ( $self ) = @_;
	debug "in WebFetch::do_actions";

	# we *really* need the data and actions to be set!
	# otherwise assume we're in WebFetch 0.09 compatibility mode and
	# $self->fetch() better have created its own savables already
	if ((not exists $self->{data}) or (not exists $self->{actions})) {
		return
	}

	# loop through all the actions
	foreach my $action_spec ( keys %{$self->{actions}} ) {
		my $handler_ref;

		# check for modules to handle the specified dest_format
		my $action_handler = "fmt_handler_".$action_spec;
		if ( exists $modules{output}{$action_spec}) {
			foreach my $class ( @{$modules{output}{$action_spec}}) {
				if ( $class->can( $action_handler )) {
					$handler_ref = \&{$class."::".$action_handler};
					last;
				}
			}
		}

		if ( defined $handler_ref )
		{
			# loop through action spec entries (parameter lists)
			foreach my $entry (@{$self->{actions}{$action_spec}}) {
				# parameters must be in an ARRAY ref
				if (ref $entry ne "ARRAY" ) {
					warn "warning: entry in action spec "
						."\"".$action_spec."\""
						."expected to be ARRAY, found "
						.(ref $entry)." instead "
						."- ignored\n";
					next;
				}

				# everything looks OK - call the handler
				&$handler_ref($self, @$entry);

				# if there were errors, the handler should
				# have created a savable entry which
				# contains only the error entry so that
				# it will be reported by $self->save()
			}
		} else {
			warn "warning: action \"$action_spec\" specified but "
				."\&{\$self->$action_handler}() "
				."not defined in "
				.(ref $self)." - ignored\n";
		}
	}
    return;
}

=item $obj->fetch

B<This function must be provided by each derived module to perform the
fetch operaton specific to that module.>
It will be called from C<new()> so you should not call it directly.
Your fetch function should extract some data from somewhere
and place of it in HTML or other meaningful form in the "savable" array.

TODO: cleanup references to WebFetch 0.09 and 0.10 APIs.

Upon entry to this function, $obj must contain the following attributes:

=over 4

=item dir

The name of the directory to save in.
(If called from the command-line, this will already have been provided
by the required C<--dir> parameter.)

=item savable

a reference to an array where the "savable" items will be placed by
the $obj->fetch function.
(You only need to provide an array reference -
other WebFetch functions can write to it.)

In WebFetch 0.10 and later,
this parameter should no longer be supplied by the I<fetch> function
(unless you wish to use 0.09 backward compatibility)
because it is filled in by the I<do_actions>
after the I<fetch> function is completed
based on the I<data> and I<actions> variables
that are set in the I<fetch> function.
(See below.)

Each entry of the savable array is a hash reference with the following
attributes:

=over 4

=item file

file name to save in

=item content

scalar w/ entire text or raw content to write to the file

=item group

(optional) group setting to apply to file

=item mode

(optional) file permissions to apply to file

=back

Contents of savable items may be generated directly by derived modules
or with WebFetch's C<html_gen>, C<html_savable> or C<raw_savable>
functions.
These functions will set the group and mode parameters from the
object's own settings, which in turn could have originated from
the WebFetch command-line if this was called that way.

=back

Note that the fetch functions requirements changed in WebFetch 0.10.
The old requirement (0.09 and earlier) is supported for backward compatibility.

I<In WebFetch 0.09 and earlier>,
upon exit from this function, the $obj->savable array must contain
one entry for each file to be saved.
More than one array entry means more than one file to save.
The WebFetch infrastructure will save them, retaining backup copies
and setting file modes as needed.

I<Beginning in WebFetch 0.10>, the "WebFetch embedding" capability was introduced.
In order to do this, the captured data of the I<fetch> function 
had to be externalized where other Perl routines could access it.  
So the fetch function now only populates data structures
(including code references necessary to process the data.)

Upon exit from the function,
the following variables must be set in C<$obj>:

=over 4

=item data

is a reference to a hash which will be used by the I<do_actions> function.
(See above.)

=item actions

is a reference to a hash which will be used by the I<do_actions> function.
(See above.)

=back

=cut

# placeholder for fetch routines by derived classes
sub fetch
{
	throw_abstract "fetch is an abstract function and must be overridden by a subclass";
}


=item $obj->get

This WebFetch utility function will get a URL and return a reference
to a scalar with the retrieved contents.
Upon entry to this function, C<$obj> must contain the following attributes: 

=over 4

=item source

the URL to get

=item quiet

a flag which, when set to a non-zero (true) value,
suppresses printing of HTTP request errors on STDERR

=back

=cut

# utility function to get the contents of a URL
sub get
{
        my ( $self, $source ) = @_;

	if (not defined $source) {
		$source = $self->{source};
	}
	if ( $self->{debug}) {
		print STDERR "debug: get(".$source.")\n";
	}

        # send request, capture response
        my $ua = LWP::UserAgent->new;
	$ua->agent("WebFetch/$WebFetch::VERSION ".$ua->agent);
        my $request = HTTP::Request->new(GET => $source);
        my $response = $ua->request($request);

        # abort on failure
        if ($response->is_error) {
                WebFetch::Exception::NetworkGet->throw(
			"The request received an error: "
			.$response->as_string );
        }

        # return the content
        my $content = $response->content;
	return \$content;
}

=item $obj->html_savable( $filename, $content )

I<In WebFetch 0.10 and later, this should be used only in
format handler functions.  See do_actions() for details.>

This WebFetch utility function stores pre-generated HTML in a new entry in
the $obj->{savable} array, for later writing to a file.
It's basically a simple wrapper that puts HTML comments
warning that it's machine-generated around the provided HTML text.
This is generally a good idea so that neophyte webmasters
(and you know there are a lot of them in the world :-)
will see the warning before trying to manually modify
your automatically-generated text.

See $obj->fetch for details on the contents of the C<savable> parameter

=cut

# utility function to make a savable record for HTML text
sub html_savable
{
        my ( $self, $filename, $content ) = @_;

	$self->raw_savable( $filename,
		"<!--- begin text generated by "
		."Perl5 WebFetch $WebFetch::VERSION - do not manually edit --->\n"
		."<!--- WebFetch can be found at "
		."http://www.webfetch.org/ --->\n"
		.$content
		."<!--- end text generated by "
		."Perl5 WebFetch $WebFetch::VERSION - do not manually edit --->\n" );
    return;
}

=item $obj->raw_savable( $filename, $content )

I<In WebFetch 0.10 and later, this should be used only in
format handler functions.  See do_actions() for details.>

This WebFetch utility function stores any raw content and a filename
in the $obj->{savable} array,
in preparation for writing to that file.
(The actual save operation may also automatically include keeping
backup files and setting the group and mode of the file.)

See $obj->fetch for details on the contents of the C<savable> parameter

=cut

# utility function to make a savable record for raw text
sub raw_savable
{
        my ( $self, $filename, $content ) = @_;

	if (not exists $self->{savable}) {
		$self->{savable} = [];
	}
        push ( @{$self->{savable}}, {
                'file' => $filename,
                'content' => $content,
		(( exists $self->{group}) ? ('group' => $self->{group}) : ()),
		(( exists $self->{mode}) ? ('mode' => $self->{mode}) : ())
                });
    return;
}

=item $obj->direct_fetch_savable( $filename, $source )

I<This should be used only in format handler functions.
See do_actions() for details.>

This adds a task for the save function to fetch a URL and save it
verbatim in a file.  This can be used to download links contained
in a news feed.

=cut

sub direct_fetch_savable
{
	my ( $self, $url ) = @_;

	if (not exists $self->{savable}) {
		$self->{savable} = [];
	}
	my $filename = $url;
	$filename =~ s=[;?].*==x;
	$filename =~ s=^.*/==x;
	push ( @{$self->{savable}}, {
		'url' => $url,
		'file' => $filename,
		'index' => 1,
		(( exists $self->{group}) ? ('group' => $self->{group}) : ()),
		(( exists $self->{mode}) ? ('mode' => $self->{mode}) : ())
		});
    return;
}

=item $obj->no_savables_ok

This can be used by an output function which handles its own intricate output
operation (such as WebFetch::Output::TWiki).  If the savables array is empty,
it would cause an error.  Using this function drops a note in it which
basically says that's OK.

=cut

sub no_savables_ok
{
	my $self = shift;

	push ( @{$self->{savable}}, {
		'ok_empty' => 1,
		});
    return;
}

# check conditions are met to perform a save()
# internal method used by save()
sub _save_precheck
{
	my $self = shift;

	# check if we have attributes needed to proceed
	if (not exists $self->{"dir"}) {
		croak "WebFetch: directory path missing - required for save\n";
	}
	if (not exists $self->{savable}) {
		croak "WebFetch: nothing to save\n";
	}
	if ( ref($self->{savable}) ne "ARRAY" ) {
		croak "WebFetch: cannot save - savable is not an array\n";
	}
    return;
}

# convert link fields to savables
# internal method used by save()
sub _save_fetch_urls
{
	my $self = shift;

	# if fetch_urls is defined, turn link fields in the data to savables
	if (( exists $self->{fetch_urls}) and $self->{fetch_urls}) {
		my $entry;
		$self->data->reset_pos;
		while ( $entry = $self->data->next_record()) {
			my $url = $entry->url;
			if ( defined $url ) {
				$self->direct_fetch_savable( $entry->url );
			}
		}
	}
    return;
}

# write new content for save operation
# internal method used by save()
sub _save_write_content
{
	my ($self, $savable, $new_content) = @_;

    # write content to the "new content" file
    ## no critic (InputOutput::RequireBriefOpen)
    my $new_file;
    if (not open($new_file, ">:encoding(UTF-8)", "$new_content")) {
        $savable->{error} = "cannot open $new_content: $!";
        return 0;
    }
    if (not print $new_file $savable->{content}) {
        $savable->{error} = "failed to write to ".$new_content.": $!";
        close $new_file;
        return 0;
    }
    if (not close $new_file) {
        # this can happen with NFS errors
        $savable->{error} = "failed to close "
            .$new_content.": $!";
        return 0;
    }
    return 1;
}

# save previous main content as old backup
# internal method used by save()
sub _save_main_to_backup
{
	my ($self, $savable, $main_content, $old_content) = @_;

    # move the main content to the old content - now it's a backup
    if ( -f $main_content ) {
        if (not rename $main_content, $old_content ) {
            $savable->{error} = "cannot rename "
                .$main_content." to "
                .$old_content.": $!";
            return 0;
        }
    }
    return 1;
}

# chgrp and chmod the "new content" before final installation
# internal method used by save()
sub _save_file_mode
{
    my ($self, $savable, $new_content) = @_;

    # chgrp the "new content" before final installation
    if ( exists $savable->{group}) {
        my $gid = $savable->{group};
        if ( $gid !~ /^[0-9]+$/ox ) {
            $gid = (getgrnam($gid))[2];
            if (not defined $gid ) {
                $savable->{error} = "cannot chgrp "
                    .$new_content.": "
                    .$savable->{group}
                    ." does not exist";
                return 0;
            }
        }
        if (not chown $>, $gid, $new_content ) {
            $savable->{error} = "cannot chgrp "
                .$new_content." to "
                .$savable->{group}.": $!";
            return 0;
        }
    }

    # chmod the "new content" before final installation
    if ( exists $savable->{mode}) {
        if (not chmod oct($savable->{mode}), $new_content ) {
            $savable->{error} = "cannot chmod "
                .$new_content." to "
                .$savable->{mode}.": $!";
            return 0;
        }
    }
    return 1;
}

# check if content is already in index file
# internal method used by save()
sub _save_check_index
{
    my ($self, $savable) = @_;

    # if a URL was provided and index flag is set, use index file
    my %id_index;
    my ( $timestamp, $filename );
    my $was_in_index = 0;
    if (( exists $savable->{url}) and ( exists $savable->{index}))
    {
        require DB_File;
        tie %id_index, 'DB_File',
            $self->{dir}."/id_index.db",
            &DB_File::O_CREAT|&DB_File::O_RDWR, oct(640);
        if ( exists $id_index{$savable->{url}}) {
            ( $timestamp, $filename ) =
                split /#/x, $id_index{$savable->{url}};
            $was_in_index = 1;
        } else {
            $timestamp = time;
            $id_index{$savable->{url}} =
                $timestamp."#".$savable->{file};
        }
        untie %id_index ;
    }

    # For now, we consider it done if the file was in the index.
    # Future options would be to check if URL was modified.
    if ( $was_in_index ) {
        return 0;
    }
    return 1;
}

# if a URL was provided and no content, get content from URL
# internal method used by save()
sub _save_fill_empty_from_url
{
    my ($self, $savable) = @_;

    # if a URL was provided and no content, get content from URL
    if ((not exists $savable->{content}) and ( exists $savable->{url}))
    {
        try {
            $savable->{content} = ${$self->get($savable->{url})}; 
        } catch {
            return 0;
        }
    }
    return 1;
}

# print errors from save operation
# internal method used by save()
sub _save_report_errors
{
    my ($self) = @_;

	# loop through savable to report any errors
	my $err_count = 0;
	foreach my $savable ( @{$self->{savable}}) {
		if ( exists $savable->{error}) {
			print STDERR "WebFetch: failed to save "
				.$savable->{file}.": "
				.$savable->{error}."\n";
			$err_count++;
		}
	}
	if ( $err_count ) {
		croak "WebFetch: $err_count errors - fetch/save failed\n";
	}
    return;
}

=item $obj->save

This WebFetch utility function goes through all the entries in the
$obj->{savable} array and saves their contents,
providing several services such as keeping backup copies, 
and setting the group and mode of the file, if requested to do so.

If you call a WebFetch-derived module from the command-line run()
or fetch_main() functions, this will already be done for you.
Otherwise you will need to call it after populating the
C<savable> array with one entry per file to save.

Upon entry to this function, C<$obj> must contain the following attributes: 

=over 4

=item dir

directory to save files in

=item savable

names and contents for files to save

=back

See $obj->fetch for details on the contents of the C<savable> parameter

=cut

# file-save routines for all WebFetch-derived classes
sub save
{
	my $self = shift;

	if ( $self->{debug} ) {
		print STDERR "entering save()\n";
	}

	# check if we have attributes needed to proceed
    $self->_save_precheck();

	# if fetch_urls is defined, turn link fields in the data to savables
    $self->_save_fetch_urls();

	# loop through "savable" (grouped content and filename destination)
	foreach my $savable ( @{$self->{savable}}) {

		if (exists $savable->{file}) {
			debug "saving ".$savable->{file}."\n";
		}

		# an output module may have handled a more intricate operation
		last if (exists $savable->{ok_empty});

		# verify contents of savable record
		if (not exists $savable->{file}) {
			$savable->{error} = "missing file name - skipped";
			next;
		}
		if ((not exists $savable->{content}) and (not exists $savable->{url}))
		{
			$savable->{error} = "missing content or URL - skipped";
			next;
		}

		# generate file names
		my $new_content = $self->{"dir"}."/N".$savable->{file};
		my $main_content = $self->{"dir"}."/".$savable->{file};
		my $old_content = $self->{"dir"}."/O".$savable->{file};

		# make sure the Nxx "new content" file does not exist yet
		if ( -f $new_content ) {
			if (not unlink $new_content ) {
				$savable->{error} = "cannot unlink "
					.$new_content.": $!";
				next;
			}
		}

		# if a URL was provided and index flag is set, use index file
        if (not $self->_save_check_index($savable)) {
            # done since it was found in the index
            next;
        }

		# if a URL was provided and no content, get content from URL
        if (not $self->_save_fill_empty_from_url($savable)) {
            # error occurred - available in $savable->{error}
            next;
        }

		# write content to the "new content" file
        if (not $self->_save_write_content($savable, $new_content)) {
            # error occurred - available in $savable->{error}
            next;
        }

		# remove the "old content" file to get it out of the way
		if ( -f $old_content ) {
			if (not unlink $old_content ) {
				$savable->{error} = "cannot unlink "
					.$old_content.": $!";
				next;
			}
		}

		# move the main content to the old content - now it's a backup
        if (not $self->_save_main_to_backup($savable, $main_content), $old_content) {
            # error occurred - available in $savable->{error}
            next;
        }

        # chgrp and chmod the "new content" before final installation
        if (not $self->_save_file_mode($savable, $new_content)) {
            # error occurred - available in $savable->{error}
            next;
        }

		# move the new content to the main content - final install
		if ( -f $new_content ) {
			if (not rename $new_content, $main_content ) {
				$savable->{error} = "cannot rename "
					.$new_content." to "
					.$main_content.": $!";
				next;
			}
		}
	}

	# loop through savable to report any errors
    $self->_save_report_errors();

	# success if we got here
	return 1;
}

#
# shortcuts to data object functions
#

sub data { my $self = shift; return $self->{data}; }
sub wk2fname { my ($self, @args) = @_; return $self->{data}->wk2fname(@args)};
sub fname2fnum { my ($self, @args) = @_; return $self->{data}->fname2fnum(@args)};
sub wk2fnum { my ($self, @args) = @_; return $self->{data}->wk2fnum(@args)};

=item AUTOLOAD functionality

When a WebFetch input object is passed to an output class, operations
on $self would not usually work.  WebFetch subclasses are considered to be
cooperating with each other.  So WebFetch provides AUTOLOAD functionality
to catch undefined function calls for its subclasses.  If the calling 
class provides a function by the name that was attempted, then it will
be redirected there.

=back

=cut

# autoloader catches calls to unknown functions
# redirect to the class which made the call, if the function exists
## no critic (ClassHierarchies::ProhibitAutoloading Subroutines::RequireFinalReturn)
sub AUTOLOAD
{
	my ($self, @args) = @_;
	my $name = $AUTOLOAD;
	my $type = ref($self) or throw_autoload_fail "AUTOLOAD failed on $name: self is not an object";

	$name =~ s/.*://x;   # strip fully-qualified portion, just want function

	# decline all-caps names - reserved for special Perl functions
	my ( $package, $filename, $line ) = caller;
	( $name =~ /^[A-Z]+$/x ) and return;
	debug __PACKAGE__."::AUTOLOAD $name";

	# check for function in caller package
	# (WebFetch may hand an input module's object to an output module)
	if ( $package->can( $name )) {
		# make an alias of the sub
		{
            ## no critic (TestingAndDebugging::ProhibitNoStrict)
			no strict 'refs';
			*{__PACKAGE__."::".$name} = \&{$package."::".$name};
		}
		my $retval;
        try {
            $retval = $self->$name( @args );
        } catch {
			my $e = Exception::Class->caught();
			ref $e ? $e->rethrow
				: throw_autoload_fail "failure in "
					."autoloaded function: ".$e;
		};
		return $retval;
	}

	# if we got here, we failed
	throw_autoload_fail "function $name not found - "
		."called by $package ($filename line $line)";
}
## critic (ClassHierarchies::ProhibitAutoloading Subroutines::RequireFinalReturn)

1;
__END__
# remainder of POD docs follow

=head2 WRITING WebFetch-DERIVED MODULES

The easiest way to make a new WebFetch-derived module is to start
from the module closest to your fetch operation and modify it.
Make sure to change all of the following:

=over 4

=item fetch function

The fetch function is the meat of the operation.
Get the desired info from a local file or remote site and place the
contents that need to be saved in the C<savable> parameter.

=item module name

Be sure to catch and change them all.

=item file names

The code and documentation may refer to output files by name.

=item module parameters

Change the URL, number of links, etc as necessary.

=item command-line parameters

If you need to add command-line parameters, modify both the
B<C<@Options>> and B<C<$Usage>> variables.
Don't forget to add documentation for your command-line options
and remove old documentation for any you removed.

When adding documentation, if the existing formatting isn't enough
for your changes, there's more information about
Perl's
POD ("plain old documentation")
embedded documentation format at
http://www.cpan.org/doc/manual/html/pod/perlpod.html

=item authors

Do not modify the names unless instructed to do so.
The maintainers have discretion whether one's contributions are significant enough to qualify as a co-author.

=back

Please consider contributing any useful changes back to the WebFetch
project at C<maint@webfetch.org>.

=head1 ACKNOWLEDGEMENTS

WebFetch was written by Ian Kluft
Send patches, bug reports, suggestions and questions to
C<maint@webfetch.org>.

Some changes in versions 0.12-0.13 (Aug-Sep 2009) were made for and
sponsored by Twiki Inc (formerly TWiki.Net).

=head1 LICENSE

WebFetch is Open Source software licensed under the GNU General Public License Version 3.
See L<https://www.gnu.org/licenses/gpl-3.0-standalone.html>.

=head1 SEE ALSO

Included in WebFetch module: 
L<WebFetch::Input::PerlStruct>,
L<WebFetch::Input::SiteNews>,
L<WebFetch::Output::Dump>,
L<WebFetch::Data::Config>,
L<WebFetch::Data::Record>,
L<WebFetch::Data::Store>

Modules separated to contain external module dependencies:
L<WebFetch::Input::Atom>,
L<WebFetch::Input::RSS>,
L<WebFetch::Output::TT>,
L<WebFetch::Output::TWiki>,

Source code repository:
L<https://github.com/ikluft/WebFetch>

=head1 BUGS AND LIMITATIONS

Please report bugs via GitHub at L<https://github.com/ikluft/WebFetch/issues>

Patches and enhancements may be submitted via a pull request at L<https://github.com/ikluft/WebFetch/pulls>

=cut
