% ANTSpath='/Applications/SegmentationSoftware/ANTS/';
% 
% for i=1:length(filenames)
%         [dir name ext]=fileparts(filenames{i});
%         cmd=horzcat(ANTSpath,'SmoothImage 3 ',filenames{i},' 4 ',dir,'/',name,'_smooth',ext);
%         system(cmd);
% end

path='/Volumes/trinityspace/Projects/Stanford_Rat_Perinatal_Stroke/stats/*smooth.nii';

filenames = SurfStatListDir( path );


[ Y0, vol0 ] = SurfStatReadVol( filenames, [], { [], [], 8 } );

control=[1 0 1 0 1 0];

layout = reshape( [ find(1-control) find(control) ], 3, 2 );

figure(1); SurfStatViews( Y0, vol0, 0, layout );
title('FA for 3 cell treated subjects (left) and 3 saline controls (right)','FontSize',18);

[ wmav, volwmav ] = SurfStatAvVol( filenames( find(control) ) );


%figure(2); SurfStatView1( wmav, volwmav );


%SurfStatView1( wmav, volwmav, 'datathresh', 0.4 );

[ Y, vol ] = SurfStatReadVol( filenames, wmav > 0.0 );

Group = term( var2fac( control, { 'cells'; 'control' } ) );

slm = SurfStatLinMod( Y, Group, vol );
slm = SurfStatT( slm, Group.cells - Group.control );
figure(3); SurfStatView1( slm.t, vol );
title( 'T-statistic, 7 df' ,'FontSize',18);
caxis([0 15])

figure(4); SurfStatView1( SurfStatP( slm ), vol );
title( 'P-value<0.05' ,'FontSize',18);

[ pval, peak, clus] = SurfStatP( slm );


figure(5); SurfStatView1( SurfStatQ( slm ), vol );
title('Q-value < 0.05','FontSize',18);

% qval=SurfStatQ( slm );
% SurfStatWriteVol('/Volumes/androsspace/evan/blast_analysis/qval.nii',qval.Q,vol);
