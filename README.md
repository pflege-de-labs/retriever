<p align="center">
  <img src="doc/images/logo.jpg" alt="retriever logo" width="300">
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
- If the list is missing or empty, the helper downloads nothing and your app starts normally.

The helper reads the list from `/config/artifacts`. Set `SPEC` to use another path.

## Access to private projects

Public projects need nothing. For private ones, the helper needs a GitHub token that can read the projects on your list.

Use a **fine-grained personal access token** (GitHub → Settings → Developer settings):

- **Resource owner:** the account or organization that owns the projects. An organization may have to approve the token first.
- **Repository access:** only the projects on your list.
- **Permissions:** *Contents: Read-only*. That is all; release downloads count as contents.

Fine-grained tokens expire. When yours does, downloads from private projects fail, so renew it in time. A classic token with the `repo` scope also works, but it can change every private project you have access to, which is far more than needed.

Store the token in Kubernetes:

```sh
kubectl create secret generic gh-token --from-literal=token=<your-token>
```

If GitHub refuses access (a missing, wrong or too limited token), the helper stops with an error that names the project, and your app does not start.

### Download limit without a token

Without a token, GitHub allows only 60 requests per hour, counted per internet address. All pods in a cluster usually share one address, so they share these 60 requests. Each line of the list uses one request, plus one per downloaded file. When the limit is used up, the helper stops with an error and your app does not start until the hour is over. With a token, the limit is 5,000 requests per hour, so set a token whenever many pods start often, even for public projects.

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
