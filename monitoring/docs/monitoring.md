# Monitoring

## Overview

Monitoring is a critical component of any production-grade Kubernetes platform. It provides real-time visibility into the health, performance, and availability of the cluster and its deployed applications. A proper monitoring solution enables early detection of issues, performance analysis, and proactive incident response.

In this project, the monitoring stack was deployed using the **kube-prometheus-stack** Helm chart. The stack includes Prometheus for metrics collection, Grafana for visualization, Alertmanager for alert management, Node Exporter for node-level metrics, kube-state-metrics for Kubernetes object metrics, and the Prometheus Operator for managing Prometheus resources.

The following sections describe the monitoring stack components, deployment process, and verification steps used in this project.

## Monitoring Stack Components

The monitoring solution deployed in this project consists of the following components:

| Component | Description |
|---|---|
| Prometheus | Collects and stores time-series metrics from Kubernetes and infrastructure components. |
| Grafana | Visualizes metrics using interactive dashboards. |
| Alertmanager | Receives alerts from Prometheus and manages alert routing and notifications. |
| Node Exporter | Collects hardware and operating system metrics from each worker node. |
| kube-state-metrics | Exposes metrics about Kubernetes objects such as Pods, Deployments, Nodes, and ReplicaSets. |
| Prometheus Operator | Simplifies the deployment, configuration, and lifecycle management of Prometheus inside Kubernetes. |

## Deployment

The monitoring stack was deployed using the **kube-prometheus-stack** Helm chart, following the steps outlined below.

### Add the Helm Repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm repo update
```

### Install the Monitoring Stack

```bash
helm install monitoring prometheus-community/kube-prometheus-stack \
--namespace monitoring \
--create-namespace
```

After the installation completed successfully, Kubernetes created all required resources, including Deployments, StatefulSets, Services, ConfigMaps, ServiceAccounts, and Custom Resource Definitions (CRDs).

The deployment included the following core services:

- Prometheus
- Grafana
- Alertmanager
- Prometheus Operator
- Node Exporter
- kube-state-metrics

## Monitoring Verification

After deploying the monitoring stack, several verification steps were performed to confirm that all components were operating correctly. These steps verified that the monitoring services were running, Prometheus was successfully collecting metrics, and Grafana was able to visualize the collected data.

The following verification steps were performed:

- Verify that all monitoring Pods are running.
- Verify that Prometheus successfully scrapes metrics from all configured targets.
- Verify that Grafana dashboards display real-time metrics.

### 1. Verify Monitoring Components

The first verification step was to ensure that all monitoring components were successfully deployed and running inside the `monitoring` namespace.

The following command was used:

```bash
kubectl get pods -n monitoring
```

The output confirmed that all core monitoring services were running successfully, including:

- Prometheus
- Grafana
- Alertmanager
- Prometheus Operator
- kube-state-metrics
- Node Exporter (running on all worker nodes)

This verification confirms that the monitoring stack was deployed successfully and all required services were available.

> **Screenshot:** Monitoring Components

![Monitoring Components](../screenshots/Verify%20Monitoring%20Components.png)

### 2. Verify Prometheus Targets

To verify that Prometheus was successfully collecting metrics from the Kubernetes cluster, the Prometheus web interface was accessed using port forwarding.

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
```

After accessing the Prometheus UI at `http://localhost:9090`, the **Status → Targets** page was used to verify all configured scrape targets.

All targets were reported as **UP**, including:

- Prometheus
- Grafana
- Alertmanager
- Kubernetes API Server
- CoreDNS
- kubelet
- kube-proxy
- kube-state-metrics
- Node Exporter

Additionally, Prometheus successfully scraped metrics from all four Kubernetes worker nodes through Node Exporter.

This verification confirms that Prometheus was successfully collecting metrics from the entire Kubernetes cluster.

> **Screenshot:** Prometheus Status → Targets

![Prometheus Targets](../screenshots/prometheus/target%20health.png)

### Verification Summary

The monitoring stack was successfully deployed and verified. All monitoring components were running correctly, Prometheus was collecting metrics from the Kubernetes cluster, and Grafana was successfully visualizing the collected data through its dashboards.

The verification confirmed the following:

- All monitoring Pods were running successfully.
- Prometheus targets were healthy and in the **UP** state.
- Metrics were collected from all Kubernetes worker nodes.
- Grafana dashboards displayed real-time monitoring data.

# Alert Rules

## Overview

Prometheus Alert Rules continuously evaluate metrics collected from the Kubernetes cluster and generate alerts when predefined conditions are met. These rules help detect infrastructure and application issues in real time, allowing operators to respond quickly before they impact system availability.

In this project, custom alert rules were created to monitor the overall health of the Kubernetes cluster, including pod availability, node status, CPU utilization, and memory utilization.

## Alert Rules File

Location:

```text
monitoring/alerts/custom-alerts.yaml
```

## Deploy Alert Rules

Apply the custom alert rules to the monitoring namespace.

```bash
kubectl apply -f alerts/custom-alerts.yaml
```

## Verify Deployment

Verify that the PrometheusRule resource has been created successfully.

```bash
kubectl get prometheusrules -n monitoring
```

Expected Output

```text
NAME                 AGE
custom-alert-rules   5s
```

## Configured Alert Rules

| Alert Name | Description | Severity |
|---|---|---|
| PodDown | Detects when a pod becomes unavailable. | Warning |
| NodeNotReady | Detects Kubernetes nodes that are not in the Ready state. | Critical |
| HighCPUUsage | Triggers when CPU usage exceeds the configured threshold. | Warning |
| HighMemoryUsage | Triggers when memory usage exceeds the configured threshold. | Warning |

## Validation

The alert rules were validated by intentionally creating failure scenarios within the Kubernetes cluster. Once the alert conditions were met, Prometheus successfully evaluated the rules and forwarded the generated alerts to Alertmanager for notification processing.

# Alertmanager

## Overview

Alertmanager is responsible for processing alerts generated by Prometheus. It groups alerts, applies routing rules, suppresses duplicate notifications, and delivers notifications through configured communication channels.

In this project, Alertmanager was configured to send email notifications using Gmail SMTP.

## Configuration File

Location:

```text
monitoring/alerts/alertmanager-values.yaml
```

## Features

The Alertmanager configuration includes:

- Gmail SMTP integration
- Email notification receiver
- Alert grouping
- Alert routing
- Watchdog suppression
- Inhibit rules
- Automatic resolved notifications

## Deploy Alertmanager Configuration

After updating the configuration, apply the changes using Helm.

```bash
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f alerts/alertmanager-values.yaml
```

## Verify Deployment

Verify that the Alertmanager pod is running successfully.

```bash
kubectl get pods -n monitoring
```

Expected Output

```text
alertmanager-monitoring-kube-prometheus-alertmanager-0   Running
```

## Verify Configuration

Check that Alertmanager loaded the latest configuration.

```bash
kubectl logs alertmanager-monitoring-kube-prometheus-alertmanager-0 \
-n monitoring
```

Expected Output

```text
Loading configuration file
Completed loading of configuration file
```

## Alert Flow

```
Prometheus
      │
      ▼
Evaluate Alert Rules
      │
      ▼
Alertmanager
      │
      ▼
Group Alerts
      │
      ▼
Email Receiver
      │
      ▼
Gmail SMTP
      │
      ▼
Email Notification
```

## Alert Testing

To validate the monitoring pipeline, a running application pod was intentionally deleted.

```bash
kubectl delete pod <pod-name> -n <namespace>
```

Validation Results:

- Prometheus detected the pod failure.
- The corresponding alert entered the Firing state.
- Alertmanager received the alert.
- The alert was routed to the configured email receiver.
- An email notification was generated.
- Kubernetes automatically recreated the deleted pod.
- The alert was resolved after the application recovered.

## Summary

The monitoring solution provides complete observability for the Kubernetes environment by combining Prometheus, Grafana, and Alertmanager. Custom alert rules continuously monitor cluster health, while Alertmanager ensures that critical events are delivered through email notifications, enabling rapid detection and response to operational issues.
