package HC::Graphite::API;

use v5.10;
use strictures 2;
use Moo::Role;
use Carp;

use Memoize;
use Net::Async::HTTP;
use namespace::clean;

with 'HC::Role::Async';

with 'HC::Role::JSONCodec';

=head1 ATTRIBUTES

=over

=item _http (read-only)

The L<Net::Async::HTTP> object which performs the HTTP queries.

=cut

has _http => is => lazy => init_arg => undef, builder => sub {
  my $self = shift;
  my $http = Net::Async::HTTP->new(
    user_agent               => __PACKAGE__ . '/0.0', # $VERSION?
    max_connections_per_host => $self->max_connections,
   );
  $self->_loop->add($http);
  $http;
};

=item max_connections (read-only)

The maximum number of simultaneous HTTP connections to allow. See
C<max_connections_per_host> in L<Net::Async::HTTP>.

Default: 0; no limit.

=cut

has max_connections => is => ro => default => 0;

=item username (read-only, predicable)

=item password (read-only, predicable)

The username and password to authenticate with.

In addition to C<has_username()> and C<has_password()> there is
C<has_auth()> which returns true if there is a username I<and> a
password.

=cut

has [qw(username password)] => is => ro => predicate => 1;

sub has_auth { $_[0]->has_username and $_[0]->has_password }

=item endpoint (required, read-only)

The base of the graphite URL to which metrics and render requests will
be directed. Everything up to and B<including> the
C</>. eg. C<https://monitoring.example.com:8080/graphite/>.

=cut

has endpoint => (
  is       => 'ro',
  isa      => sub {
    carp 'endpoint should include a trailing "/", attempting to continue'
      unless $_[0] =~ /\/$/;
    croak 'endpoint must include a protocol' unless $_[0] =~ /^[a-z-]+:/i;
  },
  required => 1,
 );

=back

=head1 PUBLIC METHODS

All of these methods return a L<Future> which will complete with the
indicated result.

=over

=item metrics ($method, $query, [%extra])

Perform C<$method> on/with the metrics which match C<$query>, which
may be a scalar or an arrayref of scalars if multiple query arguments
makes sense in the context of the given method call. ie. Request
C<< <graphite-endpoint>/metrics/<$method>?query=<$query> >>. If
arguments are supplied in C<%extra>, they are added to the generated
URI as encoded query parameters.

find

expand

index[.json]

=cut

sub metrics {
  my $self = shift;
  my ($method, $query, %extra) = @_;
  $method = 'index.json' if $method eq 'index';
  my $uri = URI->new($self->endpoint . "metrics/$method");
  $uri->query_form(%extra, query => $query);
  $self->_download($uri)->then(sub { Future->done($_[0]->content) });
}

=item perl_metrics ($method, $query, [%extra])

Calls C<metrics> with the same arguments and decodes the result, which
is assumed to be JSON text, into a perl data structure.

=cut

sub perl_metrics {
  my $self = shift;
  $self->metrics(@_)->then(sub { Future->done($self->_json->decode(shift)); });
}

=item render ($format, $target, [%extra])

Fetch the metric data for the given C<$target>, which may be a scalar
or an arrayref of scalars. As with C<metrics> arguments in C<%extra>
are included in the generated URI's query parameters.

The name of the format may also be called as a method directly,
without the first argument:

=over

=item csv

=item dygraph

=item json

=item pdf

=item png

=item raw

=item rickshaw

=item svg

=back

=cut

sub render {
  my $self = shift;
  my ($format, $target, %extra) = @_;
  my $uri = URI->new($self->endpoint . 'render');
  $uri->query_form(%extra, format => $format, target => $target);
  $self->_download($uri)->then(sub { Future->done($_[0]->content) });
}

for my $format (qw(
  csv
  dygraph
  json
  pdf
  png
  raw
  rickshaw
  svg
)) {
  no strict 'refs';
  *{$format} = sub { $_[0]->render($format => @_[1..$#_]) };
}

=item find_target_from_spec ($spec, ...)

Construct target strings from the specifications in each C<$spec>,
which must be a plain scalar or an arrayref containing 1 or 2 items:

=over

=item Function name

=item Arrayref containing 0 or more arguments [optional]

Each argument may be a scalar, which is returned as-is, or an arrayref
which must itself be another C<$spec>-like pair.

=back

=cut

sub find_target_from_spec {
  my $self = shift;
  return map { __construct_target_argument($_) } @_;
}

=back

=head1 PRIVATE METHODS

=over

=item _download ($uri)

Return a L<Future> which completes with an L<HTTP::Response> object
when the HTTP request has finished.

=cut

sub _download {
  my $self = shift;
  my ($uri) = @_;
  #$self->_debugf("Downloading from uri <%s>.", $uri);
  $self->_http->do_request(
    uri      => "$uri",
    # timeout=> ?,
    on_error => sub {
      #$self->_errorf('Error conducting HTTP transaction to %s?%s: %s',
      #               $self->endpoint, $uri, $_[0]);
      # Future has already been fail()ed elsewhere.
    },
    ($self->has_auth
       ? (user => $self->username, pass => $self->password)
       : ()));
}

=item __construct_target_argument ($argument)

This is not an object or class method.

Compile C<$argument> into its part of the string which will build up
the target component of a Graphite request URI. C<$argument> must be a
scalar or an arrayref with one or two items in it. The second must be
another arrayref of arguments.

Returns the scalar as-is or calls C<__construct_target_function> to
decode the arrayref.

This function uses L<Memoize> for which it serialises its arguments
into L<JSON>.

=cut

memoize('__construct_target_argument',
        NORMALIZER => sub { ref($_[0]) ? encode_json($_[0]) : $_[0] });

sub __construct_target_argument {
  my ($argument) = @_;
  my $ref = ref $argument;
  if (not $ref) {
    $argument;
  } elsif ($ref eq 'ARRAY' and scalar @$argument <= 2) {
    croak 'Function arguments must be an arrayref'
      unless not defined $argument->[1] or ref $argument->[1] eq 'ARRAY';
    __construct_target_function($argument->[0], @{ $argument->[1] || [] });
  } else {
    croak "Unknown argument reference type: $ref";
  }
}

=item __construct_target_function ($name, [@arguments])

This is not an object or class method.

Compile C<$name> and C<@arguments> into their part of the string which
will build up the target component of a Graphite request URI. Recurses
back into C<__construct_target_argument> to build each argument
component.

This function uses L<Memoize> for which it serialises its arguments
into L<JSON>.

=cut

memoize('__construct_target_function',
        NORMALIZER => sub { encode_json({@_}) });

sub __construct_target_function {
  my $name = shift;
  croak 'Function name must be a scalar' if ref $name;
  my @arguments = map { __construct_target_argument($_) } @_;
  $name . '(' . join(',', @arguments) . ')';
}

1;
