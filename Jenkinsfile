pipeline {
  agent {
    kubernetes {
      yaml '''
apiVersion: v1
kind: Pod
spec:
  imagePullSecrets:
  - name: dockerhub-secret
  volumes:
  - name: npm-cache
    persistentVolumeClaim:
      claimName: npm-cache-pvc
  - name: docker-storage
    emptyDir: {}
  containers:
  - name: node
    image: node:22-alpine  # based on node version
    command:
    - cat
    tty: true
    resources:
      requests:
        memory: "512Mi"
        cpu: "500m"
      limits:
        memory: "1Gi"
        cpu: "1000m"
    volumeMounts:
    - name: npm-cache
      mountPath: /root/.npm 
  - name: docker
    image: docker:27-dind
    securityContext:
      privileged: true
    tty: true
    resources:
      requests:
        memory: "1Gi"
        cpu: "500m"
      limits:
        memory: "2Gi"
        cpu: "1000m"
    volumeMounts:
    - name: docker-storage
      mountPath: /var/lib/docker
    env:
    - name: DOCKER_TLS_CERTDIR
      value: ""
      '''
    }
  }

  environment {
    DOCKER_IMAGE = "node-project:${BUILD_NUMBER}"
    DEVTRON_URL = 'http://80.225.201.22:8000/orchestrator/webhook/ext-ci/3'
  }
  triggers {
        pollSCM('H/5 * * * *')
  }
  options {
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '10', daysToKeepStr: '30', artifactNumToKeepStr: '5'))
    timeout(time: 60, unit: 'MINUTES')
    skipDefaultCheckout(false)
  }

  stages {
    stage('Checkout') {
      steps {
        echo "🔄 Checking out branch: ${env.BRANCH_NAME}"
        checkout scm
      }
    }

    stage('Validate Commit Message') {
            when { expression { env.BRANCH_NAME.startsWith("feature/") } }
              steps {
                script {
            // Get the latest commit message
            def commitMsg = sh(
                script: "git log -1 --pretty=%B",
                returnStdout: true
            ).trim()

            echo "Latest commit message: ${commitMsg}"

            // Split by '#' to separate message and Jira ID
            def parts = commitMsg.split('#')

            if (parts.length != 2) {
                error "❌ Commit message must contain a '#' followed by Jira ID!"
            }

            def msgText = parts[0].trim()
            def jiraId = parts[1].trim()

            // Check message length
            if (msgText.length() < 30) {
                error "❌ Commit message text must be at least 30 characters!"
            }

            // Check Jira ID format (e.g., ABC-123 or PC-01)
            if (!jiraId.matches("^[A-Z]{2,}-\\d+\$")) {
                error "❌ Jira ID after '#' is invalid! Format: PROJECT-123 (e.g., PC-01, ABC-123). Received: '${jiraId}'"
            }

            echo "✅ Commit message validation passed"
        }
    }
}

    stage('Install Dependencies') {
      steps {
        echo "📦 Installing Node.js dependencies (with npm cache)"
        container('node') {
          // Use npm cache for faster installs
          sh '''
            echo "⚡ Using cached ~/.npm if available"
            npm ci --prefer-offline --no-audit --progress=false
          '''
        }
      }
    }


    stage('Run Tests') {
      when { expression { env.BRANCH_NAME.startsWith("feature/") } }
      steps {
        echo "🧪 Running React Tests with Coverage"
        container('node') {
          sh 'JEST_JUNIT_OUTPUT_DIR=. JEST_JUNIT_OUTPUT_NAME=test-results.xml CI=true npx react-scripts test --coverage --watchAll=false --reporters=default --reporters=jest-junit'
          junit allowEmptyResults: true, testResults: 'test-results.xml'
          recordCoverage(
            tools: [[parser: 'COBERTURA', pattern: '**/coverage/cobertura-coverage.xml']],
            id: 'jest-coverage',
            name: 'Jest Coverage',
            sourceCodeRetention: 'EVERY_BUILD',
            qualityGates: [
              [threshold: 80.0, metric: 'LINE', baseline: 'PROJECT', unstable: true],
              [threshold: 70.0, metric: 'BRANCH', baseline: 'PROJECT', unstable: true]
            ],
            enabledForFailure: true,
            failOnError: false
          ) 
        }
      }
    }


    stage('SonarQube Scan') {
      when { expression { env.BRANCH_NAME.startsWith("feature/") } }
      steps {
        echo "🔍 SonarQube Scan - To be implemented"
        echo "⚠️  Skipping for now"
      }
    }

    stage('OWASP Dependency Check') {
      when { expression { env.BRANCH_NAME.startsWith("feature/") } }
      steps {
        echo "🛡️ OWASP Dependency Check - To be implemented"
        echo "⚠️  Skipping for now"
      }
    }

    stage('Gitleaks Scan') {
      when { expression { env.BRANCH_NAME.startsWith("feature/") } }
      steps {
        echo "🔒 Gitleaks Scan - To be implemented"
        echo "⚠️  Skipping for now"
      }
    }

    stage('Build Docker Image') {
      when { branch 'develop' }
      steps {
        container('docker') {
          echo "🐳 Building Docker image..."
          withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
            sh 'echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin || true'
          }
          sh "docker build --pull -t ${DOCKER_IMAGE} . && docker images ${DOCKER_IMAGE}"
          sh 'docker logout || true'
        }
      }
    }

    stage('Push Docker Image') {
      when { branch 'develop' }
      steps {
        container('docker') {
          echo "🚀 Pushing Docker image to Docker Hub"
          withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
            sh """
              echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
              docker tag ${DOCKER_IMAGE} ${DOCKER_USER}/${DOCKER_IMAGE}
              docker push ${DOCKER_USER}/${DOCKER_IMAGE}
              docker logout
            """
          }
        }
      }
    }

    stage('Version Push') {
      when { branch 'develop' }
      steps { echo "📝 Pushing updated version.txt from develop" }
    }
  }

  post {
    success {
      script {
        if (env.BRANCH_NAME == 'develop') {
          echo "🚀 Triggering Devtron Deployment"
          withCredentials([string(credentialsId: 'DEVTRON-TOKEN', variable: 'DEVTRON_TOKEN')]) {
            sh """
              curl --location --request POST "$DEVTRON_URL" \
                   --header "Content-Type: application/json" \
                   --header "api-token: $DEVTRON_TOKEN" \
                   --data-raw '{ "dockerImage": "${DOCKER_USER}/${DOCKER_IMAGE}" }'
            """
          }
        }
      }
    }
    always {
      echo "✅ Pipeline finished for branch: ${env.BRANCH_NAME}"
      
    }
  }
}
