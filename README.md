# Cilium BGP Test

Sets up a test environment for Cilium with BGP on a kind cluster in a Linux environment.

To validate the cluster, an nginx deployment is exported via BGP to the host via a private class A IPv4 address on port 80.

## Requirements:

1. Docker
2. Linux kernel with eBPF support (I'm using WSL2 with a custom kernel).

## Setup

```bash
./cilium-install.sh
```

Then, check for a 10.12.x.x nhid address:

```bash
edwin@DADSTATION:~$ ip route
default via 172.27.192.1 dev eth0 proto kernel
10.12.253.51 nhid 45 proto bgp metric 20
10.242.0.0/24 nhid 34 via 172.28.0.3 dev br-4ef17eb25f80 proto bgp metric 20
10.242.1.0/24 nhid 44 via 172.28.0.2 dev br-4ef17eb25f80 proto bgp metric 20
10.242.2.0/24 nhid 38 via 172.28.0.4 dev br-4ef17eb25f80 proto bgp metric 20
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1 linkdown
172.27.192.0/20 dev eth0 proto kernel scope link src 172.27.204.227
172.28.0.0/16 dev br-4ef17eb25f80 proto kernel scope link src 172.28.0.1
```

In this case the interesting address is 10.12.253.51.

Then see what you get from port 80 at that address from the host:

```bash
curl 10.12.253.51
```
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

PROFIT!