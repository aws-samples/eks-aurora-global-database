#!/bin/bash

REGION1=us-east-2
REGION2=us-west-2

kubectl delete ingress,services,deployments,statefulsets -n octank --all

kubectl delete ns octank --cascade=true

eksctl delete iamserviceaccount --name aws-load-balancer-controller --cluster eksgdbclu --namespace kube-system --region $AWS_REGION  

aws iam get-roles 
eksctl delete cluster --name eksgdbclu -r ${REGION1} --force -w
eksctl delete cluster --name eksgdbclu -r ${REGION2} --force -w

aws efs delete-file-system --file-system-id=EFS_VOLUME_ID

aws iam delete-policy k8s-asg-policy

VPCID1=$(aws cloudformation describe-stacks --stack-name EKSGDB1 --region ${REGION1} --query 'Stacks[].Outputs[?(OutputKey == `VPC`)][].{OutputValue:OutputValue}' --output text)
CIDR1=$(aws ec2 describe-vpcs --vpc-ids "${VPCID1}" --region ${REGION1} --query 'Vpcs[].CidrBlock' --output text)
VPCID2=$(aws cloudformation describe-stacks --stack-name EKSGDB1 --region ${REGION2} --query 'Stacks[].Outputs[?(OutputKey == `VPC`)][].{OutputValue:OutputValue}' --output text)
CIDR2=$(aws ec2 describe-vpcs --vpc-ids "${VPCID2}" --region ${REGION2} --query 'Vpcs[].CidrBlock' --output text)

VPCPEERID=$(aws ec2 describe-vpc-peering-connections --region ${REGION1} --query "VpcPeeringConnections[?(RequesterVpcInfo.VpcId == '${VPCID1}')].VpcPeeringConnectionId" --output text)

aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id ${VPCPEERID} --region ${REGION1}
aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id ${VPCPEERID} --region ${REGION2}

aws cloudformation delete-stack --stack-name EKSGDB2 --region ${REGION2}
# delete IAM role Cloud9DevIAMRole
# delete InstanceProfile cloud9InstanceProfile
# delete policy AWSLoadBalancerControllerAdditionalIAMPolicy
# delete policy AWSLoadBalancerControllerIAMPolicy

aws cloudformation delete-stack --stack-name EKSGDB1 --region ${REGION2}
aws cloudformation delete-stack --stack-name EKSGDB1 --region ${REGION1}
