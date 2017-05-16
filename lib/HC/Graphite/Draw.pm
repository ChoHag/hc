package HC::Graphite::Draw;

use v5.10;
use strictures 2;
use Moo::Role;
use Carp;

use Gnuplot::Builder::Dataset;
use Gnuplot::Builder::Script;
use Future;
use List::Util   qw(min max);
use Scalar::Util qw(looks_like_number);
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
    } split /\r?\n/, $response);
  });
}

=item plot ($target, [%extra])

TODO: Format

TODO: Scale

=cut

sub _plot_gather_datasets {
  my $self = shift;
  $self->render_asperl(@_)->then(sub {
    Future->done(map {
      my ($min, $max) = (0,0);
      my $dataset = Gnuplot::Builder::Dataset->new_data(join "\n",
        map {
          my $datum = looks_like_number $_ ? $_ : 0;
          $min = min($min, $datum);
          $max = max($max, $datum);
          $datum;
        } @{ $_->{data} });
      $dataset->set(title => "\"$_->{target}\"");
      +{ %$_, min => $min, max => $max, dataset => $dataset };
    } @_);
  });
}

my %plots = (
  ascii => {
    terminal     => 'dumb',
    # Use a proper module instead of tput.
    default_size => sub { [ map int, `tput cols`, `tput lines` ] },
  },
  png   => {
    terminal     => 'png',
    default_size => [ 640, 480 ],
  }
);

sub _default_plot_size {
  my $self = shift;
  my ($format) = @_;
  my $default = $plots{$format}{default_size};
  ref $default eq 'ARRAY' ? $default : $default->($self);
}

sub plot {
  my $self = shift;
  my (undef, %extra) = @_;
  my $format = delete $extra{format} || 'ascii'; # To not confuse render()
  return Future->fail("Invalid plot format: $format")
    unless exists $plots{$format};
  $self->_plot_gather_datasets(@_)->then(sub {
    my @req_size     = ( $extra{width} || 0, $extra{height} || 0 );
    my @default_size = @{ $self->_default_plot_size($format) };
    my @real_size    = map {
      $req_size[$_] < 0
        ? $default_size[$_] + $req_size[$_]
        : $req_size[$_] || $default_size[$_]
      } 0..1;
    my @sets = @_;
    my $min = min (map { $_->{min} } @sets);
    my $max = max (map { $_->{max} } @sets);
    my $plot = Gnuplot::Builder::Script->new(
      terminal => "$plots{$format}{terminal} size $real_size[0],$real_size[1] enhanced",
      yrange   => "[$min:$max]",
    )->plot_with(dataset   => [ map { $_->{dataset} } @_ ],
                 no_stderr => 1); # Would be nice to put it somewhere
                                  # but it's all or nothing.
    Future->done($plot);
  });
}

1;
