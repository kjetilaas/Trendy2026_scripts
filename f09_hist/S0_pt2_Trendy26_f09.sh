#!/bin/bash 

module load NRIS/CPU
module load Python/3.12.3-GCCcore-13.3.0 

#Scrip to clone, build and run NorESM

dosetup1=1 #do first part of setup
dosetup2=1 #do second part of setup (after first manual modifications)
dosetup3=1 #do second part of setup (after namelist manual modifications)
dosubmit=1 #do the submission stage
forcenewcase=1 #scurb all the old cases and start again

echo "setup1, setup2, setup3, submit, forcenewcase:", $dosetup1, $dosetup2, $dosetup3, $dosubmit, $forcenewcase

USER="kjetisaa"
project='nn9188k' #nn8057k: EMERALD, nn2806k: METOS, nn9188k: CICERO, nn9560k: NorESM (INES2), nn9039k: NorESM (UiB: Climate predition unit?), nn2345k: NorESM (EU projects)
machine='olivia'

#NorESM dir
noresmrepo="ctsm5.4.042_noresm_v3_Trendy26" 
noresmversion="ctsm5.4.042_noresm_v3"

resolution="f09_g17" #f19_g17, ne30pg3_tn14, f45_f45_mg37, ne16pg3_tn14 
casename="ihist.$resolution.$noresmrepo.T26_S0_pt2.`date +"%Y-%m-%d"`"
echo "casename: $casename"
compset="1850_DATM%TRENDY26_CLM60%FATES-NCFB%NORESM_SICE_SOCN_SROF_SGLC_SWAV_SESP"
startdate="1901-01-01" 
refcase=""


# aka where do you want the code and scripts to live?
workpath="/cluster/work/projects/nn9560k/$USER/" 

# some more derived path names to simplify scripts
scriptsdir=$workpath$noresmrepo/cime/scripts/

#case dir
casedir=$workpath$casename

#where are we now?
startdr=$(pwd)

#Download code and checkout externals
if [ $dosetup1 -eq 1 ] 
then
    cd $workpath

    pwd
    #go to repo, or checkout code
    if [[ -d "$noresmrepo" ]] 
    then
        cd $noresmrepo
        echo "Already have NorESM repo"
    else
        echo "Cloning NorESM"
        
        if [[ $noresmversion == ctsm* ]] ; then
            echo "Using CTSM version $noresmversion"
            git clone https://github.com/NorESMhub/CTSM/ $noresmrepo
        else
            echo "Using NorESM version $noresmversion"
            git clone https://github.com/NorESMhub/NorESM/ $noresmrepo
        fi
        cd $noresmrepo
        git checkout $noresmversion
#        sed -i 's/sci.1.92.5_api.46.0.0_nor_sci5_api2/sci.1.92.5_api.46.0.0_nor_sci6_api2/g' .gitmodules
#        echo "Updated .gitmodules to sci.1.92.5_api.46.0.0_nor_sci5_api2:"
#        grep -i -n 'sci.1.92.5_api.46.0.0_nor_sci5_api2' .gitmodules  
	./bin/git-fleximod update

	echo "Built model here: $workpath$noresmrepo"        

    fi
fi

#Make case
if [[ $dosetup2 -eq 1 ]] 
then
    cd $scriptsdir

    if [[ $forcenewcase -eq 1 ]]
    then 
        if [[ -d "$workpath$casename" ]] 
        then    
        echo "$workpath$casename exists on your filesystem. Removing it!"
        rm -rf /cluster/work/projects/nn9560k/kjetisaa/$casename
        rm -rf /cluster/work/projects/nn9560k/kjetisaa/noresm/$casename
        rm -rf /cluster/work/projects/nn9560k/kjetisaa/archive/$casename
        rm -r $casename
	fi
    fi
    if [[ -d "$workpath$casename" ]] 
    then    
        echo "$workpath$casename exists on your filesystem."
    else
        
        echo "making case:" $workpath$casename        
        ./create_newcase --case $workpath$casename --compset $compset --res $resolution --project $project --run-unsupported --mach $machine --compiler intel

        cd $workpath$casename
        #XML changes
        echo 'updating settings'        
        ./xmlchange DIN_LOC_ROOT_CLMFORC=/cluster/work/projects/nn9560k/inputdata/TRENDY2026/inputs/
        ./xmlchange RUN_STARTDATE=$startdate
        ./xmlchange STOP_OPTION=nyears
        ./xmlchange CLM_FORCE_COLDSTART=off
    	./xmlchange CLM_ACCELERATED_SPINUP=off
        ./xmlchange CCSM_CO2_PPMV=277.58
        ./xmlchange CLM_CO2_TYPE=constant        
        ./xmlchange DATM_YR_START=1901
        ./xmlchange DATM_YR_ALIGN=1901
        ./xmlchange DATM_YR_END=1920
        ./xmlchange DATM_PRESAERO=clim_1850         
    	./xmlchange STOP_N=25
        ./xmlchange RESUBMIT=4
        ./xmlchange --subgroup case.run JOB_WALLCLOCK_TIME=48:00:00
        ./xmlchange --subgroup case.st_archive JOB_WALLCLOCK_TIME=00:30:00        

        ./xmlchange NTASKS_CPL=2048
        ./xmlchange NTASKS_ATM=256
        ./xmlchange NTASKS_LND=2048
        ./xmlchange ROOTPE_CPL=256
        ./xmlchange ROOTPE_ATM=0
        ./xmlchange ROOTPE_LND=256   

        echo 'done with xmlchanges'        
        
        ./case.setup
        echo ' '
        echo "Done with Setup. Update namelists in $workpath$casename/user_nl_*"

        #Add following lines to user_nl_clm   
cat <<EOF >> user_nl_clm
fates_paramfile = '/cluster/work/projects/nn9560k/jessica/smort_param_files/fates_params_noresm_c260615_vhsmort_increasebmort.json'
finidat='/cluster/work/projects/nn9188k/kjetisaa/archive/ihist.f09_g17.ctsm5.4.042_noresm_v3_Trendy26.T26_S0_pt1.2026-08-17/rest/1901-01-01-00000/ihist.f09_g17.ctsm5.4.042_noresm_v3_Trendy26.T26_S0_pt1.2026-08-17.clm2.r.1901-01-01-00000.nc'
use_fates_luh = .true.
use_fates_lupft = .true.
fates_harvest_mode = 'luhdata_area'
use_fates_potentialveg = .false.
fluh_timeseries = '/cluster/work/projects/nn9560k/inputdata/kjetisaa/TRENDY26_LU_FATES/LUH3_1700_steadystate_0.9x1.25_c2026-08-04.nc'                        
flandusepftdat = '/cluster/work/projects/nn9560k/inputdata/kjetisaa/TRENDY26_LU_FATES/fates_landuse_pft_surfdata_0.9x1.25_c260803.nc'
hist_fincl1 = 'FATES_LITTER_BG_CWD_EL', 'FATES_VEGC_PF', 'FATES_STRUCTC', 'FATES_CROWNAREA_PF', 'TOTSOMC', 'TOTLITC', 'TOT_WOODPRODC', 'CROPPROD1C'
EOF

    fi
fi

#Build case case
if [[ $dosetup3 -eq 1 ]] 
then
    cd $workpath$casename
    echo "Currently in" $(pwd)
    ./case.build
    echo ' '    
    echo "Done with Build"


    # copy restart files and pointers
    #echo "copied restart files and pointers"
    
fi

#Submit job
if [[ $dosubmit -eq 1 ]] 
then
    cd $workpath$casename
    ./case.submit
    echo " "
    echo 'done submitting'       
fi

#After it has finised:
# - copy to NIRD: https://noresm-docs.readthedocs.io/en/noresm2/output/archive_output.html
# - run land diag: https://github.com/NorESMhub/xesmf_clm_fates_diagnostic 
    # python run_diagnostic_full_from_terminal.py /nird/datalake/NS9560K/kjetisaa/i1850.FATES-NOCOMP-coldstart.ne30pg3_tn14.alpha08d.20250130/lnd/hist/ pamfile=short_nocomp.json outpath=/datalake/NS9560K/www/diagnostics/noresm/kjetisaa/
#Useful commands: 
# - cdo -fldmean -mergetime -apply,selvar,FATES_GPP,TOTSOMC,TLAI,TWS,TOTECOSYSC [ n1850.FATES-NOCOMP-AD.ne30_tn14.alpha08d.20250127_fixFincl1.clm2.h0.00* ] simple_mean_of_gridcells.nc
