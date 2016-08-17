## NGINX Hello World Image

## Purpose

This image is used to demonstrate a simple Hello World Docker image using NGINX. It serves up a single HTML page that shows the hostname of the container.

## Usage

Start the container and publish port 80 to some port on the host.

```
docker run -d -p 80 scottsbaldwin/docker-hello-world
```
