package OpenXPKI::Server::Workflow::Validator::KeyParams;

use strict;
use warnings;
use base qw( OpenXPKI::Server::Workflow::Validator );
use Data::Dumper;
use OpenXPKI::Debug;
use OpenXPKI::Crypto::CSR;
use OpenXPKI::Server::Context qw( CTX );
use Workflow::Exception qw( validation_error configuration_error );
 
sub _validate {
    
    ##! 1: 'start'
    my ( $self, $wf, $cert_profile, $pkcs10 ) = @_;
    
    if (!$pkcs10) {
        ##! 8: 'skip - no data' 
        return 1; 
    }
        
    my $default_token = CTX('api')->get_default_token();
    my $csr_obj = OpenXPKI::Crypto::CSR->new(
        DATA  => $pkcs10,
        TOKEN => $default_token 
    );
    
    my $csr_body = $csr_obj->get_parsed_ref()->{BODY};
    ##! 32: 'csr_parsed: ' . Dumper $csr_body
    if (!$csr_body) {
        validation_error('I18N_OPENXPKI_UI_VALIDATOR_KEY_PARAM_CAN_NOT_PARSE_PKCS10');
    }
      
    ##! 32: 'CSR body ' . Dumper $csr_body
    
    my $key_alg;
    my $key_params = {};
    
    if ($csr_body->{PUBKEY_ALGORITHM} eq 'rsaEncryption') {
        $key_alg = 'rsa';
        $key_params = { key_length =>  $csr_body->{KEYSIZE} };
    } elsif ($csr_body->{PUBKEY_ALGORITHM} eq 'dsaEncryption') {
        $key_alg = 'dsa';
        $key_params = { key_length =>  $csr_body->{KEYSIZE} };
    } elsif ($csr_body->{PUBKEY_ALGORITHM} eq 'id-ecPublicKey') {
        $key_alg = 'ec';
        $key_params = { key_length =>  $csr_body->{KEYSIZE}, curve_name => '_any' };
        # not yet defined
    } else {
        validation_error('I18N_OPENXPKI_UI_VALIDATOR_KEY_PARAM_ALGO_NOT_SUPPORTED');
    }
    
    ##! 16: "Alg: $key_alg"
    ##! 16: 'Params ' . Dumper $key_params
    
    # get the list of allowed algorithms from the config
    my $algs = CTX('api')->get_key_algs({ PROFILE => $cert_profile, NOHIDE => 1 });
    
    ##! 32: 'Alg expected ' . Dumper $algs
    
    if (!grep(/$key_alg/, @{$algs})) {
        ##! 8: "KeyParam validation failed on algo $key_alg"
        CTX('log')->log(
            MESSAGE  => "KeyParam validation failed on algo $key_alg",
            PRIORITY => 'error',
            FACILITY => 'application',
        );
        validation_error('I18N_OPENXPKI_UI_VALIDATOR_KEY_PARAM_ALGO_NOT_ALLOWED');
    }
    
    my $params = CTX('api')->get_key_params({ PROFILE => $cert_profile, ALG => $key_alg, NOHIDE => 1 });
    
    ##! 32: 'Params expected ' . Dumper $params
    
    foreach my $param (keys %{$params}) {
        my $val = $key_params->{$param} || '';
        
        if ($val eq '_any') { next; }
        
        my @expect = @{$params->{$param}};
        ##! 32: "Validate param $param, $val, " . Dumper \@expect 
        if (!grep(/$val/, @expect)) {
            ##! 32: 'Failed on ' . $val
            CTX('log')->log(
                MESSAGE  => "KeyParam validation failed on $param with value $val",
                PRIORITY => 'error',
                FACILITY => 'application',
            );
            validation_error("I18N_OPENXPKI_UI_VALIDATOR_KEY_PARAM_PARAM_NOT_ALLOWED ($param)");
        }
    }

    ##! 1: 'Validation succeeded'
    CTX('log')->log(
        MESSAGE  => "KeyParam validation succeeded",
        PRIORITY => 'debug',
        FACILITY => 'application',
    );
        
    return 1;
}

1;

__END__

=head1 NAME

OpenXPKI::Server::Workflow::Validator::KeyParams

=head1 Description

Check if the key specification imported from the context matches the one
of the profile.

=head1 Configuration

  global_validate_key_param:
      class: OpenXPKI::Server::Workflow::Validator::KeyParams
      arg:
       - $cert_profile
       - $pkcs10
      
=head2 Arguments

=over

=item cert_profile

Name of the certificate profile

=item pkcs10

PEM encoded PKCS10

=back
