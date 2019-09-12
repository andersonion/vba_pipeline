%compile me
my_dir =  '/home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/AS/'
mkdir(my_dir)
eval(['!chmod a+rwx ' my_dir])
eval(['mcc -N -d  ' my_dir...
   ' -C -m '...
   ' -R nodisplay -R nosplash -R nojvm '...
   ' -a /cm/shared/apps/MATLAB/R2015b/toolbox/stats/stats/tcdf.m '...
   ' -a /home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/surfstat/SurfStatAvVol.m '...
   ' /home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/surfstat_for_vbm_pipeline_exec.m;'])

%cp_cmd = ['cp /home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/surfstat_for_vbm_pipeline_exec.m ' my_dir];
%system(cp_cmd);
cp_cmd_2 = ['cp /home/rja20/cluster_code/workstation_code/analysis/vbm_pipe/compile_command_for_surfstat.m ' my_dir];
system(cp_cmd_2);

   %' -a /cm/shared/workstation_code_dev/shared/civm_matlab_common_utils/read_headfile.m '...
   %' -a /cm/shared/apps/MATLAB/R2015b/toolbox/images/images/padarray.m '...
   %' -a /cm/shared/apps/MATLAB/R2015b/toolbox/stats/stats/quantile.m '...
   %' -a /home/rmd22/Documents/MATLAB/MATLAB_scripts_rmd/CS/sparseMRI_v0.2/utils/ifft2c.m '...
   %' -a /cm/shared/apps/MATLAB/R2015b/toolbox/signal/signal/hamming.m '...
   %' -a /home/rmd22/Documents/MATLAB/MATLAB_scripts_rmd/CS/sparseMRI_v0.2/init.m '...
   %' -a /home/rmd22/Documents/MATLAB/MATLAB_scripts_rmd/CS/Wavelab850/WavePath2.m '...


