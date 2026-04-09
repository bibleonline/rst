FROM perl:5.42-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    patch \
    && rm -rf /var/lib/apt/lists/*

RUN cpanm --notest \
    JSON \
    File::Slurp \
    Config::General \
    Readonly \
    && rm -rf ~/.cpanm

WORKDIR /app
