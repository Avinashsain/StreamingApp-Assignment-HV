pipeline {
  agent any

  environment {
    AWS_REGION = 'us-east-1'
    ECR_PREFIX = 'streamingapp'
    RELEASE_NAME = 'streamingapp'
    K8S_NAMESPACE = 'streamingapp'
    AWS_CREDENTIALS_ID = 'aws-jenkins'
    // Set after Part 7: SNS_TOPIC_ARN = 'arn:aws:sns:us-east-1:251478238405:streamingapp-alerts'
    // Set after Part 5 (backend ELB DNS names):
    FE_AUTH   = 'http://<auth-elb>.us-east-1.elb.amazonaws.com:3001/api'
    FE_STREAM = 'http://<streaming-elb>.us-east-1.elb.amazonaws.com:3002/api'
    FE_STREAM_PUB = 'http://<streaming-elb>.us-east-1.elb.amazonaws.com:3002'
    FE_ADMIN  = 'http://<admin-elb>.us-east-1.elb.amazonaws.com:3003/api/admin'
    FE_CHAT   = 'http://<chat-elb>.us-east-1.elb.amazonaws.com:3004/api/chat'
    FE_CHAT_SOCK = 'http://<chat-elb>.us-east-1.elb.amazonaws.com:3004'
  }

  options { timestamps(); disableConcurrentBuilds() }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script { env.IMAGE_TAG = sh(returnStdout: true, script: 'git rev-parse --short=12 HEAD').trim() }
      }
    }

    stage('AWS Login') {
      steps {
        script {
          withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
            env.ACCOUNT_ID = sh(returnStdout: true, script: 'aws sts get-caller-identity --query Account --output text').trim()
            env.ECR = "${env.ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
            sh 'aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR"'
          }
        }
      }
    }

    stage('Build Backend Images') {
      steps {
        script {
          def services = [
            [name: 'auth',      context: 'backend/authService', dockerfile: 'Dockerfile'],
            [name: 'streaming', context: 'backend',             dockerfile: 'streamingService/Dockerfile'],
            [name: 'admin',     context: 'backend',             dockerfile: 'adminService/Dockerfile'],
            [name: 'chat',      context: 'backend',             dockerfile: 'chatService/Dockerfile']
          ]
          services.each { svc ->
            def img = "${env.ECR}/${env.ECR_PREFIX}/${svc.name}:${env.IMAGE_TAG}"
            sh "docker build -t ${img} -f ${svc.context}/${svc.dockerfile} ${svc.context}"
            sh "docker push ${img}"
          }
        }
      }
    }

    stage('Build Frontend Image') {
      steps {
        sh '''
          docker build -t $ECR/$ECR_PREFIX/frontend:$IMAGE_TAG \
            --build-arg REACT_APP_AUTH_API_URL=$FE_AUTH \
            --build-arg REACT_APP_STREAMING_API_URL=$FE_STREAM \
            --build-arg REACT_APP_STREAMING_PUBLIC_URL=$FE_STREAM_PUB \
            --build-arg REACT_APP_ADMIN_API_URL=$FE_ADMIN \
            --build-arg REACT_APP_CHAT_API_URL=$FE_CHAT \
            --build-arg REACT_APP_CHAT_SOCKET_URL=$FE_CHAT_SOCK \
            ./frontend
          docker push $ECR/$ECR_PREFIX/frontend:$IMAGE_TAG
        '''
      }
    }

    stage('Deploy to EKS') {
      steps {
        script {
          withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
            sh '''
              aws eks update-kubeconfig --name streamingapp-eks --region "$AWS_REGION"
              helm upgrade --install "$RELEASE_NAME" ./helm/streamingapp \
                --namespace "$K8S_NAMESPACE" --create-namespace \
                --set image.tag="$IMAGE_TAG" \
                --set image.registry="$ECR"
            '''
          }
        }
      }
    }
  }

  post {
    success {
      sh 'if [ -n "${SNS_TOPIC_ARN:-}" ]; then aws sns publish --region "$AWS_REGION" --topic-arn "$SNS_TOPIC_ARN" --subject "Deploy SUCCESS" --message "StreamingApp build $IMAGE_TAG deployed ($JOB_NAME #$BUILD_NUMBER)"; fi'
    }
    failure {
      sh 'if [ -n "${SNS_TOPIC_ARN:-}" ]; then aws sns publish --region "$AWS_REGION" --topic-arn "$SNS_TOPIC_ARN" --subject "Deploy FAILED" --message "StreamingApp build FAILED ($JOB_NAME #$BUILD_NUMBER): $BUILD_URL"; fi'
    }
  }
}