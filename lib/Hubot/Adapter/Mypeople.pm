package Hubot::Adapter::Mypeople;
{
  $Hubot::Adapter::Mypeople::VERSION = '0.0.3';
}
use Moose;
use namespace::autoclean;

extends 'Hubot::Adapter';

use AnyEvent::HTTPD;
use AnyEvent::Mypeople::Client;
use JSON::XS;
use Encode 'decode_utf8';

use Hubot::Message;

has httpd => (
    is         => 'ro',
    lazy_build => 1,
);

has client => (
    is         => 'rw',
    isa        => 'AnyEvent::Mypeople::Client',
    lazy_build => 1,
);

has groups => (
    traits  => ['Array'],
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
    handles => {
        all_groups   => 'elements',
        add_group    => 'push',
        find_group   => 'first',
        count_groups => 'count',
    }
);

sub _build_httpd  { AnyEvent::HTTPD->new(port => $ENV{HUBOT_MYPEOPLE_PORT} || 8080) }

sub send {
    my ( $self, $user, @strings ) = @_;

    $self->client->send(
        $user->{room},
        join("\n", @strings),
        undef
    );
}

sub reply {
    my ( $self, $user, @strings ) = @_;

    @strings = map { $user->{name} . ": $_" } @strings;
    $self->send( $user, @strings );
}

sub run {
    my $self = shift;

    unless ($ENV{HUBOT_MYPEOPLE_APIKEY}) {
        print STDERR "HUBOT_MYPEOPLE_APIKEY is not defined, try: export HUBOT_MYPEOPLE_APIKEY='yourapikey'";
        exit;
    }

    $self->client(AnyEvent::Mypeople::Client->new(apikey => $ENV{HUBOT_MYPEOPLE_APIKEY}));

    my $httpd = $self->httpd;

    $httpd->reg_cb(
        '/' => sub {
            my ($httpd, $req) = @_;

            my $action  = $req->parm('action');
            my $buddyId = $req->parm('buddyId');
            my $groupId = $req->parm('groupId');
            my $content = decode_utf8($req->parm('content'));

            $req->respond({ content => ['text/plain', 'Your request is succeed'] });

            $self->add_group($groupId) if $groupId && !$self->find_group(sub {/^$groupId$/});

            if ($action =~ /^sendFrom/) {
                $self->respond(
                    $buddyId,
                    $groupId,
                    sub {
                        my $user = shift;

                        $self->receive(
                            Hubot::TextMessage->new(
                                user => $user,
                                text => $content,
                            )
                        );
                    }
                );
            } elsif ($action =~ /^(createGroup|inviteToGroup)$/) {
                $self->respond(
                    $buddyId,
                    $groupId,
                    sub {
                        my $user = shift;

                        $self->receive(
                            Hubot::EnterMessage->new(
                                user => $user
                            )
                        );
                    }
                );
            } elsif ($action eq 'exitFromGroup') {
                $self->respond(
                    $buddyId,
                    $groupId,
                    sub {
                        my $user = shift;

                        $self->receive(
                            Hubot::LeaveMessage->new(
                                user => $user
                            )
                        );
                    }
                );
            }
        }
    );

    my $port = $ENV{HUBOT_MYPEOPLE_PORT} || 8080;
    print __PACKAGE__ . " Accepting connection at http://0:$port\n";

    $self->emit('connected');
    $httpd->run;
}

sub respond {
    my ( $self, $buddyId, $groupId, $cb ) = @_;

    my $user = $self->userForId($buddyId, {room => $groupId || $buddyId });
    return $cb->($user) if $user->{id} ne $user->{name};

    $self->client->profile(
        $buddyId,
        sub {
            my $data = decode_json(shift);
            $user->{name} = $data->{buddys}[0]{name};
            $cb->($user);
        }
    );
}

sub close {
    my $self = shift;

    my $exit = 0;
    for my $groupId ($self->all_groups) {
        $self->client->exit(
            $groupId,
            sub {
                my $json = shift;
                return if $self->count_groups != ++$exit;

                $self->httpd->stop;
            }
        );
    }
}

__PACKAGE__->meta->make_immutable;

1;

=pod

=head1 SYNOPSIS

    # you might be never use this module directly
    $ hubot -a mypeople

=head1 DESCRIPTION

you should register your own bot via L<http://dna.daum.net/myapi/authapi/mypeople/new>.

=head1 SEE ALSO

http://dna.daum.net/myapi/authapi/mypeople/new

=cut
