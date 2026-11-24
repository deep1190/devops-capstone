terraform {
  required_version = ">= 1.6"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.6"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

provider "kind" {}

# ---------------------------------------------------------------------------
# Kubernetes cluster (kind: 1 control-plane + 2 workers, runs inside Docker)
# ---------------------------------------------------------------------------
resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = "kindest/node:${var.k8s_version}"
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]
      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
      }
    }
    node {
      role = "worker"
    }
    node {
      role = "worker"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
  }
}

# ---------------------------------------------------------------------------
# Platform components installed with Helm (versions pinned for reproducibility)
# ---------------------------------------------------------------------------
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.chart_versions.ingress_nginx
  values           = [file("${path.module}/values/ingress-nginx.yaml")]
  wait             = true
  depends_on       = [kind_cluster.this]
}

resource "helm_release" "argo_rollouts" {
  name             = "argo-rollouts"
  namespace        = "argo-rollouts"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  version          = var.chart_versions.argo_rollouts
  set {
    name  = "dashboard.enabled"
    value = "true"
  }
  depends_on = [kind_cluster.this]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions.argocd
  depends_on       = [kind_cluster.this]
}

# Prometheus + Alertmanager + Grafana (release name "monitoring" is referenced
# by the AnalysisTemplate: monitoring-kube-prometheus-prometheus).
resource "helm_release" "monitoring" {
  name             = "monitoring"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_versions.kube_prometheus_stack
  values           = [file("${path.module}/values/kube-prometheus-stack.yaml")]
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
  timeout    = 900
  depends_on = [kind_cluster.this, helm_release.ingress_nginx]
}

# Loki (log store) + Promtail (log shipper DaemonSet)
resource "helm_release" "loki" {
  name       = "loki"
  namespace  = "monitoring"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  version    = var.chart_versions.loki_stack
  values     = [file("${path.module}/values/loki-stack.yaml")]
  depends_on = [helm_release.monitoring]
}
