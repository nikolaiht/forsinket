# The whole thing in Docker:        make up
# Every check CI runs, locally:     make test
#
# Outside Docker the backend needs JDK 25 and the frontend needs Node 22.

DEV_DATABASE = DATABASE_URL=jdbc:postgresql://localhost:54320/forsinket DATABASE_USER=forsinket DATABASE_PASSWORD=forsinket

.PHONY: up down test backend frontend contract contract-check format smoke dev

up: ## build and start the database and the app on http://localhost:8080
	docker compose up --build

down:
	docker compose down

test: backend frontend contract-check ## everything CI checks, except the Docker smoke test

backend: ## ktlint, and unit, property and integration tests (needs Docker for PostgreSQL)
	cd backend && ./gradlew check

frontend: frontend/node_modules ## formatting, elm-review, tests and the optimised build
	cd frontend && npm run check

contract: frontend/node_modules ## copy contract/examples into the Elm test module
	cd frontend && npm run contract

contract-check: contract ## fail if the committed Elm copy of the contract examples was out of date
	git diff --exit-code -- frontend/tests/Contract/Examples.elm

format: frontend/node_modules ## let ktlint and elm-format rewrite the code the way the checks want it
	cd backend && ./gradlew ktlintFormat
	cd frontend && npm run format

smoke: ## walk two claims through the running app (after `make up` or `docker compose up -d --wait`)
	./scripts/smoke.sh

dev: frontend/node_modules ## the backend outside Docker, serving a development build of the Elm app
	docker compose up --detach --wait db
	cd frontend && npm run build -- --dev
	cd backend && $(DEV_DATABASE) DEMO_MODE=true WEB_ROOT=../../frontend/dist ./gradlew :app:run

frontend/node_modules: frontend/package-lock.json
	cd frontend && npm ci
	touch frontend/node_modules
