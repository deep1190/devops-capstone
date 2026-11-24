output "cluster_name" {
  value = kind_cluster.this.name
}

output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
}

output "next_steps" {
  value = <<-EOT
    export KUBECONFIG=${kind_cluster.this.kubeconfig_path}
    kubectl apply -f argocd/application.yaml
    echo "127.0.0.1 taskflow.local" | sudo tee -a /etc/hosts
    kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
    kubectl -n argocd port-forward svc/argocd-server 8081:443
    kubectl argo rollouts dashboard -n taskflow
  EOT
}
