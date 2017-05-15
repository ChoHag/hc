package HC::Role::JSONCodec;

use v5.10;
use strictures 2;
use Moo::Role;
use Carp;

use JSON;
use namespace::clean;

=item _json (read-only)

A L<JSON> codec object.

=cut

has _json => is => lazy => init_arg => undef, builder => sub {
  JSON->new->utf8->allow_blessed(1)
};

1;
