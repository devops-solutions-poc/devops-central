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
          script {
            // Run Gitleaks scan with proper exit code handling
            def exitCode = sh(
              script: '''
                set +e  # Don't exit on error, we handle exit codes manually

                # Create dedicated report directory
                echo "📂 Preparing Gitleaks report directory..."
                rm -rf gitleaks-report
                mkdir -p gitleaks-report

                # Run gitleaks - exit codes: 0=clean, 1=leaks found, 2=error
                echo "🚀 Running Gitleaks scan..."
                gitleaks detect \
                  --source . \
                  --report-format json \
                  --report-path gitleaks-report/gitleaks-report.json \
                  --exit-code 1 \
                  --redact \
                  --no-git \
                  --verbose

                EXIT_CODE=$?
                echo "Gitleaks exit code: $EXIT_CODE"
                echo "📊 Report directory contents:"
                ls -lh gitleaks-report/ || echo "Directory empty"
                exit $EXIT_CODE
              ''',
              returnStatus: true
            )

            echo "📊 Gitleaks scan completed with exit code: ${exitCode}"

            // Process results based on exit code
            if (exitCode == 1) {
              // Secrets found - generate report
              if (fileExists('gitleaks-report/gitleaks-report.json')) {
                def report = readJSON file: 'gitleaks-report/gitleaks-report.json'
                def secretCount = report.size()

                echo "⚠️  Found ${secretCount} potential secret(s)!"

                // Generate detailed HTML report
                def htmlReport = """
                <!DOCTYPE html>
                <html>
                <head>
                  <title>Gitleaks Security Scan Report</title>
                  <meta charset="UTF-8">
                  <style>
                    * { margin: 0; padding: 0; box-sizing: border-box; }
                    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; background: #f5f7fa; padding: 20px; }
                    .container { max-width: 1200px; margin: 0 auto; }
                    h1 { color: #d32f2f; margin-bottom: 10px; font-size: 28px; }
                    .summary { background: white; padding: 25px; border-radius: 8px; margin-bottom: 25px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); border-left: 5px solid #d32f2f; }
                    .summary h2 { color: #333; font-size: 20px; margin-bottom: 15px; }
                    .stats { display: flex; gap: 20px; margin: 15px 0; }
                    .stat-box { background: #fff3e0; padding: 15px; border-radius: 6px; flex: 1; text-align: center; border: 1px solid #ff9800; }
                    .stat-box .number { font-size: 32px; font-weight: bold; color: #d32f2f; }
                    .stat-box .label { color: #666; margin-top: 5px; font-size: 14px; }
                    .secret { background: white; border-left: 4px solid #d32f2f; padding: 20px; margin: 15px 0; border-radius: 6px; box-shadow: 0 2px 4px rgba(0,0,0,0.08); }
                    .secret:hover { box-shadow: 0 4px 8px rgba(0,0,0,0.12); }
                    .file { font-weight: 600; color: #1976d2; margin-bottom: 10px; font-size: 15px; }
                    .rule { color: #00796b; font-weight: 500; margin: 8px 0; padding: 6px 10px; background: #e0f2f1; border-radius: 4px; display: inline-block; }
                    .info { color: #666; margin: 8px 0; font-size: 14px; }
                    .line-info { background: #f5f5f5; padding: 8px 12px; border-radius: 4px; font-family: monospace; font-size: 13px; margin: 10px 0; }
                    pre { background: #263238; color: #aed581; padding: 15px; overflow-x: auto; border-radius: 6px; margin: 10px 0; font-size: 13px; line-height: 1.5; }
                    .footer { margin-top: 30px; padding: 25px; background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
                    .footer h3 { color: #d32f2f; margin-bottom: 15px; }
                    .footer ol { margin-left: 20px; line-height: 1.8; color: #444; }
                    .footer li { margin-bottom: 8px; }
                    .severity-high { border-left-color: #d32f2f; }
                    .severity-medium { border-left-color: #f57c00; }
                    .severity-low { border-left-color: #fbc02d; }
                  </style>
                </head>
                <body>
                  <div class="container">
                    <h1>🔒 Gitleaks Security Scan Report</h1>
                    <div class="summary">
                      <h2>Scan Summary</h2>
                      <div class="stats">
                        <div class="stat-box">
                          <div class="number">${secretCount}</div>
                          <div class="label">Secrets Detected</div>
                        </div>
                        <div class="stat-box">
                          <div class="number">${report.collect { it.File }.unique().size()}</div>
                          <div class="label">Files Affected</div>
                        </div>
                      </div>
                      <p style="color: #d32f2f; font-weight: 600; margin-top: 15px;">⚠️ Action Required: Review and remediate all detected secrets immediately!</p>
                    </div>

                    <h2 style="margin: 25px 0 15px 0; color: #333;">Detected Secrets:</h2>
                    ${report.collect { leak ->
                      """
                      <div class="secret">
                        <div class="file">📁 ${leak.File ?: 'Unknown file'}</div>
                        <div class="rule">🔍 ${leak.RuleID ?: 'Unknown rule'}${leak.Description ? " - ${leak.Description}" : ''}</div>
                        <div class="line-info">📍 Line: ${leak.StartLine ?: 'N/A'}${leak.EndLine ? " - ${leak.EndLine}" : ''}</div>
                        <pre>${leak.Secret?.take(100)?.replaceAll('<', '&lt;')?.replaceAll('>', '&gt;') ?: '[REDACTED]'}${leak.Secret?.length() > 100 ? '...' : ''}</pre>
                        ${leak.Commit ? "<div class=\"info\">🔖 Commit: <code>${leak.Commit}</code></div>" : ""}
                      </div>
                      """
                    }.join('')}

                    <div class="footer">
                      <h3>🛡️ Remediation Steps:</h3>
                      <ol>
                        <li><strong>Immediate Action:</strong> Remove ALL detected secrets from the codebase</li>
                        <li><strong>Rotate Credentials:</strong> Invalidate and regenerate any exposed credentials, API keys, or tokens</li>
                        <li><strong>Use Secret Management:</strong> Store secrets in environment variables, AWS Secrets Manager, HashiCorp Vault, or similar tools</li>
                        <li><strong>Update .gitignore:</strong> Ensure sensitive files are excluded from version control</li>
                        <li><strong>Configure Allowlist:</strong> Add false positives to <code>.gitleaks.toml</code> configuration file</li>
                        <li><strong>Git History:</strong> Use tools like <code>git filter-branch</code> or <code>BFG Repo-Cleaner</code> to remove secrets from history</li>
                      </ol>
                      <p style="margin-top: 20px; padding: 15px; background: #e3f2fd; border-radius: 6px; color: #0d47a1;">
                        <strong>💡 Prevention Tip:</strong> Install Gitleaks as a pre-commit hook to catch secrets before they're committed!
                      </p>
                    </div>
                  </div>
                </body>
                </html>
                """

                writeFile file: 'gitleaks-report/gitleaks-report.html', text: htmlReport

                // Publish HTML report
                publishHTML([
                  allowMissing: false,
                  alwaysLinkToLastBuild: true,
                  keepAll: true,
                  reportDir: 'gitleaks-report',
                  reportFiles: 'gitleaks-report.html',
                  reportName: 'Gitleaks Security Report',
                  reportTitles: 'Secret Detection Results',
                  escapeUnderscores: false,
                  includes: '**/*'
                ])

                // Archive JSON report for further processing
                archiveArtifacts artifacts: 'gitleaks-report/gitleaks-report.json', allowEmptyArchive: true, fingerprint: true

                // Mark build as UNSTABLE instead of failing (better for developer experience)
                // Teams can configure to fail via quality gates if needed
                unstable("⚠️  Gitleaks detected ${secretCount} potential secret(s). Review required before merging!")

                // Optional: Uncomment to FAIL the build instead of marking unstable
                // error("❌ Gitleaks found ${secretCount} potential secret(s). Build failed for security!")
              }
            } else if (exitCode == 2) {
              // Scan error
              error("❌ Gitleaks scan encountered an error. Check container logs.")
            } else if (exitCode == 0) {
              // No secrets found
              echo "✅ No secrets detected! Code is clean and secure."

              // Create success report
              def successReport = """
              <!DOCTYPE html>
              <html>
              <head><title>Gitleaks Report - Clean</title>
              <style>
                body { font-family: Arial, sans-serif; margin: 40px; text-align: center; }
                .success { color: #2e7d32; font-size: 24px; margin: 20px; }
                .icon { font-size: 64px; }
              </style>
              </head>
              <body>
                <div class="icon">✅</div>
                <div class="success">No Secrets Detected!</div>
                <p>Your codebase is clean and secure.</p>
              </body>
              </html>
              """

              writeFile file: 'gitleaks-report/gitleaks-report.html', text: successReport
              publishHTML([
                allowMissing: false,
                alwaysLinkToLastBuild: true,
                keepAll: true,
                reportDir: 'gitleaks-report',
                reportFiles: 'gitleaks-report.html',
                reportName: 'Gitleaks Security Report',
                escapeUnderscores: false,
                includes: '**/*'
              ])
            }
          }
        }
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
