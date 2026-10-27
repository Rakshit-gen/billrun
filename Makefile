# Local runs need Docker or Podman. CI does the same with scripts/ci.sh.
RUNTIME ?= docker

.PHONY: db ci clean

# Starts Oracle Free 23ai with a billrun user; wait for "DATABASE IS READY" in the logs.
db:
	$(RUNTIME) run -d --name oracledb -p 1521:1521 -e ORACLE_PASSWORD=billrun \
	  -e APP_USER=billrun -e APP_USER_PASSWORD=billrun gvenzl/oracle-free:23

# Installs utPLSQL and billrun, runs the tests and the benchmark.
ci:
	RUNTIME=$(RUNTIME) ./scripts/ci.sh

clean:
	$(RUNTIME) rm -f oracledb
