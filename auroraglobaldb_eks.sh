#!/bin/sh

function print_line()
{
    echo "---------------------------------"
}

function install_jq()
{
    sudo yum install -y jq  > ${TERM1} 2>&1

}

function install_packages()
{
    print_line
    echo "Installing aws cli v2"
    print_line
    current_dir=`pwd`
    aws --version | grep aws-cli\/2 > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        cd $current_dir
	return
    fi
    cd /tmp
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" > ${TERM1} 2>&1
    unzip -o awscliv2.zip > ${TERM1} 2>&1
    sudo ./aws/install --update > ${TERM1} 2>&1
    cd $current_dir
}

function install_k8s_utilities()
{
    print_line
    echo "Installing Kubectl"
    print_line
    sudo curl -o /usr/local/bin/kubectl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"  > ${TERM1} 2>&1
    sudo chmod +x /usr/local/bin/kubectl > ${TERM1} 2>&1
    print_line
    echo "Installing eksctl"
    print_line
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp > ${TERM1} 2>&1
    sudo mv /tmp/eksctl /usr/local/bin
    sudo chmod +x /usr/local/bin/eksctl
    print_line
    echo "Installing helm"
    print_line
    curl -s https://fluxcd.io/install.sh | sudo bash > ${TERM1} 2>&1
    curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash > ${TERM1} 2>&1

}

function install_postgresql()
{
    print_line
    echo "Installing Postgresql client"
    print_line
    sudo amazon-linux-extras install -y postgresql13 > ${TERM1} 2>&1
    sudo yum -y install postgresql-contrib postgresql-devel
}


function update_kubeconfig()
{
    print_line
    echo "Updating kubeconfig"
    print_line
    aws eks update-kubeconfig --name ${EKS_CLUSTER_NAME}
}


function chk_installation()
{ 
    print_line
    echo "Checking the current installation"
    print_line
    for command in kubectl aws eksctl flux helm jq
    do
        which $command &>${TERM} && echo "$command present" || echo "$command NOT FOUND"
    done

}


function chk_cloud9_permission()
{
    print_line
    echo "Fixing the cloud9 permission"
    print_line
    aws sts get-caller-identity | grep ${INSTANCE_ROLE}  
    if [ $? -ne 0 ] ; then
	echo "Fixing the cloud9 permission"
        environment_id=`aws ec2 describe-instances --region ${AWS_REGION} --instance-id $(curl -s http://169.254.169.254/latest/meta-data/instance-id) --query "Reservations[*].Instances[*].Tags[?Key=='aws:cloud9:environment'].Value" --output text`
        aws cloud9 update-environment --environment-id ${environment_id} --region ${AWS_REGION} --managed-credentials-action DISABLE
	sleep 10
        ls -l $HOME/.aws/credentials > /dev/null 2>&1
        if [ $? -eq 0 ] ; then
             echo "!!! Credentials file exists"
        else
            echo "Credentials file does not exists"
        fi
	echo "After fixing the credentials. Current role"
        aws sts get-caller-identity | grep ${INSTANCE_ROLE} > /dev/null
        if [ $? -eq 0 ]; then
            echo "Permission set properly for the cloud9 environment"
        else
            echo "!!! Permission not set properly for the cloud9 environment"
            aws sts get-caller-identity
            exit 1
        fi
    fi
}

function create_eks_cluster()
{
    print_line
    echo "Creatingn EKS cluster"
    print_line
    typeset -i counter
    counter=0
    echo "aws cloudformation  create-stack --stack-name ${EKS_STACK_NAME} --parameters ParameterKey=VPC,ParameterValue=${vpcid} ParameterKey=SubnetAPrivate,ParameterValue=${subnetA} ParameterKey=SubnetBPrivate,ParameterValue=${subnetB} ParameterKey=SubnetCPrivate,ParameterValue=${subnetC} --template-body file://${EKS_CFN_FILE} --capabilities CAPABILITY_IAM"
    aws cloudformation  create-stack --stack-name ${EKS_STACK_NAME} --parameters ParameterKey=VPC,ParameterValue=${vpcid} ParameterKey=SubnetAPrivate,ParameterValue=${subnetA} ParameterKey=SubnetBPrivate,ParameterValue=${subnetB} ParameterKey=SubnetCPrivate,ParameterValue=${subnetC} --template-body file://${EKS_CFN_FILE} --capabilities CAPABILITY_IAM
    sleep 60
    # Checking to make sure the cloudformation completes before continuing
    while  [ $counter -lt 100 ]
    do
        STATUS=`aws cloudformation describe-stacks --stack-name ${EKS_STACK_NAME} --query  Stacks[0].StackStatus`
	echo ${STATUS} |  grep CREATE_IN_PROGRESS  > /dev/null 
	if [ $? -eq 0 ] ; then
	    echo "EKS cluster Stack creation is in progress ${STATUS}... waiting"
	    sleep 60
	else
	    echo "EKS cluster Stack creation status is ${STATUS} breaking the loop"
	    break
	fi
    done
    echo ${STATUS} |  grep CREATE_COMPLETE  > /dev/null 
    if [ $? -eq 0 ] ; then
       echo "EKS cluster Stack creation completed successfully"
    else
       echo "EKS cluster Stack creation failed with status ${STATUS}.. exiting"
       exit 1 
    fi
    print_line
}

function update_config()
{
    print_line
    echo "Updating kubectl config" 
    print_line
    aws eks update-kubeconfig --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION}
    print_line
}

function update_eks()
{
    print_line
    echo "Enabling clusters to use iam oidc"
    print_line
    eksctl utils associate-iam-oidc-provider --cluster ${EKS_CLUSTER_NAME} --region ${AWS_REGION} --approve
    print_line
}


function install_loadbalancer()
{
    print_line
    echo "Installing load balancer"
    print_line

    eksctl create iamserviceaccount \
     --cluster=${EKS_CLUSTER_NAME} \
     --namespace=${EKS_NAMESPACE} \
     --name=aws-load-balancer-controller \
     --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
     --override-existing-serviceaccounts \
     --approve

    kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
    helm repo add eks https://aws.github.io/eks-charts

    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
     --set clusterName=${EKS_CLUSTER_NAME} \
     --set serviceAccount.create=false \
     --set region=${AWS_REGION} \
     --set vpcId=${VPCID} \
     --set serviceAccount.name=aws-load-balancer-controller \
     -n ${EKS_NAMESPACE}

}


function wait_for_stack_to_complete() 
{
   stackname=${1}
   region=${2}
   while [[ true ]]; do
     status=$(aws cloudformation describe-stacks --region ${region} --query "Stacks[?(StackName == '${stackname}')].StackStatus" --output text)
     if [[ "${status}" == "CREATE_COMPLETE" ]]; then
        echo "Stack ${stackname} on region ${region} completed (${status})"
        return
     fi
     sleep 60
   done
}


function deploy_vpc_c9()
{

    print_line
    echo "Deploying VPC and C9 environment"
    print_line

    aws cloudformation create-stack \
         --stack-name EKSGDB1 \
         --disable-rollback \
         --template-body file://${CFN_VPC_C9} \
         --tags Key=Environment,Value=EKSGDB \
         --timeout-in-minutes=30 \
         --region ${REGION1} \
         --capabilities "CAPABILITY_IAM" \
         --parameters ParameterKey=DeployAurora,ParameterValue=true ParameterKey=ClassB,ParameterValue=40

    if [[ $? -ne 0 ]]; then
        echo "Stack aurora_vpc_region.yaml, EKSGDB1 failed to deploy on region ${REGION1}, Please check/fix the error and retry"
        exit 1
    fi

    aws cloudformation create-stack \
         --stack-name EKSGDB1 \
         --disable-rollback \
         --template-body file://${CFN_VPC_C9} \
         --tags Key=Environment,Value=EKSGDB \
         --timeout-in-minutes=30 \
         --region ${REGION2} \
         --capabilities "CAPABILITY_IAM" \
         --parameters ParameterKey=DeployAurora,ParameterValue=false ParameterKey=ClassB,ParameterValue=50

    if [[ $? -ne 0 ]]; then
        echo "Stack aurora_vpc_region.yaml, EKSGDB1 failed to deploy on region ${REGION2}, Please check/fix the error and retry"
        exit 1
    fi

    wait_for_stack_to_complete "EKSGDB1" "${REGION1}"
    wait_for_stack_to_complete "EKSGDB1" "${REGION2}"

    aws cloudformation create-stack \
      --stack-name EKSGDB2 \
      --template-body file://${CFN_AURORADB} \
      --tags Key=Environment,Value=EKSGDB \
      --timeout-in-minutes=30  \
      --region ${REGION2}

    if [[ $? -ne 0 ]]; then
        echo "Stack aurora_gdb.yaml, EKSGDB2 failed to deploy on region ${REGION1}, Please check/fix the error and retry"
        exit 1
    fi

    wait_for_stack_to_complete "EKSGDB2" "${REGION2}"

    echo "Completed deloying the CloudFormation Stacks on regions us-east-2 and ${REGION2}"
    print_line

}


function update_routes()
{
    print_line
    echo "Creating VPC peering between the region"
    print_line

    VPCID1=$(aws cloudformation describe-stacks --stack-name EKSGDB1 --region ${REGION1} --query 'Stacks[].Outputs[?(OutputKey == `VPC`)][].{OutputValue:OutputValue}' --output text)
    CIDR1=$(aws ec2 describe-vpcs --vpc-ids "${VPCID1}" --region ${REGION1} --query 'Vpcs[].CidrBlock' --output text)
    VPCID2=$(aws cloudformation describe-stacks --stack-name EKSGDB1 --region ${REGION2} --query 'Stacks[].Outputs[?(OutputKey == `VPC`)][].{OutputValue:OutputValue}' --output text)
    CIDR2=$(aws ec2 describe-vpcs --vpc-ids "${VPCID2}" --region ${REGION2} --query 'Vpcs[].CidrBlock' --output text)

    aws ec2 create-vpc-peering-connection \
    --peer-vpc-id ${VPCID2} --vpc-id ${VPCID1} \
    --region ${REGION1} \
    --peer-region ${REGION2}

    VPCPEERID=$(aws ec2 describe-vpc-peering-connections --region ${REGION1} --query "VpcPeeringConnections[?(RequesterVpcInfo.VpcId == '${VPCID1}')].VpcPeeringConnectionId" --output text)
    sleep 30 
    aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id ${VPCPEERID} --region ${REGION2}

    query="RouteTables[?(VpcId == '${VPCID1}')].RouteTableId"
    rtidlist=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=${VPCID1} --region ${REGION1} --query "$query" --output text)
    for rtid in $rtidlist
    do
        aws ec2 create-route --region ${REGION1} \
        --destination-cidr-block ${CIDR2} \
        --route-table-id ${rtid} \
        --vpc-peering-connection-id ${VPCPEERID}
    done

    query="RouteTables[?(VpcId == '${VPCID2}')].RouteTableId"
    rtidlist=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=${VPCID2} --region ${REGION2} --query "$query" --output text)
    for rtid in $rtidlist
    do
        aws ec2 create-route --region ${REGION2} \
        --destination-cidr-block ${CIDR1} \
        --route-table-id ${rtid} \
        --vpc-peering-connection-id ${VPCPEERID}
    done

    ## Update Aurora Cluster security group to allow connectivity between regions
    SG1=$(aws rds describe-db-clusters --region $REGION1 --query 'DBClusters[?(DBClusterIdentifier == `adbtest`)].VpcSecurityGroups[].VpcSecurityGroupId' --output text)
    aws ec2 authorize-security-group-ingress \
      --group-id ${SG1} \
      --ip-permissions IpProtocol=tcp,FromPort=5432,ToPort=5432,IpRanges=[{CidrIp=${CIDR2}}] \
      --region ${REGION1}

    SG2=$(aws rds describe-db-clusters --region $REGION2 --query 'DBClusters[?(DBClusterIdentifier == `adbtest`)].VpcSecurityGroups[].VpcSecurityGroupId' --output text)
    aws ec2 authorize-security-group-ingress \
      --group-id ${SG2} \
      --ip-permissions IpProtocol=tcp,FromPort=5432,ToPort=5432,IpRanges=[{CidrIp=${CIDR1}}] \
      --region ${REGION2}

   print_line
}

function install_retailapp()
{
    sed -e "s/%AWS_ACCOUNT_ID%/$AWS_ACCOUNT_ID/g" -e "s/%AWS_REGION%/$AWS_REGION/g"  ${RETAILAPP_K8S} > ${RETAILAPP_K8S_REGION}
    kubectl apply -f ${RETAILAPP_K8S_REGION}

}

function install_pgbouncer()
{

    export PGB_K8S=pgbouncer/pgbouncer_kubernetes.yaml
    export PGB_APP=retailapp/pgbouncer_kubernetes.yaml
    export PGB_USERLIST=/tmp/userlist.txt
    export PGB_CONF=/tmp/pgbouncer.ini

    roendpoint=$(aws rds describe-db-clusters --region ${AWS_REGION} --query 'DBClusters[?(TagList[?(Key == `Application` && Value == `EKSAURGDB`)])].ReaderEndpoint' --output text)
    replicaSourceArn=$(aws rds describe-db-clusters --region ${AWS_REGION} --query 'DBClusters[?(TagList[?(Key == `Application` && Value == `EKSAURGDB`)])].ReplicationSourceIdentifier' --output text)

    runscript=0

    if [[ -z "${replicaSourceArn}" ]]; then
        rwendpoint=$(aws rds describe-db-clusters --region ${AWS_REGION} --query 'DBClusters[?(TagList[?(Key == `Application` && Value == `EKSAURGDB`)])].Endpoint' --output text)
    else
        runscript=1
        rwregion=`echo $replicaSourceArn |awk -F: '{print $4}'`
        rwendpoint=$(aws rds describe-db-clusters --region ${rwregion} --query 'DBClusters[?(TagList[?(Key == `Application` && Value == `EKSAURGDB`)])].Endpoint' --output text)
    fi

    echo Aurora RO Endpoint : $roendpoint
    echo Aurora RW Endpoint : $rwendpoint

    if [[ -z $roendpoint || -z $rwendpoint ]]; then
	echo Error in determining ro / rw endpoints for Aurora Clusters
	exit 1
    fi

    ## Generate configuration for PgBouncer
    ## Get DB Credentials using aurora-pg/EKSGDB1
    secret=$(aws secretsmanager get-secret-value --region ${AWS_REGION} --secret-id aurora-pg/EKSGDB1 --query SecretString --output text)
    dbuser=`echo "$secret" | sed -n 's/.*"username":["]*\([^(",})]*\)[",}].*/\1/p'`
    dbpass=`echo "$secret" | sed -n 's/.*"password":["]*\([^(",})]*\)[",}].*/\1/p'`

    if [[ -z $dbuser || -z $dbpass ]]; then
	echo Error in extracting database user credentials from secretsmanager
	exit 1
    fi

    if [[ $runscript -eq 1 ]]; then
        export PGPASSWORD=$dbpass
        psql -h $rwendpoint -U $dbuser -p 5432 -d postgres -f retailapp/sql/setup_schema.sql
    fi

    DBUSER=dbuser1
    DBPASSWD=eksgdbdemo
    dbpass1=`echo -n "${DBPASSWD}${DBUSER}" | md5sum | awk '{print $1}'`
    echo \"${DBUSER}\" \"md5${dbpass1}\" > ${PGB_USERLIST}
    dbpass1=`echo -n "${dbpass}${dbuser}" | md5sum | awk '{print $1}'`
    echo \"${dbuser}\" \"md5${dbpass1}\" >> ${PGB_USERLIST}

    echo "    [databases]
    gdbdemo = host=${rwendpoint} port=5432 dbname=eksgdbdemo
    gdbdemo-ro = host=${roendpoint} port=5432 dbname=eksgdbdemo
    [pgbouncer]
    logfile = /tmp/pgbouncer.log
    pidfile = /tmp/pgbouncer.pid
    listen_addr = *
    listen_port = 6432
    auth_type = md5
    auth_file = /etc/pgbouncer/userlist.txt
    auth_user = ${DBUSER}
    stats_users = stats, root, pgbouncer
    pool_mode = transaction
    max_client_conn = 1000
    default_pool_size = 100
    tcp_keepalive = 1
    tcp_keepidle = 1
    tcp_keepintvl = 11
    tcp_keepcnt = 3
    tcp_user_timeout = 12500" > ${PGB_CONF}

    pgbouncerini=`cat  ${PGB_CONF}`
    userlisttxt=`cat  ${PGB_USERLIST} | base64 --wrap=0`

    sed -e "/%pgbouncerini%/r /tmp/pgbouncer.ini" -e "/%pgbouncerini%/d" -e "s/%userlisttxt%/$userlisttxt/g" -e "s/%AWS_ACCOUNT_ID%/$AWS_ACCOUNT_ID/g" -e "s/%AWS_REGION%/$AWS_REGION/g"  ${PGB_K8S} > ${PGB_APP}

    kubectl apply -f ${PGB_APP}

}



function configure_pgb_lambda()
{

    LAMBDA_ROLE="aurorapgbouncerlambda"
    LAYER_NAME="kubernetes"
    LAMBDA_NAME="AuroraGDBPgbouncerUpdate"
    EVENT_NAME=${LAMBDA_NAME}
    K8S_LAMBDA_BINDING=pgbouncer/pgbouncer_lambda_role_binding.yaml
    LAMBDA_CODE="pgbouncer_lambda.py"
    LAMBDA_DIR=pgbouncer

    current_dir=`pwd`
    rm -rf /tmp/python
    cd /tmp

    pip3 install kubernetes -t python/
    zip -r kubernetes.zip python  > /dev/null
    aws lambda publish-layer-version --layer-name ${LAYER_NAME} --zip-file fileb://kubernetes.zip --compatible-runtimes python3.9 --region ${AWS_REGION}

    layer_arn=$(aws lambda  get-layer-version --layer-name ${LAYER_NAME} --version-number 1 | jq -r .LayerVersionArn)
    cd ${current_dir}

    cd ${LAMBDA_DIR}
    zip -r /tmp/aurora_gdb_update.zip ${LAMBDA_CODE}
    cd ${current_dir}

    aws iam create-role --role-name ${LAMBDA_ROLE} --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}'

    aws iam attach-role-policy --role-name ${LAMBDA_ROLE} --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    aws iam put-role-policy --role-name ${LAMBDA_ROLE} --policy-name lambda_rds_policy --policy-document  '{"Version": "2012-10-17","Statement": [{ "Action": ["sts:GetCallerIdentity","eks:DescribeCluster","rds:DescribeDBClusters", "cloudformation:DescribeStacks", "cloudformation:ListStacks"],"Effect": "Allow","Resource": "*"}]}'

    lambda_role_arn=$(aws iam get-role --role-name ${LAMBDA_ROLE} | jq -r .Role.Arn)
    sleep 5

    aws lambda create-function --region ${AWS_REGION} --function-name ${LAMBDA_NAME} --zip-file fileb:///tmp/aurora_gdb_update.zip --handler pgbouncer_lambda.lambda_handler --runtime python3.9 --role ${lambda_role_arn} --layers ${layer_arn} --timeout 600  > /dev/null 

    lambda_arn=$(aws lambda get-function --function-name ${LAMBDA_NAME} | jq -r .Configuration.FunctionArn)
echo ${lambda_arn}

    aws events put-rule --region ${AWS_REGION} --name ${EVENT_NAME} --event-pattern "{\"detail-type\": [\"RDS DB Cluster Event\"],\"source\": [\"aws.rds\"],\"detail\": {\"EventCategories\": [\"global-failover\"],\"EventID\": [\"RDS-EVENT-0185\"]}}" 
    aws events put-targets --region ${AWS_REGION} --rule ${EVENT_NAME} --targets "Id"="1","Arn"="${lambda_arn}"
    rule_arn=$(aws events describe-rule --region ${AWS_REGION} --name AuroraGDBPgbouncerUpdate | jq -r .Arn)

    aws lambda add-permission --region ${AWS_REGION} --function-name ${LAMBDA_NAME} --statement-id auroraglobal-scheduled-event --action 'lambda:InvokeFunction' --principal events.amazonaws.com --source-arn ${rule_arn}

    ROLE="    - rolearn: ${lambda_role_arn}\n      username: lambda\n      groups:\n        - system:masters"
    kubectl get -n kube-system configmap/aws-auth -o yaml | awk "/mapRoles: \|/{print;print \"$ROLE\";next}1" > /tmp/aws-auth-patch.yml
    kubectl patch configmap/aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yml)"

    kubectl apply -f ${K8S_LAMBDA_BINDING}
}


function install_cluster_auto_scaler()
{

    print_line
    echo "Installing Auto Scaler configuration" 
    print_line

    cat <<EoF > /tmp/k8s-asg-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "ec2:DescribeLaunchTemplateVersions",
                "ec2:DescribeInstanceTypes"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EoF

    aws iam create-policy --policy-name k8s-asg-policy  --policy-document file:///tmp/k8s-asg-policy.json

    eksctl create iamserviceaccount \
        --name cluster-autoscaler \
        --namespace ${EKS_NAMESPACE} \
        --cluster ${EKS_CLUSTER_NAME} \
        --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/k8s-asg-policy" \
        --approve \
        --override-existing-serviceaccounts

    kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

    kubectl -n kube-system \
        annotate deployment.apps/cluster-autoscaler \
        cluster-autoscaler.kubernetes.io/safe-to-evict="false"

    # we need to retrieve the latest docker image available for our EKS version
    K8S_VERSION=$(kubectl version --short | grep 'Server Version:' | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' | cut -d. -f1,2)
    AUTOSCALER_VERSION=$(curl -s "https://api.github.com/repos/kubernetes/autoscaler/releases" | grep '"tag_name":' | sed -s 's/.*-\([0-9][0-9\.]*\).*/\1/' | grep -m1 ${K8S_VERSION})

    kubectl -n kube-system \
        set image deployment.apps/cluster-autoscaler \
        cluster-autoscaler=us.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler:v${AUTOSCALER_VERSION}

    print_line

}


function install_metric_server()
{
    print_line
    echo "Installing Metric Server"
    print_line
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.5.1/components.yaml
    sleep 30
    kubectl get apiservice v1beta1.metrics.k8s.io -o json | jq '.status'
    print_line
}


function create_global_accelerator()
{

    if [ ${AWS_REGION} == ${REGION1} ] ; then
	echo "Skipping the configuration of Global Accelerator in the Primary region"
        # Creating the Global accelerator from the REGION2
        return
    fi

    Global_Accelerator_Arn=$(aws globalaccelerator list-accelerators --region ${REGION2} --query 'Accelerators[?(Name == `eksgdb`)].AcceleratorArn' --output text)

    if [[ -z ${Global_Accelerator_Arn} ]]; then
       Global_Accelerator_Arn=$(aws globalaccelerator create-accelerator --name eksgdb --query "Accelerator.AcceleratorArn" --output text --region ${REGION2})
    fi

    echo "Global Accelerator ARN : ${Global_Accelerator_Arn}"

    Global_Accelerator_Listerner_Arn=$(aws globalaccelerator list-listeners --accelerator-arn ${Global_Accelerator_Arn} --query 'Listeners[].ListenerArn' --output text)
    if [[ -z ${Global_Accelerator_Listerner_Arn} ]]; then
        Global_Accelerator_Listerner_Arn=$(aws globalaccelerator create-listener \
          --accelerator-arn $Global_Accelerator_Arn \
          --region ${REGION2} \
          --protocol TCP \
          --port-ranges FromPort=80,ToPort=80 \
          --query "Listener.ListenerArn" \
          --output text)
    fi

    echo "Global Accelerator Listener ARN : ${Global_Accelerator_Listerner_Arn}"

    lname=$(aws elbv2 describe-load-balancers --region $REGION1 --query 'LoadBalancers[?contains(DNSName, `webapp`)].LoadBalancerArn' --output text)
    EndpointGroupArn_1=$(aws globalaccelerator create-endpoint-group \
      --region ${REGION2} \
      --traffic-dial-percentage 100 \
      --listener-arn $Global_Accelerator_Listerner_Arn \
      --endpoint-group-region ${REGION1} \
      --query "EndpointGroup.EndpointGroupArn" \
      --output text \
      --endpoint-configurations EndpointId=$lname,Weight=128,ClientIPPreservationEnabled=True) 

    lname=$(aws elbv2 describe-load-balancers --region $REGION2 --query 'LoadBalancers[?contains(DNSName, `webapp`)].LoadBalancerArn' --output text)
    EndpointGroupArn_2=$(aws globalaccelerator create-endpoint-group \
      --region ${REGION2} \
      --traffic-dial-percentage 100 \
      --listener-arn $Global_Accelerator_Listerner_Arn \
      --endpoint-group-region ${REGION2} \
      --query "EndpointGroup.EndpointGroupArn" \
      --output text \
      --endpoint-configurations EndpointId=$lname,Weight=128,ClientIPPreservationEnabled=True) 

    export WEBAPP_GADNS=$(aws globalaccelerator describe-accelerator \
      --accelerator-arn $Global_Accelerator_Arn \
      --query "Accelerator.DnsName" \
      --output text --region ${REGION2})

    echo "Global Accelerator DNS Name: $WEBAPP_GADNS"

    echo "Checking deployment status"
    status=$(aws globalaccelerator list-accelerators --query 'Accelerators[?(Name == `eksgdb`)].Status' --output text)
    while [[ "${status}" != "DEPLOYED" ]]; do
       echo "Global Accelerator deployment status ${status}"
       sleep 60
       status=$(aws globalaccelerator list-accelerators --query 'Accelerators[?(Name == `eksgdb`)].Status' --output text)
    done
    echo "Global Accelerator deployment completed. DNS Name: $WEBAPP_GADNS"

}


function set_env()
{ 
    print_line
    echo "Setting up the base environment variables"
    print_line
    install_jq
    export EKS_CFN_FILE=cfn/eks_cluster.yaml
    export EKS_STACK_NAME=auroragdbeks
    export INSTANCE_ROLE="C9Role"
    export EKS_NAMESPACE="kube-system"
    export REGION1="us-east-2"
    export REGION2="us-west-2"
    export CFN_VPC_C9=cfn/aurora_vpc_region.yaml
    export CFN_AURORADB=cfn/aurora_gdb.yaml
    if [ -z ${AWS_REGION} ] ; then
         export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
    fi
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text) 
    export RETAILAPP_K8S=retailapp/eks/retailapp.yml
    export RETAILAPP_K8S_REGION=retailapp/eks/retailapp-${AWS_REGION}.yml
    print_line
}

function set_env_from_c9_cfn()
{
    print_line
    echo "Setting up the CloudFormation variables"
    print_line
    export vpcid=$(aws cloudformation describe-stacks --region ${AWS_REGION} --stack-name EKSGDB1 --query 'Stacks[].Outputs[?(OutputKey == `VPC`)][].{OutputValue:OutputValue}' --output text)
    export subnets=$(aws ec2 describe-subnets --region ${AWS_REGION} --filters Name=vpc-id,Values=${vpcid} --query 'Subnets[?(! MapPublicIpOnLaunch)].{SubnetId:SubnetId}' --output text)
    export subnetA=`echo "${subnets}" |head -1 | tail -1`
    export subnetB=`echo "${subnets}" |head -2 | tail -1`
    export subnetC=`echo "${subnets}" |head -3 | tail -1`
    print_line
}

function set_env_from_k8s_cfn()
{
    export EKS_CLUSTER_NAME=$(aws cloudformation describe-stacks --region ${AWS_REGION} --query "Stacks[].Outputs[?(OutputKey == 'EKSClusterName')][].{OutputValue:OutputValue}" --output text)
}

export TERM1="/dev/null"

if [ "X${1}" == "Xsetup_env" ] ; then
    print_line
    echo "Setting up initial environment"
    print_line
    set_env
    deploy_vpc_c9
    update_routes
    exit
fi

if [ "X${1}" == "Xglobal-accelerator" ] ; then
    print_line
    echo "Setting up Global Accelerator"
    print_line
    set_env
    set_env_from_c9_cfn
    create_global_accelerator
    exit
fi

if [ "X${1}" == "Xconfigure-retailapp" ] ; then
    print_line
    echo "Configuration Lambda function for pgbouncer"
    print_line
    set_env
    set_env_from_c9_cfn
    install_pgbouncer
    configure_pgb_lambda
    echo "Configuration of RetailApp"
    install_retailapp
    exit
fi

set_env
set_env_from_c9_cfn

## Installing utilities
install_packages
install_k8s_utilities
install_postgresql
chk_installation

chk_cloud9_permission
create_eks_cluster
set_env_from_k8s_cfn

update_config
update_eks
install_loadbalancer
install_cluster_auto_scaler
install_metric_server

