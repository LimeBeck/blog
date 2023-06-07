# LIMEBECK.DEV personal blog

Using `zola`

## Develop

`zola serve` to run in developer mode

or in codespaces:

`docker run -u "$(id -u):$(id -g)" -v $PWD:/app --workdir /app -p 8080:8080 ghcr.io/getzola/zola:v0.17.1 serve --interface 0.0.0.0 --port 8080 --base-url /`

## Build

`zola build` - build to `public` dir

`zola build --base-url $DEPLOY_URL` - build and change base url