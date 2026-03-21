docker run --privileged --rm tonistiigi/binfmt --install all
docker build --platform linux/amd64,linux/arm64 --no-cache -t pdath/ckpool-solo:latest ..
docker push pdath/ckpool-solo:latest