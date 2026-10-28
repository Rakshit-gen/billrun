# Local runs need Docker or Podman. CI does the same with scripts/ci.sh.
RUNTIME ?= docker

.PHONY: db ci bench clean

# Starts Oracle Free 23ai with a billrun user; wait for "DATABASE IS READY" in the logs.
db:
	$(RUNTIME) run -d --name oracledb -p 1521:1521 -e ORACLE_PASSWORD=billrun \
	  -e APP_USER=billrun -e APP_USER_PASSWORD=billrun gvenzl/oracle-free:23

# Installs utPLSQL and billrun, runs the tests and the benchmark.
ci:
	RUNTIME=$(RUNTIME) ./scripts/ci.sh

# Installs billrun without the tests and runs the benchmark at the three
# sizes the bench workflow uses.
bench:
	RUNTIME=$(RUNTIME) ./scripts/install.sh
	RUNTIME=$(RUNTIME) SIZES="10000:500:3 50000:2000:3 200000:8000:3" ./scripts/bench.sh

clean:
	$(RUNTIME) rm -f oracledb
