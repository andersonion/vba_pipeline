function compare_group_stats(stats_file,vtreated,vcontrol,fileout,vols)
%example call
%set vols to 1 if dealing with volumes, this will run stats on normalized
%brain regions volumes and total brain on last line
%otherwise vols should be set to 0
vols=1;   
vtreated=[11.24746792	11.3979905	11.697399	11.48253298	10.99592152	11.28894936	11.22198677
5.678655447	5.949127232	5.860198451	5.844138121	5.413337681	5.965396624	5.300582611
5.520288294	5.506840929	5.678388143	5.904871337	5.497604617	5.276085483	5.577152314
4.998496854	4.882386348	4.689970045	5.275532909	4.829244869	4.544644018	4.883058043
3.716259744	3.689531275	3.630242589	3.860238296	3.790030086	3.639626867	3.713043392
2.760121778	2.965817375	2.735402161	2.679585314	2.79757865	2.786895898	2.974694209
2.666100601	2.62961306	2.675924829	2.554975132	2.480176288	2.406608497	2.510753662
2.097902515	2.047762592	2.190383609	2.051611485	2.15213604	1.973626794	2.032860132
1.690114548	1.660869151	1.761639278	1.726163681	1.70021937	1.714063806	1.692147432];

vcontrol=[10.79018431	11.3979905	11.25108158	11.2639322	11.11260123	10.81853104	11.19302129	10.97470473
6.228749811	5.949127232	6.684119491	5.592196277	6.027320945	6.278849396	6.46939904	6.109205995
6.220405597	5.506840929	5.975263727	5.796502029	5.612593817	5.973080669	5.635417395	5.726249707
4.958241153	4.882386348	4.806089034	4.922386076	4.789703492	4.694638409	4.852513996	4.887520587
3.851656908	3.689531275	3.784290587	3.868134244	3.808995618	3.734366639	3.7916221	3.786022242
2.636157077	2.965817375	2.716684859	2.563479818	2.637383985	2.623951948	2.512500027	2.701596106
2.606322582	2.62961306	2.459078461	2.50404268	2.427304885	2.564635623	2.380504793	2.378668435
2.17436003	2.047762592	2.096091492	1.983235412	1.928129625	2.199550567	2.204996066	2.227955874
1.778576724	1.660869151	1.77368787	1.841530308	1.727263352	1.757492991	1.866974472	1.720349733]

fileout='treated14_18_vs_allcontrol'

% writemystats(vtreated,vcontrol,fileout) 

no_treated=size(vtreated)
no_treated=no_treated(2)

no_control=size(vcontrol)
no_control=no_control(2)

no_labels=size(vcontrol);
no_labels=no_labels(1) ; 
%if dealing with volumes normalize first

    if vols==1;
        brain_vtreated=sum(vtreated)-vtreated(1,:)-vtreated(168,:);
        brain_vcontrol=sum(vcontrol)-vcontrol(1,:)-vcontrol(168,:);
        
    vtreated=100*vtreated./repmat(brain_vtreated,no_labels,1);
    vcontrol=100*vcontrol./repmat(brain_vcontrol,no_labels,1);
    %APPEND BRAIN
    vtreated=[vtreated;brain_vtreated];
    vcontrol=[vcontrol;brain_vcontrol];
    end

[h p table stats]=ttest2(vtreated',vcontrol')

[hBH, crit_p, adj_p]=fdr_bh(p,0.05,'pdep','yes');
[ppermute,tpermute,dfpermute]=mattest(vtreated,vcontrol,'Permute', 1000)


pooledsd=sqrt(std(vcontrol').^2/no_control+std(vtreated').^2/no_treated);
pooledsd=sqrt((no_control-1).*std(vcontrol').^2+(no_treated-1).*std(vtreated').^2)./sqrt(no_control+no_treated-2);
cohen_d=-(mean(vcontrol')-mean(vtreated'))./pooledsd;
difference=-(mean(vcontrol')-mean(vtreated'))*100./mean(vcontrol');

ci_l_treated=mean(vtreated')-1.96*std(vtreated');
ci_h_treated=mean(vtreated')+1.96*std(vtreated');
ci_l_control=mean(vcontrol')-1.96*std(vcontrol');
ci_h_control=mean(vcontrol')+1.96*std(vcontrol');


%% 


mystats=[mean(vtreated'); mean(vcontrol') ;std(vtreated'); std(vcontrol') ;std(vtreated')/sqrt(no_treated); std(vcontrol')/sqrt(no_control);ci_l_treated; ci_l_control; ci_h_control; ci_h_treated; h; p; ppermute'; adj_p; table;stats.tstat;cohen_d;difference]

fileout1=[fileout '.txt']

myheader={'mean_treated', 'mean_control', 'std_treated', 'std_control', 'sem_treated', 'sem_control', 'ci1_treated','ci2_treated','ci1_control','ci2_control', 'hypothesis', 'p_value', 'ppermute', 'P_FDR0.05_BH', 'CI[1]', 'CI[2]', 't_stats', 'cohen_d' ,'difference'};
fid = fopen(fileout1, 'a');
for row=1:length(myheader)
    fprintf(fid, '%s %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n', myheader{:,row});
end
fclose (fid)



dlmwrite(fileout1, mystats', 'delimiter', '\t', 'precision', '%10.8f', '-append','roffset', 1);
end
