run:
        SET_REGION=$(eval AWS_REGION=$(shell curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region'))
        SET_ACCOUNT=$(eval AWS_ACCOUNT_ID=$(shell aws sts get-caller-identity --output text --query Account))
        @echo $(AWS_REGION)
        $(SET_REGION)
        $(SET_ACCOUNT)
        @echo $(AWS_REGION)
        @echo $(AWS_ACCOUNT)
        docker build -t $(AWS_ACCOUNT_ID).dkr.ecr.${AWS_REGION}.amazonaws.com/retailapp/webapp:1.0 webapp/. 
        docker build -t $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/retailapp/product:1.0 product/.
        docker build -t $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/retailapp/kart:1.0 kart/.
        docker build -t $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/retailapp/order:1.0 order/.
        docker build -t $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/retailapp/user:1.0 user/.
        docker build --build-arg PGBOUNCER_VERSION=1.17.0 -t $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/retailapp/pgbouncer:1.17.0 pgbouncer/.
        aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
        docker push $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/retailapp/webapp:1.0
        docker push $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/retailapp/product:1.0
        docker push $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/retailapp/order:1.0
        docker push $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/retailapp/kart:1.0
        docker push $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/retailapp/user:1.0
        docker push $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/retailapp/pgbouner:1.17.0
