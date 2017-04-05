#!/usr/local/pipeline-link/perl
# apply_warps_to_bvecs.pm 
# Originally written by BJ Anderson, CIVM




my $PM = "apply_warps_to_bvecs.pm";
my $VERSION = "2017/04/03";
my $NAME = "Application of affine transforms to bvecs.";
my $DESC = "ants";

use strict;
use warnings;
no warnings qw(uninitialized bareword);

use vars qw($Hf $BADEXIT $GOODEXIT  $test_mode $combined_rigid_and_affine $permissions $ants_verbosity $reservation $intermediate_affine $dims);
require Headfile;
require pipeline_utilities;

use List::Util qw(max);


my $do_inverse_bool = 0;
my ($runlist,$rigid_path,$current_path,$write_path_for_Hf);
my ($inputs_dir,$mdt_creation_strategy);
my ($interp,$template_path, $template_name, $diffeo_path,$work_done,$vbm_reference_path,$label_reference_path,$label_refname,$label_results_path,$label_path);
my (@array_of_runnos,@jobs,@files_to_create,@files_needed);
my (%go_hash);
my $go = 1;
my $job;
my ($orientation,$ALS_to_RAS,$native_to_ALS,$ecc_string,$ecc_affine_xform,$nifti_flip,$scanner_flip);
my ($results_dir,$final_MDT_results_dir,$almost_results_dir,$almost_MDT_results_dir,$median_images_path, $final_results_dir);

my $matlab_path = "/cm/shared/apps/MATLAB/R2015b/";
my $bvec_transform_executable_path = "/nas4/rja20/bvec_transform_executable/AE/run_transform_bvecs.sh";


my ($current_contrast,$group,$gid,$affine_target);
if (! defined $dims) {$dims = 3;}
if (! defined $ants_verbosity) {$ants_verbosity = 1;}

# ------------------
sub apply_warps_to_bvecs {  # Main code
# ------------------
    my $direction='f';
    $group = 'all';
    #($direction,$group) = @_;
    my $start_time = time;

    my $PM_code;

    if ($group =~ /(control|mdt|template)/i) {
	$gid = 1;
	$PM_code = 43;
    } elsif ($group eq "compare") {
	$gid = 0;
	$PM_code = 52;
    } elsif ($group eq "all"){
	$gid = 2;
	$PM_code = 64;
    }else {
	error_out("$PM: invalid group of runnos specified.  Please consult your local coder and have them fix their problem.");
    }

    apply_warps_to_bvecs_Runtime_check($direction);

    foreach my $runno (@array_of_runnos) {
	$go = $go_hash{$runno};
	if ($go) {
	    ($job) = apply_affine_rotation($runno,$direction);

	    if ($job > 1) {
		push(@jobs,$job);
	    }
	} 
    }
     

    if (cluster_check() && ($jobs[0] ne '')) {
	my $interval = 2;
	my $verbose = 1;
	my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs);
	
	if ($done_waiting) {
	    print STDOUT  "  affine rotations have been applied to the b-vectors for all ${group} runnos; moving on to next step.\n";
	}
    }
    my $case = 2;
    my ($dummy,$error_message)=apply_warps_to_bvecs_Output_check($case,$direction);

    my $real_time = write_stats_for_pm($PM_code,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    @jobs=(); # Clear out the job list, since it will remember everything if this module is used iteratively.

    if ($error_message ne '') {
	error_out("${error_message}",0);
    } else {
	$Hf->write_headfile($write_path_for_Hf);
    }
}



# ------------------
sub apply_warps_to_bvecs_Output_check {
# ------------------
     my ($case, $direction) = @_;
     my $message_prefix ='';
     my ($out_file,$dir_string);
     if ($direction eq 'f' ) {
	 $dir_string = 'forward';
     } elsif ($direction eq 'i') {
	 $dir_string = 'inverse';
     } else {
	 error_out("$PM: direction of warp \"$direction \"not recognized. Use \"f\" for forward and \"i\" for inverse.\n");
     }
     my @file_array=();
     if ($case == 1) {
  	$message_prefix = "  ${dir_string} affine rotations have already been applied to the bvecs for the following runno(s) and will not be recalculated:\n";
     } elsif ($case == 2) {
 	$message_prefix = "  Unable to apply ${dir_string} affine rotations to the bvecs for the following runno(s):\n";
     }   # For Init_check, we could just add the appropriate cases.

     
     my $existing_files_message = '';
     my $missing_files_message = '';
     
     foreach my $runno (@array_of_runnos) {
	 if ($direction eq 'f' ) {
	     $out_file = "${current_path}/${runno}_${orientation}${ecc_string}_bvecs.txt";
	 } #elsif ($direction eq 'i') {
	   #  $out_file =  "${current_path}/MDT_to_${runno}_${current_contrast}.nii.gz";  #Added '.gz', 2 September 2015
	 #}

	 if (data_double_check($out_file)) {
	     if (data_double_check($out_file)) {
		 $go_hash{$runno}=1;
		 push(@file_array,$out_file);
		 #push(@files_to_create,$full_file); # This code may be activated for use with Init_check and generating lists of work to be done.
		 $missing_files_message = $missing_files_message."\t$runno\n";
	     } else {
		 $go_hash{$runno}=0;
		 $existing_files_message = $existing_files_message."\t$runno\n";
	     }
	     
	 } else {
	     $go_hash{$runno}=0;
	     $existing_files_message = $existing_files_message."\t$runno\n";
	 }
     }
     if (($existing_files_message ne '') && ($case == 1)) {
	 $existing_files_message = $existing_files_message."\n";
     } elsif (($missing_files_message ne '') && ($case == 2)) {
	 $missing_files_message = $missing_files_message."\n";
     }
     
     my $error_msg='';

     if (($existing_files_message ne '') && ($case == 1)) {
	 $error_msg =  "$PM:\n${message_prefix}${existing_files_message}";
     } elsif (($missing_files_message ne '') && ($case == 2)) {
	 $error_msg =  "$PM:\n${message_prefix}${missing_files_message}";
     }

     my $file_array_ref = \@file_array;
     return($file_array_ref,$error_msg);
 }

# ------------------
sub apply_warps_to_bvecs_Input_check {
# ------------------

}


# ------------------
sub apply_affine_rotation {
# ------------------
    my ($runno,$direction) = @_;
    my ($cmd);
    my $out_file = '';
    my $direction_string = '';
    my ($start,$stop);
    my $reference_image;
    my $option_letter = "t";

    $out_file = "${current_path}/${runno}_${orientation}${ecc_string}_bvecs.txt";
    
    if ($direction eq 'f') {
	$direction_string = 'forward';
	if ($label_space eq 'pre_rigid') {
	    $start=0;
	    $stop=0;
	    $option_letter = '';
	} elsif (($label_space eq 'pre_affine') ||($label_space eq 'post_rigid')) {
	    $start=3;
	    $stop=3;
	} elsif ($label_space eq 'post_affine') {
	    $start=2;
	    $stop=3;
	}
    }
  

    # my $image_to_warp = get_nii_from_inputs($inputs_dir,$runno,$current_contrast); 
    my $original_bvecs = $Hf->get_value("${runno}_original_bvecs");
	my $exes_from_zeros;
    if ($eddy_current_correction) {
	my $zero_tester = '1';
	my $test_ecc_affine_xform = "${inputs_dir}/xform_${runno}_m${zero_tester}.nii0GenericAffine.mat"; # This is assuming that we are dealing with the outputs of tensor_create, as of April 2017
	if (data_double_check($test_ecc_affine_xform)) {
	    $zero_tester = '01';
	    $test_ecc_affine_xform = "${inputs_dir}/xform_${runno}_m${zero_tester}.nii0GenericAffine.mat";
	    if (data_double_check($test_ecc_affine_xform)) {
		$zero_tester = '001';
		$test_ecc_affine_xform = "${inputs_dir}/xform_${runno}_m${zero_tester}.nii0GenericAffine.mat";
		if (data_double_check($test_ecc_affine_xform)) {
		    $eddy_current_correction=0; 
		} else {
		    $exes_from_zeros = 'XXX'
		}
		
	    } else {
		$exes_from_zeros = 'XX'
	    }
	} else {
	    $exes_from_zeros = 'X';
	}
    }

    if ($eddy_current_correction) {
	$ecc_affine_xform = "${inputs_dir}/xform_${runno}_m${exes_from_zeros}.nii0GenericAffine.mat"; # This is assuming that we are dealing with the outputs of tensor_create, as of April 2017
	$ecc_string = '_ecc';
    } else {
	$ecc_affine_xform = '';
	$ecc_string = '';
	my $message_prefix="$PM:\n";
	my $log_msg = "No eddy current correction has been applied to bvecs for runno ${runno}.";
	    log_info("${message_prefix}${log_msg}");
    }
    
    $out_file = "${current_path}/${runno}_${orientation}${ecc_string}_bvecs.txt";
    my $out_file_prefix =  "${current_path}/${runno}_${orientation}${ecc_string}";
    my $warp_string = $Hf->get_value("${direction_string}_xforms_${runno}");
    if ($warp_string eq 'NO_KEY') {
	$warp_string=$Hf->get_value("mdt_${direction_string}_xforms_${runno}")
    }

    my $warp_train = format_transforms_for_command_line($warp_string,$option_letter,$start,$stop);

    $cmd = "${bvec_transform_executable_path} ${matlab_path} ${original_bvecs} -o ${out_file_prefix} ${ALS_to_RAS} ${warp_train} ${native_to_ALS} ${ecc_affine_xform} ${nifti_flip} ${scanner_flip}";  
 

    my $go_message =  "$PM: apply ${direction_string} affine rotations to bvecs for ${runno}";
    my $stop_message = "$PM: could not apply ${direction_string} affine rotations to bvecs  for  ${runno}:\n${cmd}\n";

    my @test=(0);
    if (defined $reservation) {
	@test =(0,$reservation);
    }

    my $mem_request = 3000;  # Added 23 November 2016,  Will need to make this smarter later.

    my $jid = 0;
    if (cluster_check) {
	my $home_path = $current_path;
	my $Id= "${runno}_apply_${direction_string}_affine_rotations_to_bvecs";
	my $verbose = 2; # Will print log only for work done.
	$jid = cluster_exec($go, $go_message, $cmd ,$home_path,$Id,$verbose,$mem_request,@test);     
	if (! $jid) {
	    error_out($stop_message);
	}
    } else {
	my @cmds = ($cmd);
	if (! execute($go, $go_message, @cmds) ) {
	    error_out($stop_message);
	}
    }

    if ((!-e $out_file) && ($jid == 0)) {
	error_out("$PM: missing bvecs with ${direction_string} affine rotations  applied for ${runno}: ${out_file}");
    }
    print "** $PM created ${out_file}\n";
  
    return($jid,$out_file);
}


# ------------------
sub apply_warps_to_bvecs_Init_check {
# ------------------
# It does not make sense to have the images for label overlay in post-rigid space if 
# the rigid and affine transforms are combined. While it is easy to get the images into
# post-rigid space, it is not straightfoward to get the labels into said space. It could
# in theory by lastly applying an forward rigid transform, but we will leave such tomfoolery for another day.

    my $init_error_msg='';
    my $message_prefix="$PM:\n";

    my $do_connectivity = $Hf->get_value('do_connectivity');

    if (($do_connectivity ne 'NO_KEY') && ($do_connectivity == 1)) {
    # my $rigid_plus_affine = $Hf->get_value('combined_rigid_and_affine');
    # my $do_labels = $Hf->get_value('create_labels');
    # $label_space = $Hf->get_value('label_space');
    # if ($label_space eq ('post_rigid' || 'pre_affine' || 'postrigid' || 'preaffine')) {
    # 	if (($do_labels == 1) && ($rigid_plus_affine) && ($old_ants)) {
    # 	    $init_error_msg = $init_error_msg."Label space of ${label_space} is not compatible with combined rigid and affine transforms using old ants.\n".
    # 		"Please consider setting label space to either \"pre_rigid\" or \"post_affine\".\n";
    # 	}
    # } 

	$eddy_current_correction = $Hf->get_value('eddy_current_correction');
	$Hf->get_value("${runno}_original_bvecs");


	if ($init_error_msg ne '') {
	$init_error_msg = $message_prefix.$init_error_msg;
	}
    }
    return($init_error_msg);
}


# ------------------
sub apply_warps_to_bvecs_Runtime_check {
# ------------------
    my ($direction)=@_;
 
# # Set up work

    $inputs_dir = $Hf->get_value('inputs_dir');
    $rigid_path = $Hf->get_value('rigid_work_dir');

    $template_path = $Hf->get_value('template_work_dir');
    $template_name = $Hf->get_value('template_name');

    $affine_target = $Hf->get_value('affine_target_image');
    $vbm_reference_path = $Hf->get_value('vbm_reference_path');

    if ($gid == 1) {
	$diffeo_path = $Hf->get_value('mdt_diffeo_path');   
	#$current_path = $Hf->get_value('mdt_images_path');
	#if ($current_path eq 'NO_KEY') {
	   # $current_path = "${predictor_path}/MDT_images";
	    $current_path = "${template_path}/MDT_images";
	    $Hf->set_value('mdt_images_path',$current_path);
	#}
#	$runlist = $Hf->get_value('control_comma_list');
	$runlist = $Hf->get_value('template_comma_list');

	if ($runlist eq 'NO_KEY') {
	    $runlist = $Hf->get_value('control_comma_list');
	    $Hf->set_value('template_comma_list',$runlist); # 1 Feb 2016, just added these. If bug, then check here.
	}
	
    } elsif ($gid == 0) {
	$diffeo_path = $Hf->get_value('reg_diffeo_path');   
	#$current_path = $Hf->get_value('reg_images_path');
	#if ($current_path eq 'NO_KEY') {
	 #  $current_path = "${predictor_path}/reg_images";
	    $current_path = "${template_path}/reg_images";
	    $Hf->set_value('reg_images_path',$current_path);
	#}
	# $runlist = $Hf->get_value('compare_comma_list');
	$runlist = $Hf->get_value('nontemplate_comma_list');

	if ($runlist eq 'NO_KEY') {
	    $runlist = $Hf->get_value('compare_comma_list');
	    $Hf->set_value('nontemplate_comma_list',$runlist);  # 1 Feb 2016, just added these. If bug, then check here.
	}


    } elsif ($gid == 2) {
	$inputs_dir = $Hf->get_value('label_refspace_folder');
	$label_reference = $Hf->get_value('label_reference');
	$label_reference_path = $Hf->get_value('label_reference_path');
	$label_refname = $Hf->get_value('label_refname');

	$label_space = $Hf->get_value('label_space');
	$label_path=$Hf->get_value('labels_dir');
	$label_results_path=$Hf->get_value('label_results_path');
   

	$current_path=$Hf->get_value('label_images_dir');



	my $intermediary_path = "${label_path}/${label_space}_${label_refname}_space";

	if (! -e  $intermediary_path) {
	    mkdir ( $intermediary_path,$permissions);
	}

	#if ($current_path eq 'NO_KEY') {
	    $current_path = "${intermediary_path}/images";
	    $Hf->set_value('label_images_dir',$current_path);
	#}
	if (! -e $current_path) {
	    mkdir ($current_path,$permissions);
	}

	$runlist = $Hf->get_value('complete_comma_list');
    } else {
	print " ERROR: Invalid group ID in $PM.  Dying now...\n";
	die;
    }
    
    $results_dir = $Hf->get_value('results_dir');

    $ecc_string = '';
    my $eddy_current_correction = $Hf->get_value('eddy_current_correction');
    if (($eddy_current_correction ne 'NO_KEY') && ($eddy_current_correction == 1)) {
	$ecc_string = '_ecc';
    }  

    $native_to_ALS = '';
    my $flip_x = $Hf->get_value('flip_x');
    my $flip_z = $Hf->get_value('flip_z');

    if ($flip_x) {
	$native_to_ALS = $native_to_ALS." -z ";
    }
    
    if ($flip_z) {
	$native_to_ALS = $native_to_ALS." -x ";
    }

    my $convert_images_to_RAS=$Hf->get_value('convert_labels_to_RAS');
    $ALS_to_RAS = '';
    $orientation = 'ALS';
    if (($convert_images_to_RAS ne 'NO_KEY') && ($convert_images_to_RAS == 1)) {
	$ALS_to_RAS = " ALS_to_RAS ";
	$orientation = 'RAS';
    }	    

    $almost_results_dir = "${results_dir}/connectomics/";
    if (! -e $almost_results_dir) {
	mkdir ($almost_results_dir,$permissions);
    }

    $final_results_dir = "${almost_results_dir}/${label_space}_${label_refname}_space/";
    if (! -e $final_results_dir) {
	mkdir ($final_results_dir,$permissions);
    }

    if (! -e $current_path) {
	mkdir ($current_path,$permissions);
    }
    
    $write_path_for_Hf = "${current_path}/${template_name}_temp.headfile";
    
    $scanner_flip='';
    my $scanner = $Hf->get_value('scanner');
    if ($scanner eq 'Agilent_9T') {
	$scanner_flip=' -x  '; # This has been tested...may need a better methods for figuring this shit out.
    } elsif ($scanner eq 'Agilent_7T') {
	$scanner_flip=' -y  '; # This has NOT been tested and should be WRONG...may need a better methods for figuring this shit out.
    } elsif ($scanner eq 'Bruker_7T') {
	$scanner_flip=' -z  '; # This has NOT  been tested and should be WRONG...may need a better methods for figuring this shit out.
    } else {
	$scanner_flip = ' -x '; # Let's assume it's 9T data for now.
    }

    $nifti_flip = ' -z '; # For now we will assume that we are using default niis.  Can get the proper info from PrintHeader if we want to get fancy.

#   Functionize?
    if ($runlist eq 'EMPTY_VALUE') {
	@array_of_runnos = ();
    } else {
	@array_of_runnos = split(',',$runlist);
    }    

#

    $mdt_creation_strategy = $Hf->get_value('mdt_creation_strategy');

    my $case = 1;
    my ($dummy,$skip_message)=apply_warps_to_bvecs_Output_check($case,$direction);

    if ($skip_message ne '') {
	print "${skip_message}";
    }

# check for needed input files to produce output files which need to be produced in this step?

}

1;