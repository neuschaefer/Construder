package Games::Construder::Server::World;
use common::sense;
use Games::Construder::Vector;
use Games::Construder;
use Time::HiRes qw/time/;
use Carp qw/confess/;
use Compress::LZF qw/decompress compress/;
use JSON;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   world_init
   world_pos2id
   world_pos2chnkpos
   world_chnkpos2secpos
   world_secpos2chnkpos
   world_pos2relchnkpos
   world_mutate_at
   world_load_at
   world_find_free_spot
   world_sector_info
/;


=head1 NAME

Games::Construder::Server::World - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

our $CHNK_SIZE = 12;
our $CHNKS_P_SEC = 5;

our $REGION_SEED = 42;
our $REGION_SIZE = 100; # 100x100x100 sections
our $REGION;

our %SECTORS;

our $STORE_SCHED_TMR;
our @SAVE_SECTORS_QUEUE;

sub world_init {
   my ($server, $region_cmds) = @_;

   Games::Construder::World::init (
      sub {
         my ($x, $y, $z) = @_;

         my $sec = world_chnkpos2secpos ([$x, $y, $z]);
         my $id  = world_pos2id ($sec);
         unless (exists $SECTORS{$id}) {
            confess "Sector which is not loaded was updated! (chunk $x,$y,$z [@$sec]) $id\n";
         }
         $SECTORS{$id}->{dirty} = 1;
         push @SAVE_SECTORS_QUEUE, [$id, $sec];

         my $chnk = [@_];
         for (values %{$server->{players}}) {
            $_->chunk_updated ($chnk);
         }
      }, sub {
         my ($x, $y, $z, $type) = @_;
         # we have no entity at $x,$y,$z yet:
           # and type is active => create entity at $x,$y,$z
           # and type is not active => should not happen, active entity should be instanciated .)
         # else
           # type is not active: delete entity at $x,$y,$z
           # type is active: delete entity at $x,$y,$z and instanciate $type entity here

         # TODO: how is movement made? eg. entity is removed from $x,$y,$z, but should
         #       be used later to instanciate an entity somewhere else, or even
         #       be mvoed into the inventory of the player!
      }
   );

   Games::Construder::VolDraw::init ();

   $STORE_SCHED_TMR = AE::timer 0, 2, sub {
      NEXT:
      my $s = shift @SAVE_SECTORS_QUEUE
         or return;
      if ($SECTORS{$s->[0]}->{dirty}) {
         _world_save_sector ($s->[1]);
      } else {
         goto NEXT;
      }
   };

   region_init ($region_cmds);
}

sub _world_make_sector {
   my ($sec) = @_;

   my $val = Games::Construder::Region::get_sector_value ($REGION, @$sec);

   my ($stype, $param) =
      $Games::Construder::Server::RES->get_sector_desc_for_region_value ($val);

   my $seed = Games::Construder::Region::get_sector_seed (@$sec);

   warn "Create sector @$sec, with seed $seed value $val and "
        . "type $stype->{type} and param $param\n";

   my $cube = $CHNKS_P_SEC * $CHNK_SIZE;
   Games::Construder::VolDraw::alloc ($cube);

   Games::Construder::VolDraw::draw_commands (
     $stype->{cmds},
     { size => $cube, seed => $seed, param => $param }
   );

   Games::Construder::VolDraw::dst_to_world (@$sec, $stype->{ranges} || []);

   $SECTORS{world_pos2id ($sec)} = {
      created    => time,
      pos        => [@$sec],
      region_val => $val,
      seed       => $seed,
      param      => $param,
      type       => $stype->{type},
   };
   _world_save_sector ($sec);

   Games::Construder::World::query_desetup ();
}

sub _world_load_sector {
   my ($sec) = @_;

   my $t1 = time;

   my $id   = world_pos2id ($sec);
   my $mpd  = $Games::Construder::Server::Resources::MAPDIR;
   my $file = "$mpd/$id.sec";

   return 1 if ($SECTORS{$id}
                && !$SECTORS{$id}->{broken});

   unless (-e $file) {
      return 0;
   }

   if (open my $mf, "<", "$file") {
      binmode $mf, ":raw";
      my $cont = eval { decompress (do { local $/; <$mf> }) };
      if ($@) {
         warn "map sector data corrupted '$file': $@\n";
         return -1;
      }

      warn "read " . length ($cont) . "bytes\n";

      my ($metadata, $mapdata, $data) = split /\n\n\n*/, $cont, 3;
      unless ($mapdata =~ /MAPDATA/) {
         warn "map sector file '$file' corrupted! Can't find 'MAPDATA'. "
              . "Please delete or move it away!\n";
         return -1;
      }

      my ($md, $datalen, @lens) = split /\s+/, $mapdata;
      #d#warn "F $md, $datalen, @lens\n";
      unless (length ($data) == $datalen) {
         warn "map sector file '$file' corrupted, sector data truncated, "
              . "expected $datalen bytes, but only got ".length ($data)."!\n";
         return -1;
      }

      my $meta = eval { JSON->new->relaxed->utf8->decode ($metadata) };
      if ($@) {
         warn "map sector meta data corrupted '$file': $@\n";
         return -1;
      }

      $SECTORS{$id} = $meta;
      $meta->{load_time} = time;

      my $offs;
      my $first_chnk = world_secpos2chnkpos ($sec);
      my @chunks;
      for my $dx (0..($CHNKS_P_SEC - 1)) {
         for my $dy (0..($CHNKS_P_SEC - 1)) {
            for my $dz (0..($CHNKS_P_SEC - 1)) {
               my $chnk = vaddd ($first_chnk, $dx, $dy, $dz);

               my $len = shift @lens;
               my $chunk = substr $data, $offs, $len;
               Games::Construder::World::set_chunk_data (
                  @$chnk, $chunk, length ($chunk));
               $offs += $len;
            }
         }
      }

      delete $SECTORS{$id}->{dirty}; # saved with the sector
      warn "loaded sector $id from '$file', took "
           . sprintf ("%.3f seconds", time - $t1)
           . ".\n";

   } else {
      warn "couldn't open map sector '$file': $!\n";
      return -1;
   }
}

sub _world_save_sector {
   my ($sec) = @_;

   my $t1 = time;

   my $id   = world_pos2id ($sec);
   my $meta = $SECTORS{$id};

   if ($meta->{broken}) {
      warn "map sector '$id' marked as broken, won't save!\n";
      return;
   }

   $meta->{save_time} = time;

   my $first_chnk = world_secpos2chnkpos ($sec);
   my @chunks;
   for my $dx (0..($CHNKS_P_SEC - 1)) {
      for my $dy (0..($CHNKS_P_SEC - 1)) {
         for my $dz (0..($CHNKS_P_SEC - 1)) {
            my $chnk = vaddd ($first_chnk, $dx, $dy, $dz);
            push @chunks,
               Games::Construder::World::get_chunk_data (@$chnk);
         }
      }
   }

   my $meta_data = JSON->new->utf8->pretty->encode ($meta || {});

   my $data = join "", @chunks;
   my $filedata = compress (
      $meta_data . "\n\nMAPDATA "
      . join (' ', map { length $_ } ($data, @chunks))
      . "\n\n" . $data
   );

   my $mpd = $Games::Construder::Server::Resources::MAPDIR;
   my $file = "$mpd/$id.sec";

   if (open my $mf, ">", "$file~") {
      binmode $mf, ":raw";
      print $mf $filedata;
      close $mf;
      unless (-s "$file~" == length ($filedata)) {
         warn "couldn't save sector completely to '$file~': $!\n";
         return;
      }

      if (rename "$file~", $file) {
         delete $SECTORS{$id}->{dirty};
         warn "saved sector $id to '$file', took "
              . sprintf ("%.3f seconds", time - $t1)
              . "\n";

      } else {
         warn "couldn't rename '$file~' to '$file': $!\n";
      }

   } else {
      warn "couldn't save sector $id to '$file~': $!\n";
   }
}


sub region_init {
   my ($cmds) = @_;

   my $t1 = time;

   warn "calculating region, with seed $REGION_SEED.\n";
   Games::Construder::VolDraw::alloc ($REGION_SIZE);

   Games::Construder::VolDraw::draw_commands (
     $cmds,
     { size => $REGION_SIZE, seed => $REGION_SEED, param => 1 }
   );

   $REGION = Games::Construder::Region::new_from_vol_draw_dst ();
   warn "done, took " . (time - $t1) . " seconds.\n";
}

sub world_sector_info {
   my ($x, $y, $z) = @_;
   my $sec = world_chnkpos2secpos ([$x, $y, $z]);
   my $id  = world_pos2id ($sec);
   unless (exists $SECTORS{$id}) {
      return undef;
   }
   $SECTORS{$id}
}

sub world_pos2id {
   my ($pos) = @_;
   join "x", map { $_ < 0 ? "N" . abs ($_) : $_ } @{vfloor ($pos)};
}

sub world_pos2chnkpos {
   vfloor (vsdiv ($_[0], $CHNK_SIZE))
}

sub world_chnkpos2secpos {
   vfloor (vsdiv ($_[0], $CHNKS_P_SEC))
}

sub world_secpos2chnkpos {
   vsmul ($_[0], $CHNKS_P_SEC);
}

sub world_pos2relchnkpos {
   my ($pos) = @_;
   my $chnk = world_pos2chnkpos ($pos);
   vsub ($pos, vsmul ($chnk, $CHNK_SIZE))
}

sub world_load_at {
   my ($pos, $cb) = @_;
   world_load_at_chunk (world_pos2chnkpos ($pos), $cb);
}

sub world_load_at_chunk {
   my ($chnk, $cb) = @_;

   for my $dx (-2, 0, 2) {
      for my $dy (-2, 0, 2) {
         for my $dz (-2, 0, 2) {
            my $sec   = world_chnkpos2secpos (vaddd ($chnk, $dx, $dy, $dz));
            my $secid = world_pos2id ($sec);
            unless ($SECTORS{$secid}) {
               warn "LOAD SECTOR $secid\n";
               my $r = _world_load_sector ($sec);
               if ($r == 0) {
                  _world_make_sector ($sec);
               }
            }
         }
      }
   }

   $cb->() if $cb;
}

sub world_mutate_at {
   my ($poses, $cb, %arg) = @_;

   if (ref $poses->[0]) {
      my $min = [];
      my $max = [];
      for (@$poses) {
         world_load_at ($_); # blocks for now :-/

         $min->[0] = $_->[0] if !defined $min->[0] || $min->[0] > $_->[0];
         $min->[1] = $_->[1] if !defined $min->[1] || $min->[1] > $_->[1];
         $min->[2] = $_->[2] if !defined $min->[2] || $min->[2] > $_->[2];
         $max->[0] = $_->[0] if !defined $max->[0] || $max->[0] < $_->[0];
         $max->[1] = $_->[1] if !defined $max->[1] || $max->[1] < $_->[1];
         $max->[2] = $_->[2] if !defined $max->[2] || $max->[2] < $_->[2];
      }
      warn "MUTL @$min | @$max\n";
      Games::Construder::World::flow_light_query_setup (@$min, @$max);

   } else {
      world_load_at ($poses); # blocks for now :-/

      Games::Construder::World::flow_light_query_setup (@$poses, @$poses);
      $poses = [$poses];
   }

   for my $pos (@$poses) {
      my $b = Games::Construder::World::at (@$pos);
      print "MULT MUTATING (@$b) (AT @$pos)\n";
      if ($cb->($b)) {
         print "MULT MUTATING TO => (@$b) (AT @$pos)\n";
         Games::Construder::World::query_set_at_abs (@$pos, $b);
         unless ($arg{no_light}) {
            my $t1 = time;
            Games::Construder::World::flow_light_at (@{vfloor ($pos)});
            printf "mult light calc took: %f\n", time - $t1;
         }
      }
   }

   Games::Construder::World::query_desetup ();
}

sub world_find_free_spot {
   my ($pos, $wflo) = @_;
   $wflo = 0 unless defined $wflo;
   Games::Construder::World::find_free_spot (@$pos, $wflo);
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

