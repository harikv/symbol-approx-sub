#
# Symbol::Approx::Sub
#
# $Id$
#
# Perl module for calling subroutines using approximate names.
#
# Copyright (c) 2000, Magnum Solutions Ltd. All rights reserved.
#
# This module is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# $Log$
# Revision 1.62  2001/07/15 20:47:16  dave
# Version 2 - RC2
#
# Revision 1.61  2001/06/24 20:04:33  dave
# Version 2 - Release Candidate 1
#
# Revision 1.60  2000/11/17 14:33:14  dave
# Changed name (again!)
# Use Devel::Symdump instead of GlobWalker
#
# Revision 1.50  2000/11/09 21:29:27  dave
# Renamed to Approx::Sub
#
# Revision 1.3  2000/10/30 17:20:07  dave
# Removed all glob-walking code to GlobWalker.pm.
#
# Revision 1.2  2000/10/09 18:52:48  dave
# Incorporated Robin's patches:
# * Don't assume we're being called from main
# * Allow different packages to use different Approx semantics
# * New tests
#
# Revision 1.1  2000/08/24 19:50:18  dave
# Various tidying.
#
#
package Symbol::Approx::Sub;

use strict;
use vars qw($VERSION @ISA $AUTOLOAD);

use Devel::Symdump;

$VERSION = sprintf "%d.%02d", '$Revision$ ' =~ /(\d+)\.(\d+)/;

use Carp;

# List of functions that we _never_ try to match approximately.
my @_BARRED = qw(AUTOLOAD BEGIN CHECK INIT DESTROY END);
my %_BARRED = (1) x @_BARRED;

sub _pkg2file {
  $_ = shift;
  s|::|/|g;
  "$_.pm";
}

# import is called when another script uses this module.
# All we do here is overwrite the callers AUTOLOAD subroutine
# with our own.
sub import  {
  my $class = shift;

  no strict 'refs'; # WARNING: Deep magic here!

  my %param;
  my %CONF;
  %param = @_ if @_;

  my %defaults = (xform => 'Text::Soundex',
		  match => 'String::Equal',
		  choose => 'Random');

  # Work out which transformer(s) to use. The valid options are:
  # 1/ $param{xform} doesn't exist. Use default transformer.
  # 2/ $param{xform} is undef. Use no transformers.
  # 3/ $param{xform} is a reference to a subroutine. Use the 
  #    referenced subroutine as the transformer.
  # 4/ $param{xform} is a scalar. This is the name of a transformer
  #    module which should be loaded.
  # 5/ $param{xform} is a reference to an array. Each element of the
  #    array is one of the previous two options.

  if (exists $param{xform}) {
    if (defined $param{xform}) {
      my $type = ref $param{xform};
      if ($type eq 'CODE') {
	$CONF{xform} = [$param{xform}];
      } elsif ($type eq '') {
	my $mod = "Symbol::Approx::Sub::$param{xform}";
	require(_pkg2file($mod));
	$CONF{xform} = [\&{"${mod}::transform"}];
      } elsif ($type eq 'ARRAY') {
	foreach (@{$param{xform}}) {
	  my $type = ref $_;
	  if ($type eq 'CODE') {
	    push @{$CONF{xform}}, $_;
	  } elsif ($type eq '') {
	    my $mod = "Symbol::Approx::Sub::$_";
	    require(_pkg2file($mod));
	    push @{$CONF{xform}}, \&{"${mod}::transform"};
	  } else {
	    croak 'Invalid transformer passed to Symbol::Approx::Sub';
	  }
	}
      } else {
	croak 'Invalid transformer passed to Symbol::Approx::Sub';
      }
    } else {
      $CONF{xform} = [];
    }
  } else {
    my $mod = "Symbol::Approx::Sub::$defaults{xform}";
    require(_pkg2file($mod));
    $CONF{xform} = [\&{"${mod}::transform"}];
  }

  # Work out which matcher to use. The valid options are:
  # 1/ $param{match} doesn't exist. Use default matcher.
  # 2/ $param{match} is undef. Use no matcher.
  # 3/ $param{match} is a reference to a subroutine. Use the 
  #    referenced subroutine as the matcher.
  # 4/ $param{match} is a scalar. This is the name of a matcher
  #    module which should be loaded.

  if (exists $param{match}) {
    if (defined $param{match}) {
      my $type = ref $param{match};
      if ($type eq 'CODE') {
	$CONF{match} = $param{match};
      } elsif ($type eq '') {
	my $mod = "Symbol::Approx::Sub::$param{match}";
	require(_pkg2file($mod));
	$CONF{match} = \&{"${mod}::match"};
      } else {
	croak 'Invalid matcher passed to Symbol::Approx::Sub';
      }
    } else {
      $CONF{match} = undef;
    }
  } else {
    my $mod = "Symbol::Approx::Sub::$defaults{match}";
    require(_pkg2file($mod));
    $CONF{match} = \&{"${mod}::match"};
  }

  # Work out which chooser to use. The valid options are:
  # 1/ $param{choose} doesn't exist. Use default chooser.
  # 2/ $param{choose} is undef. Use default chooser.
  # 3/ $param{choose} is a reference to a subroutine. Use the 
  #    referenced subroutine as the chooser.
  # 4/ $param{choose} is a scalar. This is the name of a chooser
  #    module which should be loaded.

  if (exists $param{choose}) {
    if (defined $param{choose}) {
      my $type = ref $param{choose};
      if ($type eq 'CODE') {
	$CONF{chooser} = $param{chooser};
      } elsif ($type eq '') {
	my $mod = "Symbol::Approx::Sub::$param{choose}";
	require(_pkg2file($mod));
	$CONF{choose} = \&{"${mod}::choose"};
      } else {
	croak 'Invalid chooser passed to Symbol::Approx::Sub';
      }
    } else {
      my $mod = "Symbol::Approx::Sub::$defaults{choose}";
      require(_pkg2file($mod));
      $CONF{choose} = \&{"4mod::choose"};
    }
  } else {
    my $mod = "Symbol::Approx::Sub::$defaults{choose}";
    require(_pkg2file($mod));
    $CONF{choose} = \&{"${mod}::choose"};
  }

  # Now install appropriate AUTOLOAD routine in caller's package

  my $pkg =  caller(0);
  *{"${pkg}::AUTOLOAD"} = make_AUTOLOAD(%CONF);
}

# Create a subroutine which is called when a given subroutine
# name can't be found in the current package. In the import subroutine
# above we have already arranged that our calling package will use
# the AUTOLOAD created here instead of its own.
sub make_AUTOLOAD {
  my %CONF = @_;

  return sub {
    my @c = caller(0);
    my ($pkg, $sub) = $AUTOLOAD =~ /^(.*)::(.*)$/;

    # Get a list of all of the subroutines in the current package
    # using the get_subs function from GlobWalker.pm
    # Note that we deliberately omit function names that exist
    # in the %_BARRED hash
    my (@subs, @orig);
    my $sym = Devel::Symdump->new($pkg);
    @orig = @subs = grep { ! $_BARRED{$_} } 
                    map { s/${pkg}:://; $_ }
                    grep { defined &{$_} } $sym->functions($pkg);

    unshift @subs, $sub;

    # Transform all of the subroutine names
    foreach (@{$CONF{xform}}) {
      carp "Invalid transformer passed to Symbol::Approx::Sub\n"
	unless defined &$_;
      @subs = $_->(@subs);
    }

    # Call the subroutine that will look for matches
    # The matcher returns a list of the _indexes_ that match
    my @match_ind;
    if ($CONF{match}) {
      carp "Invalid matcher passed to Symbol::Approx::Sub\n"
	unless defined &{$CONF{match}};
      @match_ind = $CONF{match}->(@subs);
    } else {
      @match_ind = @subs[1 .. $#subs];
    }

    shift @subs;

    @subs = @subs[@match_ind];
    @orig = @orig[@match_ind];

    # If we've got more than one matched subroutine, then call the
    # chooser to pick one.
    # Call the matched subroutine using magic goto.
    # If no match was found, die recreating Perl's usual behaviour.
    if (@match_ind) {
      if (@match_ind == 1) {
        $sub = "${pkg}::" . $orig[0];
      } else {
	carp "Invalid chooser passed to Symbol::Approx::Sub\n"
	  unless defined $CONF{choose};
        $sub = "${pkg}::" . $orig[$CONF{choose}->(@subs)];
      }
      goto &$sub;
    } else {
      die "REALLY Undefined subroutine $AUTOLOAD called at $c[1] line $c[2]\n";
    }
  }
}

1;
__END__

=head1 NAME

Symbol::Approx::Sub - Perl module for calling subroutines by approximate names!

=head1 SYNOPSIS

  use Symbol::Approx::Sub;

  sub a {
    # blah...
  }

  &aa; # executes &a if &aa doesn't exist.

  use Symbol::Approx::Sub (xform => 'Text::Metaphone');
  use Symbol::Approx::Sub (xform => undef,
			   match => 'String::Approx');
  use Symbol::Approx::Sub (xform => 'Text::Soundex');
  use Symbol::Approx::Sub (xform => \&my_transform);
  use Symbol::Approx::Sub (xform => [\&my_transform, 'Text::Soundex']);
  use Symbol::Approx::Sub (xform => \&my_transform,
			   match => \&my_matcher,
			   choose => \&my_chooser);


=head1 DESCRIPTION

This is _really_ stupid. This module allows you to call subroutines by
_approximate_ names. Why you would ever want to do this is a complete
mystery to me. It was written as an experiment to see how well I
understood typeglobs and AUTOLOADing.

To use it, simply include the line:

  use Symbol::Approx::Sub;

somewhere in your program. Then each time you call a subroutine that doesn't
exist in the the current package Perl will search for a subroutine with
approximately the same name. The meaning of 'approximately the same' is
configurable. The default is to find subroutines with the same Soundex
value (as defined by Text::Soundex) as the missing subroutine. There are
two other built-in matching styles using Text::MetaPhone and 
String::Approx. To use either of these use:

  use Symbol::Approx::Sub (xform => 'text_metaphone');

or

  use Symbol::Approx::Sub (xfrom => undef,
                           match => 'string_approx');

when using Symbol::Approx::Sub.

=head2 Configuring The Fuzzy Matching

There are three phases to the matching process. They are:

=over 4

=item *

B<transform> - a transform subroutine applies some kind of transformation
to the subroutine names. For example the default transformer applies the
Soundex algorithm to each of the subroutine names. Other obvious 
tranformations would be to remove all the underscores or to change the
names to lower case.

A transform subroutine should simply apply its transformation to each
item in its parameter list and return the transformed list. For example, a
transformer that removed underscores from its parameters would look like
this:

  sub tranformer {
    map { s/_//g; $_ } @_;
  }

Transform subroutines can be chained together.

=item *

B<match> - a match subroutine takes a target string and a list of other
strings. It matches each of the strings against the target and determines
whether or not it 'matches' according to some criteria. For example the
default matcher simply checks to see if the strings are equal.

A match subroutine is passed the target string as its first parameter,
followed by the list of potential matches. For each string that matches,
the matcher should return the index number from the input list. For example, 
the default matcher is implemented like this:

  sub matcher {
    my ($sub, @subs) = @_;
    my (@ret);

    foreach (0 .. $#subs) {
      push @ret, $_ if $sub eq $subs[$_];
    }

    @ret;
  }

=item *

B<choose> - a chooser subroutine takes a list of matches and chooses exactly
one item from the list. The default matcher chooses one item at random.

A chooser subroutine is passed a list of matches and must simply return one
index number from that list. For example, the default chooser is implemented 
like this:

  sub chooser {
    rand @_;
  }

=back

You can override any of these behaviours by writing your own transformer,
matcher or chooser. You can either define the subroutine in your own
script or you can put the subroutine in a separate module which 
Symbol::Approx::Sub can then use as a I<plug-in>. See below for more details
on plug-ins.

To use your own function, simply pass a reference to the subroutine to the
C<use Symbol::Approx::Sub> line like this:

  use Symbol::Approx::Sub(xfrom => \&my_transform,
                          match => \&my_matcher,
                          choose => \&my_chooser);

A plug-in is simply a module that lives in the Symbol::Approx::Sub 
namespace. For example, if you had a line of code like this:

  use Symbol::Approx::Sub(xfrom => 'MyTransform');

then Symbol::Approx::Sub will try to load a module called
Symbol::Approx::Sub::MyTranform and it will use a function from within that
module called C<tranformer> as the transform function. Similarly, the 
matcher function is called C<match> and the chooser function is called
C<choose>.

The default transformer, matcher and chooser are available as plug-ins
called Text::Soundex, String::Equal and Random.

=head1 CAVEAT

I can't stress too strongly that this will make your code completely 
unmaintainable and you really shouldn't use this module unless you're 
doing something very stupid.

=head1 ACKNOWLEDGEMENTS

This idea came to me whilst sitting in Mark-Jason Dominus' "Tricks of
the Wizards" tutorial. In order to protect his reputation I should
probably point out that just as the idea was forming in my head he
clearly said that this kind of thing was a very bad idea.

Leon Brocard is clearly as mad as me as he pointed out some important bugs
and helped massively with the 'fuzzy-configurability'.

Matt Freake helped by pointing out that Perl generally does what you
mean, not what you think it should do.

Robin Houston spotted some nasty problems and (more importantly) supplied
patches.

=head1 AUTHOR

Dave Cross <dave@dave.org.uk>

With lots of help from Leon Brocard <leon@astray.com>

=head1 SEE ALSO

perl(1).

=cut
