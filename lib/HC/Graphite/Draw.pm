package HC::Graphite::Draw;

use v5.10;
use strictures 2;
use Moo::Role;
use Carp;

use Future;
use namespace::clean;

=item last_value ($target, [%extra])

Calls C<render('raw')> with the same arguments and returns a list of
the final data point on each line returned in the result.

=cut

sub last_value {
  my $self = shift;
  $self->render(raw => @_)->then(sub {
    my $response = shift or return Future->fail('no data');
    Future->done(map {
      my $result = (split /\|/)[-1];
      # Blessed object which scalar's into this but has attributes for other data?
      (split /,/, $result)[-1];
    } grep /\S/, split /\r?\n/, $response);
  });
}

1;
