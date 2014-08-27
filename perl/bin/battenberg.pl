use strict;
use warnings FATAL => 'all';
use autodie qw(:all);

use File::Path qw( remove_tree make_path );
use File::Spec;
use Getopt::Long;
use Pod::Usage qw(pod2usage);
use List::Util qw(first);
use Const::Fast qw(const);
use File::Copy;

use PCAP::Cli;
use Sanger::CGP::Battenberg::Implement;

const my @VALID_PROCESS => qw( allelecount baflog imputefromaf
															impute combineimpute haplotypebafs
															cleanuppostbaf plothaplotypes combinebafs
															segmentphased fitcn subclones finalise );

const my $DEFAULT_ALLELE_COUNT_MBQ => 20;
const my $DEFAULT_PLATFORM_GAMMA=>1;
const my $DEFAULT_PHASING_GAMMA=>1;
const my $DEFAULT_SEGMENTATION_GAMMA=>10;
const my $DEFAULT_CLONALITY_DIST=>0;
const my $DEFAULT_ASCAT_DIST=>1;
const my $DEFAULT_MIN_PLOIDY=>1.6;
const my $DEFAULT_MAX_PLOIDY=>4.8;
const my $DEFAULT_MIN_RHO=>0.1;
const my $DEFAULT_MIN_GOODNESS_OF_FIT=>0.63;
const my $DEFAULT_BALANCED_THRESHOLD=>0.51;

my %index_max = ( 'allelecount' => -1,
									'baflog' => 1,
									'imputefromaf' => -1,
									'impute' => -1,
									'combineimpute' => -1,
									'haplotypebafs' => -1,
									'cleanuppostbaf' => -1,
									'plothaplotypes' => -1,
									'combinebafs' => 1,
									'segmentphased' => 1,
									'fitcn' => 1,
									'subclones' => 1,
									'finalise' => 1,
								);

{
	my $options = setup();
	Sanger::CGP::Battenberg::Implement::prepare($options);

	my $threads = PCAP::Threaded->new($options->{'threads'});
	&PCAP::Threaded::disable_out_err if(exists $options->{'index'});

	# register multi  processes
	$threads->add_function('battenberg_allelecount', \&Sanger::CGP::Battenberg::Implement::battenberg_allelecount);
	$threads->add_function('battenberg_imputefromaf', \&Sanger::CGP::Battenberg::Implement::battenberg_imputefromaf);
	$threads->add_function('battenberg_runimpute', \&Sanger::CGP::Battenberg::Implement::battenberg_runimpute);
	$threads->add_function('battenberg_combineimpute', \&Sanger::CGP::Battenberg::Implement::battenberg_combineimpute);
  $threads->add_function('battenberg_haplotypebaf', \&Sanger::CGP::Battenberg::Implement::battenberg_haplotypebaf);
	$threads->add_function('battenberg_postbafcleanup', \&Sanger::CGP::Battenberg::Implement::battenberg_postbafcleanup);
	$threads->add_function('battenberg_plothaplotypes', \&Sanger::CGP::Battenberg::Implement::battenberg_plothaplotypes);

	my $no_of_jobs = Sanger::CGP::Battenberg::Implement::file_line_count_with_ignore($options->{'reference'},$options->{'ignored_contigs'});
	$options->{'job_count'} = $no_of_jobs;
  #Now the single processes built into the battenberg flow in order of execution.
  $threads->run(($no_of_jobs*2), 'battenberg_allelecount', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'allelecount');

	Sanger::CGP::Battenberg::Implement::battenberg_runbaflog($options) if(!exists $options->{'process'} || $options->{'process'} eq 'baflog');

	$threads->run($no_of_jobs, 'battenberg_imputefromaf', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'imputefromaf');

	$threads->run($no_of_jobs, 'battenberg_runimpute', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'impute');

	$threads->run($no_of_jobs, 'battenberg_combineimpute', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'combineimpute');

	$threads->run($no_of_jobs, 'battenberg_haplotypebaf', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'haplotypebafs');

	$threads->run($no_of_jobs, 'battenberg_postbafcleanup', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'cleanuppostbaf');

	$threads->run($no_of_jobs, 'battenberg_plothaplotypes', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'plothaplotypes');

	Sanger::CGP::Battenberg::Implement::battenberg_combinebafs($options) if(!exists $options->{'process'} || $options->{'process'} eq 'combinebafs');

	Sanger::CGP::Battenberg::Implement::battenberg_segmentphased($options) if(!exists $options->{'process'} || $options->{'process'} eq 'segmentphased');

	Sanger::CGP::Battenberg::Implement::battenberg_fitcopyno($options) if(!exists $options->{'process'} || $options->{'process'} eq 'fitcn');

	Sanger::CGP::Battenberg::Implement::battenberg_callsubclones($options) if(!exists $options->{'process'} || $options->{'process'} eq 'subclones');

	if(!exists $options->{'process'} || $options->{'process'} eq 'finalise'){
		#Sanger::CGP::Battenberg::Implement::battenberg_finalise($options);
		#cleanup($options);
	}
}

sub setup {
  my %opts;
  GetOptions(
  				'h|help' => \$opts{'h'},
					'm|man' => \$opts{'m'},
					'o|outdir=s' => \$opts{'outdir'},
					'tb|tumour-bam=s' => \$opts{'tumbam'},
					'nb|normal-bam=s' => \$opts{'normbam'},
					't|threads=i' => \$opts{'threads'},
					'i|index=i' => \$opts{'index'},
					'l|limit=i' => \$opts{'limit'},
					'p|process=s' => \$opts{'process'},
					'u|thousand-genomes-loc=s' => \$opts{'1kgenloc'},
					'r|reference=s' => \$opts{'reference'},
					's|is-male' => \$opts{'is_male'},
					'e|impute-info=s' => \$opts{'impute_info'},
					'c|prob-loci=s' => \$opts{'prob_loci'},
					'g|logs=s' => \$opts{'lgs'},
					'ig|ignore-contigs-file=s' => \$opts{'ignore_file'},
					#The following are optional params with defaults as constants
					'q|min-bq-allcount=i' => \$opts{'mbq'},
					'sg|segmentation-gamma=i' => \$opts{'seg_gamma'},
					'pg|phasing-gamma=i' => \$opts{'phase_gamma'},
					'cd|clonality-distance=i' => \$opts{'clonality_dist'},
					'ad|ascat-distance=i' => \$opts{'ascat_dist'},
					'bt|balanced-threshold=f' => \$opts{'balanced_thresh'},
					'lg|platform-gamma=i' => \$opts{'plat_gamma'},
					'mp|min-ploidy=f' => \$opts{'min_ploidy'},
					'xp|max-ploidy=f' => \$opts{'max_ploidy'},
					'mr|min-rho=f' => \$opts{'min_rho'},
					'mg|min-goodness-of-fit=f' => \$opts{'min_goodness'},
		) or pod2usage(2);

	pod2usage(-message => PCAP::license, -verbose => 2) if(defined $opts{'h'});
  pod2usage(-message => PCAP::license, -verbose => 1) if(defined $opts{'m'});

  # then check for no args:
  my $defined;
  for(keys %opts) { $defined++ if(defined $opts{$_}); }

	pod2usage(-msg  => "\nERROR: Options must be defined.\n", -verbose => 2,  -output => \*STDERR) unless($defined);

  PCAP::Cli::file_for_reading('tumour-bam',$opts{'tumbam'});
  PCAP::Cli::file_for_reading('normal-bam',$opts{'normbam'});
  #We should also check the bam indexes exist.
  my $tumidx = $opts{'tumbam'}.".bai";
  my $normidx = $opts{'normbam'}.".bai";
  PCAP::Cli::file_for_reading('tumour-bai',$tumidx);
  PCAP::Cli::file_for_reading('normal-bai',$normidx);
  PCAP::Cli::file_for_reading('impute_info.txt',$opts{'impute_info'});
  PCAP::Cli::file_for_reading('prob_loci.txt',$opts{'prob_loci'});

	@{$opts{'ignored_contigs'}} = ();
	if(exists ($opts{'ignore_file'}) && defined($opts{'ignore_file'})){
		$opts{'ignored_contigs'} = Sanger::CGP::Battenberg::Implement::read_contigs_from_file($opts{'ignore_file'});
	}


	delete $opts{'process'} unless(defined $opts{'process'});
  delete $opts{'index'} unless(defined $opts{'index'});
  delete $opts{'limit'} unless(defined $opts{'limit'});

	if(exists $opts{'process'}) {
    PCAP::Cli::valid_process('process', $opts{'process'}, \@VALID_PROCESS);
    if(exists $opts{'index'}) {
      my $max = $index_max{$opts{'process'}};
      if($max==-1){
        if(exists $opts{'limit'}) {
          $max = $opts{'limit'};
        }
      }

      die "ERROR: based on reference and exclude option index must be between 1 and $max\n" if($opts{'index'} < 1 || $opts{'index'} > $max);
      PCAP::Cli::opt_requires_opts('index', \%opts, ['process']);

      die "No max has been defined for this process type\n" if($max == 0);

      PCAP::Cli::valid_index_by_factor('index', $opts{'index'}, $max, 1);
    }
  }
  elsif(exists $opts{'index'}) {
    die "ERROR: -index cannot be defined without -process\n";
  }

  # now safe to apply defaults
	$opts{'threads'} = 1 unless(defined $opts{'threads'});

	#Create the results directory in the output directory given.
	my $tmpdir = File::Spec->catdir($opts{'outdir'}, 'tmpBattenberg');
	make_path($tmpdir) unless(-d $tmpdir);
	$opts{'tmp'} = $tmpdir;
	my $resultsdir = File::Spec->catdir($opts{'tmp'}, 'results');
	make_path($resultsdir) unless(-d $resultsdir);
	#directory to store progress reports
	my $progress = File::Spec->catdir($opts{'tmp'}, 'progress');
  make_path($progress) unless(-d $progress);
	#Directory to store run logs.
	my $logs;
	if(defined $opts{'lgs'}){
	  $logs = $opts{'lgs'};
	}else{
    $logs = File::Spec->catdir($opts{'tmp'}, 'logs');
	}
	make_path($logs) unless(-d $logs);
	$opts{'logs'} = $logs;

	if(exists($opts{'is_male'}) && defined($opts{'is_male'})){
		$opts{'is_male'} = 'TRUE';
	}else{
		$opts{'is_male'} = 'FALSE';
	}

	#Setup default values if they're not set at commandline

	$opts{'mbq'} = $DEFAULT_ALLELE_COUNT_MBQ if(!exists($opts{'mbq'}) || !defined($opts{'mbq'}));
	$opts{'seg_gamma'} = $DEFAULT_SEGMENTATION_GAMMA if(!exists($opts{'seg_gamma'}) || !defined($opts{'seg_gamma'}));
	$opts{'phase_gamma'} = $DEFAULT_PHASING_GAMMA if(!exists($opts{'phase_gamma'}) || !defined($opts{'phase_gamma'}));
	$opts{'clonality_dist'} = $DEFAULT_CLONALITY_DIST if(!exists($opts{'clonality_dist'}) || !defined($opts{'clonality_dist'}));
	$opts{'ascat_dist'} = $DEFAULT_ASCAT_DIST if(!exists($opts{'ascat_dist'}) || !defined($opts{'ascat_dist'}));
	$opts{'balanced_thresh'} = $DEFAULT_BALANCED_THRESHOLD if(!exists($opts{'balanced_thresh'}) || !defined($opts{'balanced_thresh'}));
	$opts{'plat_gamma'} = $DEFAULT_PLATFORM_GAMMA if(!exists($opts{'plat_gamma'}) || !defined($opts{'plat_gamma'}));
	$opts{'min_ploidy'} = $DEFAULT_MIN_PLOIDY if(!exists($opts{'min_ploidy'}) || !defined($opts{'min_ploidy'}));
	$opts{'max_ploidy'} = $DEFAULT_MAX_PLOIDY if(!exists($opts{'max_ploidy'}) || !defined($opts{'max_ploidy'}));
	$opts{'min_rho'} = $DEFAULT_MIN_RHO if(!exists($opts{'min_rho'}) || !defined($opts{'min_rho'}));
	$opts{'min_goodness'} = $DEFAULT_MIN_GOODNESS_OF_FIT if(!exists($opts{'min_goodness'}) || !defined($opts{'min_goodness'}));

	return \%opts;
}





__END__

=head1 NAME

battenberg.pl - Analyse aligned bam files for battenberg subclones and CN variations.

=head1 SYNOPSIS

battenberg.pl [options]

  Required parameters:
    -outdir                -o   Folder to output result to.
    -reference             -r   Path to reference genome index file *.fai
    -tumour-bam            -tb  Path to tumour bam file
    -normal-bam            -nb  Path to normal bam file
    -is-male               -s   Flag, if the sample is male
    -impute-info           -e   location of the impute info file
    -thousand-genomes-loc  -u   location of the directory containing 1k genomes data

   Optional parameters:
    -min-bq-allcount       -q   Minimum base quality to permit allele counting
    -segmentation-gamma    -sg  Segmentation gamma
    -phasing-gamma         -pg  Phasing gamma
    -clonality-distance    -cd  Clonality distance
    -ascat-distance        -ad  ASCAT distance
    -balanced-threshold    -bt  Balanced threshold
    -platform-gamma        -lg  Platform gamma
    -min-ploidy            -mp  Min ploidy
    -max-ploidy            -xp  Max ploidy
    -min-rho               -mr  Min Rho
    -min-goodness-of-fit   -mg  Min goodness of fit

   Optional system related parameters:
    -threads           -t   Number of threads allowed on this machine (default 1)
    -limit             -l   Limit the number of jobs required for m/estep (default undef)
    -logs              -g   Location to write logs (default is ./logs)

   Targeted processing (further detail under OPTIONS):
    -process  -p  Only process this step then exit, optionally set -index
    -index    -i  Optionally restrict '-p' to single job

   Other:
    -help     -h  Brief help message.
    -man      -m  Full documentation.

=head1 OPTIONS

=over 8

=item B<-outdir>

Directory to write output to.  During processing a temp folder will be generated in this area,
should the process fail B<only delete this if> you are unable to resume the process.

Final output files are: muts.vcf.gz, snps.vcf.gz, no_analysis.bed.gz no_analysis.bed.gz.tbi

=back

=head1 DESCRIPTION

B<caveman.pl> will attempt to run all caveman steps automatically including collation of output files.

=cut

