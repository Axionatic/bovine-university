#!/bin/bash
set -e

# Bovine University Setup Script
# Configures any project for the ralph-wiggum plugin
# https://github.com/Axionatic/bovine-university

REPO_URL="https://raw.githubusercontent.com/Axionatic/bovine-university/main"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ========================================
# Platform gate
# ========================================
detect_os() {
  case "$(uname)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

OS=$(detect_os)
if [[ "$OS" == "windows" ]]; then
  echo ""
  echo -e "${RED}Bovine University requires Linux or macOS for OS-level sandboxing.${NC}"
  echo ""
  echo "To use on Windows:"
  echo "  1. Install WSL2: wsl --install"
  echo "  2. Open a WSL2 terminal"
  echo "  3. Re-run this setup script from within WSL2"
  exit 1
fi

# Check dependencies
check_deps() {
  command -v jq >/dev/null 2>&1 || error "jq is required. Install: brew install jq / apt install jq"
  command -v curl >/dev/null 2>&1 || error "curl is required"
  command -v git >/dev/null 2>&1 || error "git is required"
}

# Find project root (look for .git, package.json, etc.)
find_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" ]] || [[ -f "$dir/package.json" ]] || [[ -f "$dir/Cargo.toml" ]] || [[ -f "$dir/go.mod" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  echo "$PWD"
}

# Download template from repo
fetch_template() {
  local path="$1"
  curl -fsSL "$REPO_URL/templates/$path" 2>/dev/null || error "Failed to fetch template: $path"
}

# Ask question with numbered options, returns the selected index (1-based)
ask() {
  local prompt="$1"
  shift
  local options=("$@")
  local default=1

  echo ""
  echo -e "${BLUE}$prompt${NC}"
  for i in "${!options[@]}"; do
    local label="${options[$i]}"
    if [[ "$label" == *"(Recommended)"* ]]; then
      default=$((i + 1))
    fi
    echo "  $((i+1))) $label"
  done

  read -p "Choice [$default]: " choice
  choice="${choice:-$default}"

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#options[@]} ]]; then
    echo "$default"
  else
    echo "$choice"
  fi
}

# ========================================
# Ecosystem detection
# ========================================
detect_ecosystems() {
  local dir="$1"
  DETECTED_ECOSYSTEMS=()
  DETECTED_DOMAINS=()

  # Always-included base domains
  DETECTED_DOMAINS+=("api.anthropic.com" "github.com" "api.github.com" "raw.githubusercontent.com")

  # Node.js
  if [[ -f "$dir/package.json" ]] || [[ -f "$dir/yarn.lock" ]] || [[ -f "$dir/pnpm-lock.yaml" ]] || [[ -f "$dir/bun.lockb" ]]; then
    DETECTED_ECOSYSTEMS+=("Node.js")
    DETECTED_DOMAINS+=("registry.npmjs.org" "registry.yarnpkg.com")
  fi

  # TypeScript
  if [[ -f "$dir/tsconfig.json" ]]; then
    DETECTED_ECOSYSTEMS+=("TypeScript")
    # Same domains as Node.js, add if not already present
    if [[ ! " ${DETECTED_DOMAINS[*]} " =~ " registry.npmjs.org " ]]; then
      DETECTED_DOMAINS+=("registry.npmjs.org" "registry.yarnpkg.com")
    fi
  fi

  # Deno
  if [[ -f "$dir/deno.json" ]] || [[ -f "$dir/deno.jsonc" ]]; then
    DETECTED_ECOSYSTEMS+=("Deno")
    DETECTED_DOMAINS+=("deno.land" "jsr.io")
  fi

  # Bun
  if [[ -f "$dir/bunfig.toml" ]]; then
    DETECTED_ECOSYSTEMS+=("Bun")
    if [[ ! " ${DETECTED_DOMAINS[*]} " =~ " registry.npmjs.org " ]]; then
      DETECTED_DOMAINS+=("registry.npmjs.org" "registry.yarnpkg.com")
    fi
  fi

  # Python
  if [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/setup.py" ]] || [[ -f "$dir/Pipfile" ]] || [[ -f "$dir/poetry.lock" ]]; then
    DETECTED_ECOSYSTEMS+=("Python")
    DETECTED_DOMAINS+=("pypi.org" "files.pythonhosted.org")
  fi

  # Rust
  if [[ -f "$dir/Cargo.toml" ]]; then
    DETECTED_ECOSYSTEMS+=("Rust")
    DETECTED_DOMAINS+=("crates.io" "static.crates.io")
  fi

  # Go
  if [[ -f "$dir/go.mod" ]]; then
    DETECTED_ECOSYSTEMS+=("Go")
    DETECTED_DOMAINS+=("proxy.golang.org" "sum.golang.org")
  fi

  # Java/Kotlin
  if [[ -f "$dir/pom.xml" ]] || [[ -f "$dir/build.gradle" ]] || [[ -f "$dir/build.gradle.kts" ]]; then
    DETECTED_ECOSYSTEMS+=("Java/Kotlin")
    DETECTED_DOMAINS+=("repo.maven.apache.org" "plugins.gradle.org" "services.gradle.org")
  fi

  # Ruby
  if [[ -f "$dir/Gemfile" ]]; then
    DETECTED_ECOSYSTEMS+=("Ruby")
    DETECTED_DOMAINS+=("rubygems.org")
  fi

  # PHP
  if [[ -f "$dir/composer.json" ]]; then
    DETECTED_ECOSYSTEMS+=("PHP")
    DETECTED_DOMAINS+=("packagist.org" "repo.packagist.org")
  fi

  # Dart/Flutter
  if [[ -f "$dir/pubspec.yaml" ]]; then
    DETECTED_ECOSYSTEMS+=("Dart/Flutter")
    DETECTED_DOMAINS+=("pub.dev")
  fi

  # C#/.NET
  if compgen -G "$dir/*.csproj" > /dev/null 2>&1 || compgen -G "$dir/*.sln" > /dev/null 2>&1 || [[ -f "$dir/global.json" ]]; then
    DETECTED_ECOSYSTEMS+=("C#/.NET")
    DETECTED_DOMAINS+=("api.nuget.org")
  fi

  # C/C++
  if [[ -f "$dir/CMakeLists.txt" ]] || [[ -f "$dir/meson.build" ]] || [[ -f "$dir/conanfile.py" ]] || [[ -f "$dir/vcpkg.json" ]]; then
    DETECTED_ECOSYSTEMS+=("C/C++")
    DETECTED_DOMAINS+=("conan.io" "vcpkg.io")
  fi

  # Swift
  if [[ -f "$dir/Package.swift" ]] || compgen -G "$dir/*.xcodeproj" > /dev/null 2>&1; then
    DETECTED_ECOSYSTEMS+=("Swift")
  fi

  # R
  if [[ -f "$dir/DESCRIPTION" ]] || compgen -G "$dir/*.Rproj" > /dev/null 2>&1 || [[ -f "$dir/renv.lock" ]]; then
    DETECTED_ECOSYSTEMS+=("R")
    DETECTED_DOMAINS+=("cran.r-project.org" "cloud.r-project.org")
  fi

  # Scala
  if [[ -f "$dir/build.sbt" ]] || [[ -f "$dir/build.sc" ]]; then
    DETECTED_ECOSYSTEMS+=("Scala")
    if [[ ! " ${DETECTED_DOMAINS[*]} " =~ " repo.maven.apache.org " ]]; then
      DETECTED_DOMAINS+=("repo.maven.apache.org")
    fi
  fi

  # Lua
  if compgen -G "$dir/*.rockspec" > /dev/null 2>&1; then
    DETECTED_ECOSYSTEMS+=("Lua")
    DETECTED_DOMAINS+=("luarocks.org")
  fi
}

# ========================================
# Framework detection + quality gates
# ========================================
detect_frameworks() {
  local dir="$1"
  DETECTED_FRAMEWORKS=()
  QUALITY_GATES=()

  # Helper: check if a package.json dependency exists
  has_dep() {
    local pkg="$1"
    if [[ -f "$dir/package.json" ]]; then
      jq -e --arg p "$pkg" '(.dependencies[$p] // .devDependencies[$p] // .peerDependencies[$p]) != null' "$dir/package.json" > /dev/null 2>&1
    else
      return 1
    fi
  }

  has_dev_dep() {
    local pkg="$1"
    if [[ -f "$dir/package.json" ]]; then
      jq -e --arg p "$pkg" '.devDependencies[$p] != null' "$dir/package.json" > /dev/null 2>&1
    else
      return 1
    fi
  }

  # Helper: check if a string exists in a file
  file_contains() {
    local file="$1"
    local pattern="$2"
    [[ -f "$file" ]] && grep -q "$pattern" "$file" 2>/dev/null
  }

  # Helper: add quality gate if not already present
  add_gate() {
    local cmd="$1"
    if [[ ! " ${QUALITY_GATES[*]} " =~ " ${cmd} " ]]; then
      QUALITY_GATES+=("$cmd")
    fi
  }

  # --- Node.js / TypeScript frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Node.js " ]] || [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " TypeScript " ]] || [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Bun " ]]; then

    # Next.js
    if compgen -G "$dir/next.config."{js,mjs,ts} > /dev/null 2>&1 || has_dep "next"; then
      DETECTED_FRAMEWORKS+=("Next.js")
      add_gate "npx next build"
      add_gate "npx next lint"
    fi

    # Nuxt
    if compgen -G "$dir/nuxt.config."{js,ts} > /dev/null 2>&1 || has_dep "nuxt"; then
      DETECTED_FRAMEWORKS+=("Nuxt")
      add_gate "npx nuxi build"
    fi

    # SvelteKit
    if compgen -G "$dir/svelte.config."{js,ts} > /dev/null 2>&1 || has_dep "@sveltejs/kit"; then
      DETECTED_FRAMEWORKS+=("SvelteKit")
      add_gate "npm run build"
      add_gate "npm run check"
    fi

    # Angular
    if [[ -f "$dir/angular.json" ]] || has_dep "@angular/core"; then
      DETECTED_FRAMEWORKS+=("Angular")
      add_gate "npx ng build"
      add_gate "npx ng test"
    fi

    # Astro
    if compgen -G "$dir/astro.config."{mjs,js,ts} > /dev/null 2>&1 || has_dep "astro"; then
      DETECTED_FRAMEWORKS+=("Astro")
      add_gate "npx astro build"
    fi

    # Remix
    if compgen -G "$dir/remix.config."{js,ts} > /dev/null 2>&1 || has_dep "@remix-run/react"; then
      DETECTED_FRAMEWORKS+=("Remix")
      add_gate "npm run build"
    fi

    # Gatsby
    if compgen -G "$dir/gatsby-config."{js,ts} > /dev/null 2>&1 || has_dep "gatsby"; then
      DETECTED_FRAMEWORKS+=("Gatsby")
      add_gate "npx gatsby build"
    fi

    # SolidJS
    if has_dep "solid-js"; then
      DETECTED_FRAMEWORKS+=("SolidJS")
      add_gate "npm run build"
    fi

    # NestJS
    if [[ -f "$dir/nest-cli.json" ]] || has_dep "@nestjs/core"; then
      DETECTED_FRAMEWORKS+=("NestJS")
      add_gate "npm run build"
      add_gate "npm run test"
    fi

    # Express
    if has_dep "express"; then
      DETECTED_FRAMEWORKS+=("Express")
      add_gate "npm test"
    fi

    # Fastify
    if has_dep "fastify"; then
      DETECTED_FRAMEWORKS+=("Fastify")
      add_gate "npm test"
    fi

    # Hono
    if has_dep "hono"; then
      DETECTED_FRAMEWORKS+=("Hono")
      add_gate "npm test"
    fi

    # React Native
    if has_dep "react-native" && [[ -f "$dir/app.json" ]]; then
      DETECTED_FRAMEWORKS+=("React Native")
      add_gate "npx react-native doctor"
    fi

    # Expo
    if has_dep "expo" || [[ -f "$dir/eas.json" ]]; then
      DETECTED_FRAMEWORKS+=("Expo")
      add_gate "npx expo doctor"
    fi

    # Electron
    if has_dev_dep "electron"; then
      DETECTED_FRAMEWORKS+=("Electron")
      add_gate "npm run build"
    fi

    # Tauri
    if [[ -f "$dir/src-tauri/tauri.conf.json" ]]; then
      DETECTED_FRAMEWORKS+=("Tauri")
      add_gate "cargo test"
      add_gate "npm run build"
    fi

    # Build tools (only if no higher-level framework detected build gate)
    if compgen -G "$dir/vite.config."{js,ts,mjs} > /dev/null 2>&1; then
      DETECTED_FRAMEWORKS+=("Vite")
      add_gate "npx vite build"
    fi

    if compgen -G "$dir/webpack.config."{js,ts} > /dev/null 2>&1; then
      DETECTED_FRAMEWORKS+=("Webpack")
      add_gate "npx webpack build"
    fi

    # Test frameworks
    if compgen -G "$dir/vitest.config."{js,ts} > /dev/null 2>&1 || has_dev_dep "vitest"; then
      DETECTED_FRAMEWORKS+=("Vitest")
      add_gate "npx vitest run"
    fi

    if compgen -G "$dir/jest.config."{js,ts,cjs} > /dev/null 2>&1 || has_dev_dep "jest"; then
      DETECTED_FRAMEWORKS+=("Jest")
      add_gate "npx jest"
    fi

    if compgen -G "$dir/playwright.config."{js,ts} > /dev/null 2>&1; then
      DETECTED_FRAMEWORKS+=("Playwright")
      add_gate "npx playwright test"
    fi

    if compgen -G "$dir/.mocharc."{js,json,yaml} > /dev/null 2>&1 || has_dev_dep "mocha"; then
      DETECTED_FRAMEWORKS+=("Mocha")
      add_gate "npx mocha"
    fi

    if compgen -G "$dir/cypress.config."{js,ts} > /dev/null 2>&1 || has_dev_dep "cypress"; then
      DETECTED_FRAMEWORKS+=("Cypress")
      add_gate "npx cypress run"
    fi
  fi

  # --- Python frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Python " ]]; then
    local py_deps=""
    [[ -f "$dir/requirements.txt" ]] && py_deps+=$(cat "$dir/requirements.txt" 2>/dev/null)
    [[ -f "$dir/pyproject.toml" ]] && py_deps+=$(cat "$dir/pyproject.toml" 2>/dev/null)
    [[ -f "$dir/Pipfile" ]] && py_deps+=$(cat "$dir/Pipfile" 2>/dev/null)

    if [[ -f "$dir/manage.py" ]] || echo "$py_deps" | grep -qi "django"; then
      DETECTED_FRAMEWORKS+=("Django")
      add_gate "python manage.py test"
      add_gate "python manage.py check"
    fi

    if echo "$py_deps" | grep -qi "flask"; then
      DETECTED_FRAMEWORKS+=("Flask")
      add_gate "python -m pytest"
    fi

    if echo "$py_deps" | grep -qi "fastapi"; then
      DETECTED_FRAMEWORKS+=("FastAPI")
      add_gate "python -m pytest"
    fi

    if echo "$py_deps" | grep -qi "starlette"; then
      DETECTED_FRAMEWORKS+=("Starlette")
      add_gate "python -m pytest"
    fi

    if echo "$py_deps" | grep -qi "torch"; then
      DETECTED_FRAMEWORKS+=("PyTorch")
      add_gate "python -m pytest"
    fi

    if echo "$py_deps" | grep -qi "tensorflow"; then
      DETECTED_FRAMEWORKS+=("TensorFlow")
      add_gate "python -m pytest"
    fi

    if [[ -f "$dir/pytest.ini" ]] || file_contains "$dir/pyproject.toml" "\[tool.pytest"; then
      DETECTED_FRAMEWORKS+=("pytest")
      add_gate "python -m pytest"
    fi

    if [[ -f "$dir/mypy.ini" ]] || file_contains "$dir/pyproject.toml" "\[tool.mypy"; then
      DETECTED_FRAMEWORKS+=("mypy")
      add_gate "mypy ."
    fi

    if file_contains "$dir/pyproject.toml" "\[tool.ruff"; then
      DETECTED_FRAMEWORKS+=("Ruff")
      add_gate "ruff check ."
    fi
  fi

  # --- Rust frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Rust " ]]; then
    if file_contains "$dir/Cargo.toml" "actix-web"; then
      DETECTED_FRAMEWORKS+=("Actix-web")
    fi
    if file_contains "$dir/Cargo.toml" "axum"; then
      DETECTED_FRAMEWORKS+=("Axum")
    fi
    if file_contains "$dir/Cargo.toml" "rocket"; then
      DETECTED_FRAMEWORKS+=("Rocket")
    fi
    if file_contains "$dir/Cargo.toml" "bevy"; then
      DETECTED_FRAMEWORKS+=("Bevy")
    fi
    if [[ -d "$dir/src-tauri" ]]; then
      DETECTED_FRAMEWORKS+=("Tauri")
    fi
    add_gate "cargo test"
    add_gate "cargo clippy"
  fi

  # --- Go frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Go " ]]; then
    if file_contains "$dir/go.mod" "github.com/gin-gonic/gin"; then
      DETECTED_FRAMEWORKS+=("Gin")
    fi
    if file_contains "$dir/go.mod" "github.com/labstack/echo"; then
      DETECTED_FRAMEWORKS+=("Echo")
    fi
    if file_contains "$dir/go.mod" "github.com/gofiber/fiber"; then
      DETECTED_FRAMEWORKS+=("Fiber")
    fi
    if file_contains "$dir/go.mod" "github.com/go-chi/chi"; then
      DETECTED_FRAMEWORKS+=("Chi")
    fi
    add_gate "go test ./..."
    add_gate "go vet ./..."
  fi

  # --- Java/Kotlin frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Java/Kotlin " ]]; then
    local jvm_deps=""
    [[ -f "$dir/pom.xml" ]] && jvm_deps+=$(cat "$dir/pom.xml" 2>/dev/null)
    [[ -f "$dir/build.gradle" ]] && jvm_deps+=$(cat "$dir/build.gradle" 2>/dev/null)
    [[ -f "$dir/build.gradle.kts" ]] && jvm_deps+=$(cat "$dir/build.gradle.kts" 2>/dev/null)

    local build_cmd="./gradlew test"
    [[ -f "$dir/pom.xml" ]] && [[ ! -f "$dir/build.gradle" ]] && [[ ! -f "$dir/build.gradle.kts" ]] && build_cmd="./mvnw test"

    if echo "$jvm_deps" | grep -q "spring-boot"; then
      DETECTED_FRAMEWORKS+=("Spring Boot")
      add_gate "$build_cmd"
    fi
    if echo "$jvm_deps" | grep -q "quarkus"; then
      DETECTED_FRAMEWORKS+=("Quarkus")
      add_gate "$build_cmd"
    fi
    if echo "$jvm_deps" | grep -q "micronaut"; then
      DETECTED_FRAMEWORKS+=("Micronaut")
      add_gate "$build_cmd"
    fi
    if echo "$jvm_deps" | grep -q "com.android.application"; then
      DETECTED_FRAMEWORKS+=("Android")
      add_gate "./gradlew build"
      add_gate "./gradlew lint"
    fi

    # Default JVM gate if no specific framework matched
    if [[ ${#DETECTED_FRAMEWORKS[@]} -eq 0 ]] || ! printf '%s\n' "${DETECTED_FRAMEWORKS[@]}" | grep -qE "Spring Boot|Quarkus|Micronaut|Android"; then
      add_gate "$build_cmd"
    fi
  fi

  # --- Ruby frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Ruby " ]]; then
    if file_contains "$dir/Gemfile" "rails" || [[ -f "$dir/bin/rails" ]]; then
      DETECTED_FRAMEWORKS+=("Rails")
      add_gate "bin/rails test"
      add_gate "bin/rails db:migrate:status"
    fi
    if file_contains "$dir/Gemfile" "sinatra"; then
      DETECTED_FRAMEWORKS+=("Sinatra")
      add_gate "bundle exec rspec"
    fi
    if file_contains "$dir/Gemfile" "hanami"; then
      DETECTED_FRAMEWORKS+=("Hanami")
      add_gate "bundle exec hanami server"
    fi
  fi

  # --- PHP frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " PHP " ]]; then
    if file_contains "$dir/composer.json" "laravel/framework"; then
      DETECTED_FRAMEWORKS+=("Laravel")
      add_gate "php artisan test"
    fi
    if file_contains "$dir/composer.json" '"symfony/'; then
      DETECTED_FRAMEWORKS+=("Symfony")
      add_gate "php bin/phpunit"
    fi
  fi

  # --- C#/.NET frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " C#/.NET " ]]; then
    local csproj_content=""
    for f in "$dir"/*.csproj; do
      [[ -f "$f" ]] && csproj_content+=$(cat "$f" 2>/dev/null)
    done

    if echo "$csproj_content" | grep -q "Microsoft.AspNetCore"; then
      DETECTED_FRAMEWORKS+=("ASP.NET")
    fi
    if echo "$csproj_content" | grep -q "<UseMaui>true</UseMaui>"; then
      DETECTED_FRAMEWORKS+=("MAUI")
    fi
    add_gate "dotnet build"
    add_gate "dotnet test"
  fi

  # --- C/C++ build systems ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " C/C++ " ]]; then
    if [[ -f "$dir/CMakeLists.txt" ]]; then
      DETECTED_FRAMEWORKS+=("CMake")
      add_gate "cmake -B build && cmake --build build && ctest --test-dir build"
    fi
    if [[ -f "$dir/meson.build" ]]; then
      DETECTED_FRAMEWORKS+=("Meson")
      add_gate "meson setup build && meson compile -C build && meson test -C build"
    fi
    if [[ -f "$dir/WORKSPACE" ]] || [[ -f "$dir/BUILD.bazel" ]]; then
      DETECTED_FRAMEWORKS+=("Bazel")
      add_gate "bazel build //..."
      add_gate "bazel test //..."
    fi
    if [[ -f "$dir/Makefile" ]]; then
      DETECTED_FRAMEWORKS+=("Make")
      add_gate "make"
      add_gate "make test"
    fi
  fi

  # --- Swift frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Swift " ]]; then
    if [[ -f "$dir/Package.swift" ]]; then
      DETECTED_FRAMEWORKS+=("SPM")
      add_gate "swift build"
      add_gate "swift test"
      if file_contains "$dir/Package.swift" "vapor"; then
        DETECTED_FRAMEWORKS+=("Vapor")
      fi
    fi
  fi

  # --- Scala frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Scala " ]]; then
    if [[ -f "$dir/build.sbt" ]]; then
      DETECTED_FRAMEWORKS+=("sbt")
      add_gate "sbt compile"
      add_gate "sbt test"
      if file_contains "$dir/build.sbt" "com.typesafe.play"; then
        DETECTED_FRAMEWORKS+=("Play")
      fi
    fi
    if [[ -f "$dir/build.sc" ]]; then
      DETECTED_FRAMEWORKS+=("Mill")
      add_gate "mill compile"
      add_gate "mill test"
    fi
  fi

  # --- R ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " R " ]]; then
    add_gate "R CMD check ."
  fi

  # --- Lua ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Lua " ]]; then
    add_gate "luacheck ."
  fi

  # --- Dart/Flutter ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Dart/Flutter " ]]; then
    if file_contains "$dir/pubspec.yaml" "flutter"; then
      DETECTED_FRAMEWORKS+=("Flutter")
      add_gate "flutter analyze"
      add_gate "flutter test"
    else
      add_gate "dart analyze"
      add_gate "dart test"
    fi
  fi
}

# Process RALPH.md template to include only selected options
process_ralph_template() {
  local template="$1"
  local git_strategy="$2"
  local pr_strategy="$3"
  local pr_review="$4"

  local output="$template"

  # Remove all option definition blocks (JSON metadata)
  output=$(echo "$output" | sed '/<!--ralph-option:[a-z_]*$/,/^-->$/d')

  # Process git strategy
  case "$git_strategy" in
    never)
      output=$(echo "$output" | sed '/<!--ralph-option:git_once-->/,/<!--\/ralph-option:git_once-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_each-->/,/<!--\/ralph-option:git_each-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_squash-->/,/<!--\/ralph-option:git_squash-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_open-->/,/<!--\/ralph-option:pr_open-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_merge-->/,/<!--\/ralph-option:pr_merge-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_no-->/,/<!--\/ralph-option:pr_no-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_push-->/,/<!--\/ralph-option:pr_push-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_automerge-->/,/<!--\/ralph-option:pr_automerge-->/d')
      ;;
    once)
      output=$(echo "$output" | sed '/<!--ralph-option:git_never-->/,/<!--\/ralph-option:git_never-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_each-->/,/<!--\/ralph-option:git_each-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_squash-->/,/<!--\/ralph-option:git_squash-->/d')
      ;;
    each)
      output=$(echo "$output" | sed '/<!--ralph-option:git_never-->/,/<!--\/ralph-option:git_never-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_once-->/,/<!--\/ralph-option:git_once-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_squash-->/,/<!--\/ralph-option:git_squash-->/d')
      ;;
    squash)
      output=$(echo "$output" | sed '/<!--ralph-option:git_never-->/,/<!--\/ralph-option:git_never-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_once-->/,/<!--\/ralph-option:git_once-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_each-->/,/<!--\/ralph-option:git_each-->/d')
      ;;
  esac

  # Process PR strategy
  case "$pr_strategy" in
    open)
      output=$(echo "$output" | sed '/<!--ralph-option:pr_merge-->/,/<!--\/ralph-option:pr_merge-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_no-->/,/<!--\/ralph-option:pr_no-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_automerge-->/,/<!--\/ralph-option:pr_automerge-->/d')
      ;;
    merge)
      output=$(echo "$output" | sed '/<!--ralph-option:pr_open-->/,/<!--\/ralph-option:pr_open-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_no-->/,/<!--\/ralph-option:pr_no-->/d')
      ;;
    no)
      output=$(echo "$output" | sed '/<!--ralph-option:pr_open-->/,/<!--\/ralph-option:pr_open-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_merge-->/,/<!--\/ralph-option:pr_merge-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_push-->/,/<!--\/ralph-option:pr_push-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_automerge-->/,/<!--\/ralph-option:pr_automerge-->/d')
      ;;
  esac

  # Process PR review toolkit
  if [[ "$pr_review" == "yes" ]]; then
    output=$(echo "$output" | sed '/<!--ralph-option:pr_review_no-->/,/<!--\/ralph-option:pr_review_no-->/d')
  else
    output=$(echo "$output" | sed '/<!--ralph-option:pr_review_yes-->/,/<!--\/ralph-option:pr_review_yes-->/d')
  fi

  # Process quality gates
  if [[ ${#QUALITY_GATES[@]} -gt 0 ]]; then
    local gates_md=""
    for gate in "${QUALITY_GATES[@]}"; do
      gates_md+="- \`$gate\`\n"
    done
    output=$(echo "$output" | sed "s|<!--ralph-quality-gate-commands-->|$(echo -e "$gates_md")|")
  else
    # Remove quality gates section entirely if none detected
    output=$(echo "$output" | sed '/<!--ralph-option:quality_gates-->/,/<!--\/ralph-option:quality_gates-->/d')
  fi

  # Remove remaining option markers
  output=$(echo "$output" | sed 's/<!--ralph-option:[^>]*-->//g')
  output=$(echo "$output" | sed 's/<!--\/ralph-option:[^>]*-->//g')

  # Clean up extra blank lines
  output=$(echo "$output" | cat -s)

  echo "$output"
}

# Update CLAUDE.md to reference RALPH.md
update_claude_md() {
  local project_dir="$1"
  local marker="<!-- Ralph Loop Detection -->"
  local rule='If `.claude/ralph-loop.local.md` exists, follow rules in `.claude/RALPH.md`.'

  if [[ -f "$project_dir/CLAUDE.md" ]]; then
    if ! grep -q "$marker" "$project_dir/CLAUDE.md"; then
      echo -e "\n$marker\n$rule" >> "$project_dir/CLAUDE.md"
      info "Updated existing CLAUDE.md"
    else
      info "CLAUDE.md already configured"
    fi
  else
    echo -e "$marker\n$rule" > "$project_dir/CLAUDE.md"
    info "Created new CLAUDE.md"
  fi
}

# ========================================
# Main setup flow
# ========================================
main() {
  echo ""
  echo "========================================"
  echo "  Bovine University - Ralph Setup"
  echo "========================================"
  echo ""

  check_deps

  PROJECT_ROOT=$(find_project_root)
  info "Project root: $PROJECT_ROOT"

  # ========================================
  # Caveat emptor
  # ========================================
  echo ""
  echo -e "${YELLOW}${BOLD}  WARNING${NC}"
  echo ""
  echo "  Bovine University runs Claude Code with --dangerously-skip-permissions."
  echo "  This means Claude can execute ANY command that isn't explicitly denied."
  echo "  OS-level sandboxing restricts network and filesystem access, but Claude"
  echo "  has full control within your project directory."
  echo ""
  echo "  Recommendations:"
  echo "    - Use feature branches (the preflight hook creates them automatically)"
  echo "    - Enable GitHub branch protection on main"
  echo "    - For maximum safety, run in ephemeral/disposable environments"
  echo ""
  read -p "  Continue? [y/N]: " CONFIRM
  [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "Aborted." && exit 0

  # ========================================
  # Ecosystem & framework detection
  # ========================================
  echo ""
  info "Detecting project ecosystem..."
  detect_ecosystems "$PROJECT_ROOT"
  detect_frameworks "$PROJECT_ROOT"

  if [[ ${#DETECTED_ECOSYSTEMS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  Detected ecosystem: ${GREEN}$(IFS=', '; echo "${DETECTED_ECOSYSTEMS[*]}")${NC}"

    if [[ ${#DETECTED_FRAMEWORKS[@]} -gt 0 ]]; then
      echo -e "  Detected frameworks: ${GREEN}$(IFS=', '; echo "${DETECTED_FRAMEWORKS[*]}")${NC}"
    fi

    echo ""
    echo "  Allowed network domains:"
    # Deduplicate domains
    local unique_domains=($(printf '%s\n' "${DETECTED_DOMAINS[@]}" | sort -u))
    DETECTED_DOMAINS=("${unique_domains[@]}")
    for domain in "${DETECTED_DOMAINS[@]}"; do
      echo "    - $domain"
    done

    if [[ ${#QUALITY_GATES[@]} -gt 0 ]]; then
      echo ""
      echo "  Quality gate commands:"
      for gate in "${QUALITY_GATES[@]}"; do
        echo "    - $gate"
      done
    fi

    echo ""
    read -p "  Is this correct? [Y/n]: " ECO_CONFIRM
    if [[ "$ECO_CONFIRM" == "n" || "$ECO_CONFIRM" == "N" ]]; then
      echo ""
      echo "  Enter additional allowed domains (comma-separated, or press Enter to skip):"
      read -p "  Domains: " CUSTOM_DOMAINS
      if [[ -n "$CUSTOM_DOMAINS" ]]; then
        IFS=',' read -ra EXTRA_DOMAINS <<< "$CUSTOM_DOMAINS"
        for d in "${EXTRA_DOMAINS[@]}"; do
          d=$(echo "$d" | xargs) # trim whitespace
          [[ -n "$d" ]] && DETECTED_DOMAINS+=("$d")
        done
      fi
    fi
  else
    echo ""
    warn "No ecosystem detected."
    echo "  Enter allowed network domains (comma-separated, or press Enter for base only):"
    read -p "  Domains: " CUSTOM_DOMAINS
    if [[ -n "$CUSTOM_DOMAINS" ]]; then
      IFS=',' read -ra EXTRA_DOMAINS <<< "$CUSTOM_DOMAINS"
      for d in "${EXTRA_DOMAINS[@]}"; do
        d=$(echo "$d" | xargs)
        [[ -n "$d" ]] && DETECTED_DOMAINS+=("$d")
      done
    fi
  fi

  # ========================================
  # Question 1: Git Strategy
  # ========================================
  GIT=$(ask "How often should Ralph commit?" \
    "Never - I'll handle git myself" \
    "Once - Commit when task is complete" \
    "Each loop - Commit after every iteration" \
    "Squash - Commit each loop, squash when done (Recommended)")

  case "$GIT" in
    1) GIT_STRATEGY="never" ;;
    2) GIT_STRATEGY="once" ;;
    3) GIT_STRATEGY="each" ;;
    4) GIT_STRATEGY="squash" ;;
  esac

  # ========================================
  # Question 2: PR Strategy (if committing)
  # ========================================
  PR_STRATEGY="no"
  if [[ "$GIT_STRATEGY" != "never" ]]; then
    PR=$(ask "Auto-open a PR when task is complete?" \
      "Yes, open PR but don't merge (Recommended)" \
      "Yes, open PR and auto-merge if clean" \
      "No — keep the branch local")

    case "$PR" in
      1) PR_STRATEGY="open" ;;
      2) PR_STRATEGY="merge" ;;
      3) PR_STRATEGY="no" ;;
    esac
  fi

  # ========================================
  # Question 3: PR Review Toolkit
  # ========================================
  REVIEW=$(ask "Use pr-review-toolkit for code review?" \
    "Yes - Run code review agents during review phase (Recommended)" \
    "No - Skip automated review")

  case "$REVIEW" in
    1) PR_REVIEW="yes" ;;
    2) PR_REVIEW="no" ;;
  esac

  echo ""
  info "Setting up Ralph with:"
  info "  Git: $GIT_STRATEGY"
  info "  PR: $PR_STRATEGY"
  info "  Review: $PR_REVIEW"
  info "  Ecosystems: $(IFS=', '; echo "${DETECTED_ECOSYSTEMS[*]:-none}")"
  echo ""

  # ========================================
  # Create directories
  # ========================================
  mkdir -p "$PROJECT_ROOT/.claude/ralph"
  mkdir -p "$PROJECT_ROOT/.claude/hooks"

  # ========================================
  # Fetch and process templates
  # ========================================

  # Fetch RALPH.md template
  info "Fetching RALPH.md template..."
  RALPH_TEMPLATE=$(fetch_template "RALPH.md")

  # Process template with selected options
  RALPH_MD=$(process_ralph_template "$RALPH_TEMPLATE" "$GIT_STRATEGY" "$PR_STRATEGY" "$PR_REVIEW")
  echo "$RALPH_MD" > "$PROJECT_ROOT/.claude/RALPH.md"
  success "Created .claude/RALPH.md"

  # Fetch progress.md template
  info "Fetching progress.md template..."
  fetch_template ".claude/ralph/progress.md.template" > "$PROJECT_ROOT/.claude/ralph/progress.md"
  success "Created .claude/ralph/progress.md"

  # Fetch settings.local.json and inject domains
  info "Fetching settings.local.json..."
  SETTINGS_TEMPLATE=$(fetch_template ".claude/settings.local.json.template")

  # Deduplicate domains
  local unique_domains=($(printf '%s\n' "${DETECTED_DOMAINS[@]}" | sort -u))

  # Inject domains via jq
  SETTINGS_JSON=$(echo "$SETTINGS_TEMPLATE" | jq --argjson domains "$(printf '%s\n' "${unique_domains[@]}" | jq -R . | jq -s .)" \
    '.sandbox.network.allowedDomains = $domains')
  echo "$SETTINGS_JSON" > "$PROJECT_ROOT/.claude/settings.local.json"
  success "Created .claude/settings.local.json"

  # Fetch preflight hook
  info "Fetching preflight hook..."
  fetch_template ".claude/hooks/ralph-preflight.sh" > "$PROJECT_ROOT/.claude/hooks/ralph-preflight.sh"
  chmod +x "$PROJECT_ROOT/.claude/hooks/ralph-preflight.sh"
  success "Created .claude/hooks/ralph-preflight.sh"

  # ========================================
  # Update CLAUDE.md
  # ========================================
  update_claude_md "$PROJECT_ROOT"

  # ========================================
  # Done!
  # ========================================
  echo ""
  echo "========================================"
  success "Setup complete!"
  echo "========================================"
  echo ""
  echo "Next steps:"
  echo ""
  echo "  1. Write your task:"
  echo "     vim .claude/ralph/progress.md"
  echo ""
  echo "  2. Start Claude and launch the loop:"
  echo "     claude --dangerously-skip-permissions"
  echo '     /ralph-loop "Continue per .claude/ralph/progress.md" --max-iterations 20'
  echo ""
  echo "  The preflight hook handles the rest automatically:"
  echo "    - Verifies sandbox is enabled (configured in settings.local.json)"
  echo "    - Verifies --dangerously-skip-permissions is active"
  echo "    - Creates a ralph/<task-slug> branch if on main/master"
  echo ""
}

main "$@"
