package MetaCPAN::Plack::Base;
use base 'Plack::Component';
use strict;
use warnings;
use JSON::XS;
use Try::Tiny;
use IO::String;
use Plack::App::Proxy;
use mro 'c3';

sub process_chunks {

    my ( $self, $res, $cb ) = @_;
    Plack::Util::response_cb(
        $res,
        sub {
            my $res = shift;
            my $json;
            return sub {
                my $chunk = shift;
                unless ( defined $chunk ) {
                    try {
                        $json = JSON::XS::decode_json($json);
                    }
                    catch {
                        $res = $json;
                    };
                    my $res;
                    try {
                        $res = $cb->($json);
                    }
                    catch {
                        $res = JSON::XS::encode_json($json);
                    };
                    return $res;
                }
                $json .= $chunk;
                return '';
              }

        } );
}

sub get_source {
    my ( $self, $env ) = @_;
    my $res =
      Plack::App::Proxy->new(
                        remote => "http://127.0.0.1:9200/cpan/" . $self->index )
      ->to_app->($env);
    $self->process_chunks( $res,
                           sub { JSON::XS::encode_json( $_[0]->{_source} ) } );

}

sub get_first_result {
    my ( $self, $env ) = @_;
    $self->rewrite_request($env);
    my $res =
      Plack::App::Proxy->new( remote => "http://127.0.0.1:9200/cpan" )
      ->to_app->($env);
    $self->process_chunks(
        $res,
        sub {
            JSON::XS::encode_json( $_[0]->{hits}->{hits}->[0]->{_source} );
        } );
}

sub rewrite_request {
    my ( $self, $env ) = @_;
    my ( undef, @args ) = split( "/", $env->{PATH_INFO} );
    my $path = '/' . $self->index . '/_search';
    $env->{REQUEST_METHOD} = 'GET';
    $env->{REQUEST_URI}    = $path;
    $env->{PATH_INFO}      = $path;
    my $query = encode_json( $self->query(@args) );
    $env->{'psgi.input'} = IO::String->new($query);
    $env->{CONTENT_LENGTH} = length($query);
}

sub call {
    my ( $self, $env ) = @_;
    if ( $env->{REQUEST_METHOD} ne 'POST' ) {
        return [ 403, [], ['Not allowed'] ];
    } elsif ( $env->{PATH_INFO} =~ /^\/_search/ ) {
        warn $env->{'psgi.input'};
        my $query = "";
        $query = $env->{'psgi.input'}->getline;
        warn $query;
        $env->{'psgi.input'} = IO::String->new($query);
        $env->{CONTENT_LENGTH} = length($query);
        return Plack::App::Proxy->new(
                        remote => "http://127.0.0.1:9200/cpan/" . $self->index )
          ->to_app->($env);
    } else {
        return $self->handle($env);
    }
}

1;

__END__

=head1 DESCRIPTION

The C<MetaCPAN::Plack> namespace consists if Plack applications. For each
endpoint exists one class which handles the request.

There are two types of apps under this namespace. 
Modules like L<MetaCPAN::Plack::Module> need to perform a search based
on the name to get the latest version of a module. To make this possible
C<PATH_INFO> needs to be rewritten and a body needs to be injected 
in the request.

Other modules like L<MetaCPAN::Plack::Author> are requested by the id,
so there is no need to issue a search. Hoewever, this module will
strip the ElasticSearch meta data and return the C<_source> attribute.

=head1 METHODS

=head2 call

Catch non-GET requests and return a 403 status if there was a non-GET request.

If the C<PATH_INFO> is a C</_search>, forward request to ElasticSearch.

Otherwise let the module handle the request (i.e. call C<< $self->handle >>).

=head2 rewrite_request

Sets the C<PATH_INFO> and a body, if necessary. Calls L</query> for a
query object.

=head2 get_first_result

Returns the C<_source> of the first result.

=head2 get_source

Get the C<_source>.

=head2 process_chunks

Handling chunked responses.

=head1 SUBCLASSES

Subclasses have to implement some of the following methods:

=head2 index

Simply return the name of the index.

=head2 handle

This method is called from L</call> and passed the C<$env>.
It's purpose is to call L</get_source> or L</get_first_result>
based on the type of lookup.

=head2 query

If L</handle> calls L</get_first_result>, this method will be called
to get a query object, which is passed to the ElasticSearch server.

=head1 SEE ALSO

L<MetaCPAN::Plack::Base>
