#!/bin/bash
#SBATCH --job-name=meld-ae
#SBATCH --partition gpu_amber
#SBATCH --nodes=1
#SBATCH --gres=gpu:2080:8
#SBATCH --ntasks=8
#SBATCH --output=job_logs/slurm.out
#SBATCH --error=job_logs/slurm.err
#SBATCH --time=12:00:00

module load amber cuda12.2 openmpi

TOTAL_X=10

if [ -z "$( ls -A 'rep_segs' )" ]; then
    if [ -s meld.log ]; then
	rm meld.log
    fi
    echo "Beginning a new MELD simulation." >> meld.log
    X=0
else
    X=$(ls rep_segs | tail -n 1 | sed "s/^0*//")
    X_LST=$(ls rep_segs | tail -n 1)
    if [ -s meld.log ]; then
        mv meld.log rep_segs/$X_LST
    fi
    echo "Continuing an existing MELD simulation." >> meld.log
    echo "The old meld.log was moved to rep_segs/$X_LST." >> meld.log

    if [ -s rep_segs/$X_LST/rem.log ]; then
        let X+=1
    else
        echo "The most recent exchange failed. Repeating..." >> meld.log
        rm -r rep_segs/$X_LST
    fi
fi

while [ $X -lt $TOTAL_X ]; do

    X_PRV=`printf "%05d" $X`
    let X+=1
    X_FMT=`printf "%05d" $X`

    echo "Starting exchange $X at `date "+%Y-%m-%d %H:%M:%S"`." >> meld.log

    if [ ! -d rep_segs/$X_FMT ]; then
        mkdir rep_segs/$X_FMT
    fi

    cd rep_segs/$X_FMT

    cp ../../common_files/REST .

    if (( X == 1 )); then 
        COUNT=0
        for TEMP in `cat ../../common_files/ladder | awk {'print $1'}`; do
            let COUNT+=1
            REP=`printf "%03d" $COUNT`
            sed "s/XXXXX/$TEMP/g" ../../common_files/meld.in > meld.in.$REP
            echo "-O -rem 1 -remlog rem.log -i meld.in.$REP -o meld.out.$REP -c ../../bstates/eq.rst.$REP -r meld.rst.$REP -x meld.nc.$REP -p ../../common_files/4ake.prmtop" >> meld.groupfile
  
        done
    else
        COUNT=0
        for TEMP in `cat ../../common_files/ladder | awk {'print $1'}`; do
            let COUNT+=1
            REP=`printf "%03d" $COUNT`
            echo "-O -rem 1 -remlog rem.log -i ../00001/meld.in.$REP -o meld.out.$REP -c ../$X_PRV/meld.rst.$REP -r meld.rst.$REP -x meld.nc.$REP -p ../../common_files/4ake.prmtop" >> meld.groupfile
	done
    fi

    mpirun -np 8 pmemd.cuda.MPI -ng 8 -groupfile meld.groupfile
    
    if [ -s rem.log ]; then
        echo "Successfully completed exchange." >> ../../meld.log
    else
        echo "Failed to complete exchange. Shutting down..." >> ../../meld.log
	exit
    fi

    cd ../../

done

echo "The MELD simulation completed successfully." >> meld.log
