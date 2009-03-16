use strict;
use Module::Build;

my $build = Module::Build
  ->new( module_name  => "Net::FireEagle",
         license      => 'perl',
         script_files => [ 'bin/fireeagle' ],
         requires     => {
                          'JSON::Any'                => '0',
                          'Test::More'               => '0',
                          'Net::OAuth::Simple'       => '0.8',
                        },
         create_makefile_pl => 'traditional',
       );

$build->create_build_script;

