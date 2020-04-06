#!groovy
/*
  Intended to run from a separate project where you have deployed Jenkins.
  To allow the jenkins service account to create projects:

  oc adm policy add-cluster-role-to-user self-provisioner system:serviceaccount:$(oc project -q):jenkins
  oc adm policy add-cluster-role-to-user view system:serviceaccount:$(oc project -q):jenkins
 */
pipeline {
    environment {
        GIT_SSL_NO_VERIFY = 'true'
    }
    options {
        // set a timeout of 20 minutes for this pipeline
        timeout(time: 20, unit: 'MINUTES')
        // when running Jenkinsfile from SCM using jenkinsfilepath the node implicitly does a checkout
        skipDefaultCheckout()
        buildDiscarder(logRotator(numToKeepStr:'10'))
    }
    agent none
    parameters {
        string(name: 'APP_NAME', defaultValue: 'helloservice', description: "Application Name - all resources use this name as a label")
        string(name: 'GIT_URL', defaultValue: 'https://github.com/eformat/argocd.git', description: "Project Git URL")
        string(name: 'ARGOCD_PROJECT', defaultValue: 'argocd', description: "ArgoCD Kube Project Name")
        string(name: 'ARGOCD_TEMPLATE_URL', defaultValue: 'https://raw.githubusercontent.com/argoproj/argo-cd/v1.3.6/manifests/install.yaml', description: "ArgoCD install template URI")
        string(name: 'MAVEN_MIRROR', defaultValue: 'http://nexus.nexus.svc.cluster.local:8081/repository/maven-public/', description: "Maven Mirror")
    }
    stages {
        stage('initialise') {
            steps {
                script {
                    echo "Build Number is: ${env.BUILD_NUMBER}"
                    echo "Job Name is: ${env.JOB_NAME}"
                    echo "Branch name is: ${env.BRANCH_NAME}"
                    sh 'printenv'                
                    if ("${env.BRANCH_NAME}".length()>0) {
                        env.GIT_BRANCH = "${env.BRANCH_NAME}".toLowerCase()
                        echo "env.GIT_BRANCH is: ${env.GIT_BRANCH}"
                    }
                }
            }
        }

        stage('bootstrap-argocd') {
          agent {
            kubernetes {
              label 'jenkins-slave-argocd'
              cloud 'openshift'
              serviceAccount 'jenkins'
              containerTemplate {
                name 'jnlp'
                image "image-registry.openshift-image-registry.svc:5000/openshift/jenkins-slave-argocd"
                alwaysPullImage true
                workingDir '/tmp'
                args '${computer.jnlpmac} ${computer.name}'
                command ''
                ttyEnabled false
              }
            }
          }
          openshift.withCluster() {
            openshift.withCredentials() {
              openshift.withProject() {
                openshift.newProject("${params.ARGOCD_PROJECT}")
                openshift.raw("apply", "-n", "${params.ARGOCD_PROJECT}",
                  "-f", "image-base=${params.ARGOCD_TEMPLATE_URL}")
              }
            }
          }
        }

        stage('configure-argocd-auth') {

        }
        stage('configure-argocd-configmap') {

        }
    }
}
