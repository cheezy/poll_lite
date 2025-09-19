# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Setup and Installation
- `mix setup` - Install dependencies, create database, migrate, and build assets
- `mix deps.get` - Install dependencies

### Running the Application
- `mix phx.server` - Start Phoenix server (visit http://localhost:4000)
- `iex -S mix phx.server` - Start Phoenix server with interactive Elixir shell

### Database
- `mix ecto.create` - Create the database
- `mix ecto.migrate` - Run database migrations
- `mix ecto.reset` - Drop and recreate database with migrations and seeds
- `mix ecto.gen.migration <name>` - Generate a new migration

### Testing
- `mix test` - Run all tests
- `mix test <file_path>` - Run tests in specific file
- `mix test <file_path>:<line>` - Run specific test at line number

### Code Quality
- `mix format` - Format code according to .formatter.exs
- `mix credo` - Run code analysis with Credo
- `mix precommit` - Run compilation with warnings as errors, check unused deps, format, and test

### Assets
- `mix assets.build` - Compile and build CSS (Tailwind) and JS (ESBuild)
- `mix assets.deploy` - Build minified assets for production

## Architecture Overview

This is a Phoenix 1.8 application with LiveView 1.1, using:

- **Web Framework**: Phoenix with LiveView for interactive UIs
- **Database**: PostgreSQL via Ecto
- **Server**: Bandit web server
- **Assets**: ESBuild for JavaScript bundling, Tailwind CSS v4 for styling
- **Email**: Swoosh for email delivery

### Key Directories

- `lib/pool_lite/` - Core business logic and Ecto schemas
  - `application.ex` - OTP application supervisor tree
  - `repo.ex` - Ecto repository
  - `mailer.ex` - Email configuration

- `lib/pool_lite_web/` - Web layer
  - `router.ex` - HTTP routes and pipelines
  - `controllers/` - Request handlers
  - `components/` - Reusable UI components (core_components.ex, layouts.ex)
  - `telemetry.ex` - Metrics and monitoring

- `priv/repo/` - Database migrations and seeds
- `assets/` - Frontend assets (JS, CSS)
- `config/` - Environment-specific configuration

### Application Supervision Tree

The application starts with these supervised processes:
1. Telemetry for metrics
2. Ecto Repo for database connections
3. DNSCluster for distributed Elixir
4. Phoenix.PubSub for real-time features
5. Phoenix Endpoint for HTTP server

### Development Routes

In development, the following routes are available:
- `/dev/dashboard` - Phoenix LiveDashboard for monitoring
- `/dev/mailbox` - Swoosh mailbox preview for emails