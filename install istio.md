# How to Install istioctl

If you encounter an `istioctl not found` error, run the following commands to install the Istio CLI tool globally:

```bash
cd /tmp
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.23.0 sh -

# Then move binary with sudo
sudo mv /tmp/istio-1.23.0/bin/istioctl /usr/local/bin/

# Verify
istioctl version
```
