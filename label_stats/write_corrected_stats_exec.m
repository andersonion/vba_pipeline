function write_corrected_stats_exec(runno,label_file,contrast_list,image_dir,output_dir,space,atlas_id) % (contrast,average_mask,inputs_directory,results_directory,group_1_name,group_2_name,group_1_filenames,group_2_filenames)
% New inputs:
% runno: run number of interest
% label_file: Full path to labels
% contrast_list: comma-delimited (no spaces) string of contrasts
% image_dir: Directory containing all the contrast images
% output_dir
% space: 'native','rigid','affine','mdt', or atlas'; used in header
% atlas_id: used in header; may be used for pulling label names in the future.

expected_output_subfolder='stats';

if ~isdeployed
    % Default test variables:
    if ~exist('runno','var')
        runno='N51406';
    end
    
    if ~exist('label_file','var')
        label_file=['/glusterspace/VBM_13colton01_chass_symmetric2_April2017analysis-work/dwi/SyN_0p5_3_0p5_fa/faMDT_nos2_n28_i6/stats_by_region/labels/post_rigid_native_space/chass_symmetric2/fa_labels_warp_' runno '.nii.gz'];
    end
    
    if ~exist('contrast_list','var')
        contrast_list='adc,dwi,e1,e2,e3,fa,rd';
    end
    
    if ~exist('image_dir','var')
        image_dir='/glusterspace/VBM_13colton01_chass_symmetric2_April2017analysis-work/dwi/SyN_0p5_3_0p5_fa/faMDT_nos2_n28_i6/stats_by_region/labels/post_rigid_native_space/images/';
    end
    
    if ~exist('output_dir','var')
        output_dir='/glusterspace/VBM_13colton01_chass_symmetric2_April2017analysis-work/dwi/SyN_0p5_3_0p5_fa/faMDT_nos2_n28_i6/stats_by_region/labels/post_rigid_native_space/chass_symmetric2/stats/';
    end
    
   if ~exist('space','var')
       space='rigid';
   end
    
   if ~exist('atlas_id','var')
       atlas_id='chass_symmetric2';
   end
    
else
    if exist(output_dir)
        
        output_dir='/glusterspace/VBM_13colton01_chass_symmetric2_April2017analysis-work/dwi/SyN_0p5_3_0p5_fa/faMDT_nos2_n28_i6/stats_by_region/labels/post_rigid_native_space/chass_symmetric2/stats/';
        folder_cell = strsplit(output_dir,'/');
        folder_cell=folder_cell(~cellfun('isempty',folder_cell));
        if strcmp(folder_cell{end},expected_output_subfolder)
            folder_cell(end)=[];
        end
        
        default_atlas_id = folder_cell{end};
        
        def_space_string = folder_cell{end-1};
        
        dss_cell=strsplit(def_space_string,'_');
        dss_cell(end)=[];
        dss_cell(end)=[];
        raw_default_space = strjoin(dss_cell,'_');
        
        switch raw_default_space
            case 'pre_rigid'
                default_space = 'native';
            case 'post_rigid'
                default_space = 'rigid';
            case 'pre_affine'
                default_space = 'rigid';
            case 'post_affine'
                default_space = 'affine';
            case 'mdt'
                default_space = 'mdt';
            case 'MDT'
                default_space = 'MDT';
            case 'atlas'
                default_space = 'atlas';
            otherwise
                default_space = 'native';
        end
    end
    
    
    if ~exist('space','var')
        space=default_space;
    end
    
    if ~exist('atlas_id','var')
        atlas_id=default_atlas_id;
    end
    
    
    
    
end

%write stats
% taking
% cell array of niftis
%    first is the label file to be loaded the rest are all the volumes to
%    measure based on the labels
% output labels
%    label file output, we ... renormalize the label field in processing
% output stats, path to write a text file to
% atlas id, which of the atlases was used to create labels
%    this is useful for writing out the correct label names, not that we do
%    much with it yet.

% Need label_names! label_names=['Exterior',	'Cerebral_cortex	', 'Brainstem	', 'Cerebellum	   '	]; %et cetera, et cetera, et cetera

contrasts = strsplit(contrast_list,',');

%label_hdr
output_name=[runno '_' atlas_id '_labels_in_' space '_space'];
output_stats = [output_dir output_name '_stats.txt'];
header_info = {runno atlas_id space};
header_key = {'runno' 'atlas' 'space'};

label_hdr = 'ROI';
myheader={label_hdr , 'voxels',  'volume(mm3)'} ;

for i=1:length(contrasts)
    myheader=[myheader,contrasts{i}];
end
fprintf('Header on output \n>\t%s\n',strjoin(myheader,','));

label_orig=load_untouch_nii(label_file);
voxel_vol=label_orig.hdr.dime.pixdim(2)*label_orig.hdr.dime.pixdim(3)*label_orig.hdr.dime.pixdim(4);
labelim=label_orig.img;

label_test=label_orig;
val1=unique(labelim);
L=(length(contrasts)+1); % extra one is for volume
n=length(val1)
ar1=1:n;
volumes=zeros(size(ar1));
mystats=zeros([n,L]);
ind_mask=find(labelim);%check if used

label_test.hdr=label_orig.hdr;

%%%
for ii=1:length(contrasts)
    contrast = contrasts{ii};
    i = ii + 1;
    %get index for each region
    %get fa values, e1 values, e2 values etc for each region
    filenii_i=[image_dir runno '_' contrast '.nii'];
    if ~exist(filenii_i,'file')
        filenii_i = [filenii_i '.gz'];
    end
    fprintf('load nii %s\n',filenii_i);
    imnii_i=load_untouch_nii(filenii_i);
    for ind=1:numel(val1)
        fprintf('For contrast "%s" (%i/%i), processing region %i of %i (ROI %i)...\n',contrast,ii,length(contrasts),ind,numel(val1),val1(ind));
        volumes(ind)=numel(find(labelim==val1(ind)));
        regionindex=find(labelim==val1(ind));
        mystats(ind,1)=mean(labelim(regionindex));
        mystats(ind,i)=mean(imnii_i.img(regionindex));
    end
end


%% Calculate volume in mm^3

volumes_unit=volumes*voxel_vol;

%% Write to file

fid = fopen(output_stats, 'w');
for LL = 1:length(header_info)
    fprintf(fid, '%s=%s\n', header_key{LL},header_info{LL});
end
fclose (fid);


% Currently not implementing generalized label_names % 13 June 2017
%if strcmp(atlasid,'whs')
%    label_key=['if_using_whs_as_reference_the_label_names_are: ', label_names];
%dlmwrite(output_stats, label_key, 'precision', '%s', 'delimiter', ' ', '-append' ,'roffset', 1);
%else
label_key=['General label key support not implemented yet.'];
disp(label_key);
%end

fid = fopen(output_stats, 'a');
fprintf(fid, '%s', myheader{:,1});
for row=2:length(myheader)
    fprintf(fid, '\t%s', myheader{:,row});
end
fprintf(fid, '\n');

for c_row=1:length(val1)

    fprintf(fid, '%i\t%i\t%10.8f', val1(c_row),volumes(c_row),volumes_unit(c_row));

    for cc=1:length(contrasts)
        fprintf(fid, '\t%10.8f', mystats(c_row,(cc+1)));
    end
    fprintf(fid, '\n');
end

fclose (fid);

end
