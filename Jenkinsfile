pipeline {
  agent {
    kubernetes {
      yaml '''
apiVersion: v1
kind: Pod
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
    emptyDir: {}
  containers:
  - name: node
    image: node:22-alpine  # based on node version
    command:
    - cat
    tty: true
    resources:
      requests:
        memory: "1Gi"
        cpu: "500m"
      limits:
        memory: "3Gi"  # Increased for OWASP Dependency Check
        cpu: "1000m"
    volumeMounts:
    - name: npm-cache
      mountPath: /root/.npm 
  - name: docker
    image: docker:27-dind
    securityContext:
      privileged: true  # Required for DinD - consider Kaniko later for rootless builds
    tty: true
    resources:
      requests:
        memory: "1Gi"
        cpu: "500m"
      limits:
        memory: "2Gi"  # Increased for better stability
        cpu: "1000m"
    volumeMounts:
    - name: docker-storage
      mountPath: /var/lib/docker
    env:
    - name: DOCKER_TLS_CERTDIR
      value: ""
    - name: DOCKER_DRIVER
      value: "overlay2"  # Better performance
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
    DEVTRON_BASE_URL = credentials('DEVTRON-BASE-URL') // Store base URL in credentials
    DEVTRON_ENDPOINT = '/orchestrator/webhook/ext-ci/3' // App-specific endpoint
    APIKEY = 'wsdrfgjsdfuyaerbqbyfgja'
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
          sh '''
            JEST_JUNIT_OUTPUT_DIR=. JEST_JUNIT_OUTPUT_NAME=test-results.xml CI=true npx react-scripts test --coverage --watchAll=false --reporters=default --reporters=jest-junit
            echo "Coverage Summary:"
          '''
          junit allowEmptyResults: true, testResults: 'test-results.xml'

          // Publish HTML coverage report
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
          echo "🛡️ Running OWASP Dependency Check (Universal - Maven/Node/Python)"

          script {
            withCredentials([string(credentialsId: 'nvd-api-key', variable: 'NVD_API_KEY')]) {
              // Download and setup with caching
              sh '''
                # Create directories
                mkdir -p odc-report

                # Define Dependency Check version and cache location (organized structure)
                DEP_CHECK_VERSION=12.1.0
                CACHE_DIR=/root/.cache/owasp/dependency-check-${DEP_CHECK_VERSION}

                # Install Java (required for OWASP Dependency Check)
                if ! command -v java &> /dev/null; then
                  echo "📦 Installing OpenJDK 21 (first time only)..."
                  apk add --no-cache openjdk21-jre wget unzip
                  echo "✅ Java installed: $(java -version 2>&1 | head -n 1)"
                else
                  # Ensure wget and unzip are available
                  apk add --no-cache wget unzip 2>/dev/null || true
                fi

                # Check if already cached
                if [ -d "$CACHE_DIR" ]; then
                  echo "✅ Using cached OWASP Dependency-Check v${DEP_CHECK_VERSION}"
                else
                  echo "📥 Downloading OWASP Dependency-Check v${DEP_CHECK_VERSION} (first time only)..."

                  # Ensure parent directory exists
                  mkdir -p /root/.cache/owasp

                  # Download and extract to cache
                  wget -q -O dependency-check.zip https://github.com/jeremylong/DependencyCheck/releases/download/v${DEP_CHECK_VERSION}/dependency-check-${DEP_CHECK_VERSION}-release.zip
                  unzip -q dependency-check.zip -d /root/.cache/owasp/
                  mv /root/.cache/owasp/dependency-check $CACHE_DIR
                  rm dependency-check.zip

                  echo "✅ OWASP Dependency-Check cached in organized directory for future builds"
                fi
              '''

              // Run scan with API key and increased memory
              sh """
                echo "🚀 Running OWASP Dependency Check scan"

                # Set Java options for better memory management
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

                echo "✅ Scan completed. Reports available in odc-report/"
                ls -lh odc-report || echo "No reports generated"
              """
            }

            // Publish vulnerability statistics
            script {
              try {
                recordIssues(
                  tools: [dependencyCheck(pattern: 'odc-report/dependency-check-report.xml')],
                  qualityGates: [[threshold: 1, type: 'TOTAL', unstable: false]],
                  healthy: 0,
                  unhealthy: 1
                )
              } catch (Exception e1) {
                echo "⚠️ recordIssues failed, trying dependencyCheckPublisher..."
                try {
                  dependencyCheckPublisher pattern: 'odc-report/dependency-check-report.xml'
                } catch (Exception e2) {
                  echo "⚠️ Both methods failed. Check OWASP Dependency-Check plugin is installed."
                  echo "HTML report will still be available."
                }
              }
            }

            // Publish HTML report
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

    

    stage('Build Docker Image') {
      when { branch 'develop' }
      steps {
        container('docker') {
          echo "🐳 Building Docker image..."
          withCredentials([usernamePassword(credentialsId: 'docker-hub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
            sh '''
              set +x  # Disable command echo for security
              echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
              LOGIN_STATUS=$?
              set -x  # Re-enable command echo

              if [ $LOGIN_STATUS -ne 0 ]; then
                echo "❌ Docker login failed"
                exit 1
              fi
            '''
          }
          sh "docker build --pull -t ${DOCKER_IMAGE} . && docker images ${DOCKER_IMAGE}"
          sh 'docker logout'
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
              set +x  # Disable command echo for security
              echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
              set -x  # Re-enable command echo
            '''
            sh """
              docker tag ${DOCKER_IMAGE} \${DOCKER_USER}/${DOCKER_IMAGE}
              docker push \${DOCKER_USER}/${DOCKER_IMAGE}
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
              curl --location --request POST "${DEVTRON_BASE_URL}${DEVTRON_ENDPOINT}" \
                   --header "Content-Type: application/json" \
                   --header "api-token: \$DEVTRON_TOKEN" \
                   --data-raw '{ "dockerImage": "\${DOCKER_USER}/${DOCKER_IMAGE}" }'
            """
          }
        }
      }
    }
    always {
      echo "✅ Pipeline finished for branch: ${env.BRANCH_NAME}"

      // Print resource usage statistics
      script {
        sh '''
          echo "📊 Resource Usage Summary:"
          echo "================================"
          kubectl top pods -n jenkins --selector=jenkins=slave 2>/dev/null || echo "⚠️  Metrics server not available"
        '''
      }
    }
  }
}
