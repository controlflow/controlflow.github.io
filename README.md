Proceed to my [personal dev blog](https://controlflow.github.io).

## Local development

Install Ruby 3.3 (see `.ruby-version`), then run:

```sh
gem install bundler -v 4.0.20
bundle install
bundle exec jekyll serve
```

On Windows, install Ruby with DevKit; `serve.cmd` also installs dependencies
and opens the local preview. The lockfile supports Windows, Linux and Apple Silicon.

## Validation and dependency updates

```sh
bundle update
bundle outdated --strict
bundle exec bundle-audit check --update
bundle exec jekyll build --trace
bundle exec jekyll doctor
```

The site uses Jekyll directly instead of the `github-pages` meta-gem, which
pins unused plugins and vulnerable transitive dependencies. Dependencies are
updated to the newest releases allowed by Jekyll. Jekyll 4.4 still requires
older major versions of JSON, Liquid, Rouge and terminal-table.

Dependabot groups weekly Ruby and GitHub Actions updates into separate PRs.
CI audits dependencies against ruby-advisory-db and builds the site on each PR.

## GitHub Pages

Before merging this migration, open **Settings → Pages → Build and deployment**
and set **Source** to **GitHub Actions**. The built-in branch-based Jekyll build
uses the old GitHub Pages dependency set.

The Pages workflow deploys successful builds from `master`. Pull requests only
run validation; they do not deploy. A deployment can also be started manually
with **Actions → Build and deploy Pages → Run workflow** on `master`.
