package HC::Graphite;

=head1 NAME

HC::Graphite - Request data from graphite.

=head1 SYNOPSIS

  use HC::Graphite;

  my $graphite = HC::Graphite->new(
      endpoint => 'https://graphite.example.com/',
      ...,
  );

  my $value = $graphite->last_value('me.tr.ic');

=head1 DESCRIPTION

A interface to Graphite's data-request API. The C<construct_url()>
method is used to turn an overly-complicated data structure into a URL
and the various C<do_*()> methods use the URL it constructs to send
the request and chop up the reply to obtain the numeric result(s).

=head1 BUGS

C<_http> is added to L<IO::Async>'s loop but there's no mechanism to
remove it. For now C<_http> exists until the application exits but if
that ever changes this will be the source of memory leaks at best.

No attempt is made to configure a timeout for the HTTP request.

=cut

use v5.10;
use strictures 2;
use Moo;
use Carp;

use namespace::clean;

#with 'HC::Logger';

with 'HC::Graphite::API';

with 'HC::Graphite::Draw';

has default_from => is => rw => predicate => 1;

has default_until => is => rw => predicate => 1;

1;

=back

=head1 SEE ALSO

L<Future>

L<Moo>

L<Net::Async::HTTP>

=head1 AUTHOR

Matthew King <matthew.king@cloudbeds.com>

=cut
