pipeline {
  agent {
    kubernetes {
      yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
spec:
  activeDeadlineSeconds: 3600
  restartPolicy: Never
  imagePullSecrets:
  - name: dockerhub-secret
  volumes:
  - name: npm-cache
    persistentVolumeClaim:
      claimName: npm-cache-pvc
  - name: docker-storage
    emptyDir:
      sizeLimit: 10Gi
  containers:
  - name: node
    image: node:22-alpine
    command:
    - cat
    tty: true
    resources:
      requests:
        memory: "1Gi"
        cpu: "500m"
      limits:
        memory: "3Gi"
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
    - name: DOCKER_DRIVER
      value: "overlay2"
    lifecycle:
      preStop:
        exec:
          command:
          - /bin/sh
          - -c
          - |
            echo "🧹 Cleaning up Docker before pod termination..."
            docker system prune -af --volumes || true
            df -h /var/lib/docker
  - name: gitleaks
    image: zricethezav/gitleaks:latest
    command:
    - cat
    tty: true
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "200m"
      '''
    }
  }

  environment {
    DOCKER_IMAGE = "node-project:${BUILD_NUMBER}"
    DEVTRON_BASE_URL = credentials('DEVTRON-BASE-URL')
    DEVTRON_ENDPOINT = '/orchestrator/webhook/ext-ci/3'
    DOCKER_USER = 'gauravt11'
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

    stage('Monitor - Pipeline Start') {
      steps {
        script {
          echo "========================================="
          echo "📊 Pipeline Start - Resource Snapshot"
          echo "========================================="
          echo "Build: ${env.BUILD_NUMBER}"
          echo "Branch: ${env.BRANCH_NAME}"
          echo "Timestamp: ${new Date()}"
          
          container('docker') {
            sh '''
              echo ""
              echo "💾 Docker Disk Space (Start):"
              df -h /var/lib/docker
              
              echo ""
              echo "🐳 Docker Images:"
              docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | head -10
            '''
          }
        }
      }
    }

    stage('Check Disk Space') {
      steps {
        script {
          container('docker') {
            sh '''
              echo "💾 Detailed Disk Check"
              df -h /var/lib/docker
              
              AVAILABLE_MB=$(df -m /var/lib/docker | tail -1 | awk '{print $4}')
              echo "Available: ${AVAILABLE_MB} MB"
              
              if [ $AVAILABLE_MB -lt 1024 ]; then
                echo "⚠️  WARNING: Less than 1GB available!"
                echo "Running emergency cleanup..."
                docker system prune -f
              fi
            '''
          }
        }
      }
    }

    stage('Validate Commit Message') {
      when { expression { env.BRANCH_NAME.startsWith("feature/") } }
      steps {
        script {
          def commitMsg = sh(
            script: "git log -1 --pretty=%B",
            returnStdout: true
          ).trim()

          echo "Latest commit message: ${commitMsg}"
          def parts = commitMsg.split('#')

          if (parts.length != 2) {
            error "❌ Commit message must contain a '#' followed by Jira ID!"
          }

          def msgText = parts[0].trim()
          def jiraId = parts[1].trim()

          if (msgText.length() < 30) {
            error "❌ Commit message text must be at least 30 characters!"
          }

          if (!jiraId.matches("^[A-Z]{2,}-\\d+\$")) {
            error "❌ Jira ID after '#' is invalid! Format: PROJECT-123 (e.g., PC-01, ABC-123). Received: '${jiraId}'"
          }

          echo "✅ Commit message validation passed"
        }
      }
    }

    stage('Version Management') {
      steps {
        script {
          if (env.BRANCH_NAME == 'develop') {
            echo "Develop branch: updating version.txt"
          } else if (env.BRANCH_NAME.startsWith("feature/")) {
            echo "Feature branch: pulling latest version.txt from develop"
          }
        }
      }
    }

    stage('Install Dependencies') {
      steps {
        echo "📦 Installing Node.js dependencies (with npm cache)"
        container('node') {
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
          sh '''
            JEST_JUNIT_OUTPUT_DIR=. JEST_JUNIT_OUTPUT_NAME=test-results.xml CI=true npx react-scripts test --coverage --watchAll=false --reporters=default --reporters=jest-junit
            echo "Coverage Summary:"
          '''
          junit allowEmptyResults: true, testResults: 'test-results.xml'

          publishHTML(target: [
            allowMissing: false,
            alwaysLinkToLastBuild: true,
            keepAll: true,
            reportDir: 'coverage/lcov-report',
            reportFiles: 'index.html',
            reportName: 'Coverage Report',
            escapeUnderscores: false,
            includes: '**/*'
          ])

          recordCoverage(
            tools: [[parser: 'COBERTURA', pattern: '**/coverage/cobertura-coverage.xml']],
            id: 'jest-coverage',
            name: 'Jest Coverage',
            sourceCodeRetention: 'EVERY_BUILD',
            qualityGates: [
              [threshold: 80.0, metric: 'LINE', baseline: 'PROJECT', unstable: true]
            ],
            enabledForFailure: true,
            failOnError: false
          ) 
        }
      }
    }

    stage('Gitleaks Scan') {
      when { expression { env.BRANCH_NAME.startsWith("feature/") } }
      steps {
        echo "🔒 Scanning for secrets with Gitleaks"
        container('gitleaks') {
          sh '''
            set -e
            set -x

            echo "📂 Preparing Gitleaks report directory..."
            rm -rf gitleaks-report
            mkdir -p gitleaks-report

            echo "🚀 Running Gitleaks scan (JSON report)..."
            gitleaks detect \
                --source=. \
                --report-format=json \
                --report-path=gitleaks-report/gitleaks-report.json \
                --verbose \
                --redact || true

            echo "🪄 Converting JSON → HTML for Jenkins UI..."
            REPORT_JSON=gitleaks-report/gitleaks-report.json
            REPORT_HTML=gitleaks-report/gitleaks-report.html

            if [ -s "$REPORT_JSON" ]; then
                echo '<html><body><h3>Gitleaks Scan Report</h3><pre>' > $REPORT_HTML
                cat $REPORT_JSON >> $REPORT_HTML
                echo '</pre></body></html>' >> $REPORT_HTML
            else
                echo '<html><body><h3>Gitleaks Scan Report</h3><p>No leaks found ✅</p></body></html>' > $REPORT_HTML
            fi

            echo "✅ Gitleaks scan completed"
            ls -lh gitleaks-report
          '''
        }

        publishHTML(target: [
          allowMissing: true,
          alwaysLinkToLastBuild: true,
          keepAll: true,
          reportDir: 'gitleaks-report',
          reportFiles: 'gitleaks-report.html',
          reportName: 'Gitleaks Secret Scan Report',
          escapeUnderscores: false,
          includes: '**/*'
        ])
      }
    }

    stage('OWASP Dependency Check') {
      when { expression { env.BRANCH_NAME.startsWith("feature/") } }
      steps {
        container('node') {
          echo "🛡️ Running OWASP Dependency Check"

          script {
            withCredentials([string(credentialsId: 'nvd-api-key', variable: 'NVD_API_KEY')]) {
              sh '''
                mkdir -p odc-report

                DEP_CHECK_VERSION=12.1.0
                CACHE_DIR=/root/.cache/owasp/dependency-check-${DEP_CHECK_VERSION}

                if ! command -v java &> /dev/null; then
                  echo "📦 Installing OpenJDK 21..."
                  apk add --no-cache openjdk21-jre wget unzip
                else
                  apk add --no-cache wget unzip 2>/dev/null || true
                fi

                if [ -d "$CACHE_DIR" ]; then
                  echo "✅ Using cached OWASP Dependency-Check"
                else
                  echo "📥 Downloading OWASP Dependency-Check..."
                  mkdir -p /root/.cache/owasp
                  wget -q -O dependency-check.zip https://github.com/jeremylong/DependencyCheck/releases/download/v${DEP_CHECK_VERSION}/dependency-check-${DEP_CHECK_VERSION}-release.zip
                  unzip -q dependency-check.zip -d /root/.cache/owasp/
                  mv /root/.cache/owasp/dependency-check $CACHE_DIR
                  rm dependency-check.zip
                fi
              '''

              sh """
                export JAVA_OPTS="-Xmx2048m -Xms512m"
                /root/.cache/owasp/dependency-check-12.1.0/bin/dependency-check.sh \
                    --project "node-project" \
                    --scan . \
                    --format HTML \
                    --format JSON \
                    --format XML \
                    --out odc-report \
                    --nvdApiKey "\${NVD_API_KEY}" \
                    --exclude "**/coverage/**" \
                    --exclude "**/node_modules/**" \
                    --exclude "**/test/**" \
                    --suppression owasp-suppressions.xml \
                    --disableOssIndex \
                    --enableExperimental \
                    || true
              """
            }

            script {
              try {
                recordIssues(
                  tools: [dependencyCheck(pattern: 'odc-report/dependency-check-report.xml')],
                  qualityGates: [[threshold: 1, type: 'TOTAL', unstable: false]],
                  healthy: 0,
                  unhealthy: 1
                )
              } catch (Exception e) {
                echo "⚠️ recordIssues not available, HTML report will be published"
              }
            }

            publishHTML([
              allowMissing: false,
              alwaysLinkToLastBuild: true,
              keepAll: true,
              reportDir: 'odc-report',
              reportFiles: 'dependency-check-report.html',
              reportName: 'OWASP Dependency Check Report',
              reportTitles: 'OWASP Dependency Check',
              escapeUnderscores: false,
              includes: '**/*'
            ])
          }
        }
      }
    }
 
    stage('SonarQube Scan') {
      when { expression { env.BRANCH_NAME.startsWith("feature/") } }
      steps { echo "Running SonarQube Scan" }
    }

    stage('Build Docker Image') {
      when { branch 'develop' }
      steps {
        container('docker') {
          echo "🐳 Building Docker image..."
          
          sh '''
            echo "💾 Disk space before build:"
            df -h /var/lib/docker
          '''
          
          withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
            sh '''
              set +x
              echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
              LOGIN_STATUS=$?
              set -x

              if [ $LOGIN_STATUS -ne 0 ]; then
                echo "❌ Docker login failed"
                exit 1
              fi
            '''
          }
          
          sh """
            docker build --pull -t ${DOCKER_IMAGE} .
            docker images ${DOCKER_IMAGE}
          """
          
          sh 'docker logout'
          
          sh '''
            echo "💾 Disk space after build:"
            df -h /var/lib/docker
          '''
        }
      }
    }

    stage('Monitor - After Build') {
      when { branch 'develop' }
      steps {
        script {
          container('docker') {
            sh '''
              echo "========================================="
              echo "📊 After Build - Resource Check"
              echo "========================================="
              df -h /var/lib/docker
              
              echo ""
              echo "Images:"
              docker images | head -10
              
              echo ""
              echo "Disk usage breakdown:"
              docker system df
            '''
          }
        }
      }
    }

    stage('Push Docker Image') {
      when { branch 'develop' }
      steps {
        container('docker') {
          echo "🚀 Pushing Docker image to Docker Hub"
          withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
            sh '''
              set +x
              echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
              set -x
            '''
            sh """
              docker tag ${DOCKER_IMAGE} \${DOCKER_USER}/${DOCKER_IMAGE}
              docker push \${DOCKER_USER}/${DOCKER_IMAGE}
              
              echo "🧹 Cleaning up local images after push..."
              docker rmi ${DOCKER_IMAGE} || true
              docker rmi \${DOCKER_USER}/${DOCKER_IMAGE} || true
              
              docker logout
            """
          }
          
          sh '''
            echo "💾 Disk space after push and cleanup:"
            df -h /var/lib/docker
          '''
        }
      }
    }

    stage('Version Push') {
      when { branch 'develop' }
      steps { echo "📝 Pushing updated version.txt from develop" }
    }

    stage('Monitor - Pipeline End') {
      steps {
        script {
          container('docker') {
            sh '''
              echo "========================================="
              echo "📊 Pipeline End - Final Resource State"
              echo "========================================="
              df -h /var/lib/docker
              
              echo ""
              echo "Final Docker system usage:"
              docker system df
            '''
          }
        }
      }
    }
  }

  post {
    always {
      script {
        // Clean up Docker regardless of build result
        try {
          container('docker') {
            sh '''
              echo "========================================="
              echo "🧹 Final Cleanup"
              echo "========================================="
              
              echo "Before cleanup:"
              df -h /var/lib/docker
              docker system df
              
              docker system prune -f --volumes || true
              
              echo ""
              echo "After cleanup:"
              df -h /var/lib/docker
              docker system df
            '''
          }
        } catch (Exception e) {
          echo "⚠️ Cleanup failed: ${e.message}"
        }
      }
      
      // Clean up workspace
      cleanWs(
        deleteDirs: true,
        disableDeferredWipeout: true,
        notFailBuild: true,
        patterns: [
          [pattern: 'node_modules', type: 'INCLUDE'],
          [pattern: 'coverage', type: 'INCLUDE'],
          [pattern: 'odc-report', type: 'INCLUDE'],
          [pattern: 'gitleaks-report', type: 'INCLUDE']
        ]
      )
      
      echo "✅ Pipeline finished for branch: ${env.BRANCH_NAME}"
    }
    
    success {
      script {
        if (env.BRANCH_NAME == 'develop') {
          echo "🚀 Triggering Devtron Deployment"
          withCredentials([string(credentialsId: 'DEVTRON-TOKEN', variable: 'DEVTRON_TOKEN')]) {
            sh """
              curl --location --request POST "${DEVTRON_BASE_URL}${DEVTRON_ENDPOINT}" \
                   --header "Content-Type: application/json" \
                   --header "api-token: \$DEVTRON_TOKEN" \
                   --data-raw '{ "dockerImage": "\${DOCKER_USER}/${DOCKER_IMAGE}" }'
            """
          }
        }
      }
    }
    
    failure {
      echo "❌ Build failed. Check logs for details."
      script {
        try {
          container('docker') {
            sh 'docker system prune -af || true'
          }
        } catch (Exception e) {
          echo "Cleanup on failure: ${e.message}"
        }
      }
    }
    
    aborted {
      echo "⚠️ Build was aborted"
      script {
        try {
          container('docker') {
            sh 'docker system prune -af || true'
          }
        } catch (Exception e) {
          echo "Cleanup on abort: ${e.message}"
        }
      }
    }
  }
}