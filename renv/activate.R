# ==============================================================================
# renv activation script (bootstrap)
# Generated for renv 1.x — do not edit unless you know what you're doing.
# ==============================================================================

local({

  # the requested version of renv
  version <- "1.0.11"
  attr(version, "md5") <- "d7e87d7466ca891a830ff3136e779f4b"

  # the project directory
  project <- Sys.getenv("RENV_PROJECT")
  if (!nzchar(project))
    project <- getwd()

  # figure out whether the autoloader is enabled
  enabled <- local({
    override <- Sys.getenv("RENV_CONFIG_AUTOLOADER_ENABLED")
    if (!nzchar(override)) return(!identical(override, "FALSE"))
    enabled <- getOption("renv.config.autoloader.enabled")
    if (!is.null(enabled)) return(enabled)
    TRUE
  })

  if (!enabled)
    return(FALSE)

  # avoid recursion
  if (identical(getOption("renv.autoloader.running"), TRUE)) {
    warning("ignoring recursive attempt to run renv autoloader")
    return(invisible(TRUE))
  }

  # signal that we're loading renv during R startup
  options(renv.autoloader.running = TRUE)
  on.exit(options(renv.autoloader.running = NULL), add = TRUE)

  # signal that we've consented to use renv
  options(renv.consent = TRUE)

  # load the 'utils' package eagerly -- this ensures that renv shims, which
  # mask 'utils' packages, will come first on the search path
  library(utils, lib.loc = .Library)

  # use start-up diagnostics if requested
  diagnostics <- Sys.getenv("RENV_STARTUP_DIAGNOSTICS", unset = "FALSE")
  if (diagnostics == "TRUE") {
    cat("== renv startup diagnostics ==\n")
    cat("project: ", project, "\n")
    cat("libdir:  ", .libPaths()[1L], "\n")
  }

  # try loading renv from the project library
  if (!requireNamespace("renv", lib.loc = file.path(project, "renv/library"), quietly = TRUE)) {

    # renv not available in the project library -- bootstrap it
    cat("renv", version, "not found in project library -- bootstrapping...\n")

    # install renv into a temporary library, then move it into place
    lib <- tempfile("renv-library-")
    dir.create(lib, recursive = TRUE, showWarnings = FALSE)
    utils::install.packages("renv", lib = lib, repos = getOption("repos"),
                            quiet = TRUE)

    target <- file.path(project, "renv/library",
                        paste0("R-", getRversion()[1, 1:2]),
                        .Platform$OS.type,
                        "renv")
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    file.rename(file.path(lib, "renv"), target)

    cat("renv", version, "bootstrapped to", shQuote(target), "\n")
  }

  # load renv and activate the project
  library(renv, lib.loc = dirname(file.path(project, "renv/library",
          paste0("R-", getRversion()[1, 1:2]), .Platform$OS.type, "renv")))
  renv::load(project = project)

  invisible(TRUE)
})