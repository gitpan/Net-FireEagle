use strict;

# $Id: FireEagle.pm,v 1.6 2007/06/30 04:25:27 asc Exp $

package Net::FireEagle;
use base qw (LWP::UserAgent);

$Net::FireEagle::VERSION = '1.01';

=head1 NAME

Net::FireEagle - Object methods for working with the FireEagle location service.

=head1 SYNOPSIS

 use Getopt::Std;
 use Net::FireEagle;

 my %opts = ();
 getopts('c:', \%opts);

 my $fe = Net::FireEagle->new($opts{'c'});
 $fe->update_location("loc" => "Montreal QC");

 my $res  = $fe->query_location();
 my $city = $res->findvalue("/ResultSet/Result/city");

 print "OH HAI! IM IN UR $city\n";

=head1 DESCRIPTION

Object methods for working with the FireEagle location service.

=head1 OPTIONS

Options are passed to Net::Flickr::Backup using a Config::Simple object or
a valid Config::Simple config file. Options are grouped by "block".

=head2 fireeagle

=over 4

=item * B<app_key>

String. I<required>

A valid FireEagle application key.

=item * B<app_secret>

String. I<required>

A valid FireEagle application secret.

=item * B<auth_token>

A valid FireEagle authentication token for a user.

=item * B<api_handler>

String. I<required>

The B<api_handler> defines which XML/XPath handler to use to process API responses.

=over 4 

=item * B<LibXML>

Use XML::LibXML.

=item * B<XPath>

Use XML::XPath.

=back

=back

=cut

use Config::Simple;
use Readonly;
use URI;
use Digest::SHA1 qw(sha1_hex);
use HTTP::Request;
use Log::Dispatch;
use Log::Dispatch::Screen;

Readonly::Scalar my $FE_SCHEME => "http";
Readonly::Scalar my $FE_HOST   => "fireeagle.research.yahoo.com";

Readonly::Scalar my $FE_AUTHORIZE     => "/authorize.php";
Readonly::Scalar my $FE_DISPLAYTOKEN  => "/displayToken.php";

Readonly::Scalar my $FE_EXCHANGETOKEN => "/api/exchangeToken.php";
Readonly::Scalar my $FE_QUERYLOC      => "/api/queryLoc.php";
Readonly::Scalar my $FE_UPDATELOC     => "/api/updateLoc.php";

=head1 PACKAGE METHODS

=cut

=head2 __PACKAGE__->new($cfg)

Where B<$cfg> is either a valid I<Config::Simple> object or the path
to a file that can be parsed by I<Config::Simple>.

Returns a I<Net::FireEagle> object.

=cut

sub new {
        my $pkg = shift;
        my $cfg = shift;

        my $self = LWP::UserAgent->new();

        #
        # Log-o-rama
        #

        my $log_fmt = sub {
                my %args = @_;
                
                my $msg = $args{'message'};
                chomp $msg;
                
                if ($args{'level'} eq "error") {
                        
                        my ($ln, $sub) = (caller(4))[2,3];
                        $sub =~ s/.*:://;
                        
                        return sprintf("[%s][%s, ln%d] %s\n",
                                       $args{'level'}, $sub, $ln, $msg);
                }
                
                return sprintf("[%s] %s\n", $args{'level'}, $msg);
        };
        
        my $logger = Log::Dispatch->new(callbacks=>$log_fmt);
        my $error  = Log::Dispatch::Screen->new(name      => '__error',
                                                min_level => 'error',
                                                stderr    => 1);
        
        $logger->add($error);

        #
        # Who am I?
        #

        $self->agent("FIREBAGEL $Net::FireEagle::VERSION");

        if (ref($cfg) eq "Config::Simple") {
                $self->{'__cfg'} = $cfg;
        }
        
        elsif (-f $cfg){

                eval {
                        $self->{'__cfg'} = Config::Simple->new($cfg);                        
                };

                if ($@) {
                        $logger->error($@);
                        return undef;
                }
        }

        else {
                $logger->error("Not a valid Config::Simple object or path");
                return undef;
        }

        # 
        # Ensure we have everything we
        # need to work with
        #

        my %required = (
                        "fireeagle" => ["app_key", "app_secret", "api_handler"],
                       );

        foreach my $class (keys %required) {
                foreach my $param (@{$required{$class}}){
                        my $key = $class . "." .  $param;

                        if (! $self->{'__cfg'}->param($key)){
                                $logger->error("Missing $class $param config");
                                return undef;
                        }
                }
        }

        if ($self->{'__cfg'}->param("fireeagle.api_handler") !~ /^(?:XPath|LibXML)$/) {
                $logger->error("Invalid API handler");
                return 0;
        }
        
        #
        # Make it so...
        #
                
        $self->{'__log'} = $logger;

        bless $self, $pkg;
        return $self;
}

=head1 OBJECT METHODS YOU SHOULD CARE ABOUT

=cut

=head2 $obj->query_location()

Query FireEagle for a user's (as defined by the I<fireeagle.auth_token> config) 
current location.

If the method encounters any errors calling the API, receives an API error
or can not parse the response it will log an error event, via the B<log> method,
and return undef.

Otherwise it will return a I<XML::LibXML::Document> object (if XML::LibXML is
installed) or a I<XML::XPath> object.

=cut

sub query_location {
        my $self = shift;
        my $token = shift;
        
        $token ||= $self->{'__cfg'}->param("fireeagle.auth_token");

        my %args = ("appid"     => $self->{'__cfg'}->param("fireeagle.app_key"),
                    "userid"    => $token,
                    "timestamp" => time());

        $self->sign_args(\%args);

        my $uri = URI->new();
        $uri->scheme($FE_SCHEME);
        $uri->host($FE_HOST);
        $uri->path($FE_QUERYLOC);
        $uri->query_form(%args);

        my $url = $uri->as_string();
        return $self->execute_request($url);
}

=head2 $obj->update_location(%args)

Notify FireEagle of a user's (as defined by the I<fireeagle.auth_token> config)
current location.

Valid arguments are a hash of key/value pairs a defined by the FireEagle 
update API documentation.

If the method encounters any errors calling the API, receives an API error
or can not parse the response it will log an error event, via the B<log> method,
and return undef.

Otherwise it will return a I<XML::LibXML::Document> object (if XML::LibXML is
installed) or a I<XML::XPath> object.

=cut

sub update_location {
        my $self = shift;
        my %args = @_;

        $args{"appid"} = $self->{'__cfg'}->param("fireeagle.app_key");
        $args{"userid"} = $self->{'__cfg'}->param("fireeagle.auth_token");
        $args{"timestamp"} = time();

        $self->sign_args(\%args);

        my $uri = URI->new();
        $uri->scheme($FE_SCHEME);
        $uri->host($FE_HOST);
        $uri->path($FE_UPDATELOC);
        $uri->query_form(%args);

        my $url = $uri->as_string();
        return $self->execute_request($url);
}

=head2 $obj->authorize_url()

Generate a URL for requesting a user's authorization for your application.

Returns a string.

=cut

sub authorize_url {
        my $self = shift;
        my $uri = URI->new();
        $uri->scheme($FE_SCHEME);
        $uri->host($FE_HOST);
        $uri->path($FE_AUTHORIZE);
        $uri->query_form("appid" => $self->{'__cfg'}->param("fireeagle.app_key"));
        return $uri->as_string();
}

=head2 $obj->mobile_token_url()

Generate a URL for creating a mobile shortcode for your application.

Returns a string.

=cut

sub mobile_token_url {
        my $self = shift;
        my $uri = URI->new();
        $uri->scheme($FE_SCHEME);
        $uri->host($FE_HOST);
        $uri->path($FE_DISPLAYTOKEN);
        $uri->query_form("appid" => $self->{'__cfg'}->param("fireeagle.app_key"));
        return $uri->as_string();
}

=head2 $obj->exchange_mobile_token($shortcode)

Exchange a mobile shortcode for a permanent user authentication token.

Returns a string on success, or undef.

=cut

sub exchange_mobile_token {
        my $self = shift;
        my $shortcode = shift;

        my %args = ("appid" => $self->{'__cfg'}->param("fireeagle.app_key"),
                    "shortcode" => $shortcode,
                    "timestamp" => time());

        $self->sign_args(\%args);

        my $uri = URI->new();
        $uri->scheme($FE_SCHEME);
        $uri->host($FE_HOST);
        $uri->path($FE_EXCHANGETOKEN);
        $uri->query_form(%args);

        my $url = $uri->as_string();
        my $res = $self->execute_request($url);

        if (! $res) {
                return undef;
        }

        my $stat = $res->findvalue("/rsp/\@stat");

        if ($stat ne "ok"){
                $self->log()->error($res->findvalue("/rsp/\@msg"));
                return undef;
        }

        return $res->findvalue("/rsp/token");
}

=head1 OBJECT METHODS YOU MAY CARE ABOUT

=cut

=head2 $obj->sign_args(\%args)

Generate an API signature and adds it to the %args hash.

=cut

sub sign_args {
        my $self = shift;
        my $args = shift;
        my $sig = $self->generate_sig($args);
        $args->{'sig'} = $sig;
}

=head2 $obj->generate_sig(\%args)

Returns a string.

=cut

sub generate_sig {
        my $self = shift;
        my $args = shift;

        my $sig = $self->{'__cfg'}->param("fireeagle.app_secret");

        foreach my $key (sort keys %$args) {
                $sig .= $key;
                $sig .= $args->{$key};
        }

        return sha1_hex($sig);
}

=head2 $obj->execute_request($url)

If the method encounters any errors it will log an error event, via the B<log>
method, and return undef.

Otherwise it will return a I<XML::LibXML::Document> object (if XML::LibXML is
installed) or a I<XML::XPath> object.

=cut

sub execute_request {
        my $self = shift;
        my $url  = shift;

        my $req = HTTP::Request->new('GET' => $url);
        my $res = $self->request($req);

        if (! $res->is_success()){
                $self->log()->error("API request failed, " . $res->message());
                return undef;
        }

        my $xml = $self->parse_response($res);

        if (! $xml) {
                return undef;
        }

        return $xml;
}

=head2 $obj->parse_response(HTTP::Response)

=cut

sub parse_response {
        my $self = shift;
        my $res  = shift;

        my $xml = undef;

        if ($self->{'__cfg'}->param("fireeagle.api_handler") eq "XPath") {
                eval "require XML::XPath";

                if (! $@) {
                        eval {
                                $xml = XML::XPath->new(xml=>$res->content());
                        };
                }
        }
        
        else {
                eval "require XML::LibXML";

                if (! $@) {
                        eval {
                                my $parser = XML::LibXML->new();
                                $xml = $parser->parse_string($res->content());
                        };
                }
        }

        if (! $xml) {
                $self->log()->error("Failed to parse response, $@");
                return undef;
        }

        # 
        
        if ($xml->findvalue("/ResultSet/Error")){
                $self->log()->error("API error, " . $xml->findvalue("/ResultSet/ErrorMessage"));
                return undef;
        }

        # 

        return $xml;
}

=head2 $obj->log()

Returns a I<Log::Dispatch> object.

=cut

sub log {
        my $self = shift;
        return $self->{'__log'};
}

=head1 VERSION

1.01

=head1 DATE

$Date: 2007/06/30 04:25:27 $

=head1 AUTHOR

Aaron Straup Cope  E<lt>ascope@cpan.orgE<gt>

=head1 SEE ALSO

L<http://fireeagle.research.yahoo.com/>

L<http://www.aaronland.info/weblog/2007/06/08/pynchonite/#firebagel>

L<Config::Simple>

=head1 BUGS

Please report all bugs via http://rt.cpan.org/

=head1 LICENSE

Copyright (c) 2007 Aaron Straup Cope. All Rights Reserved.

This is free software. You may redistribute it and/or
modify it under the same terms as Perl itself.

=back

return 1;
