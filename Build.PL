# $Id: Build.PL,v 1.1 2007/06/28 04:57:30 asc Exp $

use strict;
use Module::Build;

my $build = Module::Build->new(module_name => 'Net::FireEagle',
			       # dist_author
			       # dist_abstract
			       dist_version_from => 'lib/Net/FireEagle.pm',
			       license           => 'perl',
			       requires => {
				   'Config::Simple'  => '0',
				   'LWP::UserAgent'  => '0',
				   'URI'             => '0',
				   'Digest::SHA1'    => '0',
				   'Readonly'        => '0',
				   'Log::Dispatch'   => '>= 2.10',
				   'XML::XPath'      => '>= 1.13',
			       },
			       build_requires => {
				   'Test::Simple'              => '>= 0.47',
			       },
			       create_readme      => 1,
			       create_makefile_pl => 'passthrough');

$build->create_build_script();
