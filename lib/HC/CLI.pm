package HC::CLI;

use v5.10;
use strictures 2;
use Moo; # Role?
use Carp;

use Getopt::Long qw(GetOptionsFromArray);
use List::Util qw(all);
use namespace::clean;

my $shitty_match = qr([a-zA-Z0-9_*{},\[\]-]+); # Yeah...

my %sane = (
  graphite => {
    variable => '$ENV{HC_GRAPHITE}',
    name     => 'HC_GRAPHITE environment variable',
    default  => 'http://localhost/graphite',
    rx       => qr((?x)
      ^(
        .* # Whatever
      )$),
  },

  mcwd => {
    variable => '$ENV{HC_MCWD}',
    default  => '.',
    name     => 'HC_MCWD environment variable',
    rx       => qr((?x)
      ^(
        \.
      |
        (?:\.$shitty_match)+
      )$),
  },

  path => {
    variable => '$ARGV[0]',
    default  => '.',## $mcwd eq '.' ? $mcwd : "$mcwd.",
    name     => 'path',
    rx       => qr((?x)
      ^(
        \.\.?
      |
        (?:\.$shitty_match)+\.?
      |
        $shitty_match(?:\.$shitty_match)*\.?
      )$),
  },
);

has _sanitised => is => lazy => builder => sub {+{
  graphite => _check_environment('graphite'),
  mcwd     => _check_environment('mcwd'),
}};

sub graphite { $_[0]->_sanitised->{graphite} }

sub mcwd     { $_[0]->_sanitised->{mcwd} }

sub BUILD {
  $_[0]->getopt; # unless skip?
}

sub _check_environment {
  my $self = shift if ref $_[0];
  my %defn = ( %{ $sane{shift()} || {} }, @_ );
  my $variable;
  if (ref $defn{variable}) {
    # This won't work
    $variable = ${ $defn{variable} };
    $defn{variable} = '$variable';
  }
  my $evil_eval = qq<
    (defined $defn{variable} and length $defn{variable})
      ? do {
        $defn{variable} =~ \$defn{rx}
          or die "Invalid \$defn{name}: $defn{variable}";
        \$1;
      }
      : \$defn{default};
  >;
  my $r = eval $evil_eval;
  die $@ if $@; # Somehow the fact that this included 'at (wherever)'
                # remains, even after it's been removed, and it is not
                # reapplied.
  $r;
}

my %_possible_argument = (
  standard => {
    format => 'format=s',
    from   => 'from=s',
    until  => 'until=s',
    tag    => '@tag=s',
    width  => 'width=i',
    height => 'height=i',
  },
);

# This will be _changed_ by getopt/_build_user_options.
has user_arguments => is => lazy => builder => sub { [ @ARGV ] };

# There must be an enum type somewhere...
has _standard_arguments => is => ro => init_arg => standard_arguments =>
  default => sub { [] },
  isa     => sub {
    #die 'standard_arguments must be an arrayref of legal scalars'
    #  unless 0 and ref($_[0])||'' eq 'ARRAY'
    #    and all { not ref $_
    #                and exists $_possible_argument{standard}{$_} } @{$_[0]};
  };

sub standard_arguments { @{ $_[0]->_standard_arguments } }

has user_options => is => lazy => init_arg => undef, builder => sub {
  my $self = shift;
  my %opt;
  my %argument = (
    (map {
      my $stand = $_;
      my $name  = $_possible_argument{standard}{$stand};
      my $sub = $name =~ s/^\@//
         ? sub { push @{ $opt{stand} }, $_[1] }
         : sub { $opt{$stand} = $_[1] };
      ($name => $sub);
    } $self->standard_arguments),
  );
  GetOptionsFromArray($self->user_arguments, %argument)
    or die 'Cannot parse arguments';
  \%opt;
};

sub getopt { $_[0]->user_options; $_[0] }

1;
