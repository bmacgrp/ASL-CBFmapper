#!/bin/bash

# Estimating brain CBF from ASL
# Author: Guocheng Jiang from the Brad MacIntosh neuroimaging lab at Sunnybrook Research Institute
# Version: 2.6 (2024-06-25)
# 
# Update logs:
# v1.0  Mapping function for sequence 1 tested - pass
# v2.0  ROI Analysis module installed
#          RCAF dataset test run - pass
# v2.1  Fixed a bug which makes sequence 0 unable to predict GM/WM Average value
# v2.2  Fixed a bug that makes program unable to identify T1 image.
# v2.3  Added a custom mask input option, so if you have a T1 GM/WM mask, it is advised to use this
# v2.4  Fixed a bug leads to FAST stalls running on T1w images
# v2.5  Added instructions to the MultiPLD data processing.

###############################################################
# Command line inputs: 
###############################################################
Image_sequence=$1       # Select sequence ID for CBF Mapping
asl_img=$2     	        # ASL control-tag pairs
pdw_img=$3		        # ASL Proton-density image
T1=$4     		        # Specify the path of T1w for image segmentation. If you don't have this images enter "1" for bypassing.
			 # The software will use PDw image to estimate GM/WM mask. However, this will be less accurate!
			 # If you don't have T1 and use PDw image for estimation 
             # Always QC the outputs!
			 
tag_or_control=$5       # First image C/T? C-then-T=0, T-then-C=1
Need_bet=$6         	 # Need BET? N=0, Y=1
Output_dir=$7           # Specify output directory
Patient_name=$8         # Specify the ID/Initial of your data

# List of special sequences ID:
#    0  =  Siemens Prisma 3T direct compute
#          (Voxelwise calibration)
#    1  =  Siemens Prisma 3T Danny Wang Sequence (RCAF study)
#          (Voxelwise calibration)
#          (WM intensity correction as voxel value overexposure)     


Remove_temp_files=1    # Remove all non-necessary temp files? 
                        # (Keep all = 0, Remove all = 1)
                        
# Control Center for ASL information input:
# Notes: For EMBD1F Multi-PLD scans, bolus_time is different:
# Run on 2024-01-10: bolus_time = 0.7 or 1.2
# For RCAF study and Leducq study: Bolus_time = 1.5

bolus_time=1.5
PDw_TR=4.1
ATT=1.3
Tissue_T1=1.3
Blood_T1=1.65
Inversion_Efficiency=0.85

# Modify the following codes based on how many Control-Tag pairs have been collected
# Specify whether they have same PLD (i.e. TIs) values throughout
# e.g: 2 repeats ->  TIS="a,a"  RPTS="b,b"
# Default TIS: 3.3, Default repeat value = 1

TIS_asl="3.3,3.3,3.3,3.3,3.3,3.3,3.3"
RPTS_asl="1,1,1,1,1,1,1"

# TIS and RPTS setup for multiPLD ASL analysis: Uncomment before use
# TIS = Bolus + PLD = 0.7 + 1.5 = 2.2

# TIS_asl="2.2,2.2,2.2,2.2"
# RPTS_asl="1,1,1,1"


###############################################################
# Creating an output directory

echo "Creating a new folder to save output directory:" ${Output_dir}
mkdir ${Output_dir}


###############################################################
# A quick check on whether the command is valid:  

if [ ${Image_sequence} -gt 1 ]
then
    echo "Error: You entered an invalid sequence"
    exit 1
fi

if [[ $((Image_sequence)) != $Image_sequence ]]; then
    echo "Error: Please enter a number for sequence selection"
    exit 1
fi

echo "Analysing CBF for the following patient ID:" ${Patient_name}

###############################################################
# Step 1: Brain skull scripping
###############################################################
if [ ${Need_bet} -eq 1 ]
then
    echo "BET: Now removing skull for ASL and PDw images."
    bet ${asl_img} asl_brain.nii.gz -F -f 0.5 -g 0
    bet ${pdw_img} pdw_brain.nii.gz -f 0.5

fi


###############################################################
# Step 2.0: Create WM and GM masks if not specified
###############################################################

if [ ${T1} = "1" ]
then

    echo "FSL: Genearate GM/WM mask from PDw-image "
    echo "FSL: Caution: GM/WM mask estimate from PDw is not ideal. Use T1w image is preferred!"
    echo "FSL: Caution: Always check the GM/WM mask if you want to estimate it from PDw-image!"
    
    fast -o pdw_brain_wm -t 3 -n 3 -H 0.1 -I 4 -l 20.0 pdw_brain.nii.gz
    fslmaths pdw_brain_wm_pve_1 -thr 0.9 -bin CBF_WM_mask.nii.gz
    fslmaths pdw_brain_wm_pve_2 -thr 0.9 -bin CBF_GM_mask.nii.gz

else
    echo "FSL: Locating the T1w image and brain stripping"
    cp ${T1} T1w.nii.gz
    bet T1w.nii.gz T1w_brain.nii.gz  -f 0.5 -g 0
    
    echo "FSL: Registering the T1w image to the PDw image "
    flirt -in T1w_brain.nii.gz -ref pdw_brain.nii.gz -out T1w_brain_flirt -bins 256 -cost corratio -searchrx -180 180 -searchry -180 180 -searchrz -180 180 -dof 12  -interp trilinear
    
    echo "FSL: Now segmenting T1w images using FAST "
    fast -o T1w_brain_flirt -t 3 -n 3 -H 0.1 -I 4 -l 20.0 T1w_brain_flirt
    
    echo "FSL: Creating T1 segmentation of GM and WM "
    fslmaths T1w_brain_flirt_pve_2 -thr 0.9 -bin CBF_WM_mask.nii.gz
    fslmaths T1w_brain_flirt_pve_1 -thr 0.9 -bin CBF_GM_mask.nii.gz
  
	
fi


###############################################################
# Step 2.1a: Siemens Prisma 3T direct estimate
###############################################################


if [ ${Image_sequence} -eq 0 ]
then
    
    echo "Mode 0 selected: Siemens 3T pcASL direct estimate"
    cp pdw_brain.nii.gz pdw_calibration.nii.gz
    
    
    if [ ${Remove_temp_files} -eq 1 ]
	then
   	echo "Cleaning temp files"
   	rm asl_brain_mask.nii.gz
    fi
    

fi



#########################################################################
# Step 2.1b: The following is based on the shared ASL sequence 
# installed on a Siemens Prisma 3T. Credit Danny Wang in USC for sequence
# This method uses mean WM values to correct a problem in M0
# image which shows clusters of voxels at max-value (4096)
##########################################################################

if [ ${Image_sequence} -eq 1 ]
then
    echo "Mode 1 selected: Siemens Prisma 3T pcASL"

    echo "FSL: Normalizing the PDw images"
    fslmaths pdw_brain.nii.gz -inm 1 pdw_brain_norm.nii.gz
    
    echo "FSL: Calculating normalized mean WM intensity from PDw image"
    fslmaths pdw_brain_norm.nii.gz -mul CBF_WM_mask.nii.gz pdw_brain_norm_wm.nii.gz
    wmstats=`fslstats pdw_brain_norm_wm.nii.gz -M`

    echo "FSL: Applying WM correction on original PDw image"
    fslmaths pdw_brain.nii.gz -mul ${wmstats} pdw_calibration.nii.gz
    
    if [ ${Remove_temp_files} -eq 1 ]
	then
   	echo "Cleaning temp files"
   	rm asl_brain_mask.nii.gz
   	rm pdw_brain_norm.nii.gz
   	rm pdw_brain_norm_wm.nii.gz
   	rm pdw_brain_wm_*.nii.gz
    fi

fi


echo "Done"


###############################################################
# Step 3: Oxford_ASL CBF Estimation
# Apply Voxelwise calibration using PDw images
###############################################################


echo "Creating a brain mask for the oxasl analysis"
fslmaths pdw_calibration.nii.gz -bin pdw_mask.nii.gz

   

# Sequence selection and CBF Analysis

if [ ${tag_or_control} -eq 1 ]
then

    echo "Calling Oxford ASL for CBF analysis: ASL sequence is Tag then Control"

    oxford_asl -i asl_brain.nii.gz --iaf tc --ibf rpt --casl --bolus ${bolus_time} --rpts ${RPTS_asl} --tis ${TIS_asl} -c pdw_calibration.nii.gz --cmethod voxel --tr ${PDw_TR} --cgain 1 -o Oxasl_analysis -m pdw_mask.nii.gz --bat ${ATT} --t1 ${Tissue_T1} --t1b ${Blood_T1} --alpha ${Inversion_Efficiency} --spatial --fixbolus --mc --pvcorr --artoff


fi

if [ ${tag_or_control} -eq 0 ]
then

    echo "Calling Oxford ASL for CBF analysis: ASL sequence is Control then Tag"

    oxford_asl -i asl_brain.nii.gz --iaf ct --ibf rpt --casl --bolus ${bolus_time} --rpts ${RPTS_asl} --tis ${TIS_asl} -c pdw_calibration.nii.gz --cmethod voxel --tr ${PDw_TR} --cgain 1 -o Oxasl_analysis -m pdw_mask.nii.gz --bat ${ATT} --t1 ${Tissue_T1} --t1b ${Blood_T1} --alpha ${Inversion_Efficiency} --spatial --fixbolus --mc --pvcorr --artoff


fi


# Copying the file to the output directory

echo "Now Copying files to the output directory."
mkdir ${Output_dir}/${Patient_name}
cp asl_brain.nii.gz ${Output_dir}/${Patient_name}/asl_brain.nii.gz
cp CBF_WM_mask.nii.gz ${Output_dir}/${Patient_name}/WM_mask.nii.gz
cp CBF_GM_mask.nii.gz ${Output_dir}/${Patient_name}/GM_mask.nii.gz
cp pdw_brain.nii.gz ${Output_dir}/${Patient_name}/pdw_brain.nii.gz
cp Oxasl_analysis/calib/M0.nii.gz ${Output_dir}/${Patient_name}/M0.nii.gz
cp Oxasl_analysis/native_space/perfusion_calib.nii.gz ${Output_dir}/${Patient_name}/CBF_estimate.nii.gz
cp T1w_brain_flirt.nii.gz ${Output_dir}/${Patient_name}/T1.nii.gz


# Calculate mean GM and WM CBF
echo "Now calculating GM and WM CBF and write them into a csv file."

WM_mean=$(fslstats ${Output_dir}/${Patient_name}/CBF_estimate.nii.gz -k ${Output_dir}/${Patient_name}/WM_mask.nii.gz -M)
GM_mean=$(fslstats ${Output_dir}/${Patient_name}/CBF_estimate.nii.gz -k ${Output_dir}/${Patient_name}/GM_mask.nii.gz -M)

WM_median=$(fslstats ${Output_dir}/${Patient_name}/CBF_estimate.nii.gz -k ${Output_dir}/${Patient_name}/WM_mask.nii.gz -P 50)
GM_median=$(fslstats ${Output_dir}/${Patient_name}/CBF_estimate.nii.gz -k ${Output_dir}/${Patient_name}/GM_mask.nii.gz -P 50)

WM_size=$(fslstats ${Output_dir}/${Patient_name}/CBF_estimate.nii.gz -k ${Output_dir}/${Patient_name}/WM_mask.nii.gz -V)
GM_size=$(fslstats ${Output_dir}/${Patient_name}/CBF_estimate.nii.gz -k ${Output_dir}/${Patient_name}/GM_mask.nii.gz -V)

echo ${Patient_name},${WM_mean},${GM_mean},${WM_median},${GM_median},${WM_size},${GM_size} >> ${Output_dir}/CBF_Analysis_GM_WM.csv


# Cleaning files
if [ ${Remove_temp_files} -eq 1 ]
then
   echo "Cleaning temp files"
   rm -r Oxasl_analysis
   rm asl_brain.nii.gz
   rm pdw_brain.nii.gz
   rm pdw_calibration.nii.gz
   rm pdw_mask.nii.gz
   rm CBF_GM_mask.nii.gz
   rm CBF_WM_mask.nii.gz
   rm T1w_brain*
   rm T1w.nii.gz
fi

echo "Analysis is done for the following patient ID:", ${Patient_name}
