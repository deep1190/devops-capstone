variable "cluster_name" {
  description = "Name of the kind cluster."
  type        = string
  default     = "taskflow"
}

variable "k8s_version" {
  description = "kindest/node image tag (Kubernetes version)."
  type        = string
  default     = "v1.31.2"
}

variable "grafana_admin_password" {
  description = "Grafana admin password (pass via TF_VAR_grafana_admin_password)."
  type        = string
  sensitive   = true
}

variable "chart_versions" {
  description = "Pinned Helm chart versions. Bump deliberately, review the changelog."
  type = object({
    ingress_nginx         = string
    argo_rollouts         = string
    argocd                = string
    kube_prometheus_stack = string
    loki_stack            = string
  })
  default = {
    ingress_nginx         = "4.11.3"
    argo_rollouts         = "2.38.0"
    argocd                = "7.7.11"
    kube_prometheus_stack = "67.4.0"
    loki_stack            = "2.10.2"
  }
}
