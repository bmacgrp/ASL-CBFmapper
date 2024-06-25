#!/bin/bash

# CBFmapper: Estimating brain CBF from ASL based on multiple PLD data
# Author: Guocheng Jiang from the Brad MacIntosh neuroimaging lab at Sunnybrook Research Institute

# Update logs:
# Jan 30th 2024: V1.0 released, the script generates CBF, ATT, and aCBV maps
# CBF = cerebral blood flow; ATT = arterial transit time; aCBV = arterial cerebral blood volume

# User command line inputs:
# To use this script: bash CBFmapper_MultiPLD_Siemens.sh - path of the analysis directory of raw DICOM image - 
# Input: raw DICOM image from PCASL sequence of a Siemens MRI scanner.
# Output: Model based estimates for CBF, ATT, and aCBV.


# 1. The path of analysis directory
path=$1

######################################################################################
# Control panel: input the required variables:

TC_Mark="tc"               # Input "tc" if 1st image is tag, and "ct" if 1st image is control.
Bolus_time=1.6             # bolus time (units: seconds)
TR_PDw=4.21                # repetition time for the ASL reference scan (units: seconds)
T1_tissue=1.3              # literature value for T1 recovery of grey matter tissue (units: seconds)
T1_blood=1.65              # literature value for T1 recovery of arterial blood water (units: seconds)
Inversion_efficiency=0.85  # assumed inversion efficiency for pcASL

# Design matrix for the ASL timeseries:
repeats="2,2,2,2,2"
TISs="3.4,2.2,3.7,2.8,1.8"

# Tutorial: For example, we have 3 PLD, each PLD have two repeats:
#           For your ASL image sequence: PLD1(T,C,T,C); PLD2(T,C,T,C); PLD3(T,C,T,C)
#
# First input the repeat number matrix:
#                      repeats="2,2,2"  (2 repeats for each PLD)
#
# Then for the TIS calculation:
#                      TIS = PLD + label duration
#                 e.g. TIS1 = 1.8 sec + 1.6 sec = 3.4 sec for first PLD
#                      TIS2 = 1.0 sec + 1.6 sec = 2.6 sec for 2nd PLD
#                      TIS3 = 0.2 sec + 1.6 sec = 1.8 sec for 3rd PLD
#
# Finally input your TISs matrix:
#                      TISs="3.4,2.6,1.8"


# Switches: Yes/ON = 1,  No/OFF = 0.
Need_anat=1   # Do you need anatomical preprocessing?


######################################################################################
# End of the control panel.
######################################################################################

# Step 1: Convert the DICOM image to the NIFTI format
echo "Now converting DICOM images to NIFTI."
dcm2niix ${path}/*

# Step 2: Split the image and move the calibration image out:

echo "[1/7] Now identifying the ASL images."
mkdir ${path}/asl_preprocessing
cp ${path}/*.nii ${path}/asl_preprocessing/ASL_raw.nii
cp ${path}/*.json ${path}/asl_preprocessing/ASL_config.json

# Step 3: Split the tag-control pairs and the PDw images:
echo "[2/7] Now ordering ASL timeseries."
fslsplit ${path}/asl_preprocessing/ASL_raw.nii.gz ${path}/asl_preprocessing/ -t

# Step 3.1: Rename the image files:
echo "[3/7] Now identifying PDw images. "
file=0
index=0
new_name=0

for file in [0-9][0-9][0-9][0-9].nii.gz; do
  new_name="${index}.nii.gz"
  mv "${path}/asl_preprocessing/${file}" "${path}/asl_preprocessing/${new_name}"
  ((index++))
  
 done

# Step 3.2: Rename the ASL-PDw image
echo "[4/7] PDw image has been identified. "
mv ${path}/asl_preprocessing/0000.nii.gz ${path}/asl_preprocessing/PDw.nii.gz
rm ${path}/asl_preprocessing/0001.nii.gz

# Step 3.3 Merge the ASL tag-control pairs.
echo "[5/7] ASL Tag-control pairs has been merged. "
fslmerge -t ${path}/asl_preprocessing/merged_tag_control_pairs.nii.gz ${path}/asl_preprocessing/00*.nii.gz

# Step 3.4a Optional BET: Remove skull and eye

if [ ${Need_anat} -eq 1 ]
then

   # Skull stripping
   echo "[6/7] Now perform brain stripping using BET."
   bet ${path}/asl_preprocessing/merged_tag_control_pairs.nii.gz ${path}/asl_preprocessing/merged_tag_control_pairs_brain.nii.gz -F -f 0.5 -g 0
   bet ${path}/asl_preprocessing/PDw.nii.gz ${path}/asl_preprocessing/PDw_brain.nii.gz -f 0.5 -g 0 
   
   # CBF analyis
   echo "[7/7] Now perform CBF estimation using BASIL."
   oxford_asl -i ${path}/asl_preprocessing/merged_tag_control_pairs_brain.nii.gz --iaf ${TC_Mark} --ibf tis --casl --bolus ${Bolus_time} --rpts ${repeats} --tis ${TISs} -c ${path}/asl_preprocessing/PDw_brain.nii.gz --cmethod voxel --tr ${TR_PDw} --cgain 1 -o ${path}/MultiPLD_CBF_Analysis_Output --bat 1.3 --t1 ${T1_tissue} --t1b ${T1_blood} --alpha ${Inversion_efficiency} --spatial --fixbolus --mc
   
   
   
fi

if [ ${Need_anat} -eq 0 ]
then

# Step 3.4b Calculate the CBF without BET:

echo "[6/7] -- Anatomical preprocessing has been switched off -- "
echo "[7/7] Now perform CBF estimation using BASIL."
oxford_asl -i ${path}/asl_preprocessing/merged_tag_control_pairs.nii.gz --iaf ${TC_Mark} --ibf tis --casl --bolus ${Bolus_time} --rpts ${repeats} --tis ${TISs} -c ${path}/asl_preprocessing/PDw.nii.gz --cmethod voxel --tr ${TR_PDw} --cgain 1 -o ${path}/MultiPLD_CBF_Analysis_Output --bat 1.3 --t1 ${T1_tissue} --t1b ${T1_blood} --alpha ${Inversion_efficiency} --spatial --fixbolus --mc 
   
fi
