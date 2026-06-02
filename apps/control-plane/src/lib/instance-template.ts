export const defaultInstanceValuesYaml = `ownerLayerSlug: LAYERSLUG

ingress:
  enabled: true
  className: nginx
  host: spice-INSTANCE.127.0.0.1.nip.io
  flightSQL:
    enabled: true
    port: 50051

externalSecret:
  enabled: true
  clusterSecretStoreName: vault-backend
  vaultPath: spice/instances/INSTANCE
  targetSecretName: spice-INSTANCE-env
  refreshInterval: 1m

spiceai:
  additionalLabels:
    owner-layer-slug: LAYERSLUG
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

export function renderInstanceTemplate(instance: string, ownerLayerSlug: string) {
  const slug = ownerLayerSlug.trim();
  return defaultInstanceValuesYaml.replaceAll("INSTANCE", instance).replaceAll("LAYERSLUG", slug);
}
