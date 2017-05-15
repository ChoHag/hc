package HC::Role::Async;

use v5.10;
use strictures 2;
use Moo::Role;
use Carp;

use IO::Async::Loop;
use namespace::clean;

=item _loop (read-only)

An internal reference to the L<IO::Async> loop.

=cut

has _loop => is => lazy => init_arg => undef, builder => sub {
  IO::Async::Loop->new;
};

1;
