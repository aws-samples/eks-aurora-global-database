#!/bin/bash

REGION1=us-east-2
REGION2=us-west-2
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

kubectl delete ingress,services,deployments,statefulsets -n retailapp --all

kubectl delete ns retailapp --cascade=true

eksctl delete iamserviceaccount --name aws-load-balancer-controller --cluster eksclu --namespace kube-system --region $REGION1

aws iam get-roles 
eksctl delete cluster --name eksclu -r ${REGION1} --force -w
eksctl delete cluster --name eksclu -r ${REGION2} --force -w

aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/k8s-asg-policy

VPCID1=$(aws cloudformation describe-stacks --stack-name EKSGDB1 --region ${REGION1} --query 'Stacks[].Outputs[?(OutputKey == `VPC`)][].{OutputValue:OutputValue}' --output text)
CIDR1=$(aws ec2 describe-vpcs --vpc-ids "${VPCID1}" --region ${REGION1} --query 'Vpcs[].CidrBlock' --output text)
VPCID2=$(aws cloudformation describe-stacks --stack-name EKSGDB1 --region ${REGION2} --query 'Stacks[].Outputs[?(OutputKey == `VPC`)][].{OutputValue:OutputValue}' --output text)
CIDR2=$(aws ec2 describe-vpcs --vpc-ids "${VPCID2}" --region ${REGION2} --query 'Vpcs[].CidrBlock' --output text)

VPCPEERID=$(aws ec2 describe-vpc-peering-connections --region ${REGION1} --query "VpcPeeringConnections[?(RequesterVpcInfo.VpcId == '${VPCID1}')].VpcPeeringConnectionId" --output text)

aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id ${VPCPEERID} --region ${REGION1}
aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id ${VPCPEERID} --region ${REGION2}

# delete ECR Repos
for REGION in $REGION1 $REGION2
do
aws ecr delete-repository  --repository-name retailapp/kart --force --region $REGION
aws ecr delete-repository  --repository-name retailapp/order --force --region $REGION
aws ecr delete-repository  --repository-name retailapp/pgbouncer --force --region $REGION
aws ecr delete-repository  --repository-name retailapp/product --force --region $REGION
aws ecr delete-repository  --repository-name retailapp/user --force --region $REGION
aws ecr delete-repository  --repository-name retailapp/webapp --force --region $REGION
done

#delete global accelerator
#aws globalaccelerator  delete-accelerator --accelerator-arn arn:aws:globalaccelerator::${AWS_ACCOUNT_ID}:accelerator/e73dde04-0041-4aec-8a81-0ed3421b71f0

aws cloudformation delete-stack --stack-name EKSGDB2 --region ${REGION2}
# delete IAM roles EKSGDB1-C9Role%
# delete InstanceProfiles EKSGDB1-C9InstanceProfile%

aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerAdditionalIAMPolicy
aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy

aws cloudformation delete-stack --stack-name EKSGDB1 --region ${REGION2}
aws cloudformation delete-stack --stack-name EKSGDB1 --region ${REGION1}
