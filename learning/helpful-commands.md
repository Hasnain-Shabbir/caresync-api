# Helpful commands (cheat sheet)

Run from the project root (`caresync-api/`). One line each. Add new ones as you meet them.

## Server and app

| Command | What it does |
|---|---|
| `bin/rails server` | start the app (we use port 4000, set in the config) |
| `bin/rails console` | open an interactive Ruby shell with the app loaded (`Organization.count`, `Patient.first`...) |
| `bin/rails runner "puts Organization.count"` | run one line of Ruby with the app loaded, then exit |
| `curl -i localhost:4000/up` | check the app is alive (health route, expect 200) |

## Testing and quality (run before every commit)

| Command | What it does |
|---|---|
| `bin/rails test` | run the whole test suite |
| `bin/rails test test/graphql` | run only the tests in a folder |
| `bin/rails test path/to/file_test.rb` | run one test file |
| `bin/rails test path/to/file_test.rb:24` | run the single test at line 24 |
| `bin/rubocop` | check style and syntax in every Ruby file |
| `bin/rubocop -a` | the same, and auto-fix what it can (trailing spaces, missing newline, bracket spacing) |
| `bin/rubocop app/graphql` | check only one folder |
| `bin/brakeman -q` | security scan of the code (quiet output) |
| `bin/rails test && bin/rubocop && bin/brakeman -q` | all three in one go, stops at the first failure |

## Database

| Command | What it does |
|---|---|
| `bin/rails generate model Appointment patient:references starts_at:datetime` | create a model, migration and test files |
| `bin/rails db:migrate` | apply new migrations to the **development** database and update `db/schema.rb` |
| `bin/rails db:test:prepare` | make the test database match `db/schema.rb` |
| `bin/rails db:rollback` | undo the last migration |
| `bin/rails dbconsole` | open `psql` on the development database (`\dt` lists tables, `\d patients` shows one, `\q` quits) |
| `bin/rails dbconsole -e test` | the same on the test database |

## Routes

| Command | What it does |
|---|---|
| `bin/rails routes` | list every route |
| `bin/rails routes -g organization` | only routes matching a word (grep) |
| `bin/rails routes -c api/v1/organizations` | only routes for one controller |

## GraphQL

| Command | What it does |
|---|---|
| `bin/rails runner "puts CaresyncApiSchema.to_definition"` | print the whole schema. If this prints, the schema loads. If it errors, the first line names the broken file |
| `bin/rails runner "puts CaresyncApiSchema.to_definition" \| grep -i patient` | the same, showing only lines mentioning "patient" (check a mutation is registered) |
| open `http://localhost:4000/sandbox` | the Apollo Sandbox page (development only) |
| `curl -s localhost:4000/graphql -H 'Content-Type: application/json' -d '{"query":"{ organizations { id name } }"}'` | send a GraphQL query from the terminal |

## Watching logs and SQL (find N+1)

| Command | What it does |
|---|---|
| `tail -f log/development.log` | follow the Rails log live, with every request and SQL query (`Ctrl-C` stops) |
| `tail -f log/development.log \| grep -E 'FROM "(organizations\|patients)"'` | follow the log, showing only SQL that reads those tables. Count the lines to spot N+1 |
| `grep -n "Started POST" log/development.log \| tail -5` | show the last 5 requests the server received |
| `: > log/development.log` | empty the log file, so the next run starts clean |

How the pieces work: `tail -f` follows a file, `\|` (pipe) sends its output to the next command, `grep` keeps only matching lines, `-E` lets you write `(a\|b)` to mean "a or b".

## Git (commit prefixes: `feat:`, `fix:`, `update:`, `chore:`, `test:`)

| Command | What it does |
|---|---|
| `git status --short` | one line per changed file |
| `git diff` | show your uncommitted changes (read this before committing) |
| `git add app/graphql` | stage one folder |
| `git commit -m "feat: add patient mutations"` | commit what is staged |
| `git log --oneline \| head` | the last commits, one line each |
| `git stash -u` | put all changes (including new files) aside, leaving a clean tree |
| `git stash pop` | bring the stashed changes back |
| `git restore path/to/file` | throw away your uncommitted changes in one file (cannot be undone) |

## Debugging a broken schema (the usual suspects)

| Symptom | Check |
|---|---|
| sandbox or Postman shows no schema, `/graphql` gives a 500 | run `bin/rubocop` (syntax errors by file and line), then `bin/rails runner "puts CaresyncApiSchema.to_definition"` |
| `expected file ... to define constant ...` | class name doesn't match the file name |
| `No route matches` | `bin/rails routes -g <word>` |
| a test fails with `No fixture named ...` | the label in `test/fixtures/*.yml` doesn't match the one in the test |
