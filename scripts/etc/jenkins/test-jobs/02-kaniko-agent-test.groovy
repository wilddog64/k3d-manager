// Test job for Kaniko agent - validates container image building without Docker daemon
pipeline {
    agent {
        label 'kaniko'
    }

    stages {
        stage('System Information') {
            steps {
                echo '=== Kaniko Agent Information ==='
                sh 'uname -a'
                sh 'pwd'
                sh 'whoami'
            }
        }

        stage('Create Test Dockerfile') {
            steps {
                echo '=== Creating Test Dockerfile ==='
                sh '''
                cat > Dockerfile << 'EOF'
FROM alpine:latest
RUN echo "Built with Kaniko!" > /test.txt
CMD ["cat", "/test.txt"]
EOF
                '''
                sh 'cat Dockerfile'
            }
        }

        stage('Kaniko Available Check') {
            steps {
                echo '=== Checking Kaniko Availability ==='
                container('kaniko') {
                    sh '''
                        echo "Kaniko container active"
                        ls -la /kaniko/
                        cat /kaniko/.docker/config.json || echo "No Docker config (use secret for registry auth)"
                    '''
                }
            }
        }

        stage('Build Image with Kaniko') {
            steps {
                echo '=== Building Container Image ==='
                container('kaniko') {
                    sh '''
                        /kaniko/executor \\
                            --context=${WORKSPACE} \\
                            --dockerfile=${WORKSPACE}/Dockerfile \\
                            --no-push \\
                            --tar-path=${WORKSPACE}/image.tar \\
                            --destination=test-image:${BUILD_NUMBER}
                    '''
                }
                sh 'ls -lh image.tar'
            }
        }

        stage('Verify Build Artifact') {
            steps {
                echo '=== Verifying Build Output ==='
                sh 'test -f image.tar && echo "✓ Image tarball created successfully" || exit 1'
                sh 'du -h image.tar'
            }
        }
    }

    post {
        always {
            echo '=== Cleanup ==='
            sh 'rm -f Dockerfile image.tar'
        }
        success {
            echo '✅ Kaniko agent test PASSED'
            echo 'Container image built successfully without Docker daemon!'
        }
        failure {
            echo '❌ Kaniko agent test FAILED'
        }
    }
}
