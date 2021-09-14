# How to use this

### Clean instana DB and relaunch

```
instana datastores stop && rm -rf /mnt/data/* /mnt/metrics/* /mnt/traces/* /root/.instana && instana datastores init -f settings.hcl
```

### Create a kind cluster 


```
kind create cluster --config instana-cluster.yaml --name instana
```

