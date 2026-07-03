pipeline {
  agent any

  environment {
    AWS_REGION = 'us-east-1'
    ECR_PREFIX = 'streamingapp'
    RELEASE_NAME = 'streamingapp'
    K8S_NAMESPACE = 'streamingapp'
    AWS_CREDENTIALS_ID = 'aws-jenkins'
    // Enable after Part 7 (SNS):
    SNS_TOPIC_ARN = 'arn:aws:sns:us-east-1:251478238405:streamingapp-alerts'

    // Production frontend URLs — real ELB hostnames
    FE_AUTH       = 'http://abe68b9e3cef1432d84ddfd62d921607-152744616.us-east-1.elb.amazonaws.com:3001/api'
    FE_STREAM     = 'http://a279ed5848615483bb910f00a1e41479-1064057686.us-east-1.elb.amazonaws.com:3002/api'
    FE_STREAM_PUB = 'http://a279ed5848615483bb910f00a1e41479-1064057686.us-east-1.elb.amazonaws.com:3002'
    FE_ADMIN      = 'http://a3361919d28524d818fd3626f3987bd1-1540659810.us-east-1.elb.amazonaws.com:3003/api/admin'
    FE_CHAT       = 'http://a18952c65fe4a43df893ec5b59a5bb14-2024728726.us-east-1.elb.amazonaws.com:3004/api/chat'
    FE_CHAT_SOCK  = 'http://a18952c65fe4a43df893ec5b59a5bb14-2024728726.us-east-1.elb.amazonaws.com:3004'
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
            sh "docker build --platform linux/amd64 -t ${img} -f ${svc.context}/${svc.dockerfile} ${svc.context}"
            sh "docker push ${img}"
          }
        }
      }
    }

    stage('Build Frontend Image') {
      steps {
        sh '''
          docker build --platform linux/amd64 -t $ECR/$ECR_PREFIX/frontend:$IMAGE_TAG \
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
                --set image.registry="$ECR" \
                --set env.awsAccessKeyId="$AWS_ACCESS_KEY_ID" \
                --set env.awsSecretAccessKey="$AWS_SECRET_ACCESS_KEY"
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