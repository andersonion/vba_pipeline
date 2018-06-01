#!/usr/local/pipeline-link/perl
# vbm_pipeline_start.pl
# originally created as vbm_pipeline, 2014/11/17 BJ Anderson CIVM
# vbm_pipeline_start spun off on 2017/03/14 BJ Anderson CIVM
#
# Roughly modeled after seg_pipe_mc structure. (For better or for worse.)
#


# All my includes and requires are belong to us.
# use ...

my $PM = 'vbm_pipeline_start.pl'; 

use strict;
no strict "refs";
use warnings;
no warnings qw(uninitialized bareword);

require pipeline_utilities;
require Headfile;

use Cwd qw(abs_path);
use File::Basename;
use List::MoreUtils qw(uniq);
use vars qw($Hf $BADEXIT $GOODEXIT $test_mode $syn_params $permissions  $valid_formats_string $nodes $reservation $mdt_to_reg_start_time);
use Env qw(ANTSPATH PATH BIGGUS_DISKUS WORKSTATION_DATA WORKSTATION_HOME PIPELINE_PATH);

use JSON::Parse qw(json_file_to_perl valid_json assert_valid_json);

my $full_pipeline_path = abs_path($0);
my ($pipeline_path,$dummy1,$dummy2) = fileparts($full_pipeline_path,2);

$ENV{'PATH'}=$ANTSPATH.':'.$PATH;
$ENV{'WORKSTATION_HOME'}="/cm/shared/workstation_code_dev";
$ENV{'PIPELINE_PATH'}=$pipeline_path;
$GOODEXIT = 0;
$BADEXIT  = 1;
my $ERROR_EXIT=$BADEXIT;
$permissions = 0755;
my $interval = 1;
$valid_formats_string = 'hdr|img|nii';


# a do it again variable, will allow you to pull data from another vbm_run
my $import_data = 1;

$test_mode = 0;
use vars qw($start_file);
$start_file=shift(@ARGV); #my

if ( ! -f $start_file )  {
    $nodes = $start_file;
    $start_file = '';
} else {
    $nodes = shift(@ARGV);
}

$reservation='';

if (! defined $nodes) {
    $nodes = 4 ;}
else {
    if ($nodes =~ /[^0-9]/) { # Test to see if this is not a number; if so, assume it to be a reservation.
	$reservation = $nodes;
	my $reservation_info = `scontrol show reservation ${reservation}`;
	if ($reservation_info =~ /NodeCnt=([0-9]*)/m) { # Unsure if I need the 'm' option)
	    $nodes = $1;
	} else {
	    $nodes = 4;
	    print "\n\n\n\nINVALID RESERVATION REQUESTED: unable to find reservation \"$reservation\".\nProceeding with NO reservation, and assuming you want to run on ${nodes} nodes.\n\n\n"; 
	    $reservation = '';
	    sleep(5);
	}
    }
}


print "Attempting to use $nodes nodes;\n\n";
if ($reservation) { 
    print "Using slurm reservation = \"$reservation\".\n\n\n";
}
umask(002);

use lib dirname(abs_path($0));
use Env qw(RADISH_PERL_LIB);
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quitting\n";
    exit;
}
#my $custom_pipeline_utilities_path ="${WORKSTATION_HOME}/shared/cluster_pipeline_utilities/"; #11 April 2017, BJA: I think this was to avoid having to reconcile our pipeline_utility functions. We might be able to delete that whole folder.
#$RADISH_PERL_LIB=$custom_pipeline_utilities_path.':'.$RADISH_PERL_LIB;
use lib split(':',$RADISH_PERL_LIB);

# require ...
require study_variables_vbm;
require vbm_pipeline_workflow;
require apply_warps_to_bvecs;
require Headfile;

## Example use of printd
use civm_simple_util qw(printd $debug_val);
#$debug_val = 35;
#my $msg =  "Your message here!";
#printd(5,$msg);

# variables, set up by the study vars script(study_variables_vbm.pm)
use vars qw(
$project_name 
@control_group
$control_comma_list
@compare_group
$compare_comma_list

$complete_comma_list

@group_1
$group_1_runnos
@group_2
$group_2_runnos
$all_groups_comma_list

@channel_array
$channel_comma_list

$custom_predictor_string
$template_predictor
$template_name

$flip_x
$flip_z 
$optional_suffix
$atlas_name
$label_atlas_name

$skull_strip_contrast
$threshold_code
$do_mask
$pre_masked
$port_atlas_mask
$port_atlas_mask_path
$thresh_ref

$rigid_contrast

$affine_contrast
$affine_metric
$affine_radius
$affine_shrink_factors
$affine_iterations
$affine_gradient_step
$affine_convergence_thresh
$affine_convergence_window
$affine_smoothing_sigmas
$affine_sampling_options
$affine_target

$mdt_contrast
$mdt_creation_strategy
$mdt_iterations
$mdt_convergence_threshold
$initial_template

$compare_contrast

$diffeo_metric
$diffeo_radius
$diffeo_shrink_factors
$diffeo_iterations
$diffeo_transform_parameters
$diffeo_convergence_thresh
$diffeo_convergence_window
$diffeo_smoothing_sigmas
$diffeo_sampling_options

$vbm_reference_space
$reference_path
$create_labels
$label_space
$label_reference

$do_vba
$fdr_masks
$tfce_extent
$tfce_height
$fsl_cluster_size

$nonparametric_permutations

$convert_labels_to_RAS
$eddy_current_correction
$do_connectivity
$recon_machine

$original_study_orientation
$working_image_orientation

$fixed_image_for_mdt_to_atlas_registratation

$vba_contrast_comma_list
$vba_analysis_software
$smoothing_comma_list

$U_specid
$U_species_m00
$U_code

$image_dimensions

$participants

@comparisons
@predictors
 );



my $kevin_spacey='';
foreach my $entry ( keys %main:: )  { # Build a string of all initialized variables, etc, that contain only letters, numbers, or '_'.
    if ($entry =~ /^[A-Za-z0-9_]+$/) {
    	$kevin_spacey = $kevin_spacey." $entry ";
    }
}

my $test_shit = join(' ',sort(split(' ',$kevin_spacey)))."\n\n\n";
#print $test_shit;
#die;
my $tmp_rigid_atlas_name='';
{
    if ($start_file =~ /.*\.headfile$/) {
        load_SAMBA_parameters($start_file);
    } elsif ($start_file =~ /.*\.json$/) {
        load_SAMBA_json_parameters($start_file); 
    } else {
        study_variables_vbm();
    }

    if (! defined $do_vba) {
        $do_vba = 1;
    }
    vbm_pipeline_workflow();


} #end main

# ------------------
sub load_SAMBA_parameters {
# ------------------
    my ($param_file) = (@_);
    my $tempHf = new Headfile ('rw', "${param_file}");
    if (! $tempHf->check()) {
	error_out(" Unable to open SAMBA parameter file ${param_file}.");
	return(0);
    }
    if (! $tempHf->read_headfile) {
	error_out(" Unable to read SAMBA parameter file ${param_file}."); 
	return(0);
    }
    my $is_headfile=1;  
    assign_parameters($tempHf,$is_headfile);
    }

# ------------------
sub load_SAMBA_json_parameters {
# ------------------
    my ($json_file) = (@_);
    my $tempHf = json_file_to_perl($json_file);
    if (0){
    eval {
        assert_valid_json (  $json_file);
    };
    if ($@) {
        error_out("Invalid .JSON parameter file ${json_file}: $@\n");
    #}
    #if (! valid_json($json_file)) {
    #    error_out(" Invalid .JSON parameter file ${json_file}."); 
        return(0);
    }
    }
    
    my $is_headfile=0;
    assign_parameters($tempHf,$is_headfile);

    }


# ------------------
sub assign_parameters {
# ------------------

    my ($tempHf,$is_headfile) = (@_); # Current headfile implementation only supports strings/scalars

    if ($is_headfile) {
        foreach ($tempHf->get_keys) {
            my $val = $tempHf->get_value($_);
            #if ($val eq '') { # Don't know what this code was doing; commenting out 31 May 2018.
            #    print "$val\n";
            #}

            if ($kevin_spacey =~ /$_/) {
                if (defined $val) {
#                   print "$_\n";
                    eval("\$$_=\'$val\'");
#               if (defined ${$_}) {
                    print "$_ = ${$_}\n";
#                }	   
                    if ($_ eq 'rigid_atlas_name'){
                        $tmp_rigid_atlas_name=${$_};
                    }
                }
            }
        }
    } else {
        foreach (keys %{ $tempHf }) {
            if ($kevin_spacey =~ /\b$_\b/) {

            #my $val = %{ $tempHf }->{($_)};
            #print "\n\n$_\n\n"; 
            my $val = %{ $tempHf }->{$_};
            if ($val ne '') {
                #print "LOOK HERE TO SEE NOTHING\$val = ${val}\n";
                if ($val =~ /^ARRAY\(0x[0-9,a-f]{5,}/){
                    eval("\@$_=\'@$val\'");
                    print "$_ = @{$_}\n"; 
                } elsif ($val =~ /^HASH\(0x[0-9,a-f]{5,}/){
                    eval("\%$_=\'%$val\'");
                    print "$_ = %{$_}\n"; 

                } else { # It's just a normal scalar.
                    eval("\$$_=\'$val\'");
                    print "$_ = ${$_}\n";   
                    if ($_ eq 'rigid_atlas_name') {
                        $tmp_rigid_atlas_name=${$_};
                    }
                }
            }
        }
    }
    }
    my @ps_array;

    if (! defined $project_name) {
        my $project_string;
        if ($is_headfile) {
            $project_string = $tempHf->get_value('project_id');
         } else {
            $project_string = %{ $tempHf }->{"project_id"};
         }

        @ps_array = split('_',$project_string);
        shift(@ps_array);
        my $ps2 = shift(@ps_array);
        if ($ps2  =~ /^([0-9]+)([a-zA-Z]+)([0-9]+)$/) {
            $project_name = "$1.$2.$3";
        }

        if (! defined $optional_suffix) {
            $optional_suffix = join('_',@ps_array);
            if ($tmp_rigid_atlas_name ne ''){
                if ($optional_suffix =~ s/^(${tmp_rigid_atlas_name}[_]?)//) {}
            }
        }

    }

    if ((! defined ($pre_masked)) && (defined ($do_mask))) {
	if ($do_mask) {
	    $pre_masked = 0;
	} else {
	    $pre_masked=1;
	}
    }

    if ((defined ($pre_masked)) && (! defined ($do_mask))) {
	if ($pre_masked) {
	    $do_mask = 0;
	} else {
	    $do_mask=1;
	}
    }

    if (! defined $port_atlas_mask) { $port_atlas_mask = 0;}

    if (($test_mode) && ($test_mode eq 'off')) { $test_mode = 0;}

    if (defined $channel_comma_list) {
	my @CCL = split(',',$channel_comma_list);
	foreach (@CCL) {
	    if ($_ !~ /(jac|ajax|nii4D)/) {
		push (@channel_array,$_);
	    }
	}

	@channel_array = uniq(@channel_array);
	$channel_comma_list = join(',',@channel_array);
    }

    if (! defined  $atlas_name){
        my ($r_atlas_name,$l_atlas_name);
        if ($is_headfile) {
            $r_atlas_name = $tempHf->get_value('rigid_atlas_name');
            $l_atlas_name = $tempHf->get_value('label_atlas_name');
            if ($r_atlas_name ne 'NO_KEY') {
                $atlas_name = $r_atlas_name;
            } elsif ($l_atlas_name ne 'NO_KEY') {
                $atlas_name = $l_atlas_name;
            } else {
                $atlas_name = 'chass_symmetric2'; # Will soon point this to the default dir, or let init module handle this.
            }
        } else {
            $r_atlas_name = %{ $tempHf }->{'rigid_atlas_name'};
            $l_atlas_name = %{ $tempHf }->{'label_atlas_name'};
            if ($r_atlas_name ne '') {
                $atlas_name = $r_atlas_name;
            } elsif ($l_atlas_name ne '') {
                $atlas_name = $l_atlas_name;
            } else {
                $atlas_name = 'chass_symmetric2'; # Will soon point this to the default dir, or let init module handle this.
            }
        }
    }

	if (! defined $optional_suffix) {
	    $optional_suffix = join('_',@ps_array);
        if ($optional_suffix =~ s/^(${atlas_name}[_]?)//) {}
	}

}

