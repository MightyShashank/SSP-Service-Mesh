import json, glob
import numpy as np
import matplotlib.pyplot as plt

BASE = "results/raw/microburst"
BURSTS = ["1ms","5ms","10ms"]

def get_p(data, p):
    for x in data["DurationHistogram"]["Percentiles"]:
        if x["Percentile"]==p:
            return x["Value"]

res={}

for b in BURSTS:
    files=glob.glob(f"{BASE}/*/burst_{b}/svc-a.json")
    vals=[]
    for f in files:
        d=json.load(open(f))
        vals.append(get_p(d,99))
    res[b]=vals

x=[1,5,10]
means=[np.mean(res[b]) for b in BURSTS]
stds=[np.std(res[b]) for b in BURSTS]

plt.figure()
plt.errorbar(x,means,yerr=stds,marker='o',capsize=5)
plt.xlabel("Burst (ms)")
plt.ylabel("P99 latency (s)")
plt.title("Burst vs Tail Latency")
plt.grid()
plt.savefig("burst_vs_p99.png")

print("Means:",means)
print("Stds:",stds)