package Games::Blockminer3D::Client;
use common::sense;
use Games::Blockminer3D::Client::Frontend;
use Games::Blockminer3D::Client::MapChunk;
use Games::Blockminer3D::Client::World;
use Games::Blockminer3D::Server;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Math::VectorReal;
use Benchmark qw/:all/;

=head1 NAME

Games::Blockminer3D::Client - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Client->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;
   #d# my $sect = Games::Blockminer3D::Server::Sector->new;
   #d# timethese (20, { test => sub {
   #d#    $sect->mk_random;
   #d# }});
   #d#    my $chunk = $sect->get_chunk (1, 1, 1);
   #d# exit;

   $self->{server} = Games::Blockminer3D::Server->new;
   $self->{server}->init;

   $self->{front} = Games::Blockminer3D::Client::Frontend->new;

   for my $x (-1..1) {
      for my $y (-1..1) {
         for my $z (-1..1) {
            my $chnk = Games::Blockminer3D::Client::MapChunk->new;
            $chnk->cube_fill;
            world_set_chunk ($x, $y, $z, $chnk);
         }
      }
   }
#   $chnk->random_fill;

 #  $self->{front}->change_look_lock (1);
 #  $self->{front}->compile_scene;

   $self->{front}->activate_ui ("test", {
   });

   return $self
}

sub start {
   my ($self) = @_;

   my $c = AnyEvent->condvar;

   $c->recv;
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

