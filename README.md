# WebFetch modules

The main module:

- [WebFetch](main/) - Perl module to download and save information from the Web

  - MetaCPAN: https://metacpan.org/pod/WebFetch

Subsidiary modules which were separated into their own modules due to external dependencies:

- [WebFetch::Input::Atom](submodules/Input-Atom/) - get headlines for WebFetch from Atom feeds
  
  - MetaCPAN: https://metacpan.org/pod/WebFetch::Input::Atom
  - depends on [XML::Atom](https://metacpan.org/pod/XML::Atom)

- [WebFetch::Input::RSS](submodules/Input-RSS/) - get headlines for WebFetch from RSS feed
  
  - MetaCPAN: https://metacpan.org/pod/WebFetch::Input::RSS
  - depends on [XML::RSS](https://metacpan.org/pod/XML::RSS)

- [WebFetch::Output::TT](submodules/Output-TT) - save data from WebFetch via the Perl Template Toolkit
  
  - MetaCPAN: https://metacpan.org/pod/WebFetch::Output::TT
  - depends on [Template Toolkit](https://metacpan.org/pod/Template)

- [WebFetch::Output::TWiki](submodules/Output-TWiki) - save data from WebFetch into a TWiki web site
  
  - MetaCPAN: https://metacpan.org/pod/WebFetch::Output::TWiki
  - depends on [TWiki](https://twiki.org/)

# Description

The WebFetch module is a framework for downloading and saving
information from the web, and for saving or re-displaying it.
It provides a generalized interface for saving to a file
while keeping the previous version as a backup.
This is mainly intended for use in a cron-job to acquire
periodically updated information.

WebFetch allows the user to specify a source and destination, and
the input and output formats.  It is possible to write new Perl modules
to the WebFetch API in order to add more input and output formats.

The currently provided input formats are Atom, RSS, WebFetch "SiteNews" files
and raw Perl data structures.

The currently provided output formats are RSS, WebFetch "SiteNews" files,
the Perl Template Toolkit, and export into a TWiki site.

Some modules which were specific to pre-RSS/Atom web syndication formats
have been deprecated.  Those modules can be found in the CPAN archive
in WebFetch 0.10.  Those modules are no longer compatible with changes
in the current WebFetch API.
