package Games::Construder::Client;
use common::sense;
use Compress::LZF;
use Games::Construder::Client::Frontend;
use Games::Construder::Client::World;
use Games::Construder::Protocol;
use Games::Construder;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Benchmark qw/:all/;

use base qw/Object::Event/;

=head1 NAME

Games::Construder::Client - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Construder::Client->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   Games::Construder::World::init (sub {
   }, sub { });

   $self->{res} = Games::Construder::Client::Resources->new;
   $self->{res}->init_directories;
   $self->{res}->load_config;
   $Games::Construder::Client::UI::RES = $self->{res};

   $self->{front} =
      Games::Construder::Client::Frontend->new (res => $self->{res}, client => $self);

   $self->{front}->reg_cb (
      update_player_pos => sub {
         $self->send_server ({ cmd => "player_pos", pos => $_[1], look_vec => $_[2] });
      },
      position_action => sub {
         my ($front, $pos, $build_pos, $btn) = @_;
         $self->send_server ({
            cmd => "pos_action", pos => $pos,
            build_pos => $build_pos, action => $btn
         });
      },
      visibility_radius => sub {
         my ($front, $radius) = @_;
         $self->send_server ({ cmd => "visibility_radius", radius => $radius });
      },
   );

   $self->connect ($ARGV[1] || localhost => $ARGV[2] || 9364);

   return $self
}

sub start {
   my ($self) = @_;

   my $c = AnyEvent->condvar;

   $c->recv;
}

sub connect {
   my ($self, $host, $port) = @_;

   tcp_connect $host, $port, sub {
      my ($fh) = @_;
      unless ($fh) {
         $self->{front}->msg ("Couldn't connect to server: $!");
         return;
      }

      my $hdl = AnyEvent::Handle->new (
         fh => $fh,
         on_error => sub {
            my ($hdl, $fatal, $msg) = @_;
            $hdl->destroy;
            $self->disconnected;
         }
      );

      $self->{srv} = $hdl;
      $self->handle_protocol;
      $self->connected;
   };
}

sub handle_protocol {
   my ($self) = @_;

   $self->{srv}->push_read (packstring => "N", sub {
      my ($handle, $string) = @_;
      $self->handle_packet (data2packet ($string));
      $self->handle_protocol;
   });
}

sub send_server {
   my ($self, $hdr, $body) = @_;
   if ($self->{srv}) {
      $self->{srv}->push_write (packstring => "N", packet2data ($hdr, $body));
      warn "cl> $hdr->{cmd}\n";
   }
}

sub connected : event_cb {
   my ($self) = @_;
   $self->{front}->msg ("Connected to Server!");
   $self->send_server ({ cmd => 'hello', version => "Games::Construder::Client 0.1" });
}

sub handle_packet : event_cb {
   my ($self, $hdr, $body) = @_;

   warn "cl< $hdr->{cmd} (".length ($body).")\n";

   if ($hdr->{cmd} eq 'hello') {
      $self->{front}->{server_info} = $hdr->{info};
      $self->{front}->msg ("Queried Resources");
      $self->send_server ({ cmd => 'list_resources' });

   } elsif ($hdr->{cmd} eq 'resources_list') {
      $self->{res}->set_resources ($hdr->{list});

      #  [ $_, $res->{type}, $res->{md5}, \$res->{data} ]
      my @data_res_ids = map { $_->[0] } grep { defined $_->[2] } @{$hdr->{list}};

      if (@data_res_ids) {
         $self->send_server ({ cmd => get_resources => ids => \@data_res_ids });
         $self->{front}->msg ("Initiated resource transfer (".scalar (@data_res_ids).")");
      } else {
         $self->{front}->msg ("No resources on server found!");
      }

   } elsif ($hdr->{cmd} eq 'resource') {
      my $res = $hdr->{res};
      #  [ $_, $res->{type}, $res->{md5}, \$res->{data} ]
      $self->{res}->set_resource_data ($hdr->{res}, $body);
      $self->send_server ({ cmd => 'transfer_poll' });

   } elsif ($hdr->{cmd} eq 'transfer_end') {
      $self->{front}->msg;
      #print JSON->new->pretty->encode ($self->{front}->{res}->{resource});
      $self->{res}->post_proc;
      $self->{res}->dump_resources;
      $self->send_server (
         { cmd => 'login',
           ($self->{auto_login} ? (name => $self->{auto_login}) : ()) });

   } elsif ($hdr->{cmd} eq 'place_player') {
      $self->{front}->set_player_pos ($hdr->{pos});
      $self->send_server ({ cmd => 'set_player_pos_ok', id => $hdr->{id} });

   } elsif ($hdr->{cmd} eq 'activate_ui') {
      my $desc = $hdr->{desc};
      $desc->{command_cb} = sub {
         my ($cmd, $arg, $need_selection) = @_;

         $self->send_server ({
            cmd => 'ui_response' =>
               ui => $hdr->{ui}, ui_command => $cmd, arg => $arg,
               ($need_selection
                  ? (pos => $self->{front}->{selected_box},
                     build_pos => $self->{front}->{selected_build_box})
                  : ())
         });
      };
      $self->{front}->activate_ui ($hdr->{ui}, $desc);

   } elsif ($hdr->{cmd} eq 'deactivate_ui') {
      $self->{front}->deactivate_ui ($hdr->{ui});

   } elsif ($hdr->{cmd} eq 'highlight') {
      $self->{front}->add_highlight ($hdr->{pos}, $hdr->{color}, $hdr->{fade});

   } elsif ($hdr->{cmd} eq 'model_highlight') {
      if ($hdr->{model}) {
         $self->{front}->add_highlight_model ($hdr->{pos}, $hdr->{model}, $hdr->{id});
      } else {
         $self->{front}->remove_highlight_model ($hdr->{id});
      }

   } elsif ($hdr->{cmd} eq 'chunk') {
      $body = decompress ($body);
      Games::Construder::World::set_chunk_data (@{$hdr->{pos}}, $body, length $body);
      if (!$self->{in_chunk_upd}) {
         $self->{front}->update_chunk (@{$hdr->{pos}});
      } else {
         push @{$self->{upd_chunks}}, $hdr->{pos};
      }

   } elsif ($hdr->{cmd} eq 'chunk_upd_start') {
      $self->{in_chunk_upd} = 1;

   } elsif ($hdr->{cmd} eq 'chunk_upd_done') {
      delete $self->{in_chunk_upd};
      $self->{front}->update_chunks (delete $self->{upd_chunks});

   } elsif ($hdr->{cmd} eq 'msg') {
      $self->{front}->msg ("Server: " . $hdr->{msg});
   }
}

sub disconnected : event_cb {
   my ($self) = @_;
   delete $self->{srv};
   $self->{front}->msg ("Disconnected from server!");
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

