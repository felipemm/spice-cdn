export const defaultInstanceValuesYaml = `ingress:
  enabled: true
  className: nginx
  host: spice-INSTANCE.127.0.0.1.nip.io

externalSecret:
  enabled: true
  clusterSecretStoreName: vault-backend
  vaultPath: spice/instances/INSTANCE
  targetSecretName: spice-INSTANCE-env
  refreshInterval: 1m

spiceai:
  spicepod:
    name: app
    version: v1
    kind: Spicepod
    datasets: []
  additionalEnv: []
  service:
    type: ClusterIP
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      memory: 1Gi
`;

export function renderInstanceTemplate(instance: string) {
  return defaultInstanceValuesYaml.replaceAll("INSTANCE", instance);
}
