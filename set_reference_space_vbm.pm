#!/usr/bin/false
# set_reference_space_vbm.pm 

#  2015/07/23  BJ Anderson, CIVM -- switched from PrintHeader to fslhd for getting header info, though most of this switch happened in pipeline utilites.
#  2015/03/04  BJ Anderson, CIVM

my $PM = "set_reference_space_vbm.pm";
my $VERSION = "2020/08/12";
my $NAME = "Set the reference spaces to be used for VBM and label analysis.";
my $DESC = "ants";

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

use civm_simple_util;
use convert_all_to_nifti_vbm;


my ($inputs_dir,$pristine_in_folder,$preprocess_dir,$rigid_atlas_name,$rigid_target,$rigid_contrast,$runno_list,$rigid_atlas_path,$original_rigid_atlas_path,$port_atlas_mask);#$current_path,$affine_iter);
my (%reference_space_hash,%reference_path_hash,%input_reference_path_hash,%refspace_hash,%refspace_folder_hash,%refname_hash,%refspace_file_hash);
my ($rigid_name,$rigid_dir,$rigid_ext,$new_rigid_path,$future_rigid_path,$native_ref_name,$translation_dir);
my ($base_images_for_labels);# synonymous with create_labels
my ($log_msg);
my $split_string = ",,,";
my (%file_array_ref,@ref_spaces);
my ($work_to_do_HoA);
my @jobs_1=();
my @jobs_2=();
my $go = 1;
# ref_runno is a multi-level hash, the keys are spaces, the values are runno_hashes.
# runno_hashs are runnos with work to do, and 1 of their image paths which is used 
# to get check if we need a reference space transform, and calculate it.
my %ref_runno_hash;
#my %runno_hash_vba;
#my %runno_hash_label;
my %preferred_contrast_hash;
my $rerun_init_flag;


if (! defined $dims) {$dims = 3;}
if (! defined $ants_verbosity) {$ants_verbosity = 1;}

# ------------------
sub set_reference_space_vbm {  # Main code
# ------------------
    my $start_time = time;
    set_reference_space_vbm_Runtime_check();

    my $ref_file;
    my $job;
    my @jobs;
    # lock_step, do all reference creation first, then do all apply, (the old way)
    #    off, set apply dependent on creation, (the new way)
    my $lock_step=0;
    foreach my $space (@ref_spaces) {
        my $work_folder = $refspace_folder_hash{$space};
        my $translation_dir = "${work_folder}/translation_xforms/";
	mkdir ($translation_dir,$permissions) if ! -e $translation_dir;
        $ref_file = $reference_path_hash{$space};
        
        # Hmm, turns out refspace implies this.... 
        my ($v_ok,$data_size)=$Hf->get_value_check("${space}_refsize");
        if(! $v_ok && -e $ref_file ) { 
	    confess "Missing important variable ${space}_refsize";
        }
        my %runno_hash;
        %runno_hash=%{$ref_runno_hash{$space}};
        if ( ! $lock_step ) {
            my $array_ref = $work_to_do_HoA->{$space};
            # for all runnos
            for my $runno (keys %runno_hash) {
                # First, create the refspacy transform
                my $in_file = $runno_hash{$runno};
                my $out_file = "${work_folder}/translation_xforms/${runno}_";#0DerivedInitialMovingTranslation.mat";
                ($job) = apply_new_reference_space_vbm($in_file,$ref_file,$out_file);
                my $ref_dep;
                if ($job) {
                    push(@jobs_1,$job);
                    push(@jobs,$job); 
                    $ref_dep='afterany:'.$job;
                }
                my ($dumdum,$in_name,$in_ext) = fileparts($in_file,2);
                # second, schedule the apply dependent on transformy being done.
                my @runno_files=grep /$runno/,@$array_ref;
                for my $out_file (@runno_files) {
                    my ($dumdum,$out_name,$out_ext) = fileparts($out_file,2);
                    my $ain_file = "${preprocess_dir}/${out_name}${out_ext}";
                    $ain_file = "${preprocess_dir}/${out_name}${in_ext}" if ! -e $ain_file;
                    confess "ERROR NO INPUT FILE $ain_file" if ! -e $ain_file;
                    ($job) = apply_new_reference_space_vbm($ain_file,$ref_file,$out_file,$ref_dep);
                    if ($job) {
                        push(@jobs_2,$job);
                        push(@jobs,$job);
                    }
                }

            }
        } else {
        # First for all runnos, create the refspacy transform
        foreach my $runno (keys %runno_hash) {
            my $in_file = $runno_hash{$runno};
            my $out_file = "${work_folder}/translation_xforms/${runno}_";#0DerivedInitialMovingTranslation.mat";
            ($job) = apply_new_reference_space_vbm($in_file,$ref_file,$out_file);
            if ($job) {
                push(@jobs_1,$job);
            }   
        }
        # wait for refspacy completion
        if (cluster_check() && (scalar @jobs_1)) {
            my $interval = 1;
            my $verbose = 1;
            my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs_1);
            if ($done_waiting) {
                print STDOUT  "  All translation alignment referencing jobs have completed; moving on to next step.\n";
            }
        }
        # Apply all refspaces
        my $array_ref = $work_to_do_HoA->{$space};
        foreach my $out_file (@$array_ref) {
            my ($dumdum,$in_name,$in_ext) = fileparts($out_file,2);
            my $in_file = "${preprocess_dir}/${in_name}${in_ext}";
            ($job) = apply_new_reference_space_vbm($in_file,$ref_file,$out_file);
            if ($job) {
                push(@jobs_2,$job);
            }
        }
        } # END lock_step conditional for the old way.
    }
    # All scheduling done.
    # these lock_step lines are to avoid changing code before it's tested. 
    # In the future, we'll wait on jobs here, instad of jobs_2.
    my @tmp_array;
    if (! $lock_step) {
        @tmp_array=@jobs_2;
        @jobs_2=@jobs;
    }
    if (cluster_check() && (scalar @jobs_2)) {
        my $interval = 2;
        my $verbose = 1;
        my $done_waiting = cluster_wait_for_jobs($interval,$verbose,@jobs_2);
        if ($done_waiting) {
            print STDOUT  "  All referencing jobs have completed; moving on to next step.\n";
        } else {
            printd(5,"ERROR on job wait!");
            sleep_with_countdown(3);
        }
    }
    
    foreach my $space (@ref_spaces) {
        # Why is this written to "tmp" first before being moved?
        run_and_watch("mv ${refspace_folder_hash{$space}}/refspace.txt.tmp ${refspace_folder_hash{$space}}/refspace.txt");
        # This was a clever Bash syntax chain using ls && gzip but that has proven ugly when debugging
        # Adjusted to be in perl with same idea. 
        # if "ls" command is successful (finds existing items), then executes "gzip" command.
        # "2>" will redirect STDERR to /dev/null (aka nowhere land) so it doesn't spam terminal.
        # While the first inclination is to use run_and_watch, we dont care at all if we succeed or fail here.
        # We only care if there is work found to do, so we'll simply capture output to let this fail quietly.
        #my @gzippable_file=run_and_watch("ls ${refspace_folder_hash{$space}}/*.nii  2> /dev/null","\t",0);
        my @gzippable_file=`ls ${refspace_folder_hash{$space}}/*.nii  2> /dev/null`;
        chomp(@gzippable_file);
        # tests each thing found in gzippable file, but we really only ever run one time
        foreach (@gzippable_file){ 
            if ( $_ ne '' ) {
		log_info("Inline compression of nii extension files in folder ${refspace_folder_hash{$space}}");
                run_and_watch("gzip -v ${refspace_folder_hash{$space}}/*.nii");
                last;
            }
        }
    }
    
    my $case = 2;
    my ($dummy,$error_message)=set_reference_space_Output_check($case);

    @jobs = (@jobs_1,@jobs_2);    
    my $real_time = vbm_write_stats_for_pm($PM,$Hf,$start_time,@jobs);
    print "$PM took ${real_time} seconds to complete.\n";

    if ($error_message ne '') {
        error_out("${error_message}",0);
    } 
}


# ------------------
sub set_reference_space_Output_check {
# ------------------
    my ($case) = @_;
    my $full_error_msg;
    
    foreach my $space (@ref_spaces) {
        my @file_array;
        my $message_prefix ='';  
        @file_array=();
        my $work_folder = $refspace_folder_hash{$space};
        my $ref_file = $reference_path_hash{$space};
        my $refspace = $refspace_hash{$space};
        print "refspace = $refspace\n";
        my $space_string = $space;
        if ((! $base_images_for_labels) && ($create_labels) && ($space eq 'vbm')) {
            $space_string = "vbm and label";
        }

        if ($case == 1) {
            $message_prefix = "  The following images for ${space_string} analysis in folder ${work_folder} have already been properly referenced\n".
                "and will not be reprocessed :\n";
        } elsif ($case == 2) {
            $message_prefix = "  Unable to properly set the ${space_string} reference \n".
                "\t($refspace)\n".
                "\tfor images in folder ${work_folder}:\n";
        }   # For Init_check, we could just add the appropriate cases.

        my $existing_files_message = '';
        my $missing_files_message = '';

        my @files_to_check;
        my %runno_hash;
        if ($case == 1) {
            print "$PM: Checking ${space} and preprocess folders...";
            opendir(DIR, $preprocess_dir);
            @files_to_check = grep(/(\.nii)+(\.gz)*$/ ,readdir(DIR));# @input_files;
            @files_to_check=sort(@files_to_check);
        } else {
            print "$PM: Checking ${space} folder...";
            my $array_ref = $work_to_do_HoA->{$space};
            @files_to_check = @$array_ref;
        }

        foreach my $file (@files_to_check) {
            # it appears like if we're in input mode $file doesnt have a path, 
            # but if we're in output mode it does.
            # That is a special level of unnecessary confusion
            # out_file always has a path to compensate.
            my $out_file;
            if ($case == 1) {
                # $in_file = $preprocess_dir.'/'.$file;
                $out_file = $work_folder.'/'.$file;
                # The snippet of regex below will find 0 or 1 instances of '.gz' 
                # at the end of the filename, and 'replace' it with '.gz.
                # Functionally, this will just add '.gz.' to any un-gzipped files
                # In this case, the we are looking for an output file (which will ALWAYS be gzipped)
                # that corresponds to an input file that may or may not be gzipped.
                $out_file =~ s/(\.gz)?$/\.gz/;
            } else {
                $out_file = $file;
            }
            printd(1,".");
            
            if (data_double_check($out_file,$case-1)) { 
                # Outfile not found.
                if ($case == 1) {
                    # Input mode because we didnt try to do this yet.
                    # Add first file found to runno_hash.
                    # print "\n${out_file} added to list of files to be re-referenced.\n";
                    my $temp_var = $file;
                    if ($temp_var =~ s/(_masked)//i){}
                    if ($temp_var =~ /^([^\.]+)_([^_\.])+\..+/) { 
                        # Split file into RUNNO_contrast, 
                        # (Only takes last _ -> end for contrast. 
                        # We could improve that by forcing runnos to not have underscores in them.
                        # This is made harder by virtue of tacking a gz on everything
                        # We dont use contrast so commenting that out.
                        # This is part of the general trouble of runno as specid this pipeline has.
                        my $runno = $1;
                        #my $contrast = $2;
                        if (! defined $runno_hash{$runno}) {
                            $runno_hash{$runno}= $preprocess_dir.'/'.$file;
                        }
                    }
                }
                push(@file_array,$out_file);
                my ($tp,$tn,$te)=fileparts($file,2);
                $missing_files_message = $missing_files_message."   Missing: $tn$te\n";
            } elsif (! compare_two_reference_spaces($out_file,$refspace)) {
                print "\n${out_file} added to list of files to be re-referenced.\n";
                push(@file_array,$out_file);
                my ($tp,$tn,$te)=fileparts($file,2);
                $missing_files_message = $missing_files_message."   Inconsistent ref: $tn$te\n";
            } else {
                $existing_files_message = $existing_files_message."   $file\n";
            }
        }
        print("\n");
        if (($existing_files_message ne '') && ($case == 1)) {
            $existing_files_message = $existing_files_message."\n";
        } elsif (($missing_files_message ne '') && ($case == 2)) {
            $missing_files_message = $missing_files_message."\n";
        }
        
        my $error_msg='';
        if (($existing_files_message ne '') && ($case == 1)) {
            $error_msg =  $error_msg."$PM:\n${message_prefix}${existing_files_message}";
        } elsif (($missing_files_message ne '') && ($case == 2)) {
            $error_msg =  $error_msg."$PM:\n${message_prefix}${missing_files_message}";
        }
        $full_error_msg = $full_error_msg.$error_msg;    
        $file_array_ref{$space} = \@file_array;
        
        if ($case == 1) {
            #if ($space eq 'vbm') {
            #    %runno_hash_vba = %runno_hash;
            #} else {
            #    %runno_hash_label = %runno_hash;
            #}
            $ref_runno_hash{$space}=\%runno_hash;
        }

        # THIS IS DOING WORK IN A CHECK FUNCTION THAT IS VERY NAUGHTY.
        if ($case == 2) {
            # James's highly suspecs that we didnt do slow disk checking for the results 
            # of this we were at the mercy of slow disk problems due to this cleanup.
            # So, all the better to throw this out, many parts have been made more
            # symbolic link friendly, and as such this is less and less useful. 
            # (not that he'll ever admit it was useful :p ) 
            carp("Symbolic link cleanup skipped on $refspace_folder_hash{$space}");
            #symbolic_link_cleanup($refspace_folder_hash{$space},$PM);
        }
    }
    return(\%file_array_ref,$full_error_msg);
}

# ------------------
sub get_translation_xform_to_ref_space_vbm {
# ------------------

    my ($in_file,$ref_file,$out_file)=@_;

}

# ------------------
sub apply_new_reference_space_vbm {
# ------------------
    my ($in_file,$ref_file,$out_file,$dependency)=@_;

    # Do reg is off for any output nifti's (including gzipped ones)...
    my $do_registration = 1; 
    
    
    my $test_dim = 3;
    my $opt_e_string='';
    if ($out_file =~ /\.nii(\.gz)?/) {
        $test_dim =  `fslhd ${in_file} | grep dim4 | grep -v pix | xargs | cut -d ' ' -f2` 
            || croak("ERROR Reading $in_file for header bits");
        if (! looks_like_number($test_dim) ) {
            error_out("Problem gathering dim infro from $in_file"); 
        }
        if ($in_file =~ /tensor/) {
            # Testing value for -f option, as per https://github.com/ANTsX/ANTs/wiki/Warp-and-reorient-a-diffusion-tensor-image
            $opt_e_string = ' -e 2 -f 0.00007'; 
        } elsif ($test_dim > 1) {
            $opt_e_string = ' -e 3 ';
        }
        $do_registration = 0;
    }
    my $interp = "Linear"; # Default    
    my $in_spacing = get_spacing_from_header($in_file);
    my $ref_spacing = get_spacing_from_header($ref_file);
    if ($in_spacing eq $ref_spacing) {
        $interp = "NearestNeighbor";
    }
    if ($in_file =~ /(mask|Mask|MASK)\./) {
        $interp="NearestNeighbor";
    }

    # CMD appears to be run when cluster
    # @cmds appears to be run when not cluster.
    my $cmd='';
    # CMD_SEP is a temp measure for conjoining multiple commands in a one liner
    my $CMD_SEP=";\n";
    $CMD_SEP=" && ";
    my @cmds;
    my $translation_transform;
    my $mem_request = '0'; # set to magic value 0 to request whole node.
    #print "Test output = ".compare_two_reference_spaces($in_file,$ref_file)."\n\n\n";
    #print "Do registration? ${do_registration}\n\n\n";
    if ($do_registration) {
        # in, ref, check out. out_file is a ants prefix
        $translation_transform = "${out_file}0DerivedInitialMovingTranslation.mat" ;
        if ( ! compare_two_reference_spaces($in_file,$ref_file)) {         
            # FORMERLY HAD mkdir for path dir of out_file
	    # Also had oe option resolution into opt_e_string. 
	    # but antreg doesnt take opt_e_string!
	    my $excess_transform =  "${out_file}1Translation.mat" ;
            my $translation_cmd = "antsRegistration -v ${ants_verbosity} -d ${dims} -t Translation[1] -r [${ref_file},${in_file},1] -m Mattes[${ref_file},${in_file},1,32,None] -c [0,1e-8,20] -f 8 -s 4 -z 0 -o ${out_file}";
            my $remove_cmd = "rm ${excess_transform}";
            if (data_double_check($translation_transform)) {
                push(@cmds,$translation_cmd);
                push(@cmds,$remove_cmd);
            } else {
                printd(45,"$translation_transform ready, not regnerating\n");
                $log_msg="Skipped $translation_cmd && $remove_cmd";
            }
        } else {
            my $affine_identity = $Hf->get_value('affine_identity_matrix');
            $cmd = "ln -s ${affine_identity} ${translation_transform}";
	    if( ! -e ${translation_transform}){
            push(@cmds,$cmd);
	    } else {
		$log_msg="Skipped affine_identity replication $cmd";
	    }
        }
    } else {
        if (compare_two_reference_spaces($in_file,$ref_file)) {
            # same_refspace
            $cmd = "ln -s ${in_file} ${out_file}";
            print "Linking $in_file to $out_file\n\n";
            push(@cmds,$cmd);
        } else {
            # this code runs when we've already aligned one contrast of a set. 
	    # it should apply that alignment to the next.
	    
            my $runno;
            my $gz = '';
            if ($out_file =~ s/(\.gz)$//) {$gz = '.gz';}
            my ($out_path,$out_name,$dummy_2) = fileparts($out_file,2);
            $out_file = $out_file.'.gz';
            $out_name =~ s/(_masked)//i;
	    # We are assuming that underscores are not allowed in contrast names! 14 June 2016
            if ($out_name =~ /([^\.]+)_[^_\.]+/) {
                $runno = $1;
            }
            
            # Copied from earlier location, may enable in the future when its found this is actually in use.
            #$test_dim =  `fslhd ${in_file} | grep dim4 | grep -v pix | xargs | cut -d ' ' -f2` 
            #    || croak("ERROR Reading $in_file for header bits");
            #if (! looks_like_number($test_dim) ) {
            #    error_out("Problem gathering dim infro from $in_file"); 
            #}
            #if ($in_file =~ /tensor/) {
            #    # Testing value for -f option, as per https://github.com/ANTsX/ANTs/wiki/Warp-and-reorient-a-diffusion-tensor-image
            #    $opt_e_string = ' -e 2 -f 0.00007'; 
            #} elsif ($test_dim > 1) {
            #    $opt_e_string = ' -e 3 ';
            #}
            

            $translation_transform = "${out_path}/translation_xforms/${runno}_0DerivedInitialMovingTranslation.mat";
            $cmd = "antsApplyTransforms -v ${ants_verbosity} -d ${dims} ${opt_e_string} -i ${in_file} -r ${ref_file}  -n $interp  -o ${out_file} -t ${translation_transform}";
	    
	    my $space='vbm';# or label... could use get_value_like_check... to get both refsizes
	    my ($v_ok,$refsize)=$Hf->get_value_check("${space}_refsize");
	    # a defacto okay enough guess at vox count... when this was first created. 
	    my $vx_count = 512 * 256 * 256;
	    if( $v_ok) { 
		my @d=split(" ",$refsize);
		$vx_count=1;
		foreach(@d){
		    $vx_count*=$_; }
	    } else {
		carp("Cannot set appropriate memory size, using defacto ${mem_request}M");
		sleep_with_countdown(3);
	    }
	    my ($vx_sc,$est_bytes)=ants::estimate_memory($cmd,$vx_count);
	    # convert bytes to MB(not MiB).
	    my $expected_max_mem=ceil($est_bytes/1000/1000);
	    printd(45,"Expected amount of memory required to apply warps: ${expected_max_mem} MB.\n");
	    if ($expected_max_mem > $mem_request) {
		$mem_request = $expected_max_mem;
	    }

            push(@cmds,$cmd);
        }  
    }
    
    my @list = split('/',$in_file);
    my $short_filename = pop(@list);

    my @test = (0);

    #if (defined $reservation) { 
    # Undefs are fun, just pass it :)
    # Added dependency to let this properly chain off our other work.
    #@test =(0,$reservation);
    #}
    @test=(0,$reservation,$dependency);
    $cmd=join($CMD_SEP,@cmds);
    my $go_message =  "$PM: Apply reference space of ${ref_file} to ${short_filename}";
    my $stop_message = "$PM: Unable to apply reference space of ${ref_file} to ${short_filename}:  $cmd\n";
    my $jid = 0;
    if ($cmd){
        if (cluster_check) {
            my ($home_path,$dummy1,$dummy2) = fileparts($out_file,2);
            my $Id= "${short_filename}_reference_to_proper_space";
            my $verbose = 1; # Will print log only for work done.
            $jid = cluster_exec($go, $go_message, $cmd,$home_path,$Id,$verbose,$mem_request,@test);     
            if (not $jid) {
                error_out($stop_message);
            }
        } else {
            if (! execute($go, $go_message, @cmds) ) {
                error_out($stop_message);
            }
        }

    }
    
    return($jid);
}


# ------------------
sub set_reference_space_vbm_Init_check {
# ------------------
# WARNING NAUGHTY CHECK IS DOING WORK.
    # no inputs at current, sneaking everything though the headfile.
    #my @args=@_;
    my @init_jobs;
    my $vx_count=1;
    my $init_error_msg='';
    my $message_prefix="$PM initialization check:\n";

    $pristine_in_folder = $Hf->get_value('pristine_input_dir');    
    $inputs_dir = $Hf->get_value('inputs_dir');
    $preprocess_dir = $Hf->get_value('preprocess_dir');

    #mkdir ($preprocess_dir,$permissions) if ! -e $preprocess_dir;
    #mkdir ($inputs_dir,$permissions) if ! -e $inputs_dir;

    my ($v_ok,$v_ok2);
    ($v_ok, my $resample_images) = $Hf->get_value_check('resample_images');
    ($v_ok2, my $resample_factor) = $Hf->get_value_check('resample_factor');
    #if (($resample_factor ne 'NO_KEY') ||($resample_images ne 'NO_KEY') ) { ## Need to finish fleshing out this logic!
    if ($v_ok || $v_ok2) {
        carp("Resampling on");
        sleep_with_countdown(5);
        if (($resample_images == 0) || ($resample_images =~ /^(no|off)$/i) ) {
            $resample_images=0;
            $resample_factor=1;
        } else {    
            if (($resample_images == 1) || ($resample_images == 2) || ($resample_images =~ /^(yes|on)$/i) ) {
                # Default is downsample by a factor of 2x
                $resample_images=1;
                $resample_factor=2;
            } elsif ($resample_images !~ /[\-a-zA-Z]/) {
                # We're going to cross our fingers and hope that by excluding letters and negative signs
                # that we're left with valid positive numbers by which we can multiply the voxelsize
                # Also note that "resample factor" is more accurately "downsample factor"
            } else {
                # Throw dying error.
                my $resample_error="Bad resample_images field specified ${resample_images}. Only positive real numbers allowed.\n";
                $init_error_msg=$init_error_msg.$resample_error;
            }
        }
    } elsif (($resample_images eq 'NO_KEY' ) && ($resample_factor ne 'NO_KEY') ) {
        # We assume that the resample factor has already been checked & will automatically be passed on
        $resample_images=1;
    } else {
        $resample_images=0;
        $resample_factor=1;
    }

    my $create_labels= $Hf->get_value('create_labels');
    my $do_mask= $Hf->get_value('do_mask');
    my $rigid_work_dir = $Hf->get_value('rigid_work_dir');
    my $label_image_inputs_dir;
    $inputs_dir = $Hf->get_value('inputs_dir');
    $rigid_contrast = $Hf->get_value('rigid_contrast'); 
    $runno_list= $Hf->get_value('complete_comma_list');
    $refspace_folder_hash{'vbm'} = $inputs_dir;
    ($refspace_hash{'existing_vbm'},$refname_hash{'existing_vbm'})=read_refspace_txt($inputs_dir,$split_string);
    
    ($v_ok, $reference_space_hash{'vbm'})=$Hf->get_value_check('vbm_reference_space');
    #if ((! defined $reference_space_hash{'vbm'}) || ($reference_space_hash{'vbm'} eq ('NO_KEY' || '' || 'UNDEFINED_VALUE'))) {
    if(! $v_ok){
        $log_msg=$log_msg."\tNo VBM reference space specified.  Will use native image space.\n";
        $reference_space_hash{'vbm'} = 'native';
    }
    ($v_ok, $reference_space_hash{'label'})=$Hf->get_value_check('label_reference_space');         
    $base_images_for_labels = 0;
    if ($create_labels) {
        #if ((! defined $reference_space_hash{'label'}) || ($reference_space_hash{'label'} eq (('NO_KEY') || ('') || ($reference_space_hash{'vbm'})))) {
        if (! $v_ok) {
            $log_msg=$log_msg."\tNo label reference space specified.  Will inherit from VBM reference space.\n";
            $reference_space_hash{'label'}=$reference_space_hash{'vbm'};
            $Hf->set_value('label_reference_space',$reference_space_hash{'label'});
            $refspace_folder_hash{'label'} = $inputs_dir;          
        } else {
            $base_images_for_labels = 1; 
        }
    }
    
    $Hf->set_value('base_images_for_labels',$base_images_for_labels);    
    
    my @ref_spaces;
    @ref_spaces = ("vbm");
    if ($create_labels) {#($base_images_for_labels) {
        push(@ref_spaces,"label");
    }
    
    foreach my $space (@ref_spaces) {    
        my ($ref_error,$for_labels)=('',0);
        if ($space eq "label") {
            $for_labels = 1;
        }
        
        ($input_reference_path_hash{$space},$reference_path_hash{$space},$refname_hash{$space},$ref_error) = set_reference_path_vbm($reference_space_hash{$space},$for_labels);
        #Data::Dump::dump($input_reference_path_hash{$space},$reference_path_hash{$space},$refname_hash{$space},$ref_error);
        #print "REF TESTING "; exit 1; 

        if ($input_reference_path_hash{$space} eq 'rerun_init_check_later') {
            my $log_msg = "Reference spaces not set yet. Will rerun upon start of set_reference_space module.";
            log_info("${message_prefix}${log_msg}");
            $Hf->set_value('rerun_init_check',1);
            #if ($init_error_msg ne '') {
            #    $init_error_msg = $message_prefix.$init_error_msg;
            #}
            return($init_error_msg);
        } else {

            $Hf->set_value("${space}_reference_path",$reference_path_hash{$space});
            $Hf->set_value("${space}_input_reference_path",$input_reference_path_hash{$space});
            $Hf->set_value("${space}_reference_space",$reference_space_hash{$space});
            #my $bounding_box_and_spacing = get_bounding_box_and_spacing_from_header($reference_path_hash{$space});
            my $bounding_box_and_spacing = get_bounding_box_and_spacing_from_header($input_reference_path_hash{$space});

            $refspace_hash{$space} = $bounding_box_and_spacing;
            $Hf->set_value("${space}_refspace",$refspace_hash{$space});
	    #EX refspace, {[0.015 0.015 0.015], [12.21 19.77 9.21]} 0.015x0.015x0.015
	    # ... {[first vox], [last vox]}, spacing. 
	    # In theory directionality is also hiding in this.... but we probably don't maintain negative signs correctly.
	    # Thought I could be clever and use PrintHeader one time, but it turns out we dont save the hf in time.
	    # Switched to fslhd
	    #
	    # vox first, last, size
	    my ($vx_f,$vx_l,$vx_s) = $bounding_box_and_spacing =~ m/{([^,]+),[ ]([^}]+)}[ ](.+)/;
	    $vx_f=~s/[\[\]]//g; $vx_l=~s/[\[\]]//g;
	    my @vf=split(" ",$vx_f); my @vl=split(" ",$vx_l); my @vs=split("x",$vx_s);
	    my @fov;
	    my @dx;
	    for(my $vi=0;$vi<scalar(@vl);$vi++) {
		$fov[$vi]=$vl[$vi]-$vf[$vi] || die "fov calc err d $vi";
		$dx[$vi]=$fov[$vi]/$vs[$vi] || die "dim calc err d $vi";;
	    }
	    my ($v_ok,$refsize)=$Hf->get_value_check("${space}_refsize");
	    #if(! defined $refsize) {
	    #cluck "Hf Err fetching refsize"; $v_ok=0; }
	    if(! $v_ok && -e $input_reference_path_hash{$space} ) { 
		# Oh ants PrintHeader, why you always slow :( 
		#(my $refsize)=run_and_watch("PrintHeader $input_reference_path_hash{$space} 2"); chomp($refsize); $refsize=~s/x/ /g;
		(my $refsize)=run_and_watch("fslhd $input_reference_path_hash{$space}|grep '^dim[1-3]'|cut -d ' ' -f2-|xargs");
		chomp($refsize); $refsize=trim($refsize);
		if($refsize ne join(" ",@dx) ) {
		    confess "Error getting refsize from bounding box for space:$space";
		}
		$Hf->set_value("${space}_refsize",$refsize);
		my @d=split(" ",$refsize);
		foreach(@d){
		    $vx_count*=$_; }
	    }
	    if ((defined $ref_error) && ($ref_error ne '')) {
                $init_error_msg=$init_error_msg.$ref_error;
            }
            $log_msg=$log_msg."\tReference path for ${space} analysis is ${reference_path_hash{${space}}}\n";

        }
    }    

    my $dir_work = $Hf->get_value('dir_work');
    my $rigid_work_path = "${dir_work}/${rigid_contrast}";
    $Hf->set_value('rigid_work_dir',$rigid_work_path);
    
    if ($refspace_hash{'existing_vbm'}) {
        if ($refspace_hash{'vbm'} ne $refspace_hash{'existing_vbm'}) {
            $init_error_msg=$init_error_msg."WARNING\n\tWARNING\n\t\tWARNING\nThere is an existing vbm reference space which is not consistent with the one currently specified.".
                "\nExisting bounding box/spacing: ${refspace_hash{'existing_vbm'}}\nSpecified bounding box/spacing: ${refspace_hash{'vbm'}}\n\n".
                "If you really intend to change the vbm reference space, run the following commands and then try rerunning the pipeline:\n".
                "mv ${rigid_work_path} ${rigid_work_path}_${refname_hash{'existing_vbm'}}\n".
                "mv ${inputs_dir} ${inputs_dir}_${refname_hash{'existing_vbm'}}\n\n".
                "If ${rigid_work_path} does not exist, but another previous \'rigid_work_dir\' (as noted in headfiles) does exist, it is highly recommended to adjust the first command to properly back up the folder.\n";
        } else {
            if ($refname_hash{'vbm'} ne $refname_hash{'existing_vbm'}) {
                $log_msg=$log_msg."\tThe specified vbm reference space is identical to the existing vbm reference space.  Existing vbm reference string will be used.\n".
                    "\trefname_hash{\'vbm\'} = ${refname_hash{'existing_vbm'}} INSTEAD of ${refname_hash{'vbm'}}\n";
                $Hf->set_value('vbm_refname',$refname_hash{'existing_vbm'});
                $refname_hash{'vbm'}=$refname_hash{'existing_vbm'};
                $Hf->set_value('vbm_refspace',$refspace_hash{'existing_vbm'});
                $refspace_hash{'vbm'}=$refspace_hash{'existing_vbm'};

            }
        }
    }
    if (($base_images_for_labels) && ($refspace_hash{'vbm'} eq $refspace_hash{'label'})) {
        $base_images_for_labels = 0;
        $Hf->set_value('label_reference_path',$reference_path_hash{'vbm'});     
        $Hf->set_value('label_refname',$refname_hash{'vbm'});
        $Hf->set_value('label_refspace',$refspace_hash{'vbm'});
        $Hf->set_value('label_refspace_path',$inputs_dir);
    }
    $Hf->set_value('base_images_for_labels',$base_images_for_labels);
        
    if ($base_images_for_labels) {
        my $intermediary_path = "${inputs_dir}/reffed_for_labels";
        my $current_folder;
        my $existence = 1;
        for (my $i=1; $existence== 1; $i++) {
            $current_folder =  "${intermediary_path}/ref_$i";
            if (! -d "${current_folder}") {
                $existence = 0;
                $refspace_folder_hash{'label'} = $current_folder;
                $log_msg=$log_msg."\tCreating new base images folder for label space \"ref_$i\": ${refspace_folder_hash{'label'}}\n";
            } else {
                ($refspace_hash{'existing_label'},$refname_hash{'existing_label'}) = read_refspace_txt($current_folder,$split_string);
                if ($refspace_hash{'label'} eq $refspace_hash{'existing_label'}) {
                    $existence = 0;
                    $refspace_folder_hash{'label'} = $current_folder;
                    if ($refname_hash{'label'} ne $refname_hash{'existing_label'}) {
                        $log_msg=$log_msg."\tThe specified label reference space is identical to the existing label reference space.".
                            " Existing label reference string will be used.\n".
                            "\t\'label_refname\' = ${refname_hash{'existing_label'}} INSTEAD of ${refname_hash{'label'}}\n";
                        $Hf->set_value('label_refname',$refname_hash{'existing_label'});
                        $refname_hash{'label'} = $refname_hash{'existing_label'};
                    }
                } 
            }    
        }
    }

    # Changed 1 September 2016: Implemented uniform processing for reference files. Feed source directly into function
    #    for creating a centered binary mass in the reference image.  This should automatically handle all centering 
    #    issues, including re-centering the rigid atlas target.
    my $string=$refspace_folder_hash{'vbm'};
    $Hf->set_value('vbm_refspace_folder',$refspace_folder_hash{'vbm'});
    $Hf->set_value("vbm_reference_path",$reference_path_hash{'vbm'});

    if ($create_labels){ 
        $Hf->set_value('label_refspace_folder',$refspace_folder_hash{'label'});
        if ($base_images_for_labels) {
            $Hf->set_value('label_reference_path',$reference_path_hash{'label'});
        } else {
            $Hf->set_value("label_reference_path",$reference_path_hash{'vbm'});
        } 
    }

    
    $rigid_atlas_name = $Hf->get_value('rigid_atlas_name');
    $rigid_contrast = $Hf->get_value('rigid_contrast');
    $rigid_target = $Hf->get_value('rigid_target');
    
    my $this_path;
    if ($rigid_atlas_name eq 'NO_KEY') {
        if ($rigid_target eq 'NO_KEY') {
            $Hf->set_value('rigid_atlas_path','null');
            $Hf->set_value('rigid_contrast','null');
            $log_msg=$log_msg."\tNo rigid target or atlas has been specified. No rigid registration will be performed. Rigid contrast is \"null\".\n";
        } else {
            if ($runno_list =~ /[,]*${rigid_target}[,]*}/) {
                $this_path=get_nii_from_inputs($preprocess_dir,$rigid_target,$rigid_contrast);
                if ($this_path !~ /[\n]+/) {
                    my ($dumdum,$this_name,$this_ext)= fileparts($this_path,2);
                    my $that_path = "${inputs_dir}/${this_name}${this_ext}";
                    die if ! -e $that_path;                         
                    #$Hf->set_value('rigid_atlas_path',$that_path);
                    $Hf->set_value('original_rigid_atlas_path',$that_path); #Updated 1 September 2016
                    $log_msg=$log_msg."\tA runno has been specified as the rigid target; setting ${that_path} as the expected rigid atlas path.\n";
                } else {
                    $init_error_msg=$init_error_msg."The desired target for rigid registration appears to be runno: ${rigid_target}, ".
                        "but could not locate appropriate image.\nError message is: ${this_path}";          
                }
            } else {
                if (data_double_check($rigid_target)) {
                    $log_msg=$log_msg."\tNo valid rigid targets have been implied or specified (${rigid_target} could not be validated). Rigid registration will be skipped.\n";
                    $Hf->set_value('rigid_atlas_path','');
                    die "MISSING:$rigid_atlas_path" if ! -e $rigid_atlas_path;
                    $Hf->set_value('original_rigid_atlas_path',''); # Added 1 September 2016
                } else {
                    $log_msg=$log_msg."\tThe specified file to be used as the original rigid target exists: ${rigid_target}. (Note: it has not been verified to be a valid image.)\n";
                    # $Hf->set_value('rigid_atlas_path',$rigid_target);
                    $Hf->set_value('original_rigid_atlas_path',$rigid_target);#Updated 1 September 2016
                }
            }
        }
    } else {
        if ($rigid_contrast eq 'NO_KEY') {
            $init_error_msg=$init_error_msg."No rigid contrast has been specified. Please set this to proceed.\n";
        } else {
            my $rigid_atlas_dir   = "${WORKSTATION_DATA}/atlas/${rigid_atlas_name}/";
            if (! -d $rigid_atlas_dir) {
                # BROKEN SETUP HACK!
                $rigid_atlas_dir =~ s/\/data/\/CIVMdata/;
            }
            # Expected as in typical for previous curated data... 
            # Blergh, such pain in this.
            my $expected_rigid_atlas_path = "${rigid_atlas_dir}${rigid_atlas_name}_${rigid_contrast}.nii";
            ### try to deal with upper vs lower case abbreviations.
            #
            # That should not longer be necesary.
            # In much of our effort we swippity swap extnsions, at least until I can clear that out, 
            # so, we'll do our initial search in our "output" location.
            my $test_path = get_nii_from_inputs($inputs_dir,$rigid_atlas_name,$rigid_contrast);
            # Formerly this was first, now it only happens if we havnt stuffed our rigid file into its diddle'd location.
            $test_path = get_nii_from_inputs($rigid_atlas_dir,$rigid_atlas_name,$rigid_contrast) if !-e $test_path;
            $test_path =~ s/\.gz//; # Strip '.gz', 15 March 2017
            my ($dumdum,$rigid_atlas_filename,$rigid_atlas_ext)= fileparts($test_path,2);
            #$rigid_atlas_path =  "${inputs_dir}/${rigid_atlas_name}_${rigid_contrast}.nii";#Added 1 September 2016
            $rigid_atlas_path =  "${inputs_dir}/${rigid_atlas_filename}${rigid_atlas_ext}"; #Updated 14 March 2017
            #
            ###

            if (data_double_check($rigid_atlas_path))  {
                Data::Dump::dump(["not found, so trying gz",$rigid_atlas_path]);
                $rigid_atlas_path=$rigid_atlas_path.'.gz';
                if (data_double_check($rigid_atlas_path))  {
                    $original_rigid_atlas_path  = get_nii_from_inputs($preprocess_dir,$rigid_atlas_name,$rigid_contrast);
                    if ($original_rigid_atlas_path =~ /[\n]+/) {
                        $original_rigid_atlas_path  = get_nii_from_inputs($rigid_atlas_dir,$rigid_atlas_name,$rigid_contrast);#Updated 1 September 2016
                        if (data_double_check($original_rigid_atlas_path))  { # Updated 1 September 2016
                            $init_error_msg = $init_error_msg."For rigid contrast ${rigid_contrast}: missing atlas nifti file ${expected_rigid_atlas_path}  (note optional \'.gz\')\n";
                        } else {
                            # WARNING CODER, THERE IS A REPLICATE OF THIS WHOLE BAG OF STUFF IN mask_images_vbm AND set_reference_space_vbm
                            my $cmd="cp ${original_rigid_atlas_path} ${preprocess_dir}";
                            my ($p,$n,$e)=fileparts($original_rigid_atlas_path,2);
                            # THIS WHOLE CONSTRUCT IS BAD... GONNA MAKE IT WORSE BY ADDING nhdr support via WarpImageMultiTransform. 
                            if( $e eq ".nhdr") {
                                $cmd=sprintf("WarpImageMultiTransform 3 %s %s ".
                                                " --use-NN ".
                                                " --reslice-by-header --tightest-bounding-box ".
                                                "",
                                                $original_rigid_atlas_path, File::Spec->catfile($preprocess_dir,$n.".nii"));
                            } elsif ($original_rigid_atlas_path !~ /\.gz$/) {
                                # WHY DO WE WANT TO GZIP SO BADLY!
                                carp("WARNING: Input atlas not gzipped, We're going to gzip it!");
                                #$cmd=$cmd." && "."gzip ${preprocess_dir}/${rigid_atlas_name}_${rigid_contrast}.nii";
				my $at_file="${preprocess_dir}/${rigid_atlas_name}_${rigid_contrast}.nii.gz";
				$cmd="gzip -c ${original_rigid_atlas_path} > ${at_file} && touch -r ${original_rigid_atlas_path} $at_file";
                            }
                            #run_and_watch($cmd);
			    # mem estimate of voxelcount@64-bit x2 volumes
			    my $mem_request=ceil($vx_count*8*2/1000/1000);
			    if( $e eq ".nhdr") {
				my ($vx_sc,$est_bytes)=ants::estimate_memory($cmd,$vx_count);
				# convert bytes to MB(not MiB).
				my $expected_max_mem=ceil($est_bytes/1000/1000);
				printd(45,"Expected amount of memory required to re-header atlas: ${expected_max_mem} MB.\n");
				$mem_request=$expected_max_mem;
			    }
			    #,$reservation,$dependency);
			    my @test=(0);
			    my $go_message =  "$PM: set reference space rep atlas to preprocess";
			    my $stop_message = "$PM: could not fetch atlas file into preprocess:  $cmd\n";
			    my $jid = 0;
			    if ($cmd){
				if (cluster_check) {
				    my $Id= "rigid_reference_cache";
				    my $verbose = 1; # Will print log only for work done.
				    $jid = cluster_exec($go, $go_message, $cmd,$preprocess_dir,$Id,$verbose,$mem_request,@test);
				    if (not $jid) {
					error_out($stop_message);
				    }
				    push(@init_jobs,$jid);
				} else {
				    if (! execute($go, $go_message, $cmd) ) {
					error_out($stop_message);
				    }
				}
			    }
			}
                    }
                } else {
                    #### WARNING: Disabling this due to broken logic of lets gzip a gzipped file. 
                    # It may have 
=item erroneous gzipping?
                    Data::Dump::dump(["found,... but trying gz? wtf mate",$rigid_atlas_path,$expected_rigid_atlas_path]);
                    run_and_watch("gzip ${rigid_atlas_path}");
=cut
                    #$rigid_atlas_path=$rigid_atlas_path.'.gz'; #If things break, look here! 27 Sept 2016
                    $original_rigid_atlas_path = $expected_rigid_atlas_path;
                }
            } else {
                $original_rigid_atlas_path = $expected_rigid_atlas_path;
            }
            
            $Hf->set_value('rigid_atlas_path',$rigid_atlas_path);
	    if( ! -e $rigid_atlas_path && ! scalar(@init_jobs) ){
		error_out("MISSING:$rigid_atlas_path and not scheduled.");
	    }
            $Hf->set_value('original_rigid_atlas_path',$original_rigid_atlas_path); # Updated 1 September 2016
        }
    }
    
    
    
    if ((defined $log_msg) && ($log_msg ne '') ) {
        log_info("${message_prefix}${log_msg}");
    }
    
    if ((defined $init_error_msg) && ($init_error_msg ne '') ) {
        $init_error_msg = $message_prefix.$init_error_msg;
    }
    return($init_error_msg,\@init_jobs);
    
}

#---------------------
sub set_reference_path_vbm {
#---------------------
    my ($ref_option,$for_labels) = @_;
    my $ref_string; 
    $inputs_dir = $Hf->get_value('inputs_dir');
    my $ref_path='';
    my $input_ref_path;
    my $error_message;
    
    my $which_space='vbm';
    if ($for_labels) {
        $which_space = 'label';
    }
    my $ref_folder= $refspace_folder_hash{${which_space}};    

    if (! data_double_check($ref_option)) {
        my ($r_path,$r_name,$r_extension) = fileparts($ref_option,2);
#       print "r_name = ${r_name}\n\n\n\n";
        if ($r_extension =~ m/^[.]{1}(hdr|img|nii|nii\.gz)$/) {
            $log_msg=$log_msg."\tThe selected ${which_space} reference space is an [acceptable] arbitrary file: ${ref_option}\n";
            $input_ref_path=$ref_option;
            if ($r_name =~ /^reference_file_([^\.]*)\.nii(\.gz)?$/) {
                $ref_path = "${ref_folder}/${r_name}.nii.gz";
                $ref_string=$1;
                print "ref_path = ${ref_path};\n\nref_string=${ref_string}\n\n\n"; ####
            } else {
                $r_name =~ s/([^0-9a-zA-Z]*)//g;
                $r_name =~ m/(^[\w]{2,8})/;
                $ref_string = "c_$1";  # "c" stands for custom
                $ref_path="${ref_folder}/reference_file_${ref_string}.nii.gz";
            }
            print "ref_string = ${ref_string}\n\nref_path = ${ref_path}\n\n\n";
        } else {
            $error_message="The arbitrary file selected for defining ${which_space} reference space exists but is NOT  in an acceptable format:\n${ref_option}\n";
        }
    }


    if ($ref_path ne '') {
        if ($for_labels) {
            $Hf->set_value('label_refname',$ref_string);
        } else {
            $Hf->set_value('vbm_refname',$ref_string); 
        }

        $log_msg=$log_msg."\tThe ${which_space} reference string/name = ${ref_string}\n";
        #return($ref_path,$ref_string,$error_message);
        return($input_ref_path,$ref_path,$ref_string,$error_message); #Updated 1 September 2016
    }
    
    my $atlas_dir_perhaps = "${WORKSTATION_DATA}/atlas/${ref_option}";
    if (! -d $atlas_dir_perhaps) {
        if ($atlas_dir_perhaps =~ s/\/data/\/CIVMdata/) {}
    } 


    if (-d $atlas_dir_perhaps) {
        $log_msg=$log_msg."\tThe ${which_space} reference space will be inherited from the ${ref_option} atlas.\n";
        $input_ref_path = get_nii_from_inputs($atlas_dir_perhaps,$ref_option,$rigid_contrast);
        if (($input_ref_path =~ /[\n]+/) || (data_double_check($input_ref_path))) {
            $error_message = $error_message.$input_ref_path;
        }
        $ref_string="a_${ref_option}"; # "a" stands for atlas
        $ref_path="${ref_folder}/reference_file_${ref_string}.nii.gz";
        $log_msg=$log_msg."\tThe full ${which_space} input reference path is ${input_ref_path}\n";
    } else {
        
        my $ref_runno;#=$Hf->get_value('ref_runno');
        my $preprocess_dir = $Hf->get_value('preprocess_dir');
        if ($runno_list =~ /[,]*${ref_option}[,]*/ ) {
            $ref_runno=$ref_option;
        } else {
            my @control_runnos= split(',',$Hf->get_value('control_comma_list')); #switched from "control" to "template" 1 May 2018
            $ref_runno = shift(@control_runnos);
        }
        print " Ref_runno = ${ref_runno}\n";
        $Hf->set_value('ref_runno',$ref_runno);
        #$ref_path = get_nii_from_inputs($preprocess_dir,"native_reference",$ref_runno);
        #$ref_path = get_nii_from_inputs($preprocess_dir,"reference_image_native",$ref_runno);# Updated 1 September 2016

        my $ch_runlist = $Hf->get_value('channel_comma_list');
        my @channels=split(',',$ch_runlist);
        my $c_channel=$channels[0];
        if ($c_channel =~ /nii4D/) {$c_channel=$channels[1];}
        #No, not nii4D 26 October 2018
        $input_ref_path = get_nii_from_inputs($preprocess_dir,$ref_runno,$c_channel);
        #$input_ref_path = get_nii_from_inputs($preprocess_dir,$ref_runno,""); # Will stick with looking for ANY contrast from $ . 16 March 2017
        
        $error_message='';      
        if ($input_ref_path =~ /[\n]+/) {
            $rerun_init_flag = $Hf->get_value('rerun_init_check');
            if (($rerun_init_flag ne 'NO_KEY') && ($rerun_init_flag == 1)) {
                $error_message =  "Unable to find any input image for ${ref_runno} in folder(s): ${preprocess_dir}\nnor in ${pristine_in_folder}.\n";
            } else {
                $input_ref_path =  'rerun_init_check_later';
                print "Will need to rerun the initialization protocol for ${PM} later...\n\n";
            }
        }
        
        $ref_string="native";
        $ref_path="${ref_folder}/reference_image_native_${ref_runno}.nii.gz";
        
        #} else {
#       $error_message = $error_message.$file;
        #   }
        
        $log_msg=$log_msg."\tThe ${which_space} reference space will be inherited from the native base images.\n\tThe full reference path is ${ref_path}\n";
        
    }

    if ($for_labels) {
        $Hf->set_value('label_refname',$ref_string);
    } else {
        $Hf->set_value('vbm_refname',$ref_string);
    }
    
    $log_msg=$log_msg."\tThe ${which_space} reference string/name = ${ref_string}\n";
    
    return($input_ref_path,$ref_path,$ref_string,$error_message);
}

# ------------------
sub set_reference_space_vbm_Runtime_check {
# ------------------
    $pristine_in_folder = $Hf->get_value('pristine_input_dir');
    $inputs_dir = $Hf->get_value('inputs_dir');
    $preprocess_dir = $Hf->get_value('preprocess_dir');
    
    $dims=$Hf->get_value('image_dimensions');
    $rerun_init_flag = $Hf->get_value('rerun_init_check');

    mkdir ($inputs_dir,$permissions)if ! -e $inputs_dir;
    mkdir ($preprocess_dir,$permissions)if ! -e $preprocess_dir;

    if (($rerun_init_flag ne 'NO_KEY') && ($rerun_init_flag == 1)) {
        # This looks like its a rare condition, but it may be part and parcel to the init troubles of this module.
        # our template ref file may not exist when we run init, and that is probably supposed to set this flag... 
        carp('Exceptional condition rerun_init set_reference_space_vbm_runtime');
        sleep_with_countdown(15);
        my $init_error_message_2 = set_reference_space_vbm_Init_check();
    }

    $base_images_for_labels = $Hf->get_value('base_images_for_labels');
    $refspace_folder_hash{'vbm'} = $Hf->get_value('vbm_refspace_folder');
    $refspace_folder_hash{'label'} = $Hf->get_value('label_refspace_folder');
    
    my $intermediary_path = "${inputs_dir}/reffed_for_labels";
    if ($base_images_for_labels) {
        $intermediary_path = "${inputs_dir}/reffed_for_labels";
	mkdir ($intermediary_path,$permissions) if ! -e $intermediary_path;
	mkdir ($refspace_folder_hash{'label'},$permissions) if ! -e $refspace_folder_hash{'label'};
    }
    


## TRYING TO MOVE THIS CODE TO INIT_CHECK, 16 March 2017 --> Just kidding, keep this here, rerun init check if native ref file not found. 20 March 2017
    # Not clear when these wouldn't have the same values. 
    @ref_spaces = ("vbm");
    if ($base_images_for_labels) {
	push(@ref_spaces,"label");
    }
    foreach my $space (@ref_spaces) {
        $reference_space_hash{$space} = $Hf->get_value("${space}_reference_space");
        my $inpath = $Hf->get_value("${space}_input_reference_path");
        my $outpath = $Hf->get_value("${space}_reference_path");
        $refspace_hash{$space} = $Hf->get_value("${space}_refspace");
        $refname_hash{$space} =  $Hf->get_value("${space}_refname");

        if (data_double_check($inpath)) {
            $inpath="${inpath}.gz"; # We're assuming that it exists, but isn't found because it has been gzipped. 16 March 2017
        }
        # 2020-01-29
        # New fail condition spotted here where we try to operate on a 'plain' named file, 
        # but only a _masked named file is available.
        # Suspicion is that we dont wait for code the way we might mean to, 
        # and this code is prepared/scheduled to run while another is busy renaming things.
        # 2020-08-07 these failures are(seem) more repeatable with larger data
        if (data_double_check($outpath)) {
            #centered_mass_for
            my $name = "REF_${refname_hash{$space}}";
            my $nifti_args = "\'${inpath}\' , \'${outpath}\'";
            my $nifti_command = make_matlab_command('create_centered_mass_from_image_array',$nifti_args,"${name}_",$Hf,0); # 'center_nii'
            #print ($name."_create_centered_mass_from_image_array"."\n");exit 0 ;
            #make_matlab_command($function_m_name, $args, $short_unique_purpose, $Hf,$verbose);
            #my $cmd_to_execute = make_matlab_command_nohf($function_m_name,$args,$short_unique_purpose,
            #my $mfile_stub = "$work_dir/${short_unique_purpose}${function_m_name}".".m";
            #                                    $work_dir,$matlab_app,$logpath,$matlab_opts);
            execute(1, "Creating a dummy centered mass for referencing purposes", $nifti_command);
        }
        
        # 4 Feb 2019--use ResampleImageBySpacing here to create up/downsampled working space if desired.
        #$Hf->get_value('resample_images');
        #ResampleImageBySpacing 3 $in_ref $out_ref 0.18 0.18 0.18 0 0 1
        #my $bounding_box_and_spacing = get_bounding_box_and_spacing_from_header(${out_ref});
        
        #$refspace_hash{$space} = $bounding_box_and_spacing;
        #$Hf->set_value("${space}_refspace",$refspace_hash{$space});
        
        # write refspace_temp.txt (for human purposes, in case this module fails)
        my $ref_tmp=File::Spec->catfile($refspace_folder_hash{$space},"refspace.txt.tmp");
        if ( ! -e $ref_tmp ) {
            write_refspace_txt($refspace_hash{$space},$refname_hash{$space},$refspace_folder_hash{$space},$split_string,"refspace.txt.tmp");
        } else {
            printd(5,"WARNING, $ref_tmp exists, not overwriting.\n");
        }
    }


##  2 February 2016: Had "fixed" this code several months ago, however it was sending the re-centered rigid atlas to base_images, and not even 
##  creating a version for the preprocess folder. The rigid atlas will only be rereferenced if it is found in preprocess, which for new VBA runs
##  would not be the case.  Thus we would have a recentered atlas with its own reference space being used for rigid registration, resulting in
##  unknown behavior.  An example would be that all of our images get "shoved" to the top of their bounding box and the top of the brain gets lightly
##  trimmed off.  Also, we will assume that this file will be in .gz format.  If not, then it will be gzipped.

    if ($base_images_for_labels) {
        #`cp ${refspace_folder_hash{"vbm"}}/*\.nii* ${refspace_folder_hash{"label"}}`;
        run_and_watch("cp ".${refspace_folder_hash{"vbm"}}."/*\.nii* ".${refspace_folder_hash{"label"}});
    }   
    my $case = 1;
    my $skip_message;
    # how messy, we use this to set PM scoped globals instead of returning :( 
    ($work_to_do_HoA,$skip_message)=set_reference_space_Output_check($case);
    
    if ($skip_message ne '') {
        print "${skip_message}";
    }
}
1;

