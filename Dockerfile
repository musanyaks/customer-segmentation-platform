# Pinned base image: its R repo is a fixed dated Posit Package Manager snapshot
# of precompiled Linux binaries, so builds are fast and reproducible.
FROM rocker/shiny:4.4.3

# System libraries some R packages need at install/run time
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev libssl-dev libxml2-dev libfontconfig1-dev \
    libfreetype6-dev libfribidi-dev libharfbuzz-dev libjpeg-dev \
    libpng-dev libtiff-dev \
    && rm -rf /var/lib/apt/lists/*

# Install the app's packages as binaries from the image's pinned snapshot
RUN install2.r --error --skipinstalled \
    shiny shinydashboard tidyverse lubridate scales plotly DT cluster

COPY app.R /srv/shiny-server/app.R

EXPOSE 3838

CMD ["R", "-e", "shiny::runApp('/srv/shiny-server/app.R', host = '0.0.0.0', port = 3838)"]
