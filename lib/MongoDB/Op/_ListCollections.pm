#
#  Copyright 2014 MongoDB, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

package MongoDB::Op::_ListCollections;

# Encapsulate collection list operations; returns arrayref of collection
# names

use version;
our $VERSION = 'v0.999.998.2'; # TRIAL

use Moose;

use MongoDB::Op::_Command;
use MongoDB::Op::_Query;
use MongoDB::_Types;
use Tie::IxHash;
use namespace::clean -except => 'meta';

has db_name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has client => (
    is       => 'ro',
    isa      => 'MongoDB::MongoClient',
    required => 1,
);

has bson_codec => (
    is       => 'ro',
    isa      => 'MongoDB::MongoClient', # XXX only for now
    required => 1,
);

with 'MongoDB::Role::_ReadOp';

sub execute {
    my ( $self, $link, $topology ) = @_;

    my $res =
        $link->accepts_wire_version(3)
      ? $self->_command_list_colls( $link, $topology )
      : $self->_legacy_list_colls( $link, $topology );

    return $res;
}

sub _command_list_colls {
    my ( $self, $link, $topology ) = @_;

    my $op = MongoDB::Op::_Command->new(
        db_name         => $self->db_name,
        query           => Tie::IxHash->new( listCollections => 1 ),
        read_preference => $self->read_preference,
    );

    my $res = $op->execute( $link, $topology )->result;

    return [ map { $_->{name} } @{ $res->{collections} } ];
}

sub _legacy_list_colls {
    my ( $self, $link, $topology ) = @_;

    my $db_name = $self->db_name;
    my $op      = MongoDB::Op::_Query->new(
        db_name         => $self->db_name,
        coll_name       => 'system.namespaces',
        client          => $self->client,
        bson_codec      => $self->bson_codec,
        query           => Tie::IxHash->new(),
        read_preference => $self->read_preference,
    );

    my $res = $op->execute( $link, $topology );

    # exclude names with '$' except oplog.$
    # XXX why do we include oplog.$?
    return [
        grep { not( index( $_, '$' ) >= 0 && index( $_, '.oplog.$' ) < 0 ) }
        map { substr $_->{name}, length($db_name) + 1 } $res->all
    ];
}

1;