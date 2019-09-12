function niiout=img_transform_exec(img,current_vorder,desired_vorder,varargin)
% function niiout=img_transform_exec(img,current_vorder,desired_vorder,varargin)

% img='/civmnas4/rja20/SingleSegmentation_16gaj38_chass_symmetric3_RAS_N56456-inputs/N56456_color_nqa.nii.gz';
%img='/civmnas4/rja20/img_transform_testing/S64570_m000_DTI_tensor.nii';
%img='/cm/shared/CIVMdata/atlas/C57/transforms_chass_symmetric3/chass_symmetric3_to_C57/chass_symmetric3_to_MDT_warp.nii.gz';
%current_vorder='ARI';
%desired_vorder='RAS';
%varargin={};
%path_specified='/civmnas4/rja20/SingleSegmentation_16gaj38_chass_symmetric3_RAS_N56456-work/preprocess/';
%% Modified 8 Feb 2016, BJ Anderson, CIVM
%  Added code to write corresponding affine transform matrix in ANTs format
%% Modified 22 March 2017, BJ Anderson, CIVM
%  Was originally creating affine matrix that transformed points, while the
%  ITK/ANTs paradigm is the same for affine, where the inverse needs to
%  be used. So it was updated to calculate the points transform, then
%  invert for "normal" use with images.
%% Modified 25 July 2017, BJ Anderson, CIVM
%  Making it more general to handle recentering issue.
%  Recentering in theory can be turned off now.
%  Code is handled differently if only recentering.
%  If no recentering and current_vorder and desired_vorder are the same,
%  then it just copies the file with the desired_vorder suffix.

%% 5 February 2019, BJ Anderson, CIVM
%  Attempting to add vector and color support, maybe add tensor support at another
%  time? Hope to add code that spits out a fully usable affine.mat that
%  includes proper translation.

%% Variable Check

write_transform = 0;
recenter=1;
is_RGB=0;
is_vector=0;
is_tensor=0;

if length(varargin) > 0
    if ~isempty(varargin{1})
        % temp_path = varargin{1};
        % [path_specified, ~,~] = fileparts(temp_path);
        [path_specified, ~,~] = fileparts(varargin{1});
    end
    
    if length(varargin) > 1
        if ~isempty(varargin{2})
            write_transform = varargin{2};
        end
    end
    
    if length(varargin) > 1
        if ~isempty(varargin{2})
            write_transform = varargin{2};
        end
    end
end


% image check
if ~exist(img,'file')
    error('Image cannot be found, please specify the full path as a string');
elseif ~strcmp(img(end-3:end),'.nii') && ~strcmp(img(end-6:end),'.nii.gz')
    error('Input image must be in NIfTI format')
end

%voxel order checks
if ~ischar(current_vorder)
    error('Current Voxel Order is not a string')
end
if length(current_vorder)~=3
    error('Current Voxel Order is not 3 characters long')
end
if  sum(isstrprop(current_vorder,'lower'))>0
    error('Current Voxel Order must be all upper case letters')
end
if strcmp(current_vorder(1),current_vorder(2)) || strcmp(current_vorder(1),current_vorder(3)) || strcmp(current_vorder(2),current_vorder(3))
    error('Current voxel order contains repeated elements! All three letters must be unique')
end
if isempty(strfind('RLAPSI',current_vorder(1))) || isempty(strfind('RLAPSI',current_vorder(2))) || isempty(strfind('RLAPSI',current_vorder(3)))
    error('Please use only R L A P S or I for current voxel order')
end


if  ~ischar(desired_vorder)
    error('Desired Voxel Order is not a string')
end
if  length(desired_vorder)~=3
    error('Desired Voxel Order is not 3 characters long')
end

if  sum(isstrprop(desired_vorder,'lower'))>0
    error('Desired Voxel Order must be all upper case letters')
end
if strcmp(desired_vorder(1),desired_vorder(2)) || strcmp(desired_vorder(1),desired_vorder(3)) || strcmp(desired_vorder(2),desired_vorder(3))
    error('Desired voxel order contains repeated elements! All three letters must be unique')
end
if isempty(strfind('RLAPSI',desired_vorder(1))) || isempty(strfind('RLAPSI',desired_vorder(2))) || isempty(strfind('RLAPSI',desired_vorder(3)))
    error('Please use only R L A P S or I for desired voxel order')
end

if strcmp(desired_vorder,current_vorder)
        if recenter
            %if strcmp('.gz',);
            origin=round(size(new)./2);
            origin=origin(1:3);
        else
            origin=[]; % I hope this automatically handles the origin if not recentering...
        end
else
    
    %% Load and Analyze data
    try 
        n1t=tic;
        nii=load_niigz(img);       
    catch
        time_1=toc(n1t);
        n2t=tic;
        nii=load_nii(img);
        time_2=toc(n2t);
        warning(['Function load_niigz (runtime: ' num2str(time_1) ') failed with datatype: ' num2str(nii.hdr.dime.datatype) ' (perhaps because it currently doesn''t support RGB?). Used load_nii instead (runtime: ' num2str(time_2) ').']);
    end
    dims=size(nii.img);
    if length(dims)>6
        error('Image has > 5 dimensions')
    elseif length(dims)<3
        error('Image has < 3 dimensions')
    end
    new=nii.img;
    
    %% Feb 2019 -- Figure out if we have RGB/vector/tensor here.
    
    data_string = nifti1('data_type',nii.hdr.dime.datatype);
    if strcmp(data_string(1:3),'rgb')
       is_RGB=1;
       is_vector=1;
       %todo: either here or in nifti1, pull out the intent_code that
       %matches to data_string and explicitly set in:
       % nii.hdr.dime.intent_code=verified_intent_code;
       %if length(data_string)==3;
       %     nii.hdr.dime.intent_code=2003;
       %else
       %    nii.hdr.dime.intent_code=2004;
       %    end
       
    elseif ((length(dims) > 4) && (dims(5)==3));
        is_vector=1;
    elseif ((length(dims) > 5) && (dims(5)==6)); % This a GUESS at how to tell if we have tensor...which seems to be pretty reliable.
        is_tensor=1;
    end
    
    
    
    %% Voxel order preparation
    
    orig='RLAPSI';
    flip_string='LRPAIS';
    
    %% Affine transform matrix preparation
    x_row = [1 0 0];  % x and y are swapped in Matlab --but why then don't we swap x_row and y_row here?
    y_row = [0 1 0];  % x and y are swapped in Matlab
    z_row = [0 0 1];
    
    orig_current_vorder = current_vorder;
    %% check first dim
    xpos=strfind(desired_vorder,current_vorder(1));
    if isempty(xpos) %assume flip
        display('Flipping first dimension')
        new=flip(new,1);
        orig_ind=strfind(orig,current_vorder(1));
        current_vorder(1)=flip_string(orig_ind);
        %xpos=strfind(desired_vorder,current_vorder(1));  %I think this is incorrect and unused code (BJA); see Evan's quickfix.
        if (is_vector) && (is_RGB ==0)
             new(:,:,:,1,1)=-1*new(:,:,:,1,1);
        end
        
        x_row=x_row*(-1);
    end
    
    %% check second dim
    ypos=strfind(desired_vorder,current_vorder(2));
    if isempty(ypos) %assume flip
        display('Flipping second dimension')
        new=flip(new,2);
        orig_ind=strfind(orig,current_vorder(2));
        current_vorder(2)=flip_string(orig_ind);
        %ypos=strfind(desired_vorder,current_vorder(2));  %I think this is incorrect and unused code (BJA); see Evan's quickfix.
        if (is_vector) && (is_RGB ==0)
             new(:,:,:,1,2)=-1*new(:,:,:,1,2);
        end
        y_row=y_row*(-1);
    end
    
    %% check third dim
    zpos=strfind(desired_vorder,current_vorder(3));
    if isempty(zpos) %assume flip
        display('Flipping third dimension')
        new=flip(new,3);
        orig_ind=strfind(orig,current_vorder(3));
        current_vorder(3)=flip_string(orig_ind);
        %zpos=strfind(desired_vorder,current_vorder(3)); %I think this is incorrect and unused code (BJA); see Evan's quickfix.
        if (is_vector) && (is_RGB ==0)
             new(:,:,:,1,3)=-1*new(:,:,:,1,3);
        end
        z_row=z_row*(-1);
    end
    %% quick fix for correct ordering
    xpos=strfind(current_vorder,desired_vorder(1));
    ypos=strfind(current_vorder,desired_vorder(2));
    zpos=strfind(current_vorder,desired_vorder(3));
    
    %% perform swaps
    display(['Dimension order is:' num2str(xpos) ' ' num2str(ypos) ' ' num2str(zpos)] )
    
    if length(dims)==5
        if is_tensor
            new=permute(new,[xpos ypos zpos 4 5]);  % I think more sophisticated handling is required in for tensors! I think tensors are dim==5
        else
            if is_vector
                new=new(:,:,:,1,[xpos, ypos, zpos]);
            end
            new=permute(new,[xpos ypos zpos 4 5]);
        end
    elseif length(dims)==4
        if is_RGB
            new=new(:,:,:,[xpos, ypos, zpos]);
        end
        new=permute(new,[xpos ypos zpos 4]);
        
    elseif length(dims)==3
        new=permute(new,[xpos ypos zpos]);
    end
    
    intermediate_affine_matrix = [x_row;y_row;z_row];
    iam = intermediate_affine_matrix;
    affine_matrix_for_points = [iam(xpos,:); iam(ypos,:); iam(zpos,:)]; % New code added to reflect that images are handled differently (i.e. inversely) than points
    %am4p = affine_matrix_for_points;  % New code, ibid
    affine_matrix_for_images = inv(affine_matrix_for_points); % New code, ibid
    am4i = affine_matrix_for_images; % New code, ibid
    affine_matrix_string = [am4i(1,:) am4i(2,:) am4i(3,:) 0 0 0];% New code, ibid
    %affine_matrix_string = [iam(xpos,:) iam(ypos,:) iam(zpos,:) 0 0 0];
    affine_fixed_string = [0 0 0];
    
    %% make and save outputs
    
    [path name ext]=fileparts(img);
    
    %affine_mat.AffineTransform_double_3_3=affine_matrix_string';
    %affine_mat.fixed_string=affine_fixed_string';
    affineout=[path '/' orig_current_vorder '_to_' desired_vorder '_affine.mat'];
    if (~exist(affineout,'file') && write_transform)
        write_affine_xform_for_ants(affineout,affine_matrix_string,affine_fixed_string);
        %save(affineout,'-struct','affine_mat');
    end
    
    num=0;
    if strcmp(ext,'.gz')
        ext='.nii.gz';
        num=4;
    end
    
    if recenter
        origin=round(size(new)./2);
        origin=origin(1:3);
    else
        origin=[]; % I hope this automatically handles the origin if not recentering...
    end
    newnii=make_nii(new,nii.hdr.dime.pixdim(2:4),origin,nii.hdr.dime.datatype);
    %newnii=make_nii(new,nii.hdr.dime.pixdim(2:4),[0 0 0],nii.hdr.dime.datatype);
    newnii.hdr.dime.intent_code=nii.hdr.dime.intent_code;
    
    
end
if exist('path_specified','var')
    path = path_specified;
end

niiout=[path '/' name(1:end-num) '_' desired_vorder ext];

save_nii(newnii,niiout);
%newnii = nii;
%newnii.img = new;
%save_untouch_nii(newnii,niiout);
%end