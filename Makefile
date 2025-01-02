VERSION := $(shell yq e ".version" manifest.yaml)
FULCRUM_SRC := $(shell find ./Fulcrum/src)
CONFIGURATOR_SRC := $(shell find ./configurator/src) configurator/Cargo.toml configurator/Cargo.lock
PKG_VERSION := $(shell yq e ".version" manifest.yaml)
PKG_ID := $(shell yq e ".id" manifest.yaml)
S9PK_PATH=$(shell find . -name fulcrum.s9pk -print)
TS_FILES := $(shell find . -name \*.ts )

.DELETE_ON_ERROR:

all: verify

verify: $(PKG_ID).s9pk
	start-sdk verify s9pk $(PKG_ID).s9pk

install: $(PKG_ID).s9pk
	start-cli package install $(PKG_ID).s9pk

clean:
	rm -f image.tar
	rm -f $(PKG_ID).s9pk
	rm -f scripts/*.js

# for rebuilding just the arm image. will include docker-images/x86_64.tar into the s9pk if it exists
arm: docker-images/aarch64.tar scripts/embassy.js
	start-sdk pack

# for rebuilding just the x86 image. will include docker-images/aarch64.tar into the s9pk if it exists
x86: docker-images/x86_64.tar scripts/embassy.js
	start-sdk pack

$(PKG_ID).s9pk: manifest.yaml instructions.md scripts/embassy.js fulcrum/LICENSE.txt docker-images/aarch64.tar docker-images/x86_64.tar
	start-sdk pack

docker-images/aarch64.tar: Dockerfile docker_entrypoint.sh configurator/target/aarch64-unknown-linux-musl/release/configurator $(FULCRUM_SRC)
	mkdir -p docker-images
	DOCKER_CLI_EXPERIMENTAL=enabled docker buildx build --tag start9/$(PKG_ID)/main:$(PKG_VERSION) --build-arg ARCH=aarch64 --build-arg PLATFORM=arm64 --platform=linux/arm64 -o type=docker,dest=docker-images/aarch64.tar .

docker-images/x86_64.tar: Dockerfile docker_entrypoint.sh configurator/target/x86_64-unknown-linux-musl/release/configurator $(FULCRUM_SRC)
	mkdir -p docker-images
	DOCKER_CLI_EXPERIMENTAL=enabled docker buildx build --tag start9/$(PKG_ID)/main:$(PKG_VERSION) --build-arg ARCH=x86_64 --build-arg PLATFORM=amd64 --platform=linux/amd64 -o type=docker,dest=docker-images/x86_64.tar .

configurator/target/aarch64-unknown-linux-musl/release/configurator: $(CONFIGURATOR_SRC)
	docker run --rm -it -v ~/.cargo/registry:/root/.cargo/registry -v "$(shell pwd)"/configurator:/home/rust/src start9/rust-musl-cross:aarch64-musl cargo build --release

configurator/target/x86_64-unknown-linux-musl/release/configurator: $(CONFIGURATOR_SRC)
	docker run --rm -it -v ~/.cargo/registry:/root/.cargo/registry -v "$(shell pwd)"/configurator:/home/rust/src start9/rust-musl-cross:x86_64-musl cargo build --release

scripts/embassy.js: $(TS_FILES)
	deno bundle scripts/embassy.ts scripts/embassy.js

fulcrum/LICENSE.txt:
	git submodule update --init