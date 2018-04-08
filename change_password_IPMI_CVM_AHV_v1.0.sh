#!/bin/bash

#description    :Nutanix password change bash script to be run from one of the CVMs in a configured cluster 
# after initial cluster config completed. Assume IPMI default password "ADMIN" howerver can be changed on line 12. 
#author         :Askar Sattar
#updated        :2017-09-20
#version        :1.0    
#notes          :


#IPMI define current password
ipmioldpwd=ADMIN
#echo "Enter cluster Virtual IP address or hostname: "
#read cvip
echo "Enter cluster 'nutanix' user password (default nutnaix/4u): "
read nutanix_pwd
if [ -z "$nutanix_pwd" ]; then
	nutanix_pwd=nutanix/4u
    echo "Nutanix default password $nutanix_pwd"
fi

#Variables not defined for ESX or CVM password and are set static below 

clear
selection=
until [ "$selection" = "e" ]; do

echo -e "\033[32m"
echo ""
echo  "Nutanix Change Passwords script"
echo "1 - Change all IPMI (ADMIN user) Passwords in Nutanix Cluster"
echo "2 - Change all AHV hypervisor (root user) Passwords in Nutanix Cluster"
echo "3 - Change all CVM (nutanix user) Passwords in Nutanix Cluster"
echo ""
echo ""
echo "q - Exit Utility"
echo ""
echo -n "Enter Selection: "
read selection
echo ""
case $selection in


1 )
#IPMI define New Password
echo "IPMI new password: " 
read ipminewpwd
echo ""

#read -p "Enter current IPMI password: " ipmioldpwd;
#read -p "Verify current IPMI password: " ipmioldpwd;
#while [ "ipmioldpwd" != "$ipmioldpwd" ]; do 
#read -p "Password missmatch, try again:" ipmioldpwd;
#read -p "Enter new IPMI password: " ipminewpwd;

#Define function to generate list of IPMI IPs
ntnx-ipmi(){
#ssh nutanix@$cvip 'ncli host list | grep -w "IPMI Address" | awk {'print $4'};'
ncli host list | grep -w "IPMI Address" | awk {'print $4'};
}

#Define function generate list of Host IPs

hostips(){
#ssh nutanix@cvip "ncli host list | grep -w "Hypervisor Address" | awk {'print $4'};""
ncli host list | grep -w "Hypervisor Address" | awk {'print $4'};
}

#Use IPMI tool to change password from each AHV host
#The "Close Session command failed" output is expected after change completes
for s in `hostips`; do ssh root@$s "ipmitool user set password 2 $ipminewpwd"; done ;;
#Update zeus config with new password
#for h in `ntnx-hostips`; do ncli host edit id=$h ipmi-password=$ipminewpwd; done ;;


2 )
#AHV define New Root user Password
echo "AHV new root password: " 
read ahvnewpwd
echo ""

#Change all AHV hosts passwords in Nutanix cluster for the user root 
#First define a variable that will establish an SSH session as the root user
#When the SSH connection is establsihed an echo command is run that updates the passwords
#for e in `hostips`; do echo AHV host $e && ssh root@$e 'echo "nutanix/4u" | passwd --stdin'; done ;;
for i in `hostips`; do echo "AHV host --$i--";ssh root@$i "echo -e '$ahvnewpwd\n$ahvnewpwd' | passwd";done ;;


3 )
#CVM define New nutanix user Password
echo "CVM new nutanix user password: " 
read nutanixnewpwd
echo ""

#Change all CVM passwords in Nutanix cluster for the user nutanix
#First define a variable that will establish an SSH session as the nutanix user
#When the SSH connection is establsihed an echo command is run that updates the passwords
#Note sudo is used here because only root is allowed to run the command. 
for c in `svmips`; do echo CVM $c && ssh $c "echo "$nutanixnewpwd" | sudo passwd --stdin nutanix";done ;;


q )
echo -q "\033[0m" 
clear
exit ;;
        * ) echo "Please select option"
        esac
done
