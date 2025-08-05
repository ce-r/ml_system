1. System Setup and Environment Configuration

Directories Created:
scripts, infrastructure/{terraform, ansible, kubernetes, docker}, services, monitoring, tests
Organizes codebase and separates concerns (infra, services, monitoring, testing).

Environment Variables:
PROJECT_DIR – root path for the project.
ENVIRONMENT – "local" to indicate local deployment.
KUBECONFIG – sets the path to the local kubeconfig file.

Checks:
Ensures script is not run in a virtual environment.
Verifies required commands are installed.

2. Prerequisite Installation via install-prerequisites.sh

Installs critical tooling:
Docker, kubectl, Minikube, Helm
Terraform, Ansible, jq, git, Python3 packages
Docker Compose for service orchestration

3. Docker Configuration

Listens on TCP 127.0.0.1:2375 for compatibility with Terraform.
Fixes failed Docker states, ensures Docker is started and accessible.

4. Minikube Kubernetes Cluster
Launches with:

4 CPUs, 4GB RAM, 50GB disk
Docker driver
Kubernetes v1.28.0

Enables:
Ingress, dashboard, metrics-server, registry, etc.

5. Infrastructure Provisioning

a. Terraform
Providers: kubernetes, helm, docker
Resources: Storage class for persistent volumes

Docker volumes for ml-platform-data, ml-platform-models
Uses data blocks to access existing K8s namespaces

b. Ansible
Provisions: Secrets using jwt_secret, db_password, redis_password

Docker networks
Required directories for logs, data, configs

6. Docker Services w/ docker-compose

Core Services:
Service Purpose
PostgreSQL Relational DB to store users, models, predictions
Redis Caching, rate-limiting, sessions, pub/sub
MongoDB Feature store, metadata, prediction logs
Kafka Event streaming backend
MinIO Object storage for datasets and model files
Vault Secrets management
RedisInsight GUI for Redis debugging
Redis Exporter For Prometheus monitoring

Advanced Redis Setup:
Replication: master + 2 replicas

Sentinel: auto-failover
RedisInsight + Redis Exporter for monitoring
Configured via docker-compose-redis-enhanced.yml

7. Security and RBAC

Secrets: Kubernetes secrets for DB passwords, MinIO keys, etc.
RBAC: Defines service accounts and roles to restrict API access.
Network Policies: Default deny-all with internal allow rules for pods.

8. Monitoring Stack

Prometheus:
Collects metrics from Redis, ML API, and K8s pods
Configured with alert rules e.g., API Down alert

Grafana:
Dashboards for observability
Admin user admin w/ password set in environment

9. Backups

Postgres CronJob:
Nightly pg_dump backup to PVC

Restore Script:
restore-backup.sh restores .sql.gz into container

10. ML Platform Application w/ FastAPI

Dockerized app in dir services/ml-platform
Exposes /health, /metrics, /docs, and authenticated ML endpoints.

Features:
Endpoint Purpose
/auth/register & /auth/login JWT-based user auth
/models/train Trains a RandomForestClassifier, saves to MinIO
/models/{id}/predict Loads model, returns predictions, caches result
/features/store & /features/{set} Feature store using Redis + MongoDB
/metrics Prometheus-compatible metrics

Dependencies:
FastAPI, asyncpg, motor, minio, joblib, sklearn, prometheus_client, PyJWT, uvicorn

11. Kubernetes Deployment

Deployed via:
ml-platform-deployment.yml w/ API, service, ingress
redis-k8s.yml w/ Redis StatefulSet + Services

monitoring.yml w/ Prometheus, Grafana deployments and services

12. Ingress & Port Forwarding

Ingress controller exposes API at ml-platform.local
Local port forwarding for Prometheus (9090), Grafana (3000), API (8000)

13. MinIO Buckets

Buckets created:
models, datasets, features via MinIO client or mc

14. Redis Testing and Monitoring

test-redis-comprehensive.sh:
Validates strings, lists, sets, pub/sub, Lua scripting, etc.
Use-case simulation: session, model caching, leaderboard, rate limiting

monitor-redis.sh:
Live Redis monitoring in terminal

inspect-redis.sh:
Full diagnostics on server, memory, replication, performance

15. End-to-End Testing Scripts
test-platform.sh: checks Docker services, K8s deployments, API, DBs, monitoring

test-ml-workflow.sh: tests user registration, login, model training, and prediction 1. System Setup and Environment Configuration

Directories Created:
scripts, infrastructure/{terraform, ansible, kubernetes, docker}, services, monitoring, tests
Organizes codebase and separates concerns (infra, services, monitoring, testing).

Environment Variables:
PROJECT_DIR – root path for the project.
ENVIRONMENT – "local" to indicate local deployment.
KUBECONFIG – sets the path to the local kubeconfig file.

Checks:
Ensures script is not run in a virtual environment.
Verifies required commands are installed.

2. Prerequisite Installation via install-prerequisites.sh

Installs critical tooling:
Docker, kubectl, Minikube, Helm
Terraform, Ansible, jq, git, Python3 packages
Docker Compose for service orchestration

3. Docker Configuration

Listens on TCP 127.0.0.1:2375 for compatibility with Terraform.
Fixes failed Docker states, ensures Docker is started and accessible.

4. Minikube Kubernetes Cluster
Launches with:

4 CPUs, 4GB RAM, 50GB disk
Docker driver
Kubernetes v1.28.0

Enables:
Ingress, dashboard, metrics-server, registry, etc.

5. Infrastructure Provisioning

a. Terraform
Providers: kubernetes, helm, docker
Resources: Storage class for persistent volumes

Docker volumes for ml-platform-data, ml-platform-models
Uses data blocks to access existing K8s namespaces

b. Ansible
Provisions: Secrets using jwt_secret, db_password, redis_password

Docker networks
Required directories for logs, data, configs

6. Docker Services w/ docker-compose

Core Services:
Service Purpose
PostgreSQL Relational DB to store users, models, predictions
Redis Caching, rate-limiting, sessions, pub/sub
MongoDB Feature store, metadata, prediction logs
Kafka Event streaming backend
MinIO Object storage for datasets and model files
Vault Secrets management
RedisInsight GUI for Redis debugging
Redis Exporter For Prometheus monitoring

Advanced Redis Setup:
Replication: master + 2 replicas

Sentinel: auto-failover
RedisInsight + Redis Exporter for monitoring
Configured via docker-compose-redis-enhanced.yml

7. Security and RBAC

Secrets: Kubernetes secrets for DB passwords, MinIO keys, etc.
RBAC: Defines service accounts and roles to restrict API access.
Network Policies: Default deny-all with internal allow rules for pods.

8. Monitoring Stack

Prometheus:
Collects metrics from Redis, ML API, and K8s pods
Configured with alert rules e.g., API Down alert

Grafana:
Dashboards for observability
Admin user admin w/ password set in environment

9. Backups

Postgres CronJob:
Nightly pg_dump backup to PVC

Restore Script:
restore-backup.sh restores .sql.gz into container

10. ML Platform Application w/ FastAPI

Dockerized app in dir services/ml-platform
Exposes /health, /metrics, /docs, and authenticated ML endpoints.

Features:
Endpoint Purpose
/auth/register & /auth/login JWT-based user auth
/models/train Trains a RandomForestClassifier, saves to MinIO
/models/{id}/predict Loads model, returns predictions, caches result
/features/store & /features/{set} Feature store using Redis + MongoDB
/metrics Prometheus-compatible metrics

Dependencies:
FastAPI, asyncpg, motor, minio, joblib, sklearn, prometheus_client, PyJWT, uvicorn

11. Kubernetes Deployment

Deployed via:
ml-platform-deployment.yml w/ API, service, ingress
redis-k8s.yml w/ Redis StatefulSet + Services

monitoring.yml w/ Prometheus, Grafana deployments and services

12. Ingress & Port Forwarding

Ingress controller exposes API at ml-platform.local
Local port forwarding for Prometheus (9090), Grafana (3000), API (8000)

13. MinIO Buckets

Buckets created:
models, datasets, features via MinIO client or mc

14. Redis Testing and Monitoring

test-redis-comprehensive.sh:
Validates strings, lists, sets, pub/sub, Lua scripting, etc.
Use-case simulation: session, model caching, leaderboard, rate limiting

monitor-redis.sh:
Live Redis monitoring in terminal

inspect-redis.sh:
Full diagnostics on server, memory, replication, performance

15. End-to-End Testing Scripts
test-platform.sh: checks Docker services, K8s deployments, API, DBs, monitoring

test-ml-workflow.sh: tests user registration, login, model training, and prediction 

--

This production grade system is a prototype for personal projects regarding stock prediction with numerical and text data for LLM processing/prediction.
Another system prototype to come later will be for processing, analyzing, and predicting on biological data.  
