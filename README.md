<p align="center">
  <!-- placeholder: replace docs/images/logo.png with the real image -->
  <img src="doc/images/logo.png" alt="retriever logo" width="300">
</p>

<p align="center"><em>"He is golden, he was born to fetch."</em></p>

# retriever

A small helper that fetches files from GitHub releases, private ones included, and drops them where your app expects them, before your app starts.

## Why

Some apps need extra files to run, such as plugins, tools or config files. Those files often live as downloads on a GitHub release page. This helper gets them so you don't have to bake them into your app's image.

## How it works

1. You write a short list: which project, which release, which file, and where to put it.
2. When your app starts in Kubernetes, this helper runs first. It downloads each file on the list into a shared folder.
3. Your app then starts and finds the files in that folder.

If any download fails, the helper stops and your app does not start, so it never runs with files missing.

## The list

Each line names one download, in this order:

```
<owner/project> <release> <file name> <where to put it>
```

Example:

```
myorg/plugin-a v1.0.0 plugin-a-linux-amd64 /out/bin/plugin-a
myorg/configs  v1.0.0 *.yaml               /out/conf/
```

- If the last part ends with `/`, it is a folder and the file keeps its own name.
- Otherwise it is the exact path to save the file as.
- `*` matches any text, so `*.yaml` grabs every `.yaml` file in that release.
- Empty lines and lines starting with `#` are ignored.

The helper reads the list from `/config/artifacts`. Set `SPEC` to use another path.

## Access to private projects

The helper needs a GitHub token that can read the projects on your list. Store it in Kubernetes:

```sh
kubectl create secret generic gh-token --from-literal=token=<your-token>
```

## Try it

[`k8s/deployment.yaml`](k8s/deployment.yaml) is a full example: the list, the helper, and a simple Ubuntu app that prints the files it received. Edit the list, then:

```sh
kubectl apply -f k8s/deployment.yaml
```

## Building the image

```sh
podman build -t retriever:dev .
```

Pull requests and version tags (like `v1.2.3`) are built automatically and published to `ghcr.io/<owner>/<repo>`.
